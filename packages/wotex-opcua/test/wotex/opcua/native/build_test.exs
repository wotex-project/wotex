defmodule Wotex.OPCUA.Native.BuildTest do
  @moduledoc false

  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias Mix.Tasks.Wotex.Opcua.Native.Build, as: BuildTask
  alias Wotex.OPCUA.Native.{Build, Command, Frame, Source, Workspace}

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
    custody = Path.join(workspace, "output/bin/wotex_opcua_custody")
    guardian = Path.join(workspace, "bin/build-command")

    assert {:ok, custody_hash} = Workspace.digest(custody)
    assert custody_hash == receipt["artifacts"]["output/bin/wotex_opcua_custody"]
    assert receipt["identity"]["native_sources"]["custody.c"] =~ ~r/\A[0-9a-f]{64}\z/

    assert receipt["identity"]["native_sources"]["vendor/yyjson/yyjson.c"] ==
             "ac2e9bbb2e2d9149d90878d40506a1d624fa0b33c979a11b61075c54782c6d6a"

    assert receipt["artifacts"]["output/share/licenses/yyjson/LICENSE"] ==
             "45e384d3d52c73cba3a64d6e6c25d47cd738cd8a55c30629e3201046eda62947"

    native_tests = File.read!(Path.join(workspace, "logs/native_test.log"))
    assert native_tests =~ "native_json_self_test"
    native_contract = File.read!("docs/specs/fixtures/native-contract-v1.json")
    native_contract_hash = :crypto.hash(:sha256, native_contract) |> Base.encode16(case: :lower)
    assert receipt["identity"]["native_contract_sha256"] == native_contract_hash

    for number <- 1..16 do
      id = String.pad_leading(Integer.to_string(number), 2, "0")
      assert native_tests =~ "native_contract_WOP-X-F#{id}"
    end

    corpus_path = Application.app_dir(:wotex_opcua, "priv/native/fixtures/value-v1.json")
    corpus_bytes = File.read!(corpus_path)
    corpus_hash = :crypto.hash(:sha256, corpus_bytes) |> Base.encode16(case: :lower)
    assert receipt["identity"]["native_sources"]["fixtures/value-v1.json"] == corpus_hash

    for row <- Jason.decode!(corpus_bytes)["cases"] do
      assert native_tests =~ "native_value_#{row["id"]}"
    end

    for number <- 1..17 do
      id = String.pad_leading(Integer.to_string(number), 2, "0")
      assert native_tests =~ "native_value_fault_WOP-NF#{id}"
    end

    assert native_tests =~ "native_ipc_admission"

    assert {:ok, request} =
             Frame.request(7, "r1", "read", %{}, 1000, 9_223_372_036_854_775_807)

    assert_native_terminal(native, [request], nil, "invalid_request", "validation")

    assert_native_terminal(
      native,
      [binary_part(request, 0, 23), binary_part(request, 23, byte_size(request) - 23)],
      7,
      "unsupported_protocol",
      "validation"
    )

    expired = String.replace(request, "9223372036854775807", "0")
    assert_native_terminal(native, [expired], 7, "deadline_exceeded", "admission")

    invalid = String.replace(request, "\"timeout_ms\":1000", "\"timeout_ms\":1.5")
    assert_native_terminal(native, [invalid], 7, "invalid_request", "validation")

    duplicate = String.replace(request, "\"id\":\"r1\"", "\"id\":\"r1\",\"id\":\"r2\"")
    assert_native_terminal(native, [duplicate], 7, "invalid_request", "validation")

    bytes = %{"type" => "bytes", "base64" => "AQ=="}

    open = %{
      "endpoint" => "opc.tcp://localhost:4840",
      "security_policy" => "http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256",
      "security_mode" => "SignAndEncrypt",
      "client_uri" => "urn:client",
      "server_uri" => "urn:server",
      "certificate" => bytes,
      "private_key" => bytes,
      "server_certificate" => bytes,
      "trust_certificate" => bytes,
      "crl" => bytes,
      "authentication" => %{"type" => "anonymous"},
      "session_timeout_ms" => 60_000
    }

    assert {:ok, secure_open} =
             Frame.request(7, "o1", "open", open, 1000, 9_223_372_036_854_775_807)

    assert_native_terminal(native, [secure_open], 7, "unsupported_protocol", "validation")

    assert {:ok, downgraded_open} =
             Frame.request(
               7,
               "o1",
               "open",
               %{open | "security_mode" => "None"},
               1000,
               9_223_372_036_854_775_807
             )

    assert_native_terminal(native, [downgraded_open], 7, "invalid_request", "validation")

    assert {:ok, host, %{ready: %Wotex.OPCUA.Native.Ready{}, received_at_ms: received}} =
             Wotex.OPCUA.Native.Host.start_link(
               executable: native,
               executable_digest: receipt["artifacts"]["output/bin/wotex_opcua_native"],
               guardian: custody,
               guardian_digest: custody_hash,
               timeout: 5000
             )

    assert received <= System.monotonic_time(:millisecond)
    assert :ok = GenServer.stop(host, :normal)

    assert {:ok, host, _} =
             Wotex.OPCUA.Native.Host.start_link(
               executable: native,
               executable_digest: receipt["artifacts"]["output/bin/wotex_opcua_native"],
               guardian: custody,
               guardian_digest: custody_hash,
               timeout: 5000
             )

    monitor = Process.monitor(host)

    assert {:error, %Wotex.OPCUA.Error{code: :unsupported_protocol} = failure} =
             Wotex.OPCUA.Native.Host.request(host, "read", %{}, 1000)

    assert failure.details == %{phase: :validation}

    assert_receive {:DOWN, ^monitor, :process, ^host, :normal}, 1000

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
    custody_bytes = File.read!(custody)
    File.write!(custody, "tampered-custody-executable")
    assert {:error, :build_manifest_mismatch} = Build.run(workspace)
    File.write!(custody, custody_bytes)
    forged_versions = put_in(receipt, ["evidence", "tool_versions"], %{})
    File.write!(receipt_path, Jason.encode!(forged_versions))
    assert {:error, :build_manifest_mismatch} = Build.run(workspace)
    File.write!(receipt_path, original)
    assert {:ok, %{reused: true}} = Build.run(workspace)
    assert {:ok, _} = File.rm_rf(workspace)
    refute File.exists?(workspace)
  end

  defp assert_native_terminal(executable, fragments, generation, code, phase) do
    port = Port.open({:spawn_executable, executable}, [:binary, :exit_status])

    try do
      assert_receive {^port, {:data, ready}}, 5_000

      assert %{"version" => 1, "event" => "ready", "backend" => "open62541"} =
               Jason.decode!(ready)

      if generation do
        assert {:ok, credit} = Frame.credit(generation, 1, 16, 262_144)
        assert Port.command(port, credit)
      end

      Enum.each(fragments, fn fragment -> assert Port.command(port, fragment) end)
      assert_receive {^port, {:data, terminal}}, 5_000

      assert Jason.decode!(terminal) == %{
               "version" => 1,
               "generation" => generation,
               "event" => "terminal",
               "error" => %{"code" => code, "phase" => phase, "effect" => "none"}
             }

      assert_receive {^port, {:exit_status, 70}}, 5_000
      refute_receive {^port, {:data, _}}, 50
    after
      if Port.info(port), do: Port.close(port)
    end
  end
end
