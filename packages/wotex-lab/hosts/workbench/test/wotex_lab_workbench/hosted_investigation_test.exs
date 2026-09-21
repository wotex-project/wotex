defmodule WotexLabWorkbench.HostedInvestigationTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Mix.Tasks.Wotex.Lab.Hosted.Artifact

  alias WotexLabWorkbench.Investigation.{
    BridgeAuthorization,
    HostedBroker
  }

  alias WotexLabWorkbenchWeb.Endpoint

  @tag timeout: 180_000
  test "a verified one-request VM reaches only active loopback capabilities" do
    root = temporary_directory()
    artifact = Path.join(root, "artifact")
    runtime = runtime!()
    on_exit(fn -> File.rm_rf!(root) end)
    configure_providers()

    assert :ok = Artifact.build(artifact, runtime)
    manifest_path = Path.join(artifact, "native-build.json")
    manifest = Jason.decode!(File.read!(manifest_path))
    output = Map.new(manifest["outputs"], &{Path.basename(&1["path"]), &1})

    bandit =
      start_supervised!({Bandit, plug: Endpoint, ip: {127, 0, 0, 1}, port: 0, startup_log: false})

    {:ok, {_, port}} = ThousandIsland.listener_info(bandit)
    start_supervised!({Task.Supervisor, name: WotexLabHosted.TaskSupervisor})

    command = [
      runner: Path.join(artifact, "output/bin/wotex-hosted-investigation-runner"),
      runner_sha256: output["wotex-hosted-investigation-runner"]["sha256"],
      runtime: runtime,
      runtime_sha256: manifest["runtime"]["sha256"],
      worker: Path.join(artifact, "output/bin/wotex-lab-hosted-worker"),
      worker_sha256: output["wotex-lab-hosted-worker"]["sha256"],
      work_root: artifact,
      provider_url: "http://127.0.0.1:#{port}/api/internal/beamlens/v1",
      query_url: "http://127.0.0.1:#{port}/api/internal/hosted-investigation/v1/query",
      timeout_ms: 20_000
    ]

    start_supervised!({HostedBroker, command: command, provider: :codex_then_ollama})
    durable = fn _ -> {:error, :unavailable} end
    binding = %{instance: "tenant-metrics", durable: durable}

    assert {:error, :bridge_denied} = BridgeAuthorization.authorize("not-a-capability")

    assert {:ok, reference} =
             HostedBroker.ask(
               binding,
               "Finish after inspecting the supplied run.",
               %{id: "run-a"},
               nil
             )

    active = :sys.get_state(HostedBroker).active[reference]
    assert is_binary(active.provider_capability) and byte_size(active.provider_capability) == 43
    assert is_binary(active.query_capability) and byte_size(active.query_capability) == 43
    refute active.provider_capability == active.query_capability

    for _ <- 1..8 do
      assert {:ok, %{instance: "tenant-metrics", durable: ^durable}} =
               HostedBroker.authorize_query(active.query_capability)
    end

    assert {:error, :bridge_denied} = HostedBroker.authorize_query(active.query_capability)
    assert {:error, :bridge_denied} = HostedBroker.authorize_query(active.provider_capability)

    assert_receive {:hosted_investigation, ^reference,
                    {:ok, %{notifications: [], evidence: evidence}, provider}},
                   30_000

    assert Enum.any?(evidence, &String.starts_with?(&1, "sha256:"))
    assert provider.provider == :codex and provider.model == "fake-codex"
    assert HostedBroker.status().completed == 1
    assert HostedBroker.status().running == 0

    assert {:ok, cancelled} = HostedBroker.ask(binding, "Wait for cancellation.")

    assert {:error, %Wotex.Lab.Error{code: :unknown_hosted_investigation}} =
             Task.async(fn -> HostedBroker.cancel(cancelled) end) |> Task.await()

    assert :ok = HostedBroker.cancel(cancelled)

    assert_receive {:hosted_investigation, ^cancelled, {:error, :investigation_cancelled}},
                   2_000

    eventually(fn -> private_children(artifact) == [] end)
    assert HostedBroker.status().cancelled == 1
    assert HostedBroker.status().running == 0
  end

  defp configure_providers do
    keys = [
      :beamlens_enabled,
      :hosted_investigation_enabled,
      :beamlens_codex_runner,
      :beamlens_ollama_runner,
      :fake_codex_result
    ]

    saved = Map.new(keys, &{&1, Application.get_env(:wotex_lab_workbench, &1)})

    Application.put_env(:wotex_lab_workbench, :beamlens_enabled, false)
    Application.put_env(:wotex_lab_workbench, :hosted_investigation_enabled, true)

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

    Application.put_env(
      :wotex_lab_workbench,
      :fake_codex_result,
      {:ok, ~s({"intent":"done"}),
       %{provider: :codex, model: "fake-codex", plan_type: "test", quota: %{used_percent: 1}}}
    )

    on_exit(fn ->
      Enum.each(saved, fn
        {key, nil} -> Application.delete_env(:wotex_lab_workbench, key)
        {key, value} -> Application.put_env(:wotex_lab_workbench, key, value)
      end)
    end)
  end

  defp private_children(root) do
    root
    |> File.ls!()
    |> Enum.filter(&String.starts_with?(&1, ".wotex-hosted-"))
  end

  defp runtime! do
    case System.find_executable("escript") do
      nil -> flunk("escript runtime is unavailable")
      runtime -> runtime
    end
  end

  defp temporary_directory do
    path =
      Path.join(
        System.tmp_dir!(),
        "wotex-hosted-investigation-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(path)
    path
  end

  defp eventually(fun, attempts \\ 100)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_, 0), do: flunk("condition did not become true")
end
