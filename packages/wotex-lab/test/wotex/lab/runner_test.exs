defmodule Wotex.Lab.RunnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab
  alias Wotex.Lab.Error
  alias Wotex.Lab.Runner
  alias Wotex.Lab.Runner.{Budgets, Definition, Host, Recording}
  alias Wotex.Lab.Scenario

  alias Wotex.Lab.Test.{
    AlternateComponent,
    BadStartComponent,
    DuplicateCapabilityComponent,
    InvalidManifestComponent,
    InvalidPluginComponent,
    RaisingPluginComponent,
    RoomComponent
  }

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    id = "runner-#{System.unique_integer([:positive])}"
    lab = start_supervised!({Lab, id: id, max_children: 64})
    %{lab: lab, tmp_dir: tmp_dir}
  end

  test "a revision-pinned definition executes in dependency order and cleans owned state",
       context do
    {:ok, host} = host(context, observer: self())

    steps = [
      step("scratch", "room.util", "write", "scratch.txt"),
      step("value", "room.util", "echo", %{"reading" => 21}, ["scratch"])
    ]

    {:ok, definition} =
      definition(steps,
        assertions: [%{"id" => "reading", "step" => "value", "key" => "reading", "equals" => 21}],
        upstream: ["wotex_runtime:WRT.02"]
      )

    {:ok, scenario} = scenario(definition, seed: 42)
    assert :ok = Runner.preflight(scenario, definition, host)
    assert {:ok, run} = Runner.start(scenario, definition, host)
    assert {:ok, status} = Runner.await(run, 2_000)

    assert status.phase == :terminal
    assert status.outcome == :pass
    assert status.cleanup == :ok
    assert status.results["value"] == %{"reading" => 21}
    assert status.recording.events |> Enum.map(& &1.step) == ["scratch", "value"]
    assert Recording.validate(status.recording) == :ok
    assert Recording.to_map(status.recording)["outcome"] == "pass"
    assert_receive {:wotex_lab_run, _, {:phase, :admitted}}
    assert_receive {:wotex_lab_run, _, {:phase, :terminal}}
    assert role_children(context.lab, :things) == []
    assert File.ls!(context.tmp_dir) == []
  end

  test "two concurrent attempts isolate identifiers, component state and work directories",
       context do
    {:ok, cold_host} = host(context, component: [temperature: 19.0])
    {:ok, warm_host} = host(context, component: [temperature: 27.0])

    {:ok, definition} =
      definition([step("temperature", "room.read", "read", %{"property" => "temperature"})])

    {:ok, scenario} = scenario(definition)

    assert {:ok, cold} = Runner.start(scenario, definition, cold_host)
    assert {:ok, warm} = Runner.start(scenario, definition, warm_host)
    assert Runner.status(cold).attempt_id != Runner.status(warm).attempt_id

    assert {:ok, cold_status} = Runner.await(cold, 2_000)
    assert {:ok, warm_status} = Runner.await(warm, 2_000)
    assert cold_status.results["temperature"] == 19.0
    assert warm_status.results["temperature"] == 27.0
    assert cold_status.outcome == :pass
    assert warm_status.outcome == :pass
    assert role_children(context.lab, :things) == []
    assert File.ls!(context.tmp_dir) == []
  end

  test "preflight rejects unsupported capabilities and bad fixtures before starting a child",
       context do
    {:ok, host} = host(context, component: [receiver: self()])

    {:ok, unsupported} = definition([step("remote", "other.read", "read", nil)])
    {:ok, unsupported_scenario} = scenario(unsupported)

    assert {:error, %Error{code: :unsupported, phase: :preflight}} =
             Runner.start(unsupported_scenario, unsupported, host)

    {:ok, bad_fixture} =
      definition([step("echo", "room.util", "echo", nil)],
        fixtures: %{"loopback/thing-description.json" => "sha256:" <> String.duplicate("0", 64)}
      )

    {:ok, fixture_scenario} = scenario(bad_fixture)

    assert {:error, %Error{code: :invalid_fixture_digest}} =
             Runner.start(fixture_scenario, bad_fixture, host)

    refute_receive {:probe_started, _pid}
    assert role_children(context.lab, :things) == []
    assert role_children(context.lab, :sessions) == []
  end

  test "preflight reconstructs structs and rejects forged descriptors, definitions and hosts",
       context do
    {:ok, host} = host(context)
    {:ok, definition} = definition([step("echo", "room.util", "echo", nil)])
    {:ok, scenario} = scenario(definition)

    assert {:error, %Error{code: :invalid_scenario, phase: :preflight}} =
             Runner.preflight(%{scenario | seed: -1}, definition, host)

    forged_step = %{hd(definition.steps) | operation: :system}

    assert {:error, %Error{code: :invalid_step}} =
             Runner.preflight(scenario, %{definition | steps: [forged_step]}, host)

    forged_host = %{host | modules: %{"room.util" => System}}

    assert {:error, %Error{code: :invalid_host}} =
             Runner.preflight(scenario, definition, forged_host)

    assert role_children(context.lab, :things) == []
    assert role_children(context.lab, :sessions) == []
  end

  test "partial component startup is unwound and startup limits are enforced", context do
    {:ok, partial_host} = host(context, component: [startup: :partial, receiver: self()])
    {:ok, definition} = definition([step("echo", "room.util", "echo", nil)])
    {:ok, scenario} = scenario(definition)

    assert {:ok, partial_run} = Runner.start(scenario, definition, partial_host)
    assert_receive {:probe_started, child}
    monitor = Process.monitor(child)

    assert {:ok, %{outcome: :error, reason: %{code: :child_start_failed}}} =
             Runner.await(partial_run, 2_000)

    assert_receive {:DOWN, ^monitor, :process, ^child, _reason}
    assert role_children(context.lab, :things) == []

    {:ok, bounded_host} =
      host(context,
        component: [startup: :two, receiver: self()],
        budgets: %{children_per_role: 1}
      )

    assert {:ok, bounded_run} = Runner.start(scenario, definition, bounded_host)

    assert {:ok, %{outcome: :error, reason: %{code: :children_budget_exhausted}}} =
             Runner.await(bounded_run, 2_000)

    refute_receive {:probe_started, _pid}
    assert role_children(context.lab, :things) == []
  end

  test "cleanup is bounded by its budget and a forced stop is never hidden behind pass",
       context do
    {:ok, host} =
      host(context,
        component: [startup: :stubborn, receiver: self()],
        budgets: %{cleanup_ms: 50, wall_ms: 5_000}
      )

    {:ok, definition} = definition([step("echo", "room.util", "echo", 1)])
    {:ok, scenario} = scenario(definition)
    started_at = System.monotonic_time(:millisecond)
    assert {:ok, run} = Runner.start(scenario, definition, host)
    assert_receive {:stubborn_started, first}
    assert_receive {:stubborn_started, second}
    monitors = Enum.map([first, second], &Process.monitor/1)

    assert {:ok, status} = Runner.await(run, 5_000)
    assert System.monotonic_time(:millisecond) - started_at < 2_000
    assert status.outcome == :error
    assert status.results == %{"echo" => 1}
    assert %{code: :cleanup_failed, details: %{children: failures}} = status.reason
    assert length(failures) == 2
    assert Enum.all?(failures, &(&1.reason == :cleanup_budget_exhausted and &1.forced))

    for monitor <- monitors do
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    end

    assert role_children(context.lab, :things) == []
    assert File.ls!(context.tmp_dir) == []
  end

  test "observer deliveries stop at the queued-delivery budget and end the attempt", context do
    observer = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> Process.exit(observer, :kill) end)

    {:ok, host} =
      host(context, observer: observer, budgets: %{queued_deliveries: 3, wall_ms: 2_000})

    {:ok, definition} =
      definition([
        step("one", "room.util", "echo", 1),
        step("two", "room.util", "echo", 2, ["one"]),
        step("three", "room.util", "echo", 3, ["two"])
      ])

    {:ok, scenario} = scenario(definition)
    assert {:ok, run} = Runner.start(scenario, definition, host)
    assert {:ok, status} = Runner.await(run, 2_000)

    assert status.outcome == :error
    assert status.reason == %{code: :delivery_budget_exhausted}
    assert status.cleanup == :ok
    assert {:messages, messages} = Process.info(observer, :messages)
    assert length(messages) == 3

    assert Enum.map(messages, fn {:wotex_lab_run, _, event} -> event end) == [
             {:phase, :admitted},
             {:phase, :starting},
             {:phase, :running}
           ]

    assert role_children(context.lab, :things) == []
    assert File.ls!(context.tmp_dir) == []

    {:ok, drained_host} = host(context, observer: self(), budgets: %{queued_deliveries: 16})
    assert {:ok, drained_run} = Runner.start(scenario, definition, drained_host)
    assert {:ok, %{outcome: :pass}} = Runner.await(drained_run, 2_000)
    assert_receive {:wotex_lab_run, _, {:terminal, :pass}}
  end

  test "step, ingress and result limits become explicit failures", context do
    steps = [
      step("first", "room.util", "echo", 1),
      step("second", "room.util", "echo", 2, ["first"])
    ]

    {:ok, definition} = definition(steps)
    {:ok, scenario} = scenario(definition)
    {:ok, step_host} = host(context, budgets: %{max_steps: 1})
    assert {:ok, run} = Runner.start(scenario, definition, step_host)
    assert {:ok, %{outcome: :error, reason: %{code: :step_budget_exhausted}}} = Runner.await(run)

    {:ok, ingress_definition} =
      definition([step("large-input", "room.util", "echo", String.duplicate("x", 256))])

    {:ok, ingress_scenario} = scenario(ingress_definition)
    {:ok, ingress_host} = host(context, budgets: %{ingress_bytes: 100})
    assert {:ok, ingress_run} = Runner.start(ingress_scenario, ingress_definition, ingress_host)
    assert {:ok, ingress_status} = Runner.await(ingress_run)
    assert ingress_status.outcome == :fail
    assert ingress_status.errors["large-input"].code == :ingress_budget_exhausted

    {:ok, result_definition} = definition([step("large-output", "room.util", "big", 256)])
    {:ok, result_scenario} = scenario(result_definition)
    assert {:ok, result_run} = Runner.start(result_scenario, result_definition, ingress_host)
    assert {:ok, result_status} = Runner.await(result_run)
    assert result_status.outcome == :fail
    assert result_status.errors["large-output"].code == :ingress_budget_exhausted
  end

  test "callback raises, throws, exits and invalid returns are normalized without secrets",
       context do
    {:ok, host} = host(context)

    expected = %{
      "raise" => :component_raised,
      "throw" => :component_threw,
      "exit" => :component_exited,
      "invalid_return" => :invalid_component_return
    }

    for {fault, code} <- expected do
      {:ok, definition} =
        definition([step("fault", "room.util", "echo", "secret-sentinel")],
          faults: %{"fault" => fault}
        )

      {:ok, scenario} = scenario(definition)
      assert {:ok, run} = Runner.start(scenario, definition, host)
      assert {:ok, status} = Runner.await(run)
      assert status.outcome == :fail
      assert status.errors["fault"].code == code
      refute inspect(status.errors) =~ "secret-sentinel"
    end

    {:ok, definition} = definition([step("error", "room.util", "fail", nil)])
    {:ok, scenario} = scenario(definition)
    assert {:ok, run} = Runner.start(scenario, definition, host)
    assert {:ok, status} = Runner.await(run)
    assert status.outcome == :fail
    assert status.errors["error"] == %{code: :step_failed, phase: :running}
  end

  test "wall timeout, cancellation, duplicate stop and late results stay terminal", context do
    {:ok, timeout_host} = host(context, observer: self(), budgets: %{wall_ms: 25})

    {:ok, hanging} =
      definition([step("hang", "room.util", "echo", nil)], faults: %{"hang" => "hang"})

    {:ok, hanging_scenario} = scenario(hanging)
    assert {:ok, timed_run} = Runner.start(hanging_scenario, hanging, timeout_host)
    assert {:ok, timed_status} = Runner.await(timed_run, 2_000)
    assert timed_status.outcome == :timeout
    assert timed_status.reason.code == :wall_budget_exhausted

    {:ok, cancel_host} = host(context, observer: self(), budgets: %{wall_ms: 2_000})
    {:ok, sleeping} = definition([step("late", "room.util", "sleep", 250)])
    {:ok, sleeping_scenario} = scenario(sleeping)
    assert {:ok, cancelled_run} = Runner.start(sleeping_scenario, sleeping, cancel_host)
    assert_receive {:wotex_lab_run, _, {:phase, :running}}, 1_000
    assert :ok = Runner.cancel(cancelled_run)
    assert :ok = Runner.cancel(cancelled_run)
    assert {:ok, cancelled} = Runner.await(cancelled_run)
    assert cancelled.outcome == :cancelled
    Process.sleep(300)
    assert Runner.status(cancelled_run) == cancelled
    assert role_children(context.lab, :things) == []
    assert File.ls!(context.tmp_dir) == []
  end

  test "observer death aborts the attempt and forced kill is recorded", context do
    observer = spawn(fn -> Process.sleep(:infinity) end)
    {:ok, host} = host(context, observer: observer, budgets: %{wall_ms: 2_000})

    {:ok, hanging} =
      definition([step("hang", "room.util", "echo", nil)], faults: %{"hang" => "hang"})

    {:ok, scenario} = scenario(hanging)
    assert {:ok, receiver_run} = Runner.start(scenario, hanging, host)
    assert eventually(fn -> Runner.status(receiver_run).phase == :running end)
    Process.exit(observer, :kill)
    assert {:ok, receiver_status} = Runner.await(receiver_run)
    assert receiver_status.outcome == :error
    assert receiver_status.reason.code == :receiver_down

    second_observer = spawn(fn -> Process.sleep(:infinity) end)
    {:ok, kill_host} = host(context, observer: second_observer, budgets: %{wall_ms: 2_000})
    assert {:ok, killed_run} = Runner.start(scenario, hanging, kill_host)
    assert eventually(fn -> Runner.status(killed_run).phase == :running end)
    assert :ok = Runner.kill(killed_run)
    assert {:ok, killed_status} = Runner.await(killed_run)
    assert killed_status.outcome == :error
    assert killed_status.forced
    assert killed_status.recording.forced
    assert killed_status.reason.code == :forced_kill
    Process.exit(second_observer, :kill)
  end

  test "replay consumes the pinned version and seed and detects divergence", context do
    {:ok, host} = host(context)
    {:ok, definition} = definition([step("seed", "room.util", "seed", nil)])
    {:ok, scenario} = scenario(definition, seed: 123)
    assert {:ok, run} = Runner.start(scenario, definition, host)
    assert {:ok, original} = Runner.await(run)

    assert {:ok, %{comparison: {:reproduced, 1}, status: replay}} =
             Runner.replay(original.recording, definition, host)

    assert replay.attempt_id != original.attempt_id
    assert replay.results == original.results

    changed = %{original.recording | revision: "changed"}

    assert {:diverged, %{reason: :different_definition}} =
             Recording.compare(original.recording, changed)

    forged = %{original.recording | seed: -1}
    assert {:error, %Error{code: :invalid_recording}} = Runner.replay(forged, definition, host)
  end

  test "definition and host constructors enforce closed bounded data", context do
    invalid_steps = [
      [step("same", "room.util", "echo", nil), step("same", "room.util", "echo", nil)],
      [step("unknown", "room.util", "echo", nil, ["missing"])],
      [step("self", "room.util", "echo", nil, ["self"])],
      [Map.put(step("extra", "room.util", "echo", nil), "module", System)],
      [step("atom", "room.util", "echo", :not_json)]
    ]

    for steps <- invalid_steps do
      assert {:error, %Error{phase: :preflight}} = definition(steps)
    end

    assert {:error, %Error{code: :invalid_fixture_digest}} =
             definition([step("echo", "room.util", "echo", nil)],
               fixtures: %{"../secret" => "sha256:" <> String.duplicate("0", 64)}
             )

    assert {:error, %Error{code: :invalid_options}} =
             Host.new(
               modules: [RoomComponent],
               instance: context.lab,
               dependency_versions: %{"wotex_runtime" => "0.1.0"},
               secret: "sentinel"
             )

    assert {:error, %Error{code: :dependency_mismatch}} =
             Host.new(modules: [RoomComponent], instance: context.lab)

    assert {:error, %Error{code: :invalid_host}} =
             Host.new(
               modules: [RoomComponent],
               instance: context.lab,
               work_root: "relative",
               dependency_versions: %{"wotex_runtime" => "0.1.0"}
             )

    assert {:error, %Error{code: :invalid_host}} =
             Host.new(
               modules: [{RoomComponent, [attempt_id: "forged"]}],
               instance: context.lab,
               dependency_versions: %{"wotex_runtime" => "0.1.0"}
             )

    assert {:error, %Error{code: :invalid_budget}} = Budgets.new(%{wall_ms: 0})
    assert {:error, %Error{code: :budget_ceiling}} = Budgets.new(%{wall_ms: 600_001})
    assert Budgets.defaults().queued_deliveries == 1_024
    assert Budgets.defaults().reconnect_attempts == 100
    assert Budgets.defaults().cleanup_ms == 5_000
    assert Budgets.ceilings().wall_ms == 600_000
    assert {:ok, %{wall_ms: 50}} = Budgets.new(wall_ms: 50)
    assert {:error, %Error{code: :invalid_budget}} = Budgets.new(:invalid)
    assert {:error, %Error{code: :invalid_budget}} = Budgets.new(%{unknown: 1})
  end

  test "definition validation rejects every malformed data coordinate" do
    changes = [
      nil,
      [id: "room-run", revision: "v1", capabilities: ["room.util"], steps: []],
      definition_opts([step("BAD", "room.util", "echo", nil)]),
      definition_opts([step("step", "BAD CAP", "echo", nil)]),
      definition_opts([step("step", "room.util", "", nil)]),
      definition_opts([step("step", "room.util", <<255>>, nil)]),
      definition_opts([step("step", "room.util", "echo", nil, ["BAD DEP"])]),
      definition_opts([step("step", "room.util", "echo", nil, ["dep", "dep"])]),
      definition_opts([step("step", "room.util", "echo", nil)], capabilities: []),
      definition_opts([step("step", "room.util", "echo", nil)], capabilities: :invalid),
      definition_opts([step("step", "room.util", "echo", nil)], fixtures: []),
      definition_opts([step("step", "room.util", "echo", nil)], assertions: :invalid),
      definition_opts([step("step", "room.util", "echo", nil)],
        assertions: [%{"id" => "bad", "step" => "step"}]
      ),
      definition_opts([step("step", "room.util", "echo", nil)], faults: []),
      definition_opts([step("step", "room.util", "echo", nil)],
        faults: %{"step" => "unknown"}
      ),
      definition_opts([step("step", "room.util", "echo", nil)], upstream: :invalid),
      definition_opts([step("step", "room.util", "echo", nil)], upstream: [<<255>>])
    ]

    for input <- changes do
      assert {:error, %Error{phase: :preflight}} = Definition.new(input)
    end

    {:ok, json_definition} =
      definition([
        step("json", "room.util", "echo", [1.5, true, nil, %{"nested" => "value"}])
      ])

    assert {:ok, ^json_definition} = Definition.revalidate(json_definition)
    assert {:error, %Error{code: :invalid_definition}} = Definition.revalidate(:invalid)

    assert {:error, %Error{code: :invalid_definition}} =
             Definition.revalidate(%{json_definition | steps: :invalid})
  end

  test "host validation rejects malformed plugins, duplicate claims and dead resources", context do
    versions = %{"wotex_runtime" => "0.1.0"}

    cases = [
      {Host.new(nil), :invalid_host},
      {Host.new(modules: :invalid, instance: context.lab), :invalid_host},
      {Host.new(modules: [:not_loaded_component], instance: context.lab), :invalid_host},
      {Host.new(modules: [String], instance: context.lab), :invalid_host},
      {Host.new(modules: [InvalidPluginComponent], instance: context.lab), :invalid_plugin},
      {Host.new(modules: [InvalidManifestComponent], instance: context.lab),
       :invalid_plugin_manifest},
      {Host.new(modules: [RaisingPluginComponent], instance: context.lab), :invalid_plugin},
      {Host.new(
         modules: [RoomComponent, AlternateComponent],
         instance: context.lab,
         dependency_versions: versions
       ), :duplicate_plugin},
      {Host.new(
         modules: [RoomComponent, DuplicateCapabilityComponent],
         instance: context.lab,
         dependency_versions: versions
       ), :duplicate_capability},
      {Host.new(
         modules: [{RoomComponent, [temperature: 1, temperature: 2]}],
         instance: context.lab,
         dependency_versions: versions
       ), :invalid_host},
      {Host.new(modules: [], instance: :invalid), :invalid_host},
      {Host.new(modules: [], instance: context.lab, observer: :invalid), :invalid_host},
      {Host.new(modules: [], instance: context.lab, seed: -1), :invalid_host},
      {Host.new(modules: [], instance: context.lab, clock: :invalid), :invalid_host},
      {Host.new(modules: [], instance: context.lab, dependency_versions: []), :invalid_host},
      {Host.new(modules: [], instance: context.lab, dependency_versions: %{1 => "v"}),
       :invalid_host}
    ]

    for {result, code} <- cases do
      assert {:error, %Error{code: ^code}} = result
    end

    dead = spawn(fn -> :ok end)
    assert eventually(fn -> not Process.alive?(dead) end)
    assert {:error, %Error{code: :invalid_host}} = Host.new(modules: [], instance: dead)

    assert {:error, %Error{code: :invalid_host}} =
             Host.new(modules: [], instance: context.lab, observer: dead)

    {:ok, valid_host} = host(context)
    assert {:ok, rebuilt_host} = Host.revalidate(valid_host)
    assert Host.capabilities(rebuilt_host) == ["room.act", "room.read", "room.util"]
    assert {:error, %Error{code: :invalid_host}} = Host.revalidate(:invalid)

    assert {:error, %Error{code: :invalid_host}} =
             Host.revalidate(%{valid_host | configs: :invalid})
  end

  test "component child-spec failures are bounded and normalized", context do
    {:ok, definition} =
      definition([step("start", "bad.start", "run", nil)], capabilities: ["bad.start"])

    {:ok, scenario} = scenario(definition)

    for {failure, code} <- [
          invalid: :invalid_child_specs,
          raise: :child_specs_raised,
          throw: :child_specs_failed
        ] do
      {:ok, host} =
        Host.new(
          modules: [{BadStartComponent, [failure: failure]}],
          instance: context.lab,
          work_root: context.tmp_dir
        )

      assert {:ok, run} = Runner.start(scenario, definition, host)
      assert {:ok, status} = Runner.await(run)
      assert status.outcome == :error
      assert status.reason.code == code
    end
  end

  test "failed dependencies, assertions and killed workers fail closed", context do
    {:ok, host} = host(context, observer: self(), budgets: %{wall_ms: 2_000})

    {:ok, dependent} =
      definition([
        step("first", "room.util", "fail", nil),
        step("second", "room.util", "echo", 2, ["first"])
      ])

    {:ok, dependent_scenario} = scenario(dependent)
    assert {:ok, dependent_run} = Runner.start(dependent_scenario, dependent, host)
    assert {:ok, dependent_status} = Runner.await(dependent_run)
    assert dependent_status.outcome == :fail
    assert dependent_status.errors["second"].code == :dependency_failed

    {:ok, asserted} =
      definition([step("value", "room.util", "echo", 1)],
        assertions: [%{"id" => "mismatch", "step" => "value", "equals" => 2}]
      )

    {:ok, asserted_scenario} = scenario(asserted)
    assert {:ok, asserted_run} = Runner.start(asserted_scenario, asserted, host)
    assert {:ok, %{outcome: :fail, errors: errors}} = Runner.await(asserted_run)
    assert errors == %{}

    {:ok, sleeping} = definition([step("worker", "room.util", "sleep", 1_000)])
    {:ok, sleeping_scenario} = scenario(sleeping)
    assert {:ok, worker_run} = Runner.start(sleeping_scenario, sleeping, host)
    assert eventually(fn -> Runner.status(worker_run).phase == :running end)
    {ref, _, worker} = :sys.get_state(worker_run).worker
    send(worker_run, {:step_result, Runner.status(worker_run).attempt_id, "wrong", ref, {:ok, 1}})
    send(worker_run, :unrelated)
    Process.exit(worker, :kill)
    assert {:ok, worker_status} = Runner.await(worker_run)
    assert worker_status.outcome == :fail
    assert worker_status.errors["worker"].code == :component_killed
  end

  test "await timeout, coordinator death and unusable work roots still clean children", context do
    {:ok, host} = host(context, budgets: %{wall_ms: 2_000})

    {:ok, hanging} =
      definition([step("hang", "room.util", "echo", nil)], faults: %{"hang" => "hang"})

    {:ok, scenario} = scenario(hanging)
    assert {:ok, run} = Runner.start(scenario, hanging, host)
    assert {:error, :timeout} = Runner.await(run, 1)
    assert :ok = Runner.cancel(run)

    assert {:ok, dying_run} = Runner.start(scenario, hanging, host)
    waiter = Task.async(fn -> Runner.await(dying_run, 2_000) end)
    assert eventually(fn -> :sys.get_state(dying_run).waiters != [] end)
    GenServer.stop(dying_run, :shutdown)
    assert Task.await(waiter) == {:error, :timeout}

    blocked_root = Path.join(context.tmp_dir, "regular-file")
    :ok = File.write(blocked_root, "not a directory")

    {:ok, blocked_host} =
      Host.new(
        modules: [{RoomComponent, []}],
        instance: context.lab,
        work_root: blocked_root,
        dependency_versions: %{"wotex_runtime" => "0.1.0"}
      )

    {:ok, simple} = definition([step("echo", "room.util", "echo", nil)])
    {:ok, simple_scenario} = scenario(simple)
    assert {:ok, blocked_run} = Runner.start(simple_scenario, simple, blocked_host)
    assert {:ok, blocked_status} = Runner.await(blocked_run)
    assert blocked_status.outcome == :error
    assert blocked_status.reason.code == :work_directory_unavailable
    assert role_children(context.lab, :things) == []
  end

  test "descriptor agreement and attempt admission failures are explicit", context do
    {:ok, host} = host(context)
    {:ok, definition} = definition([step("one", "room.util", "echo", 1)])

    assert {:error, %Error{code: :invalid_run}} = Runner.preflight(nil, definition, host)

    {:ok, other_id} =
      Scenario.new(
        id: "other-run",
        title: "Other",
        capabilities: definition.capabilities,
        seed: 1,
        max_steps: 1
      )

    assert {:error, %Error{code: :descriptor_mismatch}} =
             Runner.preflight(other_id, definition, host)

    {:ok, other_capability} =
      Scenario.new(
        id: definition.id,
        title: "Other",
        capabilities: ["room.read"],
        seed: 1,
        max_steps: 1
      )

    assert {:error, %Error{code: :descriptor_mismatch}} =
             Runner.preflight(other_capability, definition, host)

    {:ok, two_steps} =
      definition([
        step("one", "room.util", "echo", 1),
        step("two", "room.util", "echo", 2)
      ])

    {:ok, too_small} =
      Scenario.new(
        id: two_steps.id,
        title: "Small",
        capabilities: two_steps.capabilities,
        seed: 1,
        max_steps: 1
      )

    assert {:error, %Error{code: :step_budget_exhausted}} =
             Runner.preflight(too_small, two_steps, host)

    assert {:error, %Error{code: :invalid_recording}} = Runner.replay(nil, nil, nil)
    assert {:error, %Error{code: :invalid_recording}} = Runner.replay(nil, definition, host)

    :ok = Supervisor.terminate_child(context.lab, :sessions)
    {:ok, scenario} = scenario(definition)

    assert {:error, %Error{code: :supervisor_unavailable}} =
             Runner.start(scenario, definition, host)
  end

  test "recording comparisons distinguish every logical divergence", context do
    {:ok, host} = host(context)
    {:ok, definition} = definition([step("value", "room.util", "echo", 1)])
    {:ok, scenario} = scenario(definition)
    {:ok, run} = Runner.start(scenario, definition, host)
    {:ok, status} = Runner.await(run)
    recording = status.recording

    assert {:diverged, %{reason: :different_seed}} =
             Recording.compare(recording, %{recording | seed: recording.seed + 1})

    assert {:diverged, %{reason: :different_version}} =
             Recording.compare(recording, %{recording | lab_version: "different"})

    assert {:diverged, %{reason: :different_outcome}} =
             Recording.compare(recording, %{recording | outcome: :fail})

    [event] = recording.events
    changed_event = %{event | digest: "sha256:" <> String.duplicate("0", 64)}

    assert {:diverged, %{reason: :step, index: 0}} =
             Recording.compare(recording, %{recording | events: [changed_event]})

    assert {:diverged, %{reason: :length, index: 0}} =
             Recording.compare(recording, %{recording | events: []})

    assert {:error, %Error{code: :invalid_recording}} = Recording.validate(%{})

    assert {:error, %Error{code: :invalid_recording}} =
             Recording.validate(%{recording | events: [:invalid]})
  end

  defp host(context, opts \\ []) do
    Host.new(
      modules: [{RoomComponent, Keyword.get(opts, :component, [])}],
      instance: context.lab,
      observer: Keyword.get(opts, :observer),
      budgets: Keyword.get(opts, :budgets, %{}),
      work_root: context.tmp_dir,
      dependency_versions: %{"wotex_runtime" => "0.1.0"}
    )
  end

  defp definition(steps, opts \\ []) do
    capabilities = steps |> Enum.map(& &1["capability"]) |> Enum.filter(&is_binary/1) |> Enum.uniq()

    Definition.new(
      id: Keyword.get(opts, :id, "room-run"),
      revision: Keyword.get(opts, :revision, "fixture-v1"),
      fixtures: Keyword.get(opts, :fixtures, %{}),
      capabilities: Keyword.get(opts, :capabilities, capabilities),
      steps: steps,
      assertions: Keyword.get(opts, :assertions, []),
      faults: Keyword.get(opts, :faults, %{}),
      upstream: Keyword.get(opts, :upstream, [])
    )
  end

  defp definition_opts(steps, overrides \\ []) do
    [
      id: "room-run",
      revision: "fixture-v1",
      fixtures: Keyword.get(overrides, :fixtures, %{}),
      capabilities: Keyword.get(overrides, :capabilities, ["room.util"]),
      steps: steps,
      assertions: Keyword.get(overrides, :assertions, []),
      faults: Keyword.get(overrides, :faults, %{}),
      upstream: Keyword.get(overrides, :upstream, [])
    ]
  end

  defp scenario(definition, opts \\ []) do
    Scenario.new(
      id: definition.id,
      title: "Room runner acceptance",
      capabilities: definition.capabilities,
      seed: Keyword.get(opts, :seed, 7),
      max_steps: max(length(definition.steps), 1)
    )
  end

  defp step(id, capability, operation, input, dependencies \\ []) do
    %{
      "id" => id,
      "capability" => capability,
      "operation" => operation,
      "input" => input,
      "depends_on" => dependencies
    }
  end

  defp role_children(lab, role) do
    {^role, supervisor, :supervisor, _} =
      List.keyfind(Supervisor.which_children(lab), role, 0)

    DynamicSupervisor.which_children(supervisor)
  end

  defp eventually(fun, attempts \\ 100)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(5)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_, 0), do: false
end
