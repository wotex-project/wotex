defmodule WotexLabWorkbench.BeamlensIntegrationTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Telemetry

  alias WotexLabWorkbench.Investigation.{
    BeamlensSupervisor,
    Broker,
    Config,
    ContextStore,
    OperatorRunner,
    Provider,
    Skill
  }

  alias WotexLabWorkbench.Application, as: WorkbenchApplication
  alias WotexLabWorkbench.Observability.{Sampler, Supervisor}

  @registry %{
    primary: "Test",
    clients: [
      %{
        name: "Test",
        provider: "openai-generic",
        options: %{base_url: "http://127.0.0.1:1/v1", model: "test"}
      }
    ]
  }
  @capability "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  setup do
    Application.put_env(
      :wotex_lab_workbench,
      :beamlens_operator_runner,
      WotexLabWorkbench.FakeInvestigationRunner
    )

    Application.put_env(:wotex_lab_workbench, :fake_investigation_owner, self())

    Application.put_env(
      :wotex_lab_workbench,
      :beamlens_codex_runner,
      WotexLabWorkbench.FakeCodexRunner
    )

    Application.put_env(
      :wotex_lab_workbench,
      :beamlens_ollama_runner,
      WotexLabWorkbench.FakeOllamaRunner
    )

    on_exit(fn ->
      for key <- [
            :beamlens_operator_runner,
            :beamlens_codex_runner,
            :beamlens_ollama_runner,
            :beamlens_timeout_ms,
            :fake_investigation_owner,
            :fake_investigation_result
          ],
          do: Application.delete_env(:wotex_lab_workbench, key)
    end)

    :ok
  end

  test "activation starts only the custom skill with real eight-turn limits" do
    start_tree()
    coordinator = :sys.get_state(Beamlens.Coordinator)
    assert coordinator.max_iterations == 8
    assert coordinator.skills == [Skill]

    assert [{operator_pid, _value}] = Registry.lookup(Beamlens.OperatorRegistry, Skill)
    operator = :sys.get_state(operator_pid)
    assert operator.max_iterations == BeamlensSupervisor.max_iterations()
    assert operator.skill == Skill
    assert Beamlens.Supervisor.registered_skills() == [Skill]

    assert Process.whereis(Beamlens.Skill.Logger.LogStore)
    refute Process.whereis(Beamlens.Skill.Exception.ExceptionStore)
    refute Process.whereis(Beamlens.Skill.VmEvents.EventStore)
  end

  test "custom callbacks are closed, JSON-safe and server-scoped" do
    start_tree()
    callbacks = Skill.callbacks()

    assert Map.keys(callbacks) |> Enum.sort() ==
             ~w(lab_compare_runs lab_metric_catalogue lab_metric_query lab_run_summary)

    # BeamLens 0.3.1 adds these two callbacks at execution time. Keeping the
    # assertion explicit prevents the trusted-host disclosure from being
    # confused with the narrower custom skill contract.
    assert Map.keys(Beamlens.Skill.Base.callbacks()) |> Enum.sort() ==
             ~w(get_current_time get_node_info)

    catalogue = callbacks["lab_metric_catalogue"].("nx")
    assert catalogue.count > 0
    assert Enum.all?(catalogue.metrics, &(&1.group == "nx"))
    assert {:ok, _json} = Jason.encode(catalogue)

    assert :ok = ContextStore.put(%{id: "current", score: 2}, %{id: "baseline", score: 1})

    assert %{available: true, summary: %{"id" => "current"}} =
             callbacks["lab_run_summary"].("current")

    assert %{available: true, current: %{digest: "sha256:" <> _}} =
             callbacks["lab_compare_runs"].()

    :telemetry.execute([:wotex, :lab, :nx, :encode, :stop], %{duration: 1_000}, %{
      profile: :test,
      outcome: :ok
    })

    assert {:ok, _snapshot} = Sampler.sample_now()
    answer = callbacks["lab_metric_query"].("nx_operations_total", "sum")
    assert answer["source"] == "ets_history"
    assert answer["instance"] == "workbench"
    assert answer["digest"] =~ "sha256:"

    denied = callbacks["lab_metric_query"].("not_a_metric", "sum")
    assert denied == %{available: false, error: "invalid_request"}

    for _index <- 1..3, do: callbacks["lab_metric_catalogue"].("all")

    assert callbacks["lab_metric_catalogue"].("all") == %{
             available: false,
             error: "callback_output_budget_exhausted"
           }
  end

  test "context is bounded and cleared on cancellation while BeamLens processes are replaced" do
    start_tree()
    handler = "beamlens-broker-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler,
        [
          [:wotex, :lab, :metrics, :investigation, :start],
          [:wotex, :lab, :metrics, :investigation, :stop],
          [:wotex, :lab, :metrics, :investigation, :measurement]
        ],
        &Telemetry.forward/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    coordinator_before = Process.whereis(Beamlens.Coordinator)
    [{operator_before, _value}] = Registry.lookup(Beamlens.OperatorRegistry, Skill)

    assert {:ok, request} = Broker.ask("explain the current run", run: %{id: "run-1"})

    assert_receive {:wotex_lab_telemetry, [:wotex, :lab, :metrics, :investigation, :start],
                    %{monotonic_time: _, system_time: _}, %{profile: :other}},
                   1_000

    assert_receive {:fake_investigation_started, worker, "explain the current run"}, 1_000
    assert {:error, :investigation_busy} = Broker.ask("second request")
    assert :ok = Broker.cancel(request)
    assert_receive {:investigation, ^request, {:error, :investigation_cancelled}}, 1_000
    refute Process.alive?(worker)
    assert ContextStore.get("current") == %{available: false, reason: "run_context_not_supplied"}

    coordinator_after = Process.whereis(Beamlens.Coordinator)
    [{operator_after, _value}] = Registry.lookup(Beamlens.OperatorRegistry, Skill)
    refute coordinator_after == coordinator_before
    refute operator_after == operator_before
    assert Broker.status().cancelled == 1

    assert_receive {:wotex_lab_telemetry, [:wotex, :lab, :metrics, :investigation, :stop],
                    %{duration: duration}, %{outcome: :rejected, profile: :other}},
                   1_000

    assert duration >= 0

    assert_receive {:wotex_lab_telemetry, [:wotex, :lab, :metrics, :investigation, :measurement],
                    %{context_bytes: context_bytes, tool_calls: 0}, %{profile: :other}},
                   1_000

    assert context_bytes > 0
  end

  test "broker and context admission reject malformed input and normalize completion" do
    start_tree()

    assert {:error, :invalid_prompt} = Broker.ask(12)
    assert {:error, :invalid_prompt} = Broker.ask("   ")
    assert {:error, :invalid_context} = Broker.ask("valid", run: %{}, run: %{})
    assert {:error, :invalid_context} = Broker.ask("valid", other: %{})
    assert {:error, :unknown_investigation} = Broker.cancel(:not_a_reference)
    assert {:error, :unknown_investigation} = Broker.cancel(make_ref())

    assert {:error, :invalid_context} = ContextStore.put([], nil)

    assert {:error, :context_too_large} =
             ContextStore.put(%{text: String.duplicate("x", 8_192)}, nil)

    assert :ok = ContextStore.put(%{id: "current"}, nil)
    assert ContextStore.get("invalid") == %{available: false, reason: "unknown_run_selector"}
    assert ContextStore.compare().available == false
    assert ContextStore.usage().tool_calls == 0
    assert ContextStore.charge(%{small: true}) == %{small: true}
    assert ContextStore.usage().tool_calls == 1

    Application.put_env(:wotex_lab_workbench, :fake_investigation_result, {:ok, [%{type: :notice}]})
    assert {:ok, request} = Broker.ask("finish")

    assert_receive {:investigation, ^request, {:ok, %{notifications: [%{"type" => "notice"}]}}},
                   1_000

    assert Broker.status().completed == 1
    refute Broker.status().running
  end

  test "timeout and owner death terminate work instead of detaching callers" do
    Application.put_env(:wotex_lab_workbench, :beamlens_timeout_ms, 30)
    start_tree()
    assert {:ok, request} = Broker.ask("time out")
    assert_receive {:fake_investigation_started, worker, "time out"}, 1_000
    assert_receive {:investigation, ^request, {:error, :investigation_timeout}}, 1_000
    refute Process.alive?(worker)
    assert Broker.status().timed_out == 1

    parent = self()

    owner =
      spawn(fn ->
        send(parent, {:owner_request, Broker.ask("owner exits")})
        Process.sleep(:infinity)
      end)

    assert_receive {:owner_request, {:ok, _request}}, 1_000
    assert_receive {:fake_investigation_started, second_worker, "owner exits"}, 1_000
    monitor = Process.monitor(second_worker)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^second_worker, _reason}, 1_000
    refute Broker.status().running
  end

  test "bridge configuration refuses remote and credential-bearing URLs" do
    original = Application.fetch_env!(:wotex_lab_workbench, :beamlens_bridge_url)
    original_provider = Application.fetch_env!(:wotex_lab_workbench, :beamlens_provider)

    on_exit(fn ->
      Application.put_env(:wotex_lab_workbench, :beamlens_bridge_url, original)
      Application.put_env(:wotex_lab_workbench, :beamlens_provider, original_provider)
    end)

    assert Config.loopback_url?("http://127.0.0.1:4000/api/internal/beamlens/v1")
    assert Config.loopback_url?("http://localhost:4000/api/internal/beamlens/v1")
    refute Config.loopback_url?("https://example.test/api")
    refute Config.loopback_url?("http://user:secret@127.0.0.1:4000/api")

    Application.put_env(:wotex_lab_workbench, :beamlens_provider, :codex_then_ollama)
    assert {:ok, %{capability: capability, registry: registry}} = Config.client_registry()
    assert byte_size(capability) == 43
    assert get_in(registry, [:clients, Access.at(0), :options, :api_key]) == capability

    Application.put_env(:wotex_lab_workbench, :beamlens_bridge_url, "https://example.test")
    assert {:error, :invalid_bridge_url} = Config.client_registry()

    Application.put_env(:wotex_lab_workbench, :beamlens_bridge_url, original)
    Application.put_env(:wotex_lab_workbench, :beamlens_provider, :none)
    assert {:error, :provider_not_selected} = Config.client_registry()
  end

  test "direct activation refuses BeamLens without bounded history" do
    assert {:error, %Wotex.Lab.Error{code: :beamlens_requires_history}} =
             Supervisor.start_link(history: false, beamlens: beamlens(@registry))
  end

  test "application activation requires history and an explicit provider" do
    keys = [:beamlens_enabled, :beamlens_provider, :promex_enabled, :metrics_history_enabled]
    saved = Map.new(keys, &{&1, Application.get_env(:wotex_lab_workbench, &1)})

    on_exit(fn ->
      Enum.each(saved, fn
        {key, nil} -> Application.delete_env(:wotex_lab_workbench, key)
        {key, value} -> Application.put_env(:wotex_lab_workbench, key, value)
      end)
    end)

    Application.put_env(:wotex_lab_workbench, :beamlens_enabled, true)
    Application.put_env(:wotex_lab_workbench, :promex_enabled, true)
    Application.put_env(:wotex_lab_workbench, :metrics_history_enabled, false)

    assert {:error, :beamlens_requires_metrics_history} =
             WorkbenchApplication.start(:normal, [])

    Application.put_env(:wotex_lab_workbench, :metrics_history_enabled, true)
    Application.put_env(:wotex_lab_workbench, :beamlens_provider, :none)

    assert {:error, :provider_not_selected} =
             WorkbenchApplication.start(:normal, [])
  end

  test "real BeamLens/BAML reaches only the loopback provider bridge" do
    saved_enabled = Application.get_env(:wotex_lab_workbench, :beamlens_enabled)
    saved_provider = Application.get_env(:wotex_lab_workbench, :beamlens_provider)
    saved_result = Application.get_env(:wotex_lab_workbench, :fake_codex_result)

    Application.put_env(:wotex_lab_workbench, :beamlens_enabled, true)
    Application.put_env(:wotex_lab_workbench, :beamlens_provider, :codex_then_ollama)

    Application.put_env(
      :wotex_lab_workbench,
      :fake_codex_result,
      {:ok, ~s({"intent":"done"}),
       %{provider: :codex, model: "fake-codex", plan_type: "test", quota: %{used_percent: 1}}}
    )

    on_exit(fn ->
      restore_env(:beamlens_enabled, saved_enabled)
      restore_env(:beamlens_provider, saved_provider)
      restore_env(:fake_codex_result, saved_result)
    end)

    bandit =
      start_supervised!(
        {Bandit,
         plug: WotexLabWorkbenchWeb.Endpoint, ip: {127, 0, 0, 1}, port: 0, startup_log: false}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(bandit)

    registry =
      @registry
      |> put_in(
        [:clients, Access.at(0), :options, :base_url],
        "http://127.0.0.1:#{port}/api/internal/beamlens/v1"
      )
      |> put_in(
        [:clients, Access.at(0), :options, :model],
        "wotex-lab-investigation"
      )

    Application.put_env(:wotex_lab_workbench, :beamlens_operator_runner, OperatorRunner)
    start_supervised!({Supervisor, history: [interval_ms: 60_000], beamlens: beamlens(registry)})
    room = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> Process.exit(room, :kill) end)

    assert {:ok, request} = Broker.ask("finish now", run: %{id: "run-e2e"}, room: room)
    assert_receive {:investigation, ^request, {:ok, %{notifications: []}}}, 10_000

    assert %{provider: :codex, model: "fake-codex"} =
             Provider.status()
  end

  defp start_tree do
    start_supervised!({Supervisor, history: [interval_ms: 60_000], beamlens: beamlens(@registry)})
  end

  defp beamlens(registry) do
    registry = put_in(registry, [:clients, Access.at(0), :options, :api_key], @capability)
    %{capability: @capability, registry: registry}
  end

  defp restore_env(key, nil), do: Application.delete_env(:wotex_lab_workbench, key)
  defp restore_env(key, value), do: Application.put_env(:wotex_lab_workbench, key, value)
end
