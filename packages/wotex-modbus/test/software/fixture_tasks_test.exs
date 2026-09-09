Code.require_file("../support/software/fixture.exs", __DIR__)
Code.require_file("../support/software_other_project.ex", __DIR__)

defmodule Wotex.Modbus.FixtureTasksTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Mix.Tasks.Wotex.Modbus.Software.{Build, Run}
  alias Wotex.Modbus.{SoftwareManifest, SoftwareRun}

  setup do
    directory =
      Path.join(System.tmp_dir!(), "wotex-modbus-task-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory, root: File.cwd!()}
  end

  test "WMB-N01 WMB-N03 Mix entry points reject every ambiguous argument shape", context do
    for task <- [Build, Run],
        arguments <- [
          [],
          [context.directory],
          ["--other", context.directory],
          ["--workspace", context.directory, "--workspace", context.directory],
          ["--workspace", "relative"]
        ] do
      assert_raise Mix.Error, fn -> task.run(arguments) end
    end

    assert File.ls!(context.directory) == []
  end

  test "WMB-N01 WMB-N03 both tasks reject another project before acquisition" do
    Mix.Project.push(Wotex.Modbus.SoftwareOtherProject)

    try do
      for task <- [Build, Run] do
        assert_raise Mix.Error, "software_fixture_wrong_project", fn -> task.run([]) end
      end
    after
      Mix.Project.pop()
    end
  end

  test "WMB-N01 WMB-N03 installed tasks without source fixtures fail explicitly", context do
    File.cd!(context.directory, fn ->
      for task <- [Build, Run] do
        assert_raise Mix.Error, "software_fixture_source_required", fn -> task.run([]) end
      end
    end)
  end

  test "WMB-N01 WMB-N03 workspace roots reject source paths symlinks and files", context do
    target = Path.join(context.directory, "target")
    link = Path.join(context.directory, "link")
    File.mkdir!(target)
    File.ln_s!(target, link)
    file = Path.join(context.directory, "file")
    File.write!(file, "retain")

    for value <- [
          context.root,
          Path.join(context.root, "nested"),
          link,
          file,
          "/tmp/invalid" <> <<0>>
        ] do
      assert_raise Mix.Error, fn ->
        SoftwareManifest.arguments(["--workspace", value], context.root)
      end
    end

    assert File.read!(file) == "retain"
    assert SoftwareManifest.arguments(["--workspace", target], context.root) == target
  end

  test "WMB-N01 WMB-N03 unrelated build workspace remains untouched", context do
    sentinel = Path.join(context.directory, "retain")
    File.write!(sentinel, "consumer-owned")

    assert_raise Mix.Error, "unrelated_workspace", fn ->
      Build.run(["--workspace", context.directory])
    end

    assert File.ls!(context.directory) == ["retain"]
    assert File.read!(sentinel) == "consumer-owned"
    refute File.exists?(context.directory <> ".lock")
  end

  test "WMB-N01 WMB-N03 missing corrupt oversized and symlink manifests fail", context do
    path = Path.join(context.directory, "manifest.json")
    assert_raise Mix.Error, "invalid_manifest", fn -> SoftwareManifest.read(path) end

    for bytes <- ["{", "[]", String.duplicate("x", 1_048_577)] do
      File.write!(path, bytes)
      assert_raise Mix.Error, "invalid_manifest", fn -> SoftwareManifest.read(path) end
    end

    File.rm!(path)
    source = Path.join(context.directory, "source.json")
    File.write!(source, "{}")
    File.ln_s!(source, path)
    assert_raise Mix.Error, "invalid_manifest", fn -> SoftwareManifest.read(path) end

    assert_raise Mix.Error, "invalid_manifest", fn ->
      Run.run(["--workspace", context.directory])
    end

    refute File.exists?(context.directory <> ".lock")
  end

  test "WMB-N01 WMB-N03 archive paths types cardinality and expanded size are bounded" do
    regular = fn name, size -> {String.to_charlist(name), :regular, size, 0, 0o600, 0, 0} end
    assert :ok = SoftwareManifest.archive_members([regular.("source/file.c", 32)])

    for entries <- [
          [],
          [regular.("../escape", 1)],
          [regular.("/escape", 1)],
          [regular.("source/../../escape", 1)],
          [regular.("source\\escape", 1)],
          [regular.("source/file", 33_554_433)],
          [{~c"link", :symlink, 0, 0, 0, 0, 0}],
          List.duplicate(regular.("source/file", 1), 4097)
        ] do
      assert_raise Mix.Error, "unsafe_archive", fn -> SoftwareManifest.archive_members(entries) end
    end
  end

  test "WMB-N03 source identities bind actual file bytes without Git", context do
    lib = Path.join(context.directory, "lib")
    File.mkdir!(lib)
    source = Path.join(lib, "value.ex")
    File.write!(source, "first")
    first = SoftwareManifest.identity(context.directory)
    assert first["source_files_sha256"] == %{"lib/value.ex" => SoftwareManifest.hash("first")}
    File.write!(source, "second")
    refute SoftwareManifest.identity(context.directory)["source_sha256"] == first["source_sha256"]
  end

  test "WMB-N03 clean-source Git metadata requires one complete successful commit and tree result" do
    commit = String.duplicate("a", 40)
    tree = String.duplicate("b", 40)
    assert SoftwareManifest.git_identity({:ok, commit <> "\n" <> tree <> "\n", 0}) == {commit, tree}

    for invalid <- [
          {:ok, commit <> "\n", 0},
          {:ok, "\n", 0},
          {:ok, commit <> "\ninvalid\n", 0},
          {:ok, commit <> "\n" <> tree <> "\nextra\n", 0},
          {:ok, commit <> "\n" <> tree <> "\n", 127},
          {:error, :command_deadline, :unverified}
        ] do
      assert_raise Mix.Error, "invalid_git_identity", fn ->
        SoftwareManifest.git_identity(invalid)
      end
    end
  end

  test "WMB-N03 atomic evidence writes are complete and preserve an occupied temporary path",
       context do
    path = Path.join(context.directory, "result.json")
    assert :ok = SoftwareManifest.write(path, %{"status" => "failed"})
    assert SoftwareManifest.read(path) == %{"status" => "failed"}
    File.write!(path <> ".temporary", "retain")
    assert_raise File.Error, fn -> SoftwareManifest.write(path, %{"status" => "passed"}) end
    assert SoftwareManifest.read(path) == %{"status" => "failed"}
  end

  @tag :software
  test "WMB-N01 WMB-N03 built manifest reuses actual image and detects changed artifacts",
       context do
    workspace = copy_workspace(context.directory)
    assert :ok = Build.run(["--workspace", workspace])
    guardian = Path.join(workspace, "command")
    File.write!(guardian, "changed")

    assert_raise Mix.Error, "artifact_hash_mismatch", fn ->
      Build.run(["--workspace", workspace])
    end

    assert File.read!(workspace <> ".lock") == ""
  end

  @tag :software
  test "WMB-N02 WMB-N03 real container ends when its native Port owner dies", context do
    workspace = System.fetch_env!("WOTEX_MODBUS_SOFTWARE_WORKSPACE")
    native = native_context(context, workspace)
    parent = self()

    owner =
      spawn(fn ->
        port = SoftwareRun.start_peer(native)
        {:ok, _} = SoftwareRun.ready(port)
        send(parent, {:owned_container, SoftwareRun.container(native), port})
        receive do: (:remain -> :ok)
      end)

    assert_receive {:owned_container, cid, port}, 15_000
    monitor = Process.monitor(owner)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}
    assert Port.info(port) == nil
    assert_removed(native, cid, System.monotonic_time(:millisecond) + 5000)
  end

  @tag :software
  test "WMB-N02 WMB-N03 opening owner death removes a created but unstarted exact peer", context do
    workspace = System.fetch_env!("WOTEX_MODBUS_SOFTWARE_WORKSPACE")
    native = native_context(context, workspace)
    parent = self()

    native =
      Map.put(native, :before_start, fn cid ->
        send(parent, {:created_container, cid})
        receive do: (:continue -> :ok)
      end)

    owner = spawn(fn -> SoftwareRun.start_peer(native) end)
    assert_receive {:created_container, cid}, 15_000

    assert {:ok, "created\n", 0} =
             Wotex.Modbus.SoftwareCommand.run(
               native.guardian,
               native.docker,
               ["inspect", cid, "--format", "{{.State.Status}}"],
               cd: native.root,
               timeout: 1000
             )

    Process.exit(owner, :kill)
    assert_removed(native, cid, System.monotonic_time(:millisecond) + 5000)
  end

  @tag :software
  test "WMB-N02 WMB-N03 test failure timeout and overflow retain failed results and clean peers",
       context do
    workspace = System.fetch_env!("WOTEX_MODBUS_SOFTWARE_WORKSPACE")
    manifest = SoftwareManifest.read(Path.join(workspace, "peer-manifest.json"))

    for {name, executable, arguments, options, status} <- [
          {"exit", "/usr/bin/false", [], [], 1},
          {"timeout", "/bin/sleep", ["20"], [timeout: 100], 124},
          {"overflow", "/usr/bin/yes", ["bounded"], [limit: 4097], 125}
        ] do
      result_directory = Path.join(context.directory, name)
      File.mkdir!(result_directory)

      native = %{
        root: context.root,
        workspace: result_directory,
        guardian: Path.join(workspace, "command"),
        test_command: {executable, arguments, options}
      }

      File.cp!(
        Path.join(workspace, "peer-manifest.json"),
        Path.join(result_directory, "peer-manifest.json")
      )

      assert_raise Mix.Error, "software_fixture_failed", fn -> SoftwareRun.run(native, manifest) end
      [path] = Path.wildcard(Path.join(result_directory, "run-*/result.json"))
      result = SoftwareManifest.read(path)
      retain_fault(path, name)
      assert result["status"] == "failed"
      assert result["test_exit_code"] == status
      assert result["cleanup"] == "passed"
      assert result["owned_containers_after"] == 0
      assert result["peer_exit_code"] == 0

      assert [
               %{
                 "event" => "cleanup",
                 "open_sockets" => 0,
                 "contexts" => 0,
                 "mappings" => 0,
                 "result" => 0
               }
             ] = result["peer_cleanup"]
    end
  end

  @tag :software
  test "WMB-N02 WMB-N03 readiness and cleanup faults retain unsuccessful evidence", context do
    workspace = System.fetch_env!("WOTEX_MODBUS_SOFTWARE_WORKSPACE")
    manifest = SoftwareManifest.read(Path.join(workspace, "peer-manifest.json"))

    for {name, overrides, cleanup} <- [
          {"not_ready", %{peer_command: {"/bin/sleep", ["20"]}, ready_timeout: 100}, "failed"},
          {"cleanup_failure", %{cleanup_docker: "/usr/bin/false"}, "unverified"}
        ] do
      directory = Path.join(context.directory, name)
      File.mkdir!(directory)

      File.cp!(
        Path.join(workspace, "peer-manifest.json"),
        Path.join(directory, "peer-manifest.json")
      )

      native =
        Map.merge(
          %{
            root: context.root,
            workspace: directory,
            guardian: Path.join(workspace, "command"),
            test_command: {"/usr/bin/false", [], []}
          },
          overrides
        )

      assert_raise Mix.Error, "software_fixture_failed", fn -> SoftwareRun.run(native, manifest) end
      [path] = Path.wildcard(Path.join(directory, "run-*/result.json"))
      result = SoftwareManifest.read(path)
      retain_fault(path, name)
      assert result["status"] == "failed"
      assert result["cleanup"] == cleanup
      assert result["owned_containers_after"] == if(cleanup == "failed", do: 0, else: "unverified")

      cid =
        path
        |> Path.dirname()
        |> Path.join("owned-container.id")
        |> File.read!()
        |> String.trim()

      assert_removed(
        native_context(context, workspace),
        cid,
        System.monotonic_time(:millisecond) + 5000
      )
    end
  end

  @tag :software
  test "WMB-N02 WMB-N03 explicit zero-resource proof survives an unavailable stop acknowledgment",
       context do
    workspace = System.fetch_env!("WOTEX_MODBUS_SOFTWARE_WORKSPACE")
    manifest = SoftwareManifest.read(Path.join(workspace, "peer-manifest.json"))
    guardian = Path.join(workspace, "command")
    docker = System.find_executable("docker")

    File.cp!(
      Path.join(workspace, "peer-manifest.json"),
      Path.join(context.directory, "peer-manifest.json")
    )

    before_stop = fn cid ->
      assert {:ok, _, 0} =
               Wotex.Modbus.SoftwareCommand.run(guardian, docker, ["stop", "--time", "1", cid],
                 cd: context.root,
                 timeout: 2000
               )
    end

    native = %{
      root: context.root,
      workspace: context.directory,
      guardian: guardian,
      test_command: {"/usr/bin/false", [], []},
      before_stop: before_stop
    }

    assert_raise Mix.Error, "software_fixture_failed", fn -> SoftwareRun.run(native, manifest) end
    [path] = Path.wildcard(Path.join(context.directory, "run-*/result.json"))
    retain_fault(path, "stop_acknowledgment")
    result = SoftwareManifest.read(path)
    assert result["stop_exit_code"] != 0
    assert result["test_exit_code"] == 1
    assert result["status"] == "failed"
    assert result["peer_exit_code"] == 0
    assert result["cleanup"] == "passed"
    assert result["owned_containers_after"] == 0

    assert [%{"open_sockets" => 0, "contexts" => 0, "mappings" => 0, "result" => 0}] =
             result["peer_cleanup"]
  end

  defp retain_fault(result, name) do
    target = Path.join([System.fetch_env!("WOTEX_MODBUS_SOFTWARE_EVIDENCE"), "faults", name])
    File.mkdir_p!(target)

    for filename <- ["result.json", "tests.log", "peer.log", "stop.log"] do
      source = Path.join(Path.dirname(result), filename)
      if File.regular?(source), do: File.cp!(source, Path.join(target, filename))
    end
  end

  defp copy_workspace(directory) do
    source = System.fetch_env!("WOTEX_MODBUS_SOFTWARE_WORKSPACE")
    target = Path.join(directory, "workspace")
    File.mkdir!(target)
    manifest = SoftwareManifest.read(Path.join(source, "peer-manifest.json"))

    for name <- ["peer-manifest.json" | Map.keys(manifest["files"])] do
      destination = Path.join(target, name)
      File.mkdir_p!(Path.dirname(destination))
      File.cp!(Path.join(source, name), destination)
    end

    File.chmod!(Path.join(target, "command"), 0o700)
    target
  end

  defp native_context(context, workspace) do
    %{
      root: context.root,
      lane: context.directory,
      guardian: Path.join(workspace, "command"),
      docker: System.find_executable("docker"),
      manifest: SoftwareManifest.read(Path.join(workspace, "peer-manifest.json")),
      run_id: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    }
  end

  defp assert_removed(context, cid, deadline) do
    result =
      Wotex.Modbus.SoftwareCommand.run(
        context.guardian,
        context.docker,
        ["ps", "--all", "--quiet", "--no-trunc", "--filter", "id=" <> cid],
        cd: context.root,
        timeout: 1000
      )

    cond do
      result == {:ok, "", 0} ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("owned native peer container remains")

      true ->
        Process.sleep(20)
        assert_removed(context, cid, deadline)
    end
  end
end
