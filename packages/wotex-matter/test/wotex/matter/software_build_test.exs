Code.require_file("../../support/software/fixture.exs", __DIR__)

defmodule Wotex.Matter.SoftwareBuildTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.{SoftwareCommand, SoftwareFixture, SoftwareManifest, SoftwarePeerExtension}

  setup do
    {temporary, 0} = System.cmd("pwd", ["-P"], cd: System.tmp_dir!())

    root =
      Path.join(
        String.trim(temporary),
        "wotex-matter-build-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "WMA-B01 workspace admission rejects malformed arguments and symlink ancestors", %{
    root: root
  } do
    source = Path.join(root, "source")
    File.mkdir!(source)
    target = Path.join(root, "target")
    File.mkdir!(target)
    link = Path.join(root, "linked")
    File.ln_s!(target, link)

    for arguments <- [
          [],
          ["--workspace", "relative"],
          ["--workspace", target, "--workspace", target],
          ["--workspace", source],
          ["--workspace", source <> "/child"],
          ["--workspace", root <> "/../elsewhere"],
          ["--workspace", target <> "\n"],
          ["--workspace", link],
          ["--workspace", link <> "/child"]
        ] do
      assert_raise Mix.Error, fn -> SoftwareManifest.arguments(arguments, source) end
    end

    assert SoftwareManifest.arguments(["--workspace", root <> "/fresh"], source) == root <> "/fresh"
    assert File.ls!(target) == []
  end

  test "WMA-B01 Mix entry points require their source project before any build", %{root: root} do
    tasks = [Mix.Tasks.Wotex.Matter.Native.Build, Mix.Tasks.Wotex.Matter.Software.Build]

    for task <- tasks do
      assert_raise Mix.Error, "invalid_arguments", fn -> task.run([]) end

      File.cd!(root, fn ->
        assert_raise Mix.Error, "software_fixture_source_required", fn -> task.run([]) end
      end)
    end

    File.write!(Path.join(root, "mix.exs"), """
    defmodule Wotex.Matter.BuildWrongProject do
      @moduledoc false

      use Mix.Project
      def project, do: [app: :build_wrong_project, version: "0.0.0"]
    end
    """)

    Mix.Project.in_project(:build_wrong_project, root, fn _ ->
      for task <- tasks do
        assert_raise Mix.Error, "software_fixture_wrong_project", fn -> task.run([]) end
      end
    end)
  end

  test "WMA-B01 unrelated and locked workspaces retain their contents", %{root: root} do
    workspace = Path.join(root, "workspace")
    File.mkdir!(workspace)
    marker = Path.join(workspace, "keep")
    File.write!(marker, "owned input")

    assert_raise Mix.Error, "unrelated_workspace", fn ->
      SoftwareFixture.main(:native_build, ["--workspace", workspace])
    end

    assert File.read!(marker) == "owned input"
    refute File.exists?(workspace <> ".lock")
    File.rm!(marker)
    File.mkdir!(workspace <> ".lock")

    assert_raise Mix.Error, "workspace_locked", fn ->
      SoftwareFixture.main(:native_build, ["--workspace", workspace])
    end

    assert File.ls!(workspace) == []
  end

  test "WMA-B01 receipts reject changed binaries logs source and duplicate members", %{root: root} do
    source = Path.join(root, "source")
    workspace = Path.join(root, "workspace")
    File.mkdir!(source)
    File.mkdir!(workspace)
    File.mkdir!(Path.join(workspace, "bin"))
    File.mkdir!(Path.join(workspace, "logs"))
    binary = Path.join(workspace, "bin/wotex-matter-host")
    File.write!(binary, "fixture binary")
    File.write!(binary <> "-sanitized", "fixture sanitizer binary")
    log = Path.join(workspace, "logs/test.log")
    File.write!(log, "fixture execution")
    identity = SoftwareManifest.identity(source)

    native = %{
      "schema" => "wotex.native-build",
      "version" => 1,
      "package" => "wotex_matter",
      "source_files" => identity["source_files_sha256"],
      "logs" => %{"logs/test.log" => SoftwareManifest.digest(log)}
    }

    SoftwareManifest.write(Path.join(workspace, "native-manifest.json"), native)

    contract = Path.join(workspace, "bin/wotex-matter-contract-driver")
    File.write!(contract, "fixture contract")
    File.write!(contract <> "-sanitized", "fixture sanitized contract")

    receipt = %{
      "schema" => "wotex.matter.software-workspace@1",
      "status" => "ready",
      "mode" => "native",
      "sdk_revision" => SoftwareManifest.sdk_revision(),
      "sdk_archive_sha256" => SoftwareManifest.sdk_sha256(),
      "container_image" => SoftwareManifest.image(),
      "target" => "x86_64-linux-gnu",
      "source" => identity,
      "files" => SoftwareManifest.file_hashes(workspace, "native")
    }

    assert SoftwareManifest.verify_local(source, workspace, receipt, :native) == receipt

    assert_raise Mix.Error, "software_fixture_required", fn ->
      SoftwareManifest.verify_local(source, workspace, receipt, :software)
    end

    harnesses =
      for name <- ["flow-host", "controller-test"],
          suffix <- ["", "-sanitized"],
          do: "bin/wotex-matter-" <> name <> suffix

    peers = ~w(bin/chip-lighting-app bin/chip-all-clusters-app bin/chip-bridge-app)

    for name <- harnesses ++ peers,
        do: File.write!(Path.join(workspace, name), "fixture software executable")

    software = %{
      receipt
      | "mode" => "software",
        "files" => SoftwareManifest.file_hashes(workspace, "software")
    }

    assert SoftwareManifest.verify_local(source, workspace, software, :software) == software

    for name <- harnesses do
      path = Path.join(workspace, name)
      File.rm!(path)

      assert_raise Mix.Error, "artifact_hash_mismatch", fn ->
        SoftwareManifest.verify_local(source, workspace, software, :software)
      end

      File.write!(path, "fixture software executable")
    end

    incomplete = %{software | "files" => Map.drop(software["files"], harnesses)}

    assert_raise Mix.Error, "manifest_files", fn ->
      SoftwareManifest.verify_local(source, workspace, incomplete, :software)
    end

    File.rm!(contract)

    assert_raise Mix.Error, "artifact_hash_mismatch", fn ->
      SoftwareManifest.verify_local(source, workspace, receipt, :native)
    end

    File.write!(contract, "fixture contract")

    File.write!(binary, "changed binary")

    assert_raise Mix.Error, "artifact_hash_mismatch", fn ->
      SoftwareManifest.verify_local(source, workspace, receipt, :native)
    end

    File.write!(binary, "fixture binary")
    File.write!(log, "changed log")

    assert_raise Mix.Error, "artifact_hash_mismatch", fn ->
      SoftwareManifest.verify_local(source, workspace, receipt, :native)
    end

    File.write!(log, "fixture execution")

    for {name, value} <- [
          {"coveralls.json", ~s({"coverage_options":{"minimum_coverage":1}})},
          {".check.exs", "[tools: [ex_unit: false]]"}
        ] do
      configuration = Path.join(source, name)
      File.write!(configuration, value)

      assert_raise Mix.Error, "manifest_mismatch", fn ->
        SoftwareManifest.verify_local(source, workspace, receipt, :native)
      end

      File.rm!(configuration)
    end

    File.write!(Path.join(source, "mix.exs"), "changed source")

    assert_raise Mix.Error, "manifest_mismatch", fn ->
      SoftwareManifest.verify_local(source, workspace, receipt, :native)
    end

    invalid = Path.join(root, "invalid.json")
    File.write!(invalid, ~s({"status":"failed","status":"ready"}))
    assert_raise Mix.Error, "invalid_manifest", fn -> SoftwareManifest.read(invalid) end
  end

  test "WMA-B01 commands bound output timeout and environment without a shell", %{root: root} do
    assert {:ok, "hello"} = SoftwareCommand.run("printf", ["%s", "hello"])
    assert {:error, :command_failed} = SoftwareCommand.run("false", [])
    assert {:error, :required_tool_missing} = SoftwareCommand.run(Path.join(root, "absent"), [])
    assert {:error, :command_timeout} = SoftwareCommand.run("sleep", ["1"], timeout: 10)

    assert {:error, :command_output_limit} =
             SoftwareCommand.run("head", ["-c", "16777217", "/dev/zero"])

    canary = "WOTEX_BUILD_TEST_CANARY"
    previous = System.get_env(canary)
    System.put_env(canary, "must-not-inherit")

    try do
      assert {:ok, environment} = SoftwareCommand.run("env", [])
      refute environment =~ canary
    after
      if previous, do: System.put_env(canary, previous), else: System.delete_env(canary)
    end
  end

  test "WMA-B01 source identity includes test helpers used by native peer assertions", %{root: root} do
    before = SoftwareManifest.identity(root)
    helper = Path.join(root, "test/support/credentials.ex")
    File.mkdir_p!(Path.dirname(helper))
    File.write!(helper, "fixture helper")
    after_identity = SoftwareManifest.identity(root)
    assert after_identity != before
    assert Map.has_key?(after_identity["source_files_sha256"], "test/support/credentials.ex")
  end

  test "WMA-N03 peer controls reject unrecognized SDK source without modifying it", %{root: root} do
    files = [
      "examples/all-clusters-app/linux/AllClustersCommandDelegate.cpp",
      "examples/bridge-app/linux/main.cpp"
    ]

    for file <- files do
      path = Path.join(root, file)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "unrecognized source")
    end

    assert_raise Mix.Error, "peer_extension_source_mismatch", fn ->
      SoftwarePeerExtension.apply!(File.cwd!(), root)
    end

    for file <- files, do: assert(File.read!(Path.join(root, file)) == "unrecognized source")
  end

  test "WMA-B01 terminating the caller reaps its running command and retains bounded output", %{
    root: root
  } do
    log = Path.join(root, "owner.log")
    caller = spawn(fn -> SoftwareCommand.run("sleep", ["30"], log: log) end)
    {worker, os_pid} = command_process(caller, 100)
    monitor = Process.monitor(worker)

    try do
      Process.exit(caller, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1_000
      assert File.read!(log) == ""
      assert wait_reaped(os_pid, 100)
    after
      Process.exit(caller, :kill)
      System.cmd("kill", ["-KILL", Integer.to_string(os_pid)], stderr_to_stdout: true)
    end
  end

  test "WMA-B01 command failure and timeout leave logs without replacing an existing artifact", %{
    root: root
  } do
    failed = Path.join(root, "failed.log")
    assert {:error, :command_failed} = SoftwareCommand.run("false", [], log: failed)
    assert File.read!(failed) == ""
    timeout = Path.join(root, "timeout.log")

    assert {:error, :command_timeout} =
             SoftwareCommand.run("sleep", ["30"], timeout: 10, log: timeout)

    assert File.read!(timeout) == ""
    File.write!(failed, "existing evidence")

    assert {:error, :command_failed} =
             SoftwareCommand.run("printf", ["%s", "replacement"], log: failed)

    assert File.read!(failed) == "existing evidence"
  end

  test "WMA-B01 an already closed command Port cannot replace its collected result" do
    executable = System.find_executable("cat") |> String.to_charlist()
    port = Port.open({:spawn_executable, executable}, [:binary, :exit_status, :use_stdio])
    {:os_pid, child} = Port.info(port, :os_pid)
    assert :ok = SoftwareCommand.close_port(port)
    assert :ok = SoftwareCommand.close_port(port)
    assert wait_reaped(child, 100)
  end

  defp command_process(_, 0), do: flunk("command did not start within the bounded wait")

  defp command_process(caller, attempts) do
    {:monitors, monitors} = Process.info(caller, :monitors)

    result =
      Enum.find_value(monitors, fn {:process, worker} ->
        case Process.info(worker, :links) do
          {:links, links} ->
            Enum.find_value(links, fn link ->
              if is_port(link) do
                case Port.info(link, :os_pid) do
                  {:os_pid, pid} -> {worker, pid}
                  _ -> nil
                end
              end
            end)

          _ ->
            nil
        end
      end)

    if result do
      result
    else
      Process.sleep(10)
      command_process(caller, attempts - 1)
    end
  end

  defp wait_reaped(_, 0), do: false

  defp wait_reaped(pid, attempts) do
    case System.cmd("kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_, 0} ->
        Process.sleep(10)
        wait_reaped(pid, attempts - 1)

      _ ->
        true
    end
  end
end
