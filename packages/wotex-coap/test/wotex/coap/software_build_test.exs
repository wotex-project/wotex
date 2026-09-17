defmodule Wotex.CoAP.SoftwareBuildTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Wotex.Coap.Software.Build, as: BuildTask
  alias Wotex.CoAP.Native.Build, as: NativeBuild
  alias Wotex.CoAP.NativeBackend
  alias Wotex.CoAP.NativeBuildTest.Operations
  alias Wotex.CoAP.Software.Build

  defmodule TaskBuild do
    @moduledoc false

    @spec run(String.t()) :: {:ok, map()} | {:error, term()}
    def run(_), do: Process.get({__MODULE__, :result})

    @spec result(term()) :: term()
    def result(value), do: Process.put({__MODULE__, :result}, value)

    @spec reset() :: term()
    def reset, do: Process.delete({__MODULE__, :result})
  end

  defmodule InvalidOperations do
    @moduledoc false

    @spec resolve() :: no_return()
    def resolve, do: raise(ArgumentError, "invalid software toolchain")
  end

  setup do
    Operations.reset()
    TaskBuild.reset()

    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-coap-software-build-#{System.unique_integer([:positive])}"
      )

    on_exit(fn ->
      Operations.reset()
      TaskBuild.reset()
      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "WCO-N01 software build owns one bounded exact artifact inventory" do
    assert {:error, :invalid_build_workspace} = Build.run(nil)
    assert {:error, :invalid_build_workspace} = Build.run(nil, Operations, NativeBuild)

    assert {:error, {:software_build_setup, "invalid software toolchain"}} =
             Build.run("/absolute/workspace", InvalidOperations, NativeBuild)

    assert length(Build.artifacts(NativeBuild)) == 69
    assert length(Enum.uniq(Build.artifacts(NativeBuild))) == 69

    assert_raise Mix.Error, ~r/usage:/, fn -> BuildTask.run(["--workspace", "relative"]) end

    assert_raise Mix.Error, ~r/usage:/, fn ->
      BuildTask.execute(["--workspace", "relative"], TaskBuild)
    end

    assert Mix.Project.config()[:aliases][:"wotex.software.build"] ==
             "wotex.coap.software.build"

    assert "test/native" in Mix.Project.config()[:package][:files]
  end

  test "WCO-N01 builds, probes and reuses all software fixtures read-only", %{root: root} do
    assert {:ok, %{reused: false, manifest: manifest}} =
             Build.run(root, Operations, NativeBuild)

    assert manifest["schema"] == "wotex.coap.native@1"
    assert manifest["software_build"]["profile"] == "software"
    assert {:ok, %{reused: true}} = Build.verify(root, Operations, NativeBuild)

    assert manifest["software_build"]["peer"]["features"] == %{
             "version" => true,
             "dtls" => true,
             "oscore" => true
           }

    assert length(manifest["software_build"]["steps"]) == 3
    assert manifest["software_build"]["sanitizers"] == []
    faults = manifest["software_build"]["fault_executables"]
    assert map_size(faults) == 12

    for {name, record} <- faults do
      assert record["path"] == "bin/faults/#{name}"
      assert record["compile"]["exit_status"] == 0
      assert record["probe"]["exit_status"] == 0
      assert File.exists?(Path.join(root, record["path"]))
    end

    executable = Path.join(root, "native/bin/wotex-coap-oscore")
    manifest_path = Path.join(root, "native-manifest.json")
    assert {:ok, _} = NativeBackend.verify(%{executable: executable, manifest: manifest_path})
    refute File.exists?(Path.join(root, "sources"))
    refute File.exists?(Path.join(root, "peer-build"))

    before = snapshot(root)
    assert {:ok, %{reused: true, manifest: ^manifest}} = Build.run(root, Operations, NativeBuild)
    assert snapshot(root) == before

    File.write!(Path.join(root, "bin/faults/oscore-json"), "tampered")
    changed = snapshot(root)
    assert {:error, :build_manifest_mismatch} = Build.run(root, Operations, NativeBuild)
    assert {:error, :build_manifest_mismatch} = Build.verify(root, Operations, NativeBuild)
    assert snapshot(root) == changed
  end

  test "WCO-N01 peer and fault failures never publish the outer manifest", %{root: root} do
    for mode <- [:peer, :fault] do
      workspace = Path.join(root, Atom.to_string(mode))
      Operations.fail(mode)
      assert {:error, _} = Build.run(workspace, Operations, NativeBuild)
      refute File.exists?(Path.join(workspace, "native-manifest.json"))
      Operations.reset()
    end
  end

  test "WCO-N01 admits the independent peer only by exact archive and runtime", %{root: root} do
    failures = [
      runtime: :missing_independent_peer_runtime,
      runtime_probe: :independent_peer_runtime_probe_failed,
      independent_peer: :independent_peer_mismatch
    ]

    for {mode, reason} <- failures do
      workspace = Path.join(root, Atom.to_string(mode))
      Operations.fail(mode)
      assert {:error, ^reason} = Build.run(workspace, Operations, NativeBuild)
      refute File.exists?(Path.join(workspace, "native-manifest.json"))
      Operations.reset()
    end

    assert {:ok, %{manifest: manifest}} =
             Build.run(Path.join(root, "admitted"), Operations, NativeBuild)

    peer = manifest["software_build"]["independent_peer"]

    assert peer["path"] == "bin/cf-plugtest-server.jar"
    assert peer["stack"] == "Eclipse Californium"
    assert peer["version"] == "3.14.0"
    assert peer["sha256"] == "0bf82d45791eeebbf9d781d0e66f47ddafe67ba36984a432771127f1ee6dd7d5"
    assert peer["runtime"]["path"] == "/fixture/bin/java"
    assert peer["runtime"]["version"] == "fixture tool version"
    assert length(peer["steps"]) == 2
  end

  test "WCO-N01 rejects unreadable build inputs before workspace publication", %{root: root} do
    Operations.fail(:software_digest)

    assert {:error, :software_build_input_mismatch} =
             Build.run(root, Operations, NativeBuild)

    refute File.exists?(root)
  end

  test "WCO-N01 records the Linux sanitizer boundary", %{root: root} do
    Operations.fail(:linux)

    assert {:ok, %{manifest: manifest}} = Build.run(root, Operations, NativeBuild)

    assert manifest["software_build"]["sanitizers"] == [
             "-fsanitize=address,undefined",
             "-fno-sanitize-recover=all",
             "-fno-omit-frame-pointer"
           ]

    block = manifest["software_build"]["fault_executables"]["oscore-block-limit"]
    assert "WCO_ALLOCATION_WRAP" in block["definitions"]
  end

  test "WCO-N01 software task reports completion, verified reuse and finite failure" do
    workspace = "/absolute/workspace"
    TaskBuild.result({:ok, %{reused: false}})

    assert capture_io(fn ->
             assert :ok = BuildTask.execute(["--workspace", workspace], TaskBuild)
           end) =~ "Software build completed: #{workspace}"

    TaskBuild.result({:ok, %{reused: true}})

    output =
      capture_io(fn ->
        assert :ok = BuildTask.execute(["--workspace", workspace], TaskBuild)
      end)

    assert output =~ "Software build verified: #{workspace}"
    assert output =~ "Native executable: #{workspace}/native/bin/wotex-coap-oscore"
    assert output =~ "Peer executable: #{workspace}/bin/coap-server"
    assert output =~ "Manifest: #{workspace}/native-manifest.json"

    TaskBuild.result({:error, :fixture_failure})

    assert_raise Mix.Error, ~r/CoAP software build failed: :fixture_failure/, fn ->
      BuildTask.execute(["--workspace", workspace], TaskBuild)
    end
  end

  defp snapshot(path) do
    path
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.map(fn file ->
      stat = File.lstat!(file)
      attributes = Map.take(stat, [:size, :type, :mode, :links, :inode, :uid, :gid, :mtime, :ctime])
      {Path.relative_to(file, path), attributes, if(stat.type == :regular, do: File.read!(file))}
    end)
  end
end
