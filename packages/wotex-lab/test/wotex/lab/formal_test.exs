defmodule Wotex.Lab.FormalTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab
  alias Wotex.Lab.Error
  alias Wotex.Lab.Evidence.Digest
  alias Wotex.Lab.Formal.{Abstraction, Model, Output, Profile, Replay, Result, Serializer}
  alias Wotex.Lab.SmartRoom.Policy
  alias Wotex.Lab.Test.FormalFixtures, as: Fixtures

  describe "model catalogue" do
    test "the checked-in model matches its manifest digest and names every variant" do
      assert :thermal_control_v1 in Model.ids()
      assert {:ok, model} = Model.fetch(:thermal_control_v1)
      assert {:ok, ^model} = Model.verify(model)
      assert model.modules.safe == "SAFE-THERMAL"
      assert Map.keys(model.modules) |> Enum.sort() == Enum.sort(Model.variants())
      assert model.bounds == %{max_age: 3, max_grants: 2}
      assert model.license == "Apache-2.0"
      assert {:error, %Error{code: :unknown_model}} = Model.fetch(:other)

      assert {:error, %Error{code: :model_digest_mismatch}} =
               Model.verify(%{model | digest: "sha256:" <> String.duplicate("0", 64)})

      assert {:error, %Error{code: :model_unreadable}} =
               Model.verify(%{model | path: model.path <> ".missing"})
    end
  end

  describe "abstraction" do
    test "discretizes a concrete room and reports what is lost" do
      concrete = %{
        temperature: 18.9,
        heater: :off,
        cooler: :on,
        power: 2_100.0,
        budget: 2_000.0,
        decision: {:granted, :heat, 2_400},
        age_ms: 3_999,
        grants: 5,
        effects: 4
      }

      assert {:ok, abstract, lost} = Abstraction.room(concrete)

      assert abstract == %{
               band: :cold,
               heater: :off,
               cooler: :on,
               energy: :over,
               decision: {:granted, :heat, 2},
               age: 3,
               grants: 2,
               effects: 3
             }

      assert lost.age_rounding == 999 and lost.grants_capped and lost.effects_capped and
               lost.decision == %{age_ms: 2_400}

      assert {:ok, %{band: :comfort}, _} = Abstraction.room(%{concrete | temperature: 19.0})

      assert {:ok, %{band: :hot, energy: :within}, _} =
               Abstraction.room(%{concrete | temperature: 24.0, power: 2_000.0})

      assert {:error, %Error{code: :invalid_concrete_room}} =
               Abstraction.room(%{concrete | heater: :maybe})

      assert {:error, %Error{code: :invalid_concrete_room}} =
               Abstraction.room(%{concrete | decision: :granted})

      assert {:error, %Error{code: :invalid_concrete_room}} = Abstraction.room(%{})
    end

    test "reads model terms back and refuses foreign text" do
      assert {:ok, Abstraction.init()} ==
               Abstraction.from_term("room(comfort, off, off, within, noDecision, 0, 0, 0)")

      assert {:ok, %{decision: {:dispatched, :cool, 3}, effects: 2}} =
               Abstraction.from_term("room(hot, off, on, within, dispatched(cool, 3), 0, 1, 2)")

      assert {:error, %Error{code: :invalid_term}} =
               Abstraction.from_term("room(warm, off, off, within, noDecision, 0, 0, 0)")

      assert {:error, %Error{code: :invalid_term}} = Abstraction.from_term("init")
    end
  end

  describe "serializer" do
    test "emits only closed terms and fixed property patterns" do
      assert {:ok, "room(comfort, off, off, within, noDecision, 0, 0, 0)"} =
               Serializer.term(Abstraction.init())

      assert {:ok, term} =
               Serializer.term(%{Abstraction.init() | decision: {:granted, :cool, 2}, age: 3})

      assert term == "room(comfort, off, off, within, granted(cool, 2), 3, 0, 0)"

      assert {:ok, command} =
               Serializer.search("SAFE-THERMAL", term, :no_stale_dispatch,
                 max_depth: 100,
                 max_solutions: 1
               )

      assert command ==
               "search [1, 100] in SAFE-THERMAL : #{term} =>* room(B:Band, H:Switch, C:Switch, E:Energy, dispatched(X:Action, T:Nat), A:Nat, G:Nat, N:Nat) such that T:Nat >= maxAge ."

      assert {:ok, "search [1] in SAFE-THERMAL : " <> _} =
               Serializer.search("SAFE-THERMAL", term, :no_simultaneous_heat_cool,
                 max_depth: :unbounded
               )

      assert {:ok, "show path 5 ."} = Serializer.path(5)

      assert {:ok, "load /tmp/x/thermal-control-v1.maude"} =
               Serializer.load("/tmp/x/thermal-control-v1.maude")

      assert map_size(Serializer.properties()) == 5
    end

    test "hostile input never reaches command syntax" do
      init = Abstraction.init()
      assert {:error, %Error{code: :invalid_term}} = Serializer.term(%{init | band: "cold) . quit"})

      assert {:error, %Error{code: :invalid_term}} =
               Serializer.term(%{init | band: :"cold . load /etc/passwd"})

      assert {:error, %Error{code: :invalid_term}} = Serializer.term(%{init | age: -1})
      assert {:error, %Error{code: :invalid_term}} = Serializer.term(%{init | effects: 99})

      assert {:error, %Error{code: :invalid_term}} =
               Serializer.term(%{init | decision: {:granted, :explode, 0}})

      assert {:error, %Error{code: :invalid_term}} =
               Serializer.term("room(comfort, off, off, within, noDecision, 0, 0, 0)")

      {:ok, term} = Serializer.term(init)

      assert {:error, %Error{code: :invalid_command}} =
               Serializer.search("SAFE-THERMAL . quit", term, :no_stale_dispatch, [])

      assert {:error, %Error{code: :invalid_term}} =
               Serializer.search("SAFE-THERMAL", term <> " . quit", :no_stale_dispatch, [])

      assert {:error, %Error{code: :invalid_term}} =
               Serializer.search("SAFE-THERMAL", "init", :no_stale_dispatch, [])

      assert {:error, %Error{code: :unknown_property}} =
               Serializer.search("SAFE-THERMAL", term, :"such that true", [])

      assert {:error, %Error{code: :invalid_command}} =
               Serializer.search("SAFE-THERMAL", term, :no_stale_dispatch, max_depth: 0)

      assert {:error, %Error{code: :invalid_command}} =
               Serializer.search("SAFE-THERMAL", term, :no_stale_dispatch, max_solutions: 65)

      assert {:error, %Error{code: :invalid_command}} =
               Serializer.search(:safe, term, :no_stale_dispatch, [])

      assert {:error, %Error{code: :invalid_command}} = Serializer.path(-1)
      assert {:error, %Error{code: :invalid_command}} = Serializer.load("/tmp/x.maude ; rm -rf /")
    end
  end

  describe "output parsing" do
    test "reads solutions, no-solution reports, paths and refuses warnings or overflow" do
      assert {:ok, %{solutions: [], states: 253, rewrites: 1785, time_ms: 0}} =
               Output.search(Fixtures.safe_no_solution())

      assert {:ok, %{solutions: [%{number: 1, state: 5}], states: 6}} =
               Output.search(Fixtures.broken_energy_solution())

      assert {:error, %Error{code: :engine_warning, details: %{kind: "Warning"}}} =
               Output.search(Fixtures.warning())

      assert {:error, %Error{code: :malformed_output}} = Output.search("Bye.\n")
      assert {:error, %Error{code: :malformed_output}} = Output.search("Solution 1 (state 2)\n")

      assert {:error, %Error{code: :output_overflow}} =
               Output.search(Fixtures.safe_no_solution(), max_bytes: 10)

      assert {:ok, steps} = Output.path(Fixtures.broken_energy_path())

      assert Enum.map(steps, & &1.rule) == [
               nil,
               "coolDown",
               "proposeHeat",
               "energyOver",
               "dispatchHeat"
             ]

      assert Enum.map(steps, & &1.state) == [0, 1, 2, 3, 5]
      assert List.last(steps).term == "room(cold, on, off, over, dispatched(heat, 0), 0, 1, 1)"
      assert {:error, %Error{code: :malformed_output}} = Output.path("nothing here\n")

      assert {:error, %Error{code: :output_overflow}} =
               Output.path(Fixtures.broken_energy_path(), max_bytes: 10)
    end
  end

  describe "profile admission" do
    test "an unavailable, unverified or unpinned executable is unsupported and no report exists" do
      assert {:error, %Error{code: :unsupported}} =
               Profile.new(
                 pool: :formal_missing,
                 binary: "/nonexistent/maude",
                 binary_digest: "sha256:" <> String.duplicate("0", 64)
               )

      assert {:error, %Error{code: :unsupported}} =
               Profile.new(pool: :formal_missing, binary: nil, binary_digest: nil)

      script = Path.join(System.tmp_dir!(), "wotex-not-maude-#{System.unique_integer([:positive])}")
      File.write!(script, "#!/bin/sh\necho hello\n")
      File.chmod!(script, 0o755)
      on_exit(fn -> File.rm(script) end)
      {:ok, digest} = Digest.file(script)

      assert {:error, %Error{code: :unsupported, details: %{expected: _}}} =
               Profile.new(
                 pool: :formal_missing,
                 binary: script,
                 binary_digest: "sha256:" <> String.duplicate("1", 64)
               )

      assert {:error, %Error{code: :unsupported}} =
               Profile.new(pool: :formal_missing, binary: script, binary_digest: digest)

      assert {:error, %Error{code: :invalid_pool}} =
               Profile.new(pool: "formal", binary: script, binary_digest: digest)

      assert {:error, %Error{code: :limit_exceeded}} =
               Profile.new(
                 pool: :formal,
                 binary: script,
                 binary_digest: digest,
                 limits: %{max_depth: 5_000}
               )

      assert {:error, %Error{code: :unknown_model}} =
               Profile.new(model: :nope, pool: :formal, binary: script, binary_digest: digest)

      assert %{defaults: %{max_depth: 100, deadline_ms: 5_000}, ceilings: %{max_depth: 1_000}} =
               Profile.limits()
    end
  end

  describe "result" do
    test "the evidence form is plain data" do
      result = %Result{
        status: :inconclusive,
        property: :no_stale_dispatch,
        variant: :safe,
        model: %{id: :thermal_control_v1, digest: "sha256:x", module: "SAFE-THERMAL"},
        abstraction_digest: "sha256:a",
        input_digest: "sha256:i",
        query_digest: "sha256:q",
        engine: %{maude: "3.5.1", ex_maude: "0.4.1"},
        bounds: %{max_depth: 2, max_solutions: 1, deadline_ms: 5_000, max_output_bytes: 1_048_576},
        explored: %{states: 9, rewrites: 31},
        exhaustion: %{basis: :depth_bound, states: nil},
        error: %{code: :exhaustion_timeout}
      }

      map = Result.to_map(result)

      assert map["status"] == "inconclusive" and
               map["exhaustion"] == %{"basis" => "depth_bound", "states" => nil}

      assert map["error"] == %{"code" => "exhaustion_timeout"} and map["counterexample"] == nil
      assert {:ok, _} = Wotex.JSON.encode(map)
    end
  end

  describe "replay" do
    setup do
      lab = start_supervised!({Lab, id: "formal-replay", max_children: 4})

      {:ok, policy} =
        Lab.start_child(
          lab,
          :sessions,
          {Policy, id: :replay, allowed: [:operator], limits: Replay.policy_limits()}
        )

      %{policy: policy}
    end

    test "a safe-model path converges through the real policy", %{policy: policy} do
      {:ok, steps} = Output.path(Fixtures.safe_heating_path())

      assert {:ok, %{status: :converged, steps: 6, divergence: nil, refusals: [], effects: 1}} =
               Replay.run(policy, steps)

      assert %{decisions: [%{status: :dispatched}]} = Policy.records(policy)
    end

    test "a broken-energy counterexample diverges where the policy refuses the stale revision", %{
      policy: policy
    } do
      {:ok, steps} = Output.path(Fixtures.broken_energy_path())

      assert {:ok,
              %{
                status: :diverged,
                steps: 4,
                divergence: divergence,
                refusals: [%{rule: "dispatchHeat", code: :stale_state}],
                effects: 0
              }} = Replay.run(policy, steps)

      assert divergence.expected.heater == :on and divergence.observed.heater == :off and
               divergence.rule == "dispatchHeat"

      assert %{refusals: [%{reason: :stale_state}]} = Policy.records(policy)
    end

    test "a duplicate delivery diverges because the policy dispatches once", %{policy: policy} do
      {:ok, steps} = Output.path(Fixtures.broken_duplicate_path())

      assert {:ok,
              %{
                status: :diverged,
                steps: 4,
                refusals: [%{rule: "redeliver", code: :already_dispatched}],
                effects: 1
              }} = Replay.run(policy, steps)
    end

    test "unknown rules and empty traces are typed errors", %{policy: policy} do
      assert {:error, %Error{code: :unknown_rule}} =
               Replay.run(policy, [
                 %{
                   state: 0,
                   rule: nil,
                   term: "room(comfort, off, off, within, noDecision, 0, 0, 0)"
                 },
                 %{
                   state: 1,
                   rule: "teleport",
                   term: "room(comfort, off, off, within, noDecision, 0, 0, 0)"
                 }
               ])

      assert {:error, %Error{code: :invalid_trace}} = Replay.run(policy, [])

      assert {:error, %Error{code: :invalid_term}} =
               Replay.run(policy, [%{state: 0, rule: nil, term: "init"}])

      assert {:ok, %{status: :diverged, steps: 0}} =
               Replay.run(policy, [
                 %{state: 0, rule: nil, term: "room(hot, off, off, within, noDecision, 0, 0, 0)"}
               ])
    end
  end
end
