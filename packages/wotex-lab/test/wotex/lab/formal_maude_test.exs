defmodule Wotex.Lab.FormalMaudeTest do
  @moduledoc false

  # Runs only with WOTEX_LAB_MAUDE=<path to a Maude 3.5 executable>; the binary
  # is provisioned explicitly by the operator and never downloaded here.

  use ExUnit.Case, async: false

  alias Wotex.Lab
  alias Wotex.Lab.Error
  alias Wotex.Lab.Evidence.Digest
  alias Wotex.Lab.Formal.{Abstraction, Profile, Replay, Result, Serializer}
  alias Wotex.Lab.SmartRoom.Policy
  alias Wotex.Lab.Test.ChildEnvironment

  @moduletag :maude
  @moduletag timeout: 120_000

  setup do
    binary = System.fetch_env!("WOTEX_LAB_MAUDE")
    {:ok, digest} = Digest.file(binary)
    lab = start_supervised!({Lab, id: "formal-maude", max_children: 8})

    {:ok, profile} =
      Profile.new(pool: :wotex_lab_formal_pool, binary: binary, binary_digest: digest)

    {:ok, _} = Lab.start_child(lab, :sessions, Profile.child_spec(profile))

    {:ok, policy} =
      Lab.start_child(
        lab,
        :sessions,
        {Policy, id: :formal, allowed: [:operator], limits: Replay.policy_limits()}
      )

    %{lab: lab, profile: profile, binary: binary, digest: digest, policy: policy}
  end

  test "the safe model verifies every property by complete search and the engine is recorded", %{
    profile: profile,
    policy: policy
  } do
    for property <- Map.keys(Serializer.properties()) do
      assert {:ok,
              %Result{
                status: :verified_in_model,
                exhaustion: %{basis: :complete_search, states: states}
              } = result} =
               Profile.verify(profile, :safe, property, Abstraction.init())

      assert states > 100 and result.explored.states > 0
      assert result.engine.maude == "3.5.1" and result.engine.ex_maude == "0.4.1"
      assert result.model.digest == profile.model.digest
    end

    assert %{decisions: [], refusals: []} = Policy.records(policy)
  end

  test "each broken model yields a counterexample that replays to a recorded divergence", %{
    profile: profile,
    policy: policy
  } do
    cases = [
      {:broken_both, :no_simultaneous_heat_cool},
      {:broken_duplicate, :no_duplicate_effect},
      {:broken_stale, :no_stale_dispatch},
      {:broken_energy, :energy_limit_not_bypassed},
      {:broken_ungranted, :no_effect_without_decision}
    ]

    for {variant, property} <- cases do
      assert {:ok, %Result{status: :counterexample, counterexample: [first | _] = steps}} =
               Profile.verify(profile, variant, property, Abstraction.init())

      assert first.rule == nil and
               first.term == "room(comfort, off, off, within, noDecision, 0, 0, 0)"

      assert {:ok, %{status: :diverged}} = Replay.run(policy, steps)
    end

    assert %{decisions: decisions} = Policy.records(policy)
    assert Enum.all?(decisions, &(&1.status in [:granted, :dispatched]))
  end

  test "a depth bound without exhaustion is inconclusive; oversized output and timeouts are bounded",
       %{profile: profile, lab: lab, binary: binary, digest: digest} do
    assert {:ok, %Result{status: :inconclusive, exhaustion: %{basis: :depth_bound}}} =
             Profile.verify(profile, :safe, :no_simultaneous_heat_cool, Abstraction.init(),
               max_depth: 2,
               exhaustion: false
             )

    assert {:error, %Error{code: :bound_exceeded}} =
             Profile.verify(profile, :safe, :no_stale_dispatch, Abstraction.init(),
               max_depth: 5_000
             )

    assert {:error, %Error{code: :unknown_variant}} =
             Profile.verify(profile, :broken_everything, :no_stale_dispatch, Abstraction.init())

    assert {:error, %Error{code: :invalid_term}} =
             Profile.verify(profile, :safe, :no_stale_dispatch, %{
               Abstraction.init()
               | band: :"quit ."
             })

    {:ok, tiny} =
      Profile.new(
        pool: :wotex_lab_formal_tiny,
        binary: binary,
        binary_digest: digest,
        limits: %{max_output_bytes: 64}
      )

    {:ok, _} = Lab.start_child(lab, :sessions, Profile.child_spec(tiny))

    assert {:ok, %Result{status: :error, error: %{code: code}}} =
             Profile.verify(tiny, :safe, :no_stale_dispatch, Abstraction.init())

    assert code in [:output_overflow, :engine_error]

    # The duplicate-delivery model grows its effect counter without bound, so an
    # exhaustion attempt cannot terminate: the deadline ends it, in whichever
    # phase it strikes, the orphaned engine is killed and the pool replaces the
    # stopped worker.
    {:ok, short} =
      Profile.new(
        pool: :wotex_lab_formal_short,
        binary: binary,
        binary_digest: digest,
        limits: %{deadline_ms: 200}
      )

    {:ok, pool} = Lab.start_child(lab, :sessions, Profile.child_spec(short))

    assert {:ok, %Result{status: status, error: %{code: code}}} =
             Profile.verify(
               short,
               :broken_duplicate,
               :no_simultaneous_heat_cool,
               Abstraction.init()
             )

    assert {status, code} in [{:timeout, :engine_timeout}, {:inconclusive, :exhaustion_timeout}]
    assert Process.alive?(pool)
    Process.sleep(300)
    assert running(binary) <= 3, "a timed-out search left an orphan engine"

    assert {:ok, %Result{status: :counterexample}} =
             Profile.verify(short, :broken_both, :no_simultaneous_heat_cool, Abstraction.init())

    assert %{reaped: reaped} =
             Profile.stop(short, pool, fn -> Lab.stop_child(lab, :sessions, pool) end)

    assert reaped in [0, 1]
    refute Process.alive?(pool)
    assert running(binary) <= 2, "workers of the stopped pool survived"
  end

  defp running(binary) do
    # Anchored so the shell that carries the path in its own command line is not counted.
    {ps, _} =
      System.cmd("pgrep", ["-f", "^" <> Regex.escape(binary)],
        env: ChildEnvironment.cleared(),
        stderr_to_stdout: true
      )

    ps
    |> String.split("\n", trim: true)
    |> length()
  end

  test "two profiles with their own pools verify concurrently and in isolation", %{
    lab: lab,
    binary: binary,
    digest: digest
  } do
    {:ok, a} = Profile.new(pool: :wotex_lab_formal_a, binary: binary, binary_digest: digest)
    {:ok, b} = Profile.new(pool: :wotex_lab_formal_b, binary: binary, binary_digest: digest)
    {:ok, _} = Lab.start_child(lab, :sessions, Profile.child_spec(a))
    {:ok, _} = Lab.start_child(lab, :sessions, Profile.child_spec(b))

    [ra, rb] =
      [{a, :safe, :no_simultaneous_heat_cool}, {b, :broken_both, :no_simultaneous_heat_cool}]
      |> Task.async_stream(
        fn {profile, variant, property} ->
          Profile.verify(profile, variant, property, Abstraction.init())
        end,
        timeout: 60_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert {:ok, %Result{status: :verified_in_model}} = ra
    assert {:ok, %Result{status: :counterexample}} = rb
  end
end
