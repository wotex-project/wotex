Code.require_file("../../support/software/fixture.exs", __DIR__)
Code.require_file("../../support/bridge_wire_fixture.ex", __DIR__)

defmodule Wotex.Matter.SoftwareBuildTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.{
    BridgeWireFixture,
    SoftwareBridgeBuild,
    SoftwareCommand,
    SoftwareFixture,
    SoftwareManifest,
    SoftwarePeerExtension
  }

  setup do
    {temporary, 0} = Wotex.Matter.Native.ProcessCommand.run("pwd", ["-P"], cd: System.tmp_dir!())

    root =
      Path.join(
        String.trim(temporary),
        "wotex-matter-build-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "SDK server case receipts require their exact exit and completion marker" do
    assert :ok =
             SoftwareBridgeBuild.verify_case!(
               "server startup and shutdown probe passed\n\nbridge server exit: 0\n",
               0,
               "server startup and shutdown probe passed"
             )

    assert :ok = SoftwareBridgeBuild.verify_case!("\nbridge server exit: 74\n", 74, nil)

    for output <- [
          "server startup and shutdown probe passed\n\nbridge server exit: 70\n",
          "\nbridge server exit: 0\n",
          "prefix server startup and shutdown probe passed\n\nbridge server exit: 0\n",
          "runtime error: invalid access\nserver startup and shutdown probe passed\n\nbridge server exit: 0\n",
          "AddressSanitizer: fault\nserver startup and shutdown probe passed\n\nbridge server exit: 0\n"
        ] do
      assert_raise Mix.Error, "bridge_server_test_failed", fn ->
        SoftwareBridgeBuild.verify_case!(output, 0, "server startup and shutdown probe passed")
      end
    end
  end

  test "SDK lifecycle receipts require fixed output and the actual expected exit" do
    healthy = "owned SDK bootstrap resource lifecycle passed\n\nbridge bootstrap exit: 0\n"
    fatal = "\nbridge bootstrap exit: 70\n"
    assert :ok = SoftwareBridgeBuild.verify_lifecycle!(healthy, 0)
    assert :ok = SoftwareBridgeBuild.verify_lifecycle!(fatal, 70)

    for {output, expected} <- [
          {"", 0},
          {healthy, 70},
          {fatal, 0},
          {healthy <> healthy, 0},
          {String.trim_trailing(healthy), 0},
          {"caller payload\n" <> healthy, 0},
          {"AddressSanitizer\n" <> healthy, 0},
          {"LeakSanitizer\n" <> fatal, 70},
          {"runtime error: fixture\n" <> healthy, 0},
          {"\nbridge bootstrap exit: 74\n", 74}
        ] do
      assert_raise Mix.Error, "bridge_lifecycle_test_failed", fn ->
        SoftwareBridgeBuild.verify_lifecycle!(output, expected)
      end
    end
  end

  test "bootstrap loading receipt accepts only the exact fixed success output" do
    marker = "owned SDK bootstrap credential loading passed\n"
    assert :ok = SoftwareBridgeBuild.verify_bootstrap!(marker)

    for output <- [
          "",
          String.trim_trailing(marker),
          marker <> marker,
          "caller payload\n" <> marker,
          marker <> "AddressSanitizer\n",
          marker <> "runtime error: fixture\n",
          marker <> "LeakSanitizer\n"
        ] do
      assert_raise Mix.Error, "bridge_bootstrap_test_failed", fn ->
        SoftwareBridgeBuild.verify_bootstrap!(output)
      end
    end
  end

  test "configuration receipt accepts only the exact fixed success output" do
    marker = "bounded bridge bootstrap configuration passed\n"
    assert :ok = SoftwareBridgeBuild.verify_configuration!(marker)

    for output <- [
          "",
          String.trim_trailing(marker),
          marker <> marker,
          "caller payload\n" <> marker,
          marker <> "AddressSanitizer\n",
          marker <> "runtime error: fixture\n",
          marker <> "LeakSanitizer\n"
        ] do
      assert_raise Mix.Error, "bridge_configuration_test_failed", fn ->
        SoftwareBridgeBuild.verify_configuration!(output)
      end
    end
  end

  test "paired codec receipts validate all request cells and retained native metadata" do
    frames = codec_frames()

    assert %{
             "request_fixtures" => 13,
             "result_frames" => 8,
             "argument_fixtures" => 85,
             "probe_frames" => 2,
             "clock_samples" => 2
           } =
             SoftwareBridgeBuild.verify_codec!(codec_output(frames))

    for corrupted <- [
          tl(frames),
          Enum.reverse(frames),
          [hd(frames) | frames],
          [hd(frames) | tl(tl(frames))],
          [Map.put(hd(frames), "thing", "ff00") | tl(frames)],
          [put_in(hd(frames), ["principal", "cats"], [1, 0, 0]) | tl(frames)],
          [put_in(hd(frames), ["fabric_scope", "epoch"], "1") | tl(frames)],
          [put_in(hd(frames), ["flags", "expanded"], false) | tl(frames)],
          [Map.put(hd(frames), "generation", String.duplicate("00", 16)) | tl(frames)]
        ] do
      assert_raise Mix.Error, "bridge_codec_test_failed", fn ->
        SoftwareBridgeBuild.verify_codec!(codec_output(corrupted))
      end
    end
  end

  test "paired observation receipts preserve exact identity, outcome and allocator evidence" do
    generation = :binary.copy(<<255>>, 16)
    fixtures = SoftwareBridgeBuild.observation_fixtures() |> Enum.map(&Jason.decode!/1)
    assert length(fixtures) == 8

    assert Enum.map(fixtures, & &1["id"]) ==
             List.duplicate(["1", "18446744073709551615"], 4) |> List.flatten()

    assert Enum.map(fixtures, & &1["temperature"]) == [
             nil,
             nil,
             nil,
             nil,
             -32_767,
             -32_767,
             32_767,
             32_767
           ]

    receipts =
      for outcome <- ["applied", "refused"], id <- ["1", "18446744073709551615"] do
        "bridge observation receipt fixture: " <>
          Jason.encode!(%{
            "v" => 1,
            "backend" => "matter-bridge",
            "type" => "observation-receipt",
            "generation" => Base.encode16(generation, case: :lower),
            "id" => id,
            "outcome" => outcome
          }) <> "\n"
      end

    markers =
      "bounded observation codec preserves refusal and exact receipt roles\n" <>
        "observation decode and receipt allocation cutpoints preserve caller output\n"

    output = IO.iodata_to_binary(receipts) <> markers

    assert SoftwareBridgeBuild.verify_observation!(output) == %{
             "observation_frames" => 8,
             "receipt_frames" => 4
           }

    for invalid <- [
          "",
          markers,
          output <> output,
          output <> "AddressSanitizer\n",
          String.replace(output, "\"applied\"", "\"completed\""),
          String.replace(output, "\"id\":\"1\"", "\"id\":\"01\""),
          String.replace(output, "allocation cutpoints", "allocation snapshot"),
          "external payload\n" <> output
        ] do
      assert_raise Mix.Error, "bridge_observation_test_failed", fn ->
        SoftwareBridgeBuild.verify_observation!(invalid)
      end
    end
  end

  test "paired codec receipts reject malformed requests, missing completion and sanitizer errors" do
    output = codec_output(codec_frames())
    receipt = "bridge paired request/result codec and allocation boundaries passed\n"

    for invalid <- [
          String.replace(output, receipt, ""),
          String.trim_trailing(output),
          String.replace(output, "bridge argument fixtures: 85 passed\n", ""),
          String.replace(
            output,
            "bridge argument fixtures: 85 passed\n",
            "bridge argument fixtures: 84 passed\n"
          ),
          String.replace_prefix(output, "bridge request fixture: ", "bridge request fixture: {"),
          "AddressSanitizer: fault\n" <> output,
          "LeakSanitizer: fault\n" <> output,
          "UndefinedBehaviorSanitizer: fault\n" <> output,
          "runtime error: invalid access\n" <> output
        ] do
      assert_raise Mix.Error, "bridge_codec_test_failed", fn ->
        SoftwareBridgeBuild.verify_codec!(invalid)
      end
    end
  end

  test "paired argument fixtures cover accepted and refused SDK tag/container cells" do
    fixtures = Enum.map(SoftwareBridgeBuild.argument_fixtures(), &Jason.decode!/1)
    assert length(fixtures) == 85
    assert Enum.count(fixtures, & &1["valid"]) == 32
    assert Enum.count(fixtures, &(not &1["valid"])) == 53
    assert length(Enum.uniq(fixtures)) == 84
  end

  test "paired clock receipts require exact generation, identity, time and both fixtures" do
    output = codec_output(codec_frames())

    for invalid <- [
          String.replace(output, "bridge clock sample fixture:", "missing clock fixture:"),
          String.replace(
            output,
            "bridge clock probe frames: 2 passed",
            "bridge clock probe frames: 1 passed"
          ),
          String.replace(output, "\"native_ms\":\"0\"", "\"native_ms\":\"1\""),
          String.replace(
            output,
            "\"native_ms\":\"18446744073709551615\"",
            "\"native_ms\":\"18446744073709551616\""
          )
        ] do
      assert_raise Mix.Error, "bridge_codec_test_failed", fn ->
        SoftwareBridgeBuild.verify_codec!(invalid)
      end
    end

    probes = SoftwareBridgeBuild.probe_fixtures() |> Enum.map(&Jason.decode!/1)
    assert Enum.map(probes, & &1["id"]) == ["1", "18446744073709551615"]
    assert Enum.all?(probes, &(map_size(&1) == 5 and &1["type"] == "clock-probe"))
  end

  test "the separate SDK server profile preserves model bounds and private test paths" do
    arguments = SoftwareBridgeBuild.arguments()
    assert arguments =~ "chip_build_tools = true\n"
    assert arguments =~ "chip_logging_backend = \"external\"\n"
    [encoded] = Regex.run(~r/^target_defines = (.*)$/m, arguments, capture: :all_but_first)
    defines = Jason.decode!(encoded)
    assert "CHIP_CONFIG_MAX_FABRICS=5" in defines
    assert "CHIP_IM_MAX_NUM_SUBSCRIPTIONS=15" in defines
    assert "CHIP_DEVICE_CONFIG_DEVICE_VENDOR_ID=0xFFF1" in defines
    assert "CHIP_DEVICE_CONFIG_DEVICE_PRODUCT_ID=0x8001" in defines
    assert ~s(CHIP_CONFIG_KVS_PATH="bridge-kvs") in defines
    assert ~s(CHIP_DEFAULT_FACTORY_PATH="bridge-factory.ini") in defines
    assert ~s(CHIP_DEFAULT_CONFIG_PATH="bridge-config.ini") in defines
    assert ~s(CHIP_DEFAULT_DATA_PATH="bridge-counters.ini") in defines
  end

  test "endpoint receipts require completed setup and serialized shutdown" do
    receipts = [
      "bridge endpoint metadata, custody and observations passed",
      "bridge endpoint event loop and shutdown passed"
    ]

    output = Enum.join(receipts, "\n") <> "\n\nbridge server exit: 0\n"
    assert :ok = SoftwareBridgeBuild.verify_case!(output, 0, receipts)

    for missing <- receipts do
      assert_raise Mix.Error, "bridge_server_test_failed", fn ->
        SoftwareBridgeBuild.verify_case!(String.replace(output, missing, ""), 0, receipts)
      end
    end

    assert_raise Mix.Error, "bridge_server_test_failed", fn ->
      SoftwareBridgeBuild.verify_case!("\nbridge server exit: 74\n", 74, hd(receipts))
    end
  end

  test "handoff shutdown receipt requires a prepared context and its fatal exit" do
    receipt = "bridge handoff retained context prepared"
    output = receipt <> "\n\nbridge server exit: 70\n"
    assert :ok = SoftwareBridgeBuild.verify_case!(output, 70, receipt)

    for invalid <- ["\nbridge server exit: 70\n", receipt <> "\n\nbridge server exit: 0\n"] do
      assert_raise Mix.Error, "bridge_server_test_failed", fn ->
        SoftwareBridgeBuild.verify_case!(invalid, 70, receipt)
      end
    end
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
    tasks = [
      Mix.Tasks.Wotex.Matter.Native.Build,
      Mix.Tasks.Wotex.Matter.Software.Build,
      Mix.Tasks.Wotex.Matter.Software.Run
    ]

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
      for name <- ["flow-host", "resource-host", "controller-test"],
          suffix <- ["", "-sanitized"],
          do: "bin/wotex-matter-" <> name <> suffix

    peers = ~w(bin/chip-lighting-app bin/chip-all-clusters-app bin/chip-bridge-app)

    roots =
      ~w(paa/Chip-Test-PAA-FFF1-Cert.der paa/Chip-Test-PAA-NoVID-Cert.der paa/Chip-Test-PAA-NoVID-ToResignPAIs-Cert.der)

    File.mkdir!(Path.join(workspace, "paa"))

    for name <- harnesses ++ peers ++ roots,
        do: File.write!(Path.join(workspace, name), "fixture software executable")

    software = %{
      receipt
      | "mode" => "software",
        "files" => SoftwareManifest.file_hashes(workspace, "software")
    }

    assert SoftwareManifest.verify_local(source, workspace, software, :software) == software

    for name <- harnesses ++ roots do
      path = Path.join(workspace, name)
      File.rm!(path)

      assert_raise Mix.Error, "artifact_hash_mismatch", fn ->
        SoftwareManifest.verify_local(source, workspace, software, :software)
      end

      File.write!(path, "fixture software executable")
    end

    incomplete = %{software | "files" => Map.drop(software["files"], harnesses ++ roots)}

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
          {".check.exs", "[tools: [ex_unit: false]]"},
          {"priv/schema.json", ~s({"type":"string"})}
        ] do
      configuration = Path.join(source, name)
      File.mkdir_p!(Path.dirname(configuration))
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

  test "software execution rejects absent or mismatched build receipts before acquiring resources",
       %{root: root} do
    workspace = Path.join(root, "run-workspace")
    File.mkdir!(workspace)
    marker = Path.join(workspace, "keep")
    File.write!(marker, "owned input")

    assert_raise Mix.Error, "invalid_manifest", fn ->
      SoftwareFixture.main(:run, ["--workspace", workspace])
    end

    SoftwareManifest.write(Path.join(workspace, "workspace-manifest.json"), %{"status" => "ready"})

    assert_raise Mix.Error, "manifest_mismatch", fn ->
      SoftwareFixture.main(:run, ["--workspace", workspace])
    end

    assert File.read!(marker) == "owned input"
    refute File.exists?(workspace <> ".lock")
    assert Path.wildcard(Path.join(workspace, "run-*")) == []
  end

  test "failed native builds retain the specific cause and release their workspace lock", %{
    root: root
  } do
    source = Path.join(root, "source")
    manifest = Path.join(source, "test/support/software/sources.json")
    File.mkdir_p!(Path.dirname(manifest))
    File.write!(manifest, ~s({"schema":"unsupported"}))
    workspace = Path.join(root, "failed-workspace")

    File.cd!(source, fn ->
      assert_raise Mix.Error, "source_manifest", fn ->
        SoftwareFixture.main(:native_build, ["--workspace", workspace])
      end
    end)

    assert SoftwareManifest.read(Path.join(workspace, "build-result.json")) == %{
             "schema" => "wotex.matter.software-build@1",
             "status" => "failed"
           }

    refute File.exists?(workspace <> ".lock")
    assert File.read!(manifest) == ~s({"schema":"unsupported"})
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

      Wotex.Matter.Native.ProcessCommand.run("kill", ["-KILL", Integer.to_string(os_pid)],
        stderr_to_stdout: true
      )
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

  defp codec_frames do
    read =
      BridgeWireFixture.frame()
      |> put_in(["flags", "expanded"], true)
      |> put_in(["flags", "fabric_filtered"], true)
      |> put_in(["flags", "allows_large_payload"], true)

    write =
      BridgeWireFixture.frame("write")
      |> Map.put("data_version", 0xFFFFFFFF)
      |> put_in(["flags", "expanded"], true)
      |> put_in(["flags", "timed"], true)

    writes =
      for {cluster, member, kind, value} <- [
            {3, 0, "u16", 65_535},
            {6, 0x4001, "u16", 65_535},
            {6, 0x4002, "u16", 65_535},
            {6, 0x4003, "nullable_enum8", nil},
            {6, 0x4003, "nullable_enum8", 0},
            {6, 0x4003, "nullable_enum8", 1},
            {6, 0x4003, "nullable_enum8", 2}
          ] do
        write
        |> Map.put("path", %{"endpoint" => 3, "cluster" => cluster, "member" => member})
        |> Map.put("payload", %{"kind" => kind, "value" => value})
      end

    arguments = [
      <<21, 24>>,
      <<21, 49, 1, 65_530::little-16>> <> :binary.copy(<<255>>, 65_530) <> <<24>>,
      <<21>> <> :binary.copy(<<53, 1>>, 23) <> :binary.copy(<<24>>, 24),
      <<21>> <> :binary.copy(<<41, 1>>, 4095) <> <<24>>
    ]

    invokes =
      for bytes <- arguments do
        BridgeWireFixture.frame("invoke")
        |> put_in(["flags", "timed"], true)
        |> Map.put("payload", BridgeWireFixture.arguments(bytes))
      end

    [read, put_in(read, ["principal", "auth_mode"], "group")] ++ writes ++ invokes
  end

  defp codec_output(frames) do
    samples =
      for {id, native} <- [{1, 0}, {0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF}] do
        "bridge clock sample fixture: " <>
          Jason.encode!(%{
            "v" => 1,
            "backend" => "matter-bridge",
            "type" => "clock-sample",
            "generation" => String.duplicate("ff", 16),
            "id" => Integer.to_string(id),
            "native_ms" => Integer.to_string(native)
          }) <> "\n"
      end

    Enum.map_join(frames, "", &("bridge request fixture: " <> BridgeWireFixture.encode(&1))) <>
      "bridge argument fixtures: 85 passed\n" <>
      IO.iodata_to_binary(samples) <>
      "bridge clock probe frames: 2 passed\n" <>
      "bridge paired request/result codec and allocation boundaries passed\n"
  end

  defp command_process(_, 0), do: flunk("command did not start within the bounded wait")

  defp command_process(caller, attempts) do
    {:monitors, monitors} = Process.info(caller, :monitors)

    result = Enum.find_value(monitors, fn {:process, worker} -> linked_port_pid(worker) end)

    if result do
      result
    else
      Process.sleep(10)
      command_process(caller, attempts - 1)
    end
  end

  defp linked_port_pid(worker) do
    case Process.info(worker, :links) do
      {:links, links} -> Enum.find_value(links, &port_pid(&1, worker))
      _ -> nil
    end
  end

  defp port_pid(port, worker) when is_port(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> {worker, pid}
      _ -> nil
    end
  end

  defp port_pid(_, _), do: nil

  defp wait_reaped(_, 0), do: false

  defp wait_reaped(pid, attempts) do
    case Wotex.Matter.Native.ProcessCommand.run("kill", ["-0", Integer.to_string(pid)],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        Process.sleep(10)
        wait_reaped(pid, attempts - 1)

      _ ->
        true
    end
  end
end
