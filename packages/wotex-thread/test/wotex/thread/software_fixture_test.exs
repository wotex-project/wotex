defmodule Wotex.Thread.SoftwareFixtureTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Thread.BuildFixture
  alias Wotex.Thread.Software.{Build, Run}

  @moduletag requirements: ["WTH-B01", "WTH-B03"]

  setup do
    root = Path.join(File.cwd!(), ".wotex-thread-fixture-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    unless System.get_env("WOTEX_KEEP_FIXTURE"), do: on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, workspace: Path.join(root, "workspace")}
  end

  test "WTH-B01 the production fixture environment names the checked-in test sources" do
    environment = Build.environment()
    assert environment.platform == :os.type()
    assert Path.basename(environment.tests) == "native"
    assert File.regular?(Path.join(environment.tests, "contract_driver.cpp"))
  end

  test "WTH-B01 platform, arguments and test sources are checked before building", context do
    environment = BuildFixture.software_environment(context.root)

    assert {:error, :linux_required} =
             Build.run(context.workspace, %{environment | platform: {:unix, :darwin}})

    assert {:error, :invalid_software_build_arguments} = Build.run("relative", environment)
    assert {:error, :invalid_software_build_arguments} = Build.run(:workspace, environment)

    absent = %{environment | tests: Path.join(context.root, "absent")}
    assert {:error, :software_sources_unavailable} = Build.run(context.workspace, absent)

    missing =
      BuildFixture.software_environment(Path.join(context.root, "missing"),
        missing_tools: ["readelf"]
      )

    assert {:error, {:missing_native_tool, "readelf"}} = Build.run(context.workspace, missing)
    refute File.exists?(context.workspace)
  end

  test "WTH-B01 a fixture workspace binds both native builds and every executable", context do
    environment = BuildFixture.software_environment(context.root)
    workspace = context.workspace

    assert {:ok, %{reused: false, manifest: manifest}} = Build.run(workspace, environment)
    assert manifest["schema"] == "wotex.software-build"

    assert manifest["build_features"] == %{
             "application" => %{
               "executable" => "wotex-thread-coap-peer",
               "light" => %{
                 "content_format" => "text/plain",
                 "path" => "/light/on_off",
                 "sequence" => ["0", "1", "1"]
               },
               "port" => 5683,
               "sensor" => %{
                 "content_format" => "text/plain",
                 "path" => "/sensor/temperature",
                 "payload" => "21.50",
                 "sleepy" => true
               }
             },
             "daemon" => "pinned-posix",
             "daemon_socket" => "fixtures/run/openthread-%s.sock",
             "node_ids" => %{
               "daemon" => 43,
               "joiner" => 42,
               "leader" => 41,
               "light" => 45,
               "sensor" => 44
             },
             "sanitized_tests" => true,
             "rcp_platform" => "simulation"
           }

    assert Map.keys(manifest["source_files"]) == ["priv/openthread", "test/native"]
    executables = Build.executables(workspace)

    for path <-
          [
            executables.host,
            executables.sanitized_host,
            executables.rcp,
            executables.daemon,
            executables.coap_peer
          ] ++
            [executables.contract_driver, executables.dataset_seed, executables.flow_host] ++
            executables.native_tests do
      assert File.regular?(path), path
    end

    recorded = Map.new(manifest["audit"]["binaries"], &{&1["path"], &1["sha256"]})
    assert recorded["fixtures/bin/ot-rcp"] == digest(executables.rcp)
    assert recorded["fixtures/bin/ot-daemon"] == digest(executables.daemon)
    assert recorded["fixtures/bin/wotex-thread-coap-peer"] == digest(executables.coap_peer)
    assert recorded["fixtures/bin/wotex-thread-flow-host"] == digest(executables.flow_host)
    assert File.regular?(Path.join(workspace, "native/native-manifest.json"))
    assert File.regular?(Path.join(workspace, "native-sanitized/native-manifest.json"))

    # Both native manifests and the fixture manifest verify without rebuilding.
    assert {:ok, %{reused: true, manifest: ^manifest}} = Build.run(workspace, environment)

    File.write!(executables.rcp, "changed")
    assert {:error, :build_manifest_mismatch} = Build.run(workspace, environment)
  end

  test "WTH-B03 a software run records lanes, native tests, cleanup and source identity",
       context do
    workspace = prepared(context)
    project = project_root(context)
    environment = run_environment(context, workspace, project, proc_table(context, nil))

    assert {:ok, %{result: result, path: path}} = Run.run(workspace, environment)
    assert result["schema"] == "wotex.thread.software-run" and result["status"] == "passed"
    assert result["source_unchanged"]
    assert Enum.map(result["native_tests"], & &1["exit_status"]) == [0, 0, 0, 0, 0, 0, 0]
    assert Enum.map(result["lanes"], & &1["lane"]) == ["normal", "sanitized"]
    assert Enum.all?(result["lanes"], & &1["evaluation"]["accepted"])
    assert result["cleanup"] == %{"survivors" => 0}

    assert result["fixture"] == %{
             "daemon_socket" => "fixtures/run/openthread-wthdaemon.sock",
             "node_ids" => %{
               "daemon" => 43,
               "joiner" => 42,
               "leader" => 41,
               "light" => 45,
               "sensor" => 44
             }
           }

    assert result["toolchain"]["elixir"] == System.version()
    assert result["native_hosts"]["normal"] == digest(Build.executables(workspace).host)
    assert File.regular?(path) and Jason.decode!(File.read!(path)) == result

    # A run directory is terminal; the same workspace cannot run twice.
    assert {:error, :software_run_exists} = Run.run(workspace, environment)
  end

  test "WTH-B03 a process still executing a workspace binary fails the run and is killed",
       context do
    workspace = prepared(context)
    project = project_root(context)
    survivor = survivor(workspace)
    environment = run_environment(context, workspace, project, proc_table(context, survivor))

    assert {:error, {:software_run_failed, path}} = Run.run(workspace, environment)
    result = Jason.decode!(File.read!(path))
    assert result["status"] == "failed" and result["cleanup"] == %{"survivors" => 1}
    assert Enum.all?(result["lanes"], & &1["evaluation"]["accepted"])
    assert_eventually(fn -> Port.info(survivor.port) == nil end)
  end

  test "WTH-B03 a lane that misses a required case or changes the source fails the run", context do
    workspace = prepared(context)
    project = project_root(context)
    proc = proc_table(context, nil)

    environment =
      run_environment(context, workspace, project, proc, mix: mix_script(project, :incomplete))

    assert {:error, {:software_run_failed, path}} = Run.run(workspace, environment)
    result = Jason.decode!(File.read!(path))
    assert result["status"] == "failed"
    [normal, _] = result["lanes"]
    refute normal["evaluation"]["accepted"]
    assert normal["evaluation"]["missing_or_not_passed"] == [%{"module" => "M", "name" => "two"}]

    changed = prepared(context, "changed")

    touching =
      run_environment(context, changed, project, proc, mix: mix_script(project, :touch_source))

    assert {:error, {:software_run_failed, second}} = Run.run(changed, touching)
    refute Jason.decode!(File.read!(second))["source_unchanged"]
  end

  test "WTH-B03 platform, build state, inventory and runner are required", context do
    workspace = prepared(context)
    project = project_root(context)
    proc = proc_table(context, nil)
    environment = run_environment(context, workspace, project, proc)

    assert {:error, :linux_required} =
             Run.run(workspace, %{environment | platform: {:unix, :darwin}})

    assert {:error, :invalid_software_run_arguments} = Run.run("relative", environment)
    assert {:error, :invalid_software_run_arguments} = Run.run(:workspace, environment)

    empty = Path.join(context.root, "empty")
    File.mkdir_p!(empty)
    assert {:error, :software_workspace_not_built} = Run.run(empty, environment)

    File.write!(Path.join(project, "test/software/acceptance.json"), "{}")
    assert {:error, :invalid_software_inventory} = Run.run(workspace, environment)

    malformed = %{inventory() | "lanes" => %{"normal" => %{"paths" => []}, "sanitized" => %{}}}
    File.write!(Path.join(project, "test/software/acceptance.json"), Jason.encode!(malformed))
    assert {:error, :invalid_software_inventory} = Run.run(workspace, environment)
  end

  test "WTH-B03 a suite runner that exits nonzero fails its lane", context do
    workspace = prepared(context)
    project = project_root(context)
    proc = proc_table(context, nil)

    environment =
      run_environment(context, workspace, project, proc, mix: mix_script(project, :crash))

    assert {:error, {:software_run_failed, path}} = Run.run(workspace, environment)
    [normal, _] = Jason.decode!(File.read!(path))["lanes"]
    assert normal["exit_status"] == 7 and normal["evaluation"]["accepted"]
  end

  defp prepared(context, name \\ "workspace") do
    workspace = Path.join(context.root, name)
    environment = BuildFixture.software_environment(context.root)
    assert {:ok, %{reused: false}} = Build.run(workspace, environment)
    workspace
  end

  defp run_environment(context, _, project, proc, options \\ []) do
    build = fn path -> Build.run(path, BuildFixture.software_environment(context.root)) end

    %{
      platform: {:unix, :linux},
      project_root: project,
      build: build,
      mix: Keyword.get_lazy(options, :mix, fn -> mix_script(project, :complete) end),
      proc: proc
    }
  end

  # A disposable checkout with the inventory and the trees a run identifies.
  defp project_root(context) do
    project = Path.join(context.root, "project")

    for path <- ~w(lib priv/openthread test/software priv/fixtures) do
      File.mkdir_p!(Path.join(project, path))
      File.write!(Path.join([project, path, "placeholder"]), "disposable\n")
    end

    for path <- ~w(mix.exs mix.lock), do: File.write!(Path.join(project, path), "disposable\n")
    File.write!(Path.join(project, "test/software/acceptance.json"), Jason.encode!(inventory()))
    project
  end

  defp inventory do
    required = [%{"module" => "M", "name" => "one"}, %{"module" => "M", "name" => "two"}]

    %{
      "format" => "wotex.thread.software-acceptance",
      "version" => 1,
      "lanes" => %{
        "normal" => %{"paths" => [], "required" => required},
        "sanitized" => %{"paths" => ["test/software"], "required" => required}
      }
    }
  end

  # The recorded suite runner writes the case lines its lane observed.
  defp mix_script(project, mode) do
    path = Path.join(project, "mix-#{mode}")
    cases = if mode == :incomplete, do: ~w(one), else: ~w(one two)

    File.write!(path, """
    #!/bin/sh
    #{if mode == :touch_source, do: "date > #{Path.join(project, "lib/placeholder")}", else: ""}
    for name in #{Enum.join(cases, " ")}; do
      printf '{"module":"M","name":"%s","state":"passed"}\\n' "$name" >> "$WOTEX_THREAD_CASE_RESULTS"
    done
    exit #{if mode == :crash, do: 7, else: 0}
    """)

    File.chmod!(path, 0o755)
    path
  end

  # One owned process still executing a workspace binary after the lanes.
  defp survivor(workspace) do
    executable = Path.join(workspace, "tmp/survivor")
    File.mkdir_p!(Path.dirname(executable))
    File.write!(executable, "#!/bin/sh\nexec sleep 30\n")
    File.chmod!(executable, 0o755)
    port = Port.open({:spawn_executable, executable}, [:binary, :exit_status, args: []])
    {:os_pid, os_pid} = Port.info(port, :os_pid)

    on_exit(fn ->
      try do
        Port.close(port)
      rescue
        ArgumentError -> :ok
      end
    end)

    %{port: port, os_pid: os_pid, executable: executable}
  end

  defp proc_table(context, survivor) do
    proc = Path.join(context.root, "proc-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(proc, "self"))

    if survivor do
      entry = Path.join(proc, Integer.to_string(survivor.os_pid))
      File.mkdir_p!(entry)
      File.ln_s!(survivor.executable, Path.join(entry, "exe"))
    end

    proc
  end

  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)

  defp assert_eventually(condition, remaining \\ 200)
  defp assert_eventually(condition, 0), do: assert(condition.())

  defp assert_eventually(condition, remaining) do
    unless condition.() do
      Process.sleep(10)
      assert_eventually(condition, remaining - 1)
    end
  end
end
