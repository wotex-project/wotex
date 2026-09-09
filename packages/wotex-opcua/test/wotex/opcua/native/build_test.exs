defmodule Wotex.OPCUA.Native.BuildTest do
  @moduledoc false

  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias Mix.Tasks.Wotex.Opcua.Native.Build, as: BuildTask
  alias Wotex.OPCUA.Native.{Build, Command, Source, Workspace}

  test "WOP-X02 task accepts one absolute workspace and rejects every extra option before build I/O" do
    assert {:ok, "/absolute/workspace"} = Build.arguments(["--workspace", "/absolute/workspace"])

    for invalid <- [
          nil,
          [],
          ["--workspace"],
          ["--workspace", "relative"],
          ["--workspace", nil],
          ["--workspace", "/work", "--workspace", "/other"],
          ["--unknown", "/work"],
          ["--workspace", "/work/../other"],
          ["--workspace", "/work\nother"]
        ] do
      assert {:error, :invalid_native_build_arguments} = Build.arguments(invalid)
    end

    assert {:error, :invalid_build_workspace} = Build.run(nil)
    assert_raise Mix.Error, ~r/usage:/, fn -> BuildTask.run(["--workspace", "relative"]) end
  end

  test "WOP-X02 task refuses unrelated content without mutation" do
    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-opcua-build-unrelated-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    File.write!(Path.join(root, "preserve"), "original")

    assert_raise Mix.Error, ~r/unrecognized_build_workspace/, fn ->
      BuildTask.run(["--workspace", root])
    end

    assert File.ls!(root) == ["preserve"]
    assert File.read!(Path.join(root, "preserve")) == "original"
  end

  @tag :native_build
  @tag timeout: 1_800_000
  test "WOP-X02 real pinned static build, native dependency test, verified reuse and tamper rejection" do
    base =
      System.get_env("WOTEX_NATIVE_BUILD_WORKSPACE") ||
        flunk("selected native build requires WOTEX_NATIVE_BUILD_WORKSPACE")

    assert Path.type(base) == :absolute

    workspace =
      Path.join(base, "native-#{System.os_time(:nanosecond)}-#{System.unique_integer([:positive])}")

    output = capture_io(fn -> assert :ok = BuildTask.run(["--workspace", workspace]) end)
    assert output =~ "Native build completed:"
    receipt_path = Path.join(workspace, "wotex-native-build.json")
    receipt = Jason.decode!(File.read!(receipt_path))
    assert receipt["identity"]["source_manifest_sha256"] == Source.manifest_digest()
    assert receipt["evidence"]["native_service_acceptance"] == false
    assert length(receipt["evidence"]["steps"]) == 10
    assert Enum.all?(receipt["evidence"]["steps"], &(&1["exit_status"] == 0))

    for source_name <- [:openssl, :open62541] do
      {:ok, source} = Source.fetch(source_name)
      assert receipt["artifacts"]["downloads/#{source.name}.tar.gz"] == source.sha256
    end

    native = Path.join(workspace, "output/bin/wotex_opcua_native")
    guardian = Path.join(workspace, "bin/build-command")

    assert {:ok, %{output: self_test}} =
             Command.run(guardian, %{
               id: :native_self_test,
               executable: native,
               args: ["--self-test"],
               cwd: workspace,
               env: [{"PATH", "/no-runtime-tools"}],
               timeout_ms: 5000,
               output_bytes: 4096,
               cleanup_ms: 1000
             })

    assert Jason.decode!(self_test) == %{
             "self_test" => "ok",
             "sha256_known_answer" => true,
             "datetime_ticks" => 1,
             "network_requests" => 0
           }

    original = File.read!(receipt_path)
    assert {:ok, %{reused: true}} = Build.run(workspace)
    assert File.read!(receipt_path) == original

    assert capture_io(fn -> BuildTask.run(["--workspace", workspace]) end) =~
             "Native build verified:"

    assert {:ok, binary_hash} = Workspace.digest(native)
    assert binary_hash == receipt["artifacts"]["output/bin/wotex_opcua_native"]
    log = Path.join(workspace, "logs/native_test.log")
    bytes = File.read!(log)
    File.write!(log, "tampered-evidence")
    assert {:error, :build_manifest_mismatch} = Build.run(workspace)
    assert File.read!(log) == "tampered-evidence"
    File.write!(log, bytes)
    native_bytes = File.read!(native)
    File.write!(native, "tampered-native-executable")
    assert {:error, :build_manifest_mismatch} = Build.run(workspace)
    assert File.read!(native) == "tampered-native-executable"
    assert File.read!(receipt_path) == original
    File.write!(native, native_bytes)
    forged_versions = put_in(receipt, ["evidence", "tool_versions"], %{})
    File.write!(receipt_path, Jason.encode!(forged_versions))
    assert {:error, :build_manifest_mismatch} = Build.run(workspace)
    File.write!(receipt_path, original)
    assert {:ok, %{reused: true}} = Build.run(workspace)
  end
end
