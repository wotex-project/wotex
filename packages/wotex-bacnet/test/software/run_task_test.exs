Code.require_file("../support/software/fixture.exs", __DIR__)
Code.require_file("../support/software_other_project.ex", __DIR__)

defmodule Wotex.BACnet.RunTaskTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Mix.Tasks.Wotex.Bacnet.Software.Run
  alias Wotex.BACnet.{SoftwareCommand, SoftwareManifest, SoftwareRun}

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-bacnet-run-" <> Base.encode16(:crypto.strong_rand_bytes(12))
      )

    File.mkdir!(directory)

    on_exit(fn ->
      if destination = System.get_env("WOTEX_BACNET_RESULTS_DIR") do
        target = Path.join([destination, "faults", Path.basename(directory)])
        File.mkdir_p!(Path.dirname(target))
        File.cp_r!(directory, target)
      end

      File.rm_rf!(directory)
    end)

    %{directory: directory}
  end

  test "WBA-C09 WBA-V13 Mix run rejects ambiguous arguments before acquisition", c do
    assert Mix.Task.get("wotex.bacnet.software.run") == Run
    assert Mix.Project.config()[:aliases][:"wotex.software.run"] == "wotex.bacnet.software.run"

    for args <- [[], [c.directory], ["--workspace", "relative"], ["--other", c.directory]] do
      assert_raise Mix.Error, fn -> Run.run(args) end
    end

    assert File.ls!(c.directory) == []
  end

  test "WBA-C09 WBA-V13 Mix run requires this root and source checkout", c do
    Mix.Project.push(Wotex.BACnet.SoftwareOtherProject)

    try do
      assert_raise Mix.Error, "software_fixture_wrong_project", fn -> Run.run([]) end
    after
      Mix.Project.pop()
    end

    File.cd!(c.directory, fn ->
      assert_raise Mix.Error, "software_fixture_source_required", fn -> Run.run([]) end
    end)
  end

  @tag :software
  test "WBA-RF01 normal and instrumented peers expose cleanup counters within one deadline", c do
    for variant <- ["normal", "sanitizer"] do
      {context, manifest} = fixture(c, variant)
      result = SoftwareRun.run_case(context, manifest)
      assert result["status"] == "passed"
      assert result["peer_exit_code"] == 0
      assert result["peer_observation"] == "complete"
      assert result["owned_containers_after"] == 0
      assert result["local_cleanup_ms"] <= 1000
      assert length(result["peer_cleanup"]) == 1
      assert result["native_sanitizers"]["instrumented"] == (variant == "sanitizer")
      assert SoftwareManifest.read(Path.join(context.lane, "result.json")) == result
    end
  end

  @tag :software
  test "WBA-RF02 failed and timed out test commands retain failure and clean the native peer", c do
    for {script, options, expected} <- [
          {"printf failed-test; exit 17", [], 17},
          {"printf deadline-test; sleep 30", [timeout: 100, cleanup: 100], 124},
          {"while :; do printf xxxxxxxxxxxxxxxx; done", [limit: 1024], 125}
        ] do
      {context, manifest} = fixture(c, "normal")

      context =
        Map.put(context, :test_command, {System.find_executable("sh"), ["-c", script], options})

      result = SoftwareRun.run_case(context, manifest)
      assert result["status"] == "failed"
      assert result["test_exit_code"] == expected
      assert result["cleanup"] == "passed"
      assert result["owned_containers_after"] == 0
      assert byte_size(File.read!(Path.join(context.lane, "tests.log"))) in 1..1024
    end
  end

  @tag :software
  test "WBA-RF03 malformed and missing readiness fail with bounded retained peer output", c do
    for script <- ["printf 'invalid\\n'; sleep 30", "printf 'partial'; sleep 30"] do
      {context, manifest} = fixture(c, "normal")
      context = Map.merge(context, %{peer_command: {"/bin/sh", ["-c", script]}, ready_timeout: 200})
      result = SoftwareRun.run_case(context, manifest)
      assert result["status"] == "failed"
      assert result["owned_containers_after"] == 0
      assert result["native_sanitizers"] == %{"instrumented" => false}
      assert byte_size(File.read!(Path.join(context.lane, "peer.log"))) > 0
      refute File.exists?(Path.join(context.lane, "tests.log"))
    end
  end

  @tag :software
  test "WBA-RF04 owner death after container creation removes only its exact peer", c do
    {retained, manifest} = fixture(c, "normal")
    File.mkdir!(retained.lane)
    retained = Map.merge(retained, %{manifest: manifest, docker: System.find_executable("docker")})
    peer = SoftwareRun.start_peer(retained)
    {:ok, initial} = SoftwareRun.ready(peer)
    retained_id = SoftwareRun.container(retained)
    parent = self()
    {context, _} = fixture(c, "normal")

    context =
      Map.put(context, :before_start, fn id ->
        send(parent, {:created, id})
        receive do: (:continue -> :ok)
      end)

    owner = spawn(fn -> SoftwareRun.run_case(context, manifest) end)
    assert_receive {:created, id}, 10_000
    ref = Process.monitor(owner)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^ref, :process, ^owner, :killed}
    receipt = await_receipt(Path.join(context.lane, "owner-loss-cleanup.json"), 1500)
    assert receipt == %{"status" => "passed", "owned_containers_after" => 0}
    assert {:ok, "", 0} = docker(context, ["ps", "--all", "--quiet", "--filter", "id=" <> id])

    assert {:ok, "true\n", 0} =
             docker(context, ["inspect", retained_id, "--format", "{{.State.Running}}"])

    assert {:ok, _, 0} = docker(context, ["kill", "--signal", "TERM", retained_id])
    assert {:ok, _, 0} = SoftwareCommand.observe(peer, 1000, 4096, initial)
    send(Process.delete({SoftwareRun, :watcher, peer}), :cleaned)
  end

  @tag :software
  test "WBA-RF05 unavailable cleanup never reports unobserved container or native zeros", c do
    {context, manifest} = fixture(c, "normal")
    context = Map.put(context, :cleanup_docker, System.find_executable("false"))
    result = SoftwareRun.run_case(context, manifest)
    assert result["status"] == "failed"
    assert result["owned_containers_after"] == "unverified"
    assert result["peer_exit_code"] == "unverified"
    assert result["peer_observation"] == "command_deadline"
    assert File.read!(Path.join(context.lane, "peer.log")) =~ "\"ready\":true"
    refute result["cleanup"] == "passed"
    cleanup_exact(context)
  end

  defp fixture(c, variant) do
    workspace = System.fetch_env!("WOTEX_BACNET_SOFTWARE_WORKSPACE")

    context = %{
      root: File.cwd!(),
      workspace: workspace,
      guardian: Path.join(workspace, "command"),
      lane: Path.join(c.directory, Base.encode16(:crypto.strong_rand_bytes(12))),
      run_id: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower),
      variant: variant,
      measurements: [],
      test_command: {System.find_executable("sh"), ["-c", "printf completed"], []}
    }

    on_exit(fn -> cleanup_exact(context) end)
    {context, SoftwareManifest.read(Path.join(workspace, "peer-manifest.json"))}
  end

  defp cleanup_exact(context) do
    case File.read(Path.join(context.lane, "owned-container.id")) do
      {:ok, bytes} ->
        id = String.trim(bytes)
        assert Regex.match?(~r/\A[0-9a-f]{64}\z/, id)

        case docker(context, [
               "inspect",
               id,
               "--format",
               "{{index .Config.Labels \"wotex.bacnet.run\"}}"
             ]) do
          {:ok, label, 0} ->
            assert String.trim(label) == context.run_id
            _ = docker(context, ["rm", "--force", id])

          _ ->
            :ok
        end

        assert_absent(context, id, System.monotonic_time(:millisecond) + 1000)

      {:error, :enoent} ->
        :ok
    end
  end

  defp docker(context, arguments),
    do:
      SoftwareCommand.run(context.guardian, System.find_executable("docker"), arguments,
        cd: context.root,
        timeout: 1000,
        cleanup: 100
      )

  defp await_receipt(path, timeout),
    do: receipt(path, System.monotonic_time(:millisecond) + timeout)

  defp assert_absent(context, id, deadline) do
    case docker(context, ["ps", "--all", "--quiet", "--filter", "id=" <> id]) do
      {:ok, "", 0} ->
        :ok

      result ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(10)
          assert_absent(context, id, deadline)
        else
          flunk("owned container remains: #{inspect(result)}")
        end
    end
  end

  defp receipt(path, deadline) do
    if File.regular?(path) do
      SoftwareManifest.read(path)
    else
      assert System.monotonic_time(:millisecond) < deadline
      Process.sleep(10)
      receipt(path, deadline)
    end
  end
end
