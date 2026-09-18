defmodule Wotex.Lab.FormalSearchTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab
  alias Wotex.Lab.Error
  alias Wotex.Lab.Evidence.Digest
  alias Wotex.Lab.Formal.{Abstraction, Output, Replay, Result, Search, Serializer}
  alias Wotex.Lab.SmartRoom.Policy
  alias Wotex.Lab.Test.FormalFixtures, as: Fixtures

  @init "room(comfort, off, off, within, noDecision, 0, 0, 0)"

  defp session(overrides \\ []) do
    {:ok, command} =
      Serializer.search("SAFE-THERMAL", @init, :no_simultaneous_heat_cool, max_depth: 100)

    base = %Result{
      status: :error,
      property: :no_simultaneous_heat_cool,
      variant: :safe,
      model: %{id: :thermal_control_v1, digest: "sha256:m", module: "SAFE-THERMAL"},
      abstraction_digest: "sha256:a",
      input_digest: Digest.bytes(@init),
      query_digest: Digest.bytes(command),
      engine: %{maude: "3.5.1", ex_maude: "0.4.1"},
      bounds: %{max_depth: 100, max_solutions: 1, deadline_ms: 5_000, max_output_bytes: 1_048_576}
    }

    Map.merge(
      %{
        base: base,
        load: "load /tmp/model.maude",
        command: command,
        module: "SAFE-THERMAL",
        initial_term: @init,
        property: :no_simultaneous_heat_cool,
        deadline: System.monotonic_time(:millisecond) + 5_000,
        ceiling: 1_048_576,
        exhaustion?: true
      },
      Map.new(overrides)
    )
  end

  # A scripted engine: answers in order and records every command with its remaining budget.
  defp engine(replies) do
    {:ok, log} = Agent.start_link(fn -> %{replies: replies, commands: []} end)

    execute = fn command, remaining ->
      Agent.get_and_update(log, fn %{replies: [reply | rest], commands: commands} ->
        {reply, %{replies: rest, commands: [{command, remaining} | commands]}}
      end)
    end

    {execute, fn -> Agent.get(log, &Enum.reverse(&1.commands)) end}
  end

  test "a bounded no-solution answer becomes verified only through a terminating complete search" do
    {execute, commands} =
      engine([
        {:ok, "Maude> \n"},
        {:ok, Fixtures.bounded_no_solution()},
        {:ok, Fixtures.safe_no_solution()}
      ])

    assert {:ok,
            %Result{
              status: :verified_in_model,
              explored: %{states: 9},
              exhaustion: %{basis: :complete_search, states: 253}
            }} = Search.run(session(), execute)

    assert [
             {"load /tmp/model.maude", _},
             {"search [1, 100] in SAFE-THERMAL : " <> _, _},
             {"search [1] in SAFE-THERMAL : " <> _, _}
           ] = commands.()

    assert Enum.all?(commands.(), fn {_, remaining} ->
             remaining > 0 and remaining <= 5_000
           end)

    {execute, _} = engine([{:ok, ""}, {:ok, Fixtures.bounded_no_solution()}])

    assert {:ok, %Result{status: :inconclusive, exhaustion: %{basis: :depth_bound}}} =
             Search.run(session(exhaustion?: false), execute)

    {execute, _} =
      engine([
        {:ok, ""},
        {:ok, Fixtures.bounded_no_solution()},
        {:ok, Fixtures.broken_energy_solution()}
      ])

    assert {:ok, %Result{status: :inconclusive, exhaustion: %{basis: :depth_bound}, error: nil}} =
             Search.run(session(), execute)

    {execute, _} =
      engine([
        {:ok, ""},
        {:ok, Fixtures.bounded_no_solution()},
        {:error, {:engine_timeout, "late"}}
      ])

    assert {:ok, %Result{status: :inconclusive, error: %{code: :exhaustion_timeout}}} =
             Search.run(session(), execute)

    {execute, _} =
      engine([{:ok, ""}, {:ok, Fixtures.bounded_no_solution()}, {:ok, Fixtures.warning()}])

    assert {:error, %Error{code: :engine_warning}} = Search.run(session(), execute)
  end

  test "a solution is expanded into an ordered counterexample" do
    {execute, _} =
      engine([
        {:ok, ""},
        {:ok, Fixtures.broken_energy_solution()},
        {:ok, Fixtures.broken_energy_path()}
      ])

    assert {:ok, %Result{status: :counterexample, counterexample: steps, explored: %{states: 6}}} =
             Search.run(session(), execute)

    assert length(steps) == 5 and List.last(steps).rule == "dispatchHeat"

    {execute, _} = engine([{:ok, ""}, {:ok, Fixtures.broken_energy_solution()}, {:ok, "garbage\n"}])
    assert {:error, %Error{code: :malformed_output}} = Search.run(session(), execute)
  end

  test "deadline, ceiling and engine failures end the session boundedly" do
    {execute, commands} = engine([])

    assert {:error, {:engine_timeout, _}} =
             Search.run(session(deadline: System.monotonic_time(:millisecond) - 1), execute)

    assert commands.() == []

    {execute, _} = engine([{:ok, ""}, {:ok, String.duplicate("x", 65)}])
    assert {:error, %Error{code: :output_overflow}} = Search.run(session(ceiling: 64), execute)

    {execute, _} = engine([{:ok, ""}, {:error, {:engine_error, :crash}}])
    assert {:error, {:engine_error, :crash}} = Search.run(session(), execute)

    {execute, _} = engine([{:error, :port_closed}])
    assert {:error, :port_closed} = Search.run(session(), execute)
  end

  test "outcomes conclude into results and timeouts are recognised" do
    base = session().base

    assert %Result{status: :counterexample} =
             Search.conclude({:ok, %{base | status: :counterexample}}, base, 0)

    assert %Result{status: :error, error: %{code: :output_overflow, phase: :engine}} =
             Search.conclude({:error, Error.new(:output_overflow, :engine, "big")}, base, 0)

    assert %Result{status: :timeout, error: %{code: :engine_timeout, reaped: 1}} =
             Search.conclude({:error, {:engine_timeout, "slow"}}, base, 1)

    assert %Result{status: :error, error: %{code: :engine_error, type: :crash}} =
             Search.conclude({:error, {:engine_error, :crash}}, base, 0)

    assert %Result{status: :error, error: %{code: :engine_error, reason: ":port_closed"}} =
             Search.conclude({:error, :port_closed}, base, 0)

    assert Search.timed_out?({:error, {:engine_timeout, "x"}})
    assert Search.timed_out?({:ok, %{base | error: %{code: :exhaustion_timeout}}})
    refute Search.timed_out?({:ok, base})
    refute Search.timed_out?({:error, :other})

    map =
      Result.to_map(%{
        base
        | status: :counterexample,
          explored: %{states: 6, rewrites: 15},
          counterexample: [%{state: 0, rule: nil, term: @init}],
          error: %{code: :x, details: %{a: :b}}
      })

    assert map["counterexample"] == [%{"state" => 0, "rule" => nil, "term" => @init}]
    assert map["explored"] == %{"states" => 6, "rewrites" => 15}
    assert map["error"] == %{"code" => "x", "details" => %{"a" => "b"}}
    assert {:ok, _} = Wotex.JSON.encode(map)
  end

  describe "replay rules" do
    setup do
      lab = start_supervised!({Lab, id: "formal-search-replay", max_children: 4})

      {:ok, policy} =
        Lab.start_child(
          lab,
          :sessions,
          {Policy, id: :replay, allowed: [:operator], limits: Replay.policy_limits()}
        )

      %{policy: policy}
    end

    test "environment, energy, expiry and completion rules follow the model", %{policy: policy} do
      trace = """
      state 0, Room: room(comfort, off, off, within, noDecision, 0, 0, 0)
      ===[ rl [heatUp] ]===>
      state 1, Room: room(hot, off, off, within, noDecision, 0, 0, 0)
      ===[ rl [chill] ]===>
      state 2, Room: room(comfort, off, off, within, noDecision, 0, 0, 0)
      ===[ rl [coolDown] ]===>
      state 3, Room: room(cold, off, off, within, noDecision, 0, 0, 0)
      ===[ rl [warm] ]===>
      state 4, Room: room(comfort, off, off, within, noDecision, 0, 0, 0)
      ===[ rl [heatUp] ]===>
      state 5, Room: room(hot, off, off, within, noDecision, 0, 0, 0)
      ===[ crl [proposeCool] ]===>
      state 6, Room: room(hot, off, off, within, granted(cool, 0), 0, 1, 0)
      ===[ rl [energyOver] ]===>
      state 7, Room: room(hot, off, off, over, granted(cool, 0), 0, 1, 0)
      ===[ crl [age] ]===>
      state 8, Room: room(hot, off, off, over, granted(cool, 0), 1, 1, 0)
      ===[ crl [age] ]===>
      state 9, Room: room(hot, off, off, over, granted(cool, 0), 2, 1, 0)
      ===[ crl [age] ]===>
      state 10, Room: room(hot, off, off, over, granted(cool, 0), 3, 1, 0)
      ===[ crl [expire] ]===>
      state 11, Room: room(hot, off, off, over, noDecision, 3, 1, 0)
      ===[ rl [energyWithin] ]===>
      state 12, Room: room(hot, off, off, within, noDecision, 3, 1, 0)
      """

      {:ok, steps} = Output.path(trace)

      assert {:ok,
              %{
                status: :converged,
                steps: 12,
                refusals: [%{rule: "expire", code: :expired}],
                effects: 0
              }} = Replay.run(policy, steps)
    end

    test "dispatches and redeliveries without a decision are refused, and a complete step clears the slot",
         %{policy: policy} do
      trace = """
      state 0, Room: room(comfort, off, off, within, noDecision, 0, 0, 0)
      ===[ rl [dispatchWithoutDecision] ]===>
      state 1, Room: room(comfort, on, off, within, dispatched(heat, 0), 0, 0, 1)
      """

      {:ok, steps} = Output.path(trace)

      assert {:ok, %{status: :diverged, steps: 1, refusals: [%{code: :no_decision_to_dispatch}]}} =
               Replay.run(policy, steps)

      {:ok, steps} =
        Output.path(
          "state 0, Room: room(comfort, off, off, within, noDecision, 0, 0, 0)\n===[ crl [dispatchHeat] ]===>\nstate 1, Room: room(comfort, on, off, within, dispatched(heat, 0), 0, 0, 1)\n"
        )

      assert {:ok, %{status: :diverged, refusals: [%{code: :unknown_decision}]}} =
               Replay.run(policy, steps)

      {:ok, steps} =
        Output.path(
          "state 0, Room: room(comfort, off, off, within, noDecision, 0, 0, 0)\n===[ rl [redeliver] ]===>\nstate 1, Room: room(comfort, off, off, within, noDecision, 0, 0, 1)\n"
        )

      assert {:ok, %{status: :diverged, refusals: [%{code: :unknown_decision}]}} =
               Replay.run(policy, steps)

      {:ok, steps} =
        Output.path(
          "state 0, Room: room(comfort, off, off, within, noDecision, 0, 0, 0)\n===[ rl [heatUp] ]===>\nstate 1, Room: room(hot, off, off, within, noDecision, 0, 0, 0)\n===[ crl [proposeCool] ]===>\nstate 2, Room: room(hot, off, off, within, granted(cool, 0), 0, 1, 0)\n===[ crl [proposeCool] ]===>\nstate 3, Room: room(hot, off, off, within, granted(cool, 0), 0, 2, 0)\n"
        )

      assert {:ok, %{status: :diverged, steps: 3, refusals: [%{code: :conflicting_decision}]}} =
               Replay.run(policy, steps)
    end
  end

  test "tree digests report unreadable files and abstraction refuses malformed decisions" do
    root = Path.join(System.tmp_dir!(), "wotex-lab-tree-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    assert {:ok, empty} = Digest.tree(root, ["**/*"])
    assert empty == Digest.bytes("")

    assert {:error, %Error{code: :invalid_concrete_room}} =
             Abstraction.room(%{Map.put(%{}, :temperature, 1) | temperature: 1})

    assert {:error, %Error{code: :invalid_concrete_room}} =
             Abstraction.room(%{
               temperature: 20.0,
               heater: :off,
               cooler: :off,
               power: 0,
               budget: 1,
               decision: {:granted, :heat, -1},
               age_ms: 0,
               grants: 0,
               effects: 0
             })
  end
end
