defmodule Wotex.Thread.Software.Build do
  @moduledoc """
  Builds the manifest-bound Linux software fixtures for the Thread profile.

  One disposable workspace receives a normal and an AddressSanitizer/
  UndefinedBehaviorSanitizer native host through `Wotex.Thread.Native.Build`,
  the pinned OpenThread simulation RCP, and sanitizer-instrumented native test
  executables. The native parser, output, flow and storage tests plus the
  contract driver link only first-party headers; the Dataset seed and Spinel
  test link the manifest-bound patched SDK tree. An uninstrumented
  `wotex-thread-flow-host` adds a test-only State callback source to the
  production host for process-flow cases. Every command runs through the
  owned build guardian with separate arguments and an explicit environment.

  The source checkout must contain `test/native`; package consumers do not
  receive these fixtures. A completed workspace is reused only after its own
  manifest and both native manifests verify. Building starts no fixture and
  does not establish software acceptance; `Wotex.Thread.Software.Run` owns
  execution.
  """

  alias Wotex.Thread.Native.{Bootstrap, Build, Command, Source, Workspace}

  @project_root Path.expand("../../../..", __DIR__)
  @sdk "openthread-5c8c318627954c99cd1a957a290bbd4b1027d04b"
  @tools ~w(cmake ninja cc c++ readelf)
  @pure_tests ~w(wotex-thread-protocol-test wotex-thread-storage-test wotex-thread-output-test
    wotex-thread-streams-test wotex-thread-flow-test wotex-thread-contract-driver)
  @sdk_tests ~w(wotex-thread-dataset-seed wotex-thread-spinel-test)
  @native_tests ~w(wotex-thread-protocol-test wotex-thread-storage-test wotex-thread-output-test
    wotex-thread-streams-test wotex-thread-flow-test wotex-thread-spinel-test)
  @log_names ~w(bootstrap version_cmake version_ninja version_cc version_cxx rcp_configure
    rcp_compile tests_configure tests_compile flow_configure flow_compile)
  @build_modules [__MODULE__, Mix.Tasks.Wotex.Thread.Software.Build]
  @tool_bytes 100_000_000
  @rcp_options ~w(-DOT_PLATFORM=simulation -DOT_APP_CLI=OFF -DOT_APP_NCP=OFF -DOT_APP_RCP=ON
    -DOT_FTD=OFF -DOT_MTD=OFF -DOT_RCP=ON -DOT_COMPILE_WARNING_AS_ERROR=ON -DBUILD_TESTING=OFF)

  @doc "Validates exactly one absolute `--workspace` argument."
  @spec arguments(term()) :: {:ok, Path.t()} | {:error, :invalid_software_build_arguments}
  def arguments(["--workspace", workspace]) do
    case Workspace.arguments(["--workspace", workspace]) do
      {:ok, workspace, false} -> {:ok, workspace}
      _ -> {:error, :invalid_software_build_arguments}
    end
  end

  def arguments(_), do: {:error, :invalid_software_build_arguments}

  @doc "Returns the fixture executable paths recorded under a software workspace."
  @spec executables(Path.t()) :: %{atom() => Path.t() | [Path.t()]}
  def executables(workspace) do
    bin = Path.join(workspace, "fixtures/bin")

    %{
      host: Path.join(workspace, "native/build/wotex-thread-host"),
      sanitized_host: Path.join(workspace, "native-sanitized/build/wotex-thread-host"),
      rcp: Path.join(bin, "ot-rcp"),
      contract_driver: Path.join(bin, "wotex-thread-contract-driver"),
      dataset_seed: Path.join(bin, "wotex-thread-dataset-seed"),
      flow_host: Path.join(bin, "wotex-thread-flow-host"),
      native_tests: Enum.map(@native_tests, &Path.join(bin, &1))
    }
  end

  @typedoc """
  The explicit outside world of one fixture build.

  It extends the native build environment with `tests`, the first-party
  `test/native` sources that only a source checkout contains.
  """
  @type environment :: %{
          required(:platform) => {atom(), atom()},
          required(:native) => Path.t(),
          required(:search_path) => String.t() | nil,
          required(:fetch) => (String.t(), Path.t(), String.t() -> :ok | {:error, atom()}),
          required(:tests) => Path.t()
        }

  @doc "Returns the production fixture build environment."
  @spec environment() :: environment()
  def environment,
    do: Map.put(Build.environment(), :tests, Path.join(@project_root, "test/native"))

  @doc "Builds an empty workspace, or verifies a completed workspace without rebuilding."
  @spec run(term(), environment()) :: {:ok, Workspace.result()} | {:error, term()}
  def run(workspace, environment \\ environment())

  def run(workspace, environment) when is_binary(workspace) and is_map(environment) do
    native = environment.native
    tests = environment.tests

    with :ok <- platform(environment),
         {:ok, ^workspace} <- arguments(["--workspace", workspace]),
         true <- File.dir?(tests) || {:error, :software_sources_unavailable},
         {:ok, tools} <- tools(environment),
         {:ok, native_files} <- Source.file_hashes(native),
         {:ok, test_files} <- Source.file_hashes(tests),
         {:ok, modules} <- build_modules() do
      identity = identity(workspace, native, tests, tools, native_files, test_files, modules)
      builder = fn -> build(workspace, native, tests, tools, environment) end

      with {:ok, result} <- Workspace.run(workspace, identity, artifacts(), builder, :software),
           {:ok, _} <- Build.run(Path.join(workspace, "native"), false, environment),
           {:ok, _} <- Build.run(Path.join(workspace, "native-sanitized"), true, environment) do
        {:ok, result}
      end
    end
  end

  def run(_, _), do: {:error, :invalid_software_build_arguments}

  defp platform(%{platform: platform}) do
    if platform == {:unix, :linux}, do: :ok, else: {:error, :linux_required}
  end

  defp tools(environment) do
    Enum.reduce_while(@tools, {:ok, %{}}, fn name, {:ok, found} ->
      # Compiler names are commonly links; the recorded digest is of the selected target.
      with path when is_binary(path) <- Source.executable(name, environment.search_path),
           {:ok, hash} <- tool_digest(path) do
        {:cont, {:ok, Map.put(found, name, %{path: path, sha256: hash})}}
      else
        _ -> {:halt, {:error, {:missing_native_tool, name}}}
      end
    end)
  end

  defp tool_digest(path) do
    with {:ok, %File.Stat{type: :regular, size: size}} when size <= @tool_bytes <- File.stat(path),
         {:ok, bytes} <- File.read(path) do
      {:ok, Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)}
    end
  end

  defp build_modules do
    Enum.reduce_while(@build_modules, {:ok, %{}}, fn module, {:ok, hashes} ->
      case Source.module_digest(module) do
        {:ok, hash} -> {:cont, {:ok, Map.put(hashes, Atom.to_string(module), hash)}}
        _ -> {:halt, {:error, :missing_software_build_module}}
      end
    end)
  end

  defp identity(workspace, native, tests, tools, native_files, test_files, modules) do
    %{
      "source_files" => %{"priv/openthread" => native_files, "test/native" => test_files},
      "build_modules" => modules,
      "toolchain" => tools,
      "build_features" => %{"sanitized_tests" => true, "rcp_platform" => "simulation"},
      "arguments" => %{
        "rcp_configure" => rcp_configure(workspace, tools),
        "tests_configure" => tests_configure(workspace, native, tests, tools),
        "tests_targets" => @pure_tests ++ @sdk_tests,
        "flow_configure" => flow_configure(workspace, native, tests, tools)
      },
      "environment_allowlist" => ~w(HOME LC_ALL PATH TMPDIR)
    }
  end

  defp artifacts do
    ["bin/build-command", "native/native-manifest.json", "native-sanitized/native-manifest.json"] ++
      Enum.map(
        ["ot-rcp", "wotex-thread-flow-host" | @pure_tests ++ @sdk_tests],
        &"fixtures/bin/#{&1}"
      ) ++
      Enum.map(@log_names, &"logs/#{&1}.log")
  end

  defp build(workspace, native, tests, tools, environment) do
    guardian = Path.join(workspace, "bin/build-command")

    with :ok <- directories(workspace),
         {:ok, bootstrap} <-
           Bootstrap.compile(
             tools["cc"].path,
             Path.join(native, "build_command.c"),
             guardian,
             workspace
           ),
         :ok <-
           File.write(Path.join(workspace, "logs/bootstrap.log"), bootstrap.output, [:exclusive]),
         {:ok, versions} <- versions(guardian, workspace, tools),
         {:ok, _} <- Build.run(Path.join(workspace, "native"), false, environment),
         {:ok, _} <- Build.run(Path.join(workspace, "native-sanitized"), true, environment),
         :ok <- rcp(guardian, workspace, tools),
         :ok <- tests(guardian, workspace, native, tests, tools),
         :ok <- flow_host(guardian, workspace, native, tests, tools),
         {:ok, binaries} <- binaries(workspace) do
      {:ok, %{"toolchain_versions" => versions, "binaries" => binaries}}
    else
      {:error, code, result} -> {:error, {code, result}}
      {:error, _} = error -> error
      _ -> {:error, :software_build_failed}
    end
  end

  defp directories(workspace) do
    Enum.reduce_while(~w(bin logs tmp fixtures/bin), :ok, fn name, :ok ->
      case File.mkdir_p(Path.join(workspace, name)) do
        :ok -> {:cont, :ok}
        _ -> {:halt, {:error, :software_build_filesystem}}
      end
    end)
  end

  defp versions(guardian, workspace, tools) do
    [
      {:version_cmake, "cmake"},
      {:version_ninja, "ninja"},
      {:version_cc, "cc"},
      {:version_cxx, "c++"}
    ]
    |> Enum.reduce_while({:ok, %{}}, fn {id, name}, {:ok, found} ->
      case command(guardian, workspace, id, tools[name].path, ["--version"], 10_000) do
        {:ok, output} -> {:cont, {:ok, Map.put(found, name, String.trim(output))}}
        error -> {:halt, error}
      end
    end)
  end

  defp rcp(guardian, workspace, tools) do
    build = Path.join(workspace, "fixtures/rcp-build")

    with {:ok, _} <-
           command(
             guardian,
             workspace,
             :rcp_configure,
             tools["cmake"].path,
             rcp_configure(workspace, tools),
             300_000
           ),
         {:ok, _} <-
           command(
             guardian,
             workspace,
             :rcp_compile,
             tools["cmake"].path,
             ["--build", build, "--target", "ot-rcp", "-j4"],
             1_800_000
           ) do
      copy(
        Path.join(build, "examples/apps/ncp/ot-rcp"),
        Path.join(workspace, "fixtures/bin/ot-rcp")
      )
    end
  end

  defp tests(guardian, workspace, native, tests, tools) do
    build = Path.join(workspace, "fixtures/tests-build")

    with {:ok, _} <-
           command(
             guardian,
             workspace,
             :tests_configure,
             tools["cmake"].path,
             tests_configure(workspace, native, tests, tools),
             300_000
           ),
         {:ok, _} <-
           command(
             guardian,
             workspace,
             :tests_compile,
             tools["cmake"].path,
             ["--build", build, "-j4", "--target" | @pure_tests ++ @sdk_tests],
             1_800_000
           ) do
      Enum.reduce_while(@pure_tests ++ @sdk_tests, :ok, fn name, :ok ->
        case copy(Path.join(build, name), Path.join(workspace, "fixtures/bin/#{name}")) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  # The process-flow host is uninstrumented: its callback rate, not sanitizer coverage,
  # is what the suspended-owner cases exercise.
  defp flow_host(guardian, workspace, native, tests, tools) do
    build = Path.join(workspace, "fixtures/flow-build")

    with {:ok, _} <-
           command(
             guardian,
             workspace,
             :flow_configure,
             tools["cmake"].path,
             flow_configure(workspace, native, tests, tools),
             300_000
           ),
         {:ok, _} <-
           command(
             guardian,
             workspace,
             :flow_compile,
             tools["cmake"].path,
             ["--build", build, "--target", "wotex-thread-flow-host", "-j4"],
             1_800_000
           ) do
      copy(
        Path.join(build, "wotex-thread-flow-host"),
        Path.join(workspace, "fixtures/bin/wotex-thread-flow-host")
      )
    end
  end

  defp flow_configure(workspace, native, tests, tools) do
    [
      "-G",
      "Ninja",
      "-S",
      native,
      "-B",
      Path.join(workspace, "fixtures/flow-build"),
      "-DCMAKE_BUILD_TYPE=RelWithDebInfo",
      "-DWOTEX_NATIVE_SANITIZERS=OFF",
      "-DWOTEX_JSON_HEADER=#{Path.join(workspace, "native/downloads/json.hpp")}",
      "-DWOTEX_OPENTHREAD_SOURCE=#{Path.join([workspace, "native/sources/openthread", @sdk])}",
      "-DWOTEX_NATIVE_TEST_SOURCE=#{tests}",
      "-DCMAKE_C_COMPILER=#{tools["cc"].path}",
      "-DCMAKE_CXX_COMPILER=#{tools["c++"].path}"
    ]
  end

  defp rcp_configure(workspace, tools) do
    [
      "-G",
      "Ninja",
      "-S",
      Path.join([workspace, "native/sources/openthread", @sdk]),
      "-B",
      Path.join(workspace, "fixtures/rcp-build"),
      "-DCMAKE_C_COMPILER=#{tools["cc"].path}",
      "-DCMAKE_CXX_COMPILER=#{tools["c++"].path}" | @rcp_options
    ]
  end

  defp tests_configure(workspace, native, tests, tools) do
    [
      "-G",
      "Ninja",
      "-S",
      native,
      "-B",
      Path.join(workspace, "fixtures/tests-build"),
      "-DCMAKE_BUILD_TYPE=Debug",
      "-DWOTEX_NATIVE_SANITIZERS=ON",
      "-DWOTEX_JSON_HEADER=#{Path.join(workspace, "native-sanitized/downloads/json.hpp")}",
      "-DWOTEX_OPENTHREAD_SOURCE=#{Path.join([workspace, "native-sanitized/sources/openthread", @sdk])}",
      "-DWOTEX_NATIVE_TEST_SOURCE=#{tests}",
      "-DCMAKE_C_COMPILER=#{tools["cc"].path}",
      "-DCMAKE_CXX_COMPILER=#{tools["c++"].path}"
    ]
  end

  defp copy(source, destination) do
    with {:ok, %File.Stat{type: :regular}} <- File.lstat(source),
         :ok <- File.cp(source, destination),
         :ok <- File.chmod(destination, 0o755) do
      :ok
    else
      _ -> {:error, {:missing_software_artifact, Path.basename(source)}}
    end
  end

  defp binaries(workspace) do
    names = ["ot-rcp", "wotex-thread-flow-host" | @pure_tests ++ @sdk_tests]

    result =
      Enum.reduce_while(names, {:ok, []}, fn name, {:ok, found} ->
        path = "fixtures/bin/#{name}"

        case Source.digest(Path.join(workspace, path)) do
          {:ok, hash} -> {:cont, {:ok, [%{"path" => path, "sha256" => hash} | found]}}
          _ -> {:halt, {:error, :invalid_software_artifact}}
        end
      end)

    with {:ok, found} <- result, do: {:ok, Enum.reverse(found)}
  end

  defp command(guardian, workspace, id, executable, args, timeout_ms) do
    directories = Enum.uniq([Path.dirname(executable), "/usr/bin", "/bin"])
    path = Enum.join(directories, ":")

    step = %{
      id: id,
      executable: executable,
      cwd: workspace,
      args: args,
      env: [
        {"PATH", path},
        {"LC_ALL", "C"},
        {"HOME", workspace},
        {"TMPDIR", Path.join(workspace, "tmp")}
      ],
      timeout_ms: timeout_ms,
      output_bytes: 16_777_216,
      cleanup_ms: 5_000
    }

    result = Command.run(guardian, step)

    output =
      case result do
        {:ok, details} -> details.output
        {:error, _, details} -> details.output
      end

    with :ok <- File.write(Path.join(workspace, "logs/#{id}.log"), output, [:exclusive]) do
      case result do
        {:ok, _} -> {:ok, output}
        {:error, code, details} -> {:error, {code, id, details.exit_status}}
      end
    end
  end
end
