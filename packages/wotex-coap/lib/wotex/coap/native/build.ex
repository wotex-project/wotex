defmodule Wotex.CoAP.Native.Build do
  @moduledoc """
  Builds the pinned libcoap OSCORE helper in an explicit owned workspace.

  The build resolves and fingerprints its toolchain once, verifies the bounded
  source archive and ordered patches, builds a static libcoap, compiles the
  packaged worker and publishes `native-manifest.json` only after exact feature,
  readiness and dependency probes. Completed workspaces are verified read-only.
  Dependency loading and ordinary compilation never call this module.
  """

  alias Wotex.CoAP.Native.{BuildOperations, Toolchain, Workspace}

  @revision "7cf7465b784baded4de183290c547d582becfd28"
  @version "4.3.5"
  @source_url "https://codeload.github.com/obgm/libcoap/tar.gz/#{@revision}"
  @source_sha256 "d8ce60574b1ed60ab1ef5c8d656bdf1c4a28fff0a00e9cb9f2cce3772f9db8cd"
  @archive_root "libcoap-#{@revision}"
  @project_root Path.expand("../../../..", __DIR__)
  @native_root Path.join(@project_root, "native/oscore")
  @source_manifest Path.join(@native_root, "source.json")
  @yyjson_manifest Path.join(@native_root, "vendor/yyjson/source.json")
  @build_sources [
    __ENV__.file,
    Path.join(__DIR__, "archive.ex"),
    Path.join(__DIR__, "build_command.ex"),
    Path.join(__DIR__, "build_operations.ex"),
    Path.join(__DIR__, "toolchain.ex"),
    Path.join(__DIR__, "workspace.ex"),
    Path.join(@project_root, "lib/mix/tasks/wotex.coap.native.build.ex"),
    Path.join(@project_root, "mix.exs")
  ]
  @native_files @native_root
                |> Path.join("**/*")
                |> Path.wildcard()
                |> Enum.filter(&File.regular?/1)
                |> Enum.map(&Path.relative_to(&1, @native_root))
                |> Enum.sort()
  for file <- Enum.map(@native_files, &Path.join(@native_root, &1)), do: @external_resource(file)
  @external_resource @source_manifest
  @external_resource @yyjson_manifest

  @cmake_options [
    "ENABLE_OSCORE=ON",
    "ENABLE_DTLS=ON",
    "DTLS_BACKEND=openssl",
    "BUILD_SHARED_LIBS=OFF",
    "ENABLE_DOCS=OFF",
    "ENABLE_EXAMPLES=OFF",
    "CMAKE_BUILD_TYPE=Release"
  ]
  @worker_sources ~w(main.c worker.c exchange.c observation.c custody.c command.c json.c frame.c
    body.c credit.c identity.c store.c vendor/yyjson/yyjson.c)
  @yyjson_definitions ~w(YYJSON_DISABLE_NON_STANDARD=1 YYJSON_DISABLE_UTILS=1
    YYJSON_DISABLE_INCR_READER=1)
  @log_names [
               "bootstrap",
               "tool-versions",
               "download"
             ] ++
               Enum.map(1..7, &("patch-" <> String.pad_leading(Integer.to_string(&1), 2, "0"))) ++
               ~w(cmake-configure cmake-build feature-probe-build feature-probe worker-build
                 worker-probe-build worker-probe dynamic-dependencies)
  @artifacts ~w(bin/build-command bin/wotex-coap-oscore downloads/libcoap.tar.gz
    lib/libcoap-3.a) ++ Enum.map(@log_names, &("logs/" <> &1 <> ".log"))
  @build_timeout 600_000

  @doc "Builds or verifies one content-bound native workspace."
  @spec run(term()) :: {:ok, Workspace.result()} | {:error, term()}
  def run(workspace), do: run(workspace, BuildOperations)

  @doc false
  @spec run(term(), module()) :: {:ok, Workspace.result()} | {:error, term()}
  def run(workspace, operations) when is_binary(workspace) and is_atom(operations) do
    with {:ok, source} <- source(),
         {:ok, yyjson} <- yyjson(),
         {:ok, tools} <- operations.resolve(),
         :ok <- verify_inputs(source, yyjson, operations),
         {:ok, identity} <- identity(source, yyjson, tools, operations),
         {:ok, result} <-
           Workspace.run(workspace, identity, @artifacts, fn ->
             build(workspace, source, yyjson, tools, identity, operations)
           end) do
      verify_reuse(result, workspace, tools, operations)
    end
  rescue
    error in [ArgumentError, File.Error, UndefinedFunctionError] ->
      {:error, {:native_build_setup, Exception.message(error)}}
  end

  def run(_, _), do: {:error, :invalid_build_workspace}

  @doc "Validates the exact root-task argument shape before build I/O."
  @spec arguments(term()) :: {:ok, String.t()} | {:error, :invalid_native_build_arguments}
  def arguments(["--workspace", workspace]) when is_binary(workspace) do
    if String.valid?(workspace) and byte_size(workspace) in 1..4096 and
         Path.type(workspace) == :absolute and
         not String.contains?(workspace, [<<0>>, "\n", "\r"]) and
         Enum.all?(Path.split(workspace), &(&1 not in [".", ".."])) do
      {:ok, workspace}
    else
      {:error, :invalid_native_build_arguments}
    end
  end

  def arguments(_), do: {:error, :invalid_native_build_arguments}

  defp source do
    with {:ok, value} <- decode(@source_manifest),
         %{
           "schema" => "wotex.coap.libcoap-source@1",
           "version" => @version,
           "commit" => @revision,
           "url" => @source_url,
           "sha256" => @source_sha256,
           "patches" => patches,
           "patched_sources" => patched
         } <- value,
         true <- valid_patches?(patches),
         true <- valid_hash_map?(patched) do
      {:ok, value}
    else
      _ -> {:error, :invalid_source_manifest}
    end
  end

  defp yyjson do
    with {:ok, value} <- decode(@yyjson_manifest),
         %{
           "schema" => "wotex.coap.yyjson-source@1",
           "version" => "0.12.0",
           "commit" => "8b4a38dc994a110abaec8a400615567bd996105f",
           "license" => "MIT",
           "modifications" => [],
           "files" => files,
           "compile_definitions" => @yyjson_definitions,
           "read_flags" => ["YYJSON_READ_NUMBER_AS_RAW"]
         } <- value,
         true <- Map.keys(files) |> Enum.sort() == ~w(LICENSE yyjson.c yyjson.h),
         true <- valid_hash_map?(files) do
      {:ok, value}
    else
      _ -> {:error, :invalid_yyjson_manifest}
    end
  end

  defp decode(path) do
    with {:ok, bytes} <- File.read(path),
         true <- byte_size(bytes) <= 262_144,
         {:ok, value} when is_map(value) <- Jason.decode(bytes) do
      {:ok, value}
    else
      _ -> {:error, :invalid_native_build_input}
    end
  end

  defp valid_patches?(patches) when is_list(patches) and length(patches) == 7 do
    paths = Enum.map(patches, & &1["path"])

    length(Enum.uniq(paths)) == 7 and
      Enum.all?(patches, fn
        %{"path" => "patches/" <> path, "sha256" => hash} when is_binary(path) ->
          path != "" and not String.contains?(path, ["/", "\\", "..", <<0>>]) and hash?(hash)

        _ ->
          false
      end)
  end

  defp valid_patches?(_), do: false

  defp valid_hash_map?(value) when is_map(value),
    do: map_size(value) > 0 and Enum.all?(value, &hash_entry?/1)

  defp valid_hash_map?(_), do: false
  defp hash_entry?({path, hash}), do: is_binary(path) and path != "" and hash?(hash)
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)

  defp verify_inputs(source, yyjson, operations) do
    checks =
      Enum.map(source["patches"], fn patch ->
        {Path.join(@native_root, patch["path"]), patch["sha256"]}
      end) ++
        Enum.map(yyjson["files"], fn {file, hash} ->
          {Path.join([@native_root, "vendor/yyjson", file]), hash}
        end)

    Enum.reduce_while(checks, :ok, fn {path, expected}, :ok ->
      case operations.digest(path) do
        {:ok, ^expected} -> {:cont, :ok}
        _ -> {:halt, {:error, :native_build_input_mismatch}}
      end
    end)
  end

  defp identity(source, yyjson, tools, operations) do
    with {:ok, native_hashes} <- hashes(@native_root, @native_files, operations),
         {:ok, build_hashes} <- build_hashes(operations) do
      {:ok,
       json(%{
         "format_version" => 1,
         "source" => source,
         "yyjson" => yyjson,
         "native_inputs" => native_hashes,
         "build_inputs" => build_hashes,
         "tool_paths" => tools.paths,
         "tool_hashes" => tools.hashes,
         "openssl_root" => tools.openssl_root,
         "target" => tools.target,
         "os_version" => :os.version(),
         "cmake_options" => @cmake_options,
         "worker_definitions" => @yyjson_definitions
       })}
    end
  end

  defp hashes(root, files, operations) do
    Enum.reduce_while(files, {:ok, %{}}, fn file, {:ok, result} ->
      case operations.digest(Path.join(root, file)) do
        {:ok, digest} -> {:cont, {:ok, Map.put(result, file, digest)}}
        _ -> {:halt, {:error, :native_build_input_mismatch}}
      end
    end)
  end

  defp build_hashes(operations) do
    Enum.reduce_while(@build_sources, {:ok, %{}}, fn path, {:ok, result} ->
      case operations.digest(path) do
        {:ok, digest} ->
          {:cont, {:ok, Map.put(result, Path.relative_to(path, @project_root), digest)}}

        _ ->
          {:halt, {:error, :native_build_input_mismatch}}
      end
    end)
  end

  defp build(workspace, source, yyjson, tools, expected_identity, operations) do
    deadline = System.monotonic_time(:millisecond) + @build_timeout

    with :ok <- directories(workspace),
         {:ok, bootstrap} <- bootstrap(workspace, tools, deadline, operations),
         guardian = Path.join(workspace, "bin/build-command"),
         environment = environment(tools),
         {:ok, versions} <-
           versions(guardian, workspace, tools, environment, deadline, operations, true),
         {:ok, download, _} <-
           download(guardian, workspace, source, environment, deadline, tools, operations),
         :ok <- extract(workspace, source, operations),
         {:ok, patch_steps} <-
           patch(guardian, workspace, source, environment, deadline, tools, operations),
         :ok <- verify_patched(workspace, source, operations),
         {:ok, configure, _} <-
           configure(guardian, workspace, tools, environment, deadline, operations),
         {:ok, compile, _} <-
           compile_libcoap(guardian, workspace, tools, environment, deadline, operations),
         :ok <- copy_static_library(workspace),
         {:ok, probe_build, _} <-
           compile_probe(guardian, workspace, tools, environment, deadline, operations),
         {:ok, feature_step, feature_output} <-
           run_step(
             guardian,
             workspace,
             "feature-probe",
             probe_path(workspace),
             [],
             environment,
             deadline,
             10_000,
             operations
           ),
         {:ok, feature} <- feature(feature_output),
         {:ok, worker_build, _} <-
           compile_worker(guardian, workspace, tools, environment, deadline, operations),
         {:ok, worker_probe_build, _} <-
           compile_worker_probe(
             guardian,
             workspace,
             tools,
             environment,
             deadline,
             operations
           ),
         {:ok, worker_step, worker_output} <-
           run_step(
             guardian,
             workspace,
             "worker-probe",
             worker_probe_path(workspace),
             [worker_path(workspace)],
             environment,
             deadline,
             10_000,
             operations
           ),
         {:ok, ready} <- ready(worker_output),
         {:ok, dependency_step, dependency_output} <-
           dependencies(guardian, workspace, tools, environment, deadline, operations),
         {:ok, dependency_list} <- dependency_list(dependency_output),
         {:ok, executable_hash} <- operations.digest(worker_path(workspace)),
         {:ok, static_hash} <- operations.digest(Path.join(workspace, "lib/libcoap-3.a")),
         {:ok, current_tools} <- operations.identify(tools.paths, tools.openssl_root, tools.target),
         {:ok, ^expected_identity} <- identity(source, yyjson, current_tools, operations),
         :ok <- cleanup(workspace) do
      steps =
        [bootstrap, download] ++
          patch_steps ++
          [
            configure,
            compile,
            probe_build,
            feature_step,
            worker_build,
            worker_probe_build,
            worker_step,
            dependency_step
          ]

      {:ok,
       %{
         "schema" => "wotex.coap.native@1",
         "backend" => %{"name" => "libcoap", "version" => @version, "revision" => @revision},
         "executables" => %{
           "wotex-coap-oscore" => %{"path" => "bin/wotex-coap-oscore", "sha256" => executable_hash}
         },
         "build" => %{
           "source" => source,
           "first_party_sources" => expected_identity["native_inputs"],
           "yyjson" => yyjson,
           "platform" => %{"target" => json(tools.target), "os_version" => json(:os.version())},
           "tools" => %{
             "paths" => json(tools.paths),
             "sha256" => json(tools.hashes),
             "versions" => versions,
             "openssl_root" => tools.openssl_root
           },
           "cmake_options" => @cmake_options,
           "worker_definitions" => @yyjson_definitions,
           "static_library" => %{"path" => "lib/libcoap-3.a", "sha256" => static_hash},
           "dynamic_dependencies" => dependency_list,
           "feature_probe" => feature,
           "worker_probe" => ready,
           "sanitizers" => [],
           "steps" => steps
         }
       }}
    else
      {:error, reason, details} -> {:error, %{code: reason, details: details}}
      {:error, _} = error -> error
      _ -> {:error, :native_build_inputs_changed}
    end
  rescue
    error in File.Error -> {:error, {:native_build_filesystem, error.reason}}
  end

  defp directories(workspace) do
    Enum.reduce_while(~w(bin downloads lib logs probe), :ok, fn directory, :ok ->
      case File.mkdir_p(Path.join(workspace, directory)) do
        :ok -> {:cont, :ok}
        _ -> {:halt, {:error, :native_build_filesystem}}
      end
    end)
  end

  defp bootstrap(workspace, tools, deadline, operations) do
    guardian = Path.join(workspace, "bin/build-command")
    started = System.monotonic_time(:millisecond)

    result =
      operations.direct(
        tools.paths.cc,
        [
          "-std=c11",
          "-O2",
          "-Wall",
          "-Wextra",
          "-Werror",
          Path.join(@native_root, "build_command.c"),
          "-o",
          guardian
        ],
        workspace,
        timeout: remaining(deadline, 30_000),
        output: 1_048_576,
        env: environment(tools)
      )

    record_result(workspace, "bootstrap", started, result)
  end

  defp versions(guardian, workspace, tools, environment, deadline, operations, write?) do
    result =
      Toolchain.version_commands(tools)
      |> Enum.reduce_while({:ok, %{}}, fn {id, executable, arguments}, {:ok, found} ->
        timeout = remaining(deadline, 10_000)

        case operations.command(guardian, executable, arguments, workspace,
               timeout: timeout,
               output: 131_072,
               cleanup: 1_000,
               env: environment
             ) do
          {:ok, %{output: output}} when is_binary(output) ->
            if String.valid?(output),
              do: {:cont, {:ok, Map.put(found, Atom.to_string(id), String.trim(output))}},
              else: {:halt, {:error, :invalid_tool_version}}

          {:error, code, details} ->
            {:halt, {:error, %{code: code, step: id, exit_status: details.exit_status}}}
        end
      end)

    with {:ok, found} <- result,
         :ok <- maybe_write_versions(workspace, found, write?) do
      {:ok, found}
    end
  end

  defp maybe_write_versions(_, _, false), do: :ok

  defp maybe_write_versions(workspace, versions, true) do
    write_log(workspace, "tool-versions", Jason.encode_to_iodata!(versions, pretty: true))
  end

  defp download(guardian, workspace, source, environment, deadline, tools, operations) do
    archive = Path.join(workspace, "downloads/libcoap.tar.gz")

    arguments = [
      "--disable",
      "--silent",
      "--show-error",
      "--fail",
      "--proto",
      "=https",
      "--proto-redir",
      "=https",
      "--location",
      "--max-redirs",
      "3",
      "--max-time",
      "30",
      "--max-filesize",
      "4194304",
      "--output",
      archive,
      source["url"]
    ]

    run_step(
      guardian,
      workspace,
      "download",
      tools.paths.curl,
      arguments,
      environment,
      deadline,
      35_000,
      operations
    )
  end

  defp extract(workspace, source, operations) do
    operations.extract(
      Path.join(workspace, "downloads/libcoap.tar.gz"),
      Path.join(workspace, "sources"),
      %{root: @archive_root, sha256: source["sha256"]}
    )
  end

  defp patch(guardian, workspace, source, environment, deadline, tools, operations) do
    source_root = source_root(workspace)

    result =
      source["patches"]
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {patch, index}, {:ok, records} ->
        id = "patch-" <> String.pad_leading(Integer.to_string(index), 2, "0")

        arguments = [
          "-s",
          "-f",
          "-F",
          "0",
          "-p",
          "1",
          "-d",
          source_root,
          "-i",
          Path.join(@native_root, patch["path"])
        ]

        case run_step(
               guardian,
               workspace,
               id,
               tools.paths.patch,
               arguments,
               environment,
               deadline,
               30_000,
               operations
             ) do
          {:ok, record, _} -> {:cont, {:ok, [record | records]}}
          error -> {:halt, error}
        end
      end)

    case result do
      {:ok, records} -> {:ok, Enum.reverse(records)}
      error -> error
    end
  end

  defp verify_patched(workspace, source, operations) do
    Enum.reduce_while(source["patched_sources"], :ok, fn {file, expected}, :ok ->
      case operations.digest(Path.join(source_root(workspace), file)) do
        {:ok, ^expected} -> {:cont, :ok}
        _ -> {:halt, {:error, :patched_source_mismatch}}
      end
    end)
  end

  defp configure(guardian, workspace, tools, environment, deadline, operations) do
    fixed = [
      "-S",
      source_root(workspace),
      "-B",
      Path.join(workspace, "build"),
      "-DCMAKE_C_COMPILER=#{tools.paths.cc}",
      "-DOPENSSL_ROOT_DIR=#{tools.openssl_root}",
      "-DPKG_CONFIG_EXECUTABLE=#{tools.paths.pkg_config}"
    ]

    arguments = fixed ++ Enum.map(@cmake_options, &("-D" <> &1))

    run_step(
      guardian,
      workspace,
      "cmake-configure",
      tools.paths.cmake,
      arguments,
      environment,
      deadline,
      120_000,
      operations
    )
  end

  defp compile_libcoap(guardian, workspace, tools, environment, deadline, operations) do
    run_step(
      guardian,
      workspace,
      "cmake-build",
      tools.paths.cmake,
      ["--build", Path.join(workspace, "build"), "--parallel", "2"],
      environment,
      deadline,
      @build_timeout,
      operations
    )
  end

  defp copy_static_library(workspace) do
    source = Path.join(workspace, "build/libcoap-3.a")
    destination = Path.join(workspace, "lib/libcoap-3.a")

    with {:ok, %{type: :regular}} <- File.lstat(source),
         :ok <- File.cp(source, destination) do
      :ok
    else
      _ -> {:error, :missing_static_library}
    end
  end

  defp compile_probe(guardian, workspace, tools, environment, deadline, operations) do
    arguments =
      compiler_prefix(workspace, tools) ++
        [Path.join(@native_root, "build_probe.c"), Path.join(workspace, "lib/libcoap-3.a")] ++
        openssl_arguments(tools.openssl_root) ++ ["-o", probe_path(workspace)]

    run_step(
      guardian,
      workspace,
      "feature-probe-build",
      tools.paths.cc,
      arguments,
      environment,
      deadline,
      120_000,
      operations
    )
  end

  defp compile_worker(guardian, workspace, tools, environment, deadline, operations) do
    definitions = ["-DWCO_WITH_LIBCOAP" | Enum.map(@yyjson_definitions, &("-D" <> &1))]
    sources = Enum.map(@worker_sources, &Path.join(@native_root, &1))

    arguments =
      compiler_prefix(workspace, tools) ++
        definitions ++
        sources ++
        [Path.join(workspace, "lib/libcoap-3.a")] ++
        openssl_arguments(tools.openssl_root) ++ ["-o", worker_path(workspace)]

    run_step(
      guardian,
      workspace,
      "worker-build",
      tools.paths.cc,
      arguments,
      environment,
      deadline,
      @build_timeout,
      operations
    )
  end

  defp compile_worker_probe(
         guardian,
         workspace,
         tools,
         environment,
         deadline,
         operations
       ) do
    arguments = [
      "-std=c11",
      "-O2",
      "-Wall",
      "-Wextra",
      "-Werror",
      Path.join(@native_root, "build_worker_probe.c"),
      "-o",
      worker_probe_path(workspace)
    ]

    run_step(
      guardian,
      workspace,
      "worker-probe-build",
      tools.paths.cc,
      arguments,
      environment,
      deadline,
      120_000,
      operations
    )
  end

  defp compiler_prefix(workspace, tools) do
    [
      "-std=c11",
      "-O2",
      "-Wall",
      "-Wextra",
      "-Werror",
      "-I#{@native_root}",
      "-I#{Path.join(workspace, "build/include")}",
      "-I#{Path.join(source_root(workspace), "include")}",
      "-I#{Path.join(tools.openssl_root, "include")}"
    ]
  end

  defp openssl_arguments(root) do
    library =
      if File.dir?(Path.join(root, "lib")),
        do: Path.join(root, "lib"),
        else: Path.join(root, "lib64")

    ["-L#{library}", "-lssl", "-lcrypto"]
  end

  defp dependencies(guardian, workspace, tools, environment, deadline, operations) do
    arguments =
      if elem(tools.target, 0) == :darwin,
        do: ["-L", worker_path(workspace)],
        else: [worker_path(workspace)]

    run_step(
      guardian,
      workspace,
      "dynamic-dependencies",
      tools.paths.system,
      arguments,
      environment,
      deadline,
      10_000,
      operations
    )
  end

  defp run_step(
         guardian,
         workspace,
         id,
         executable,
         arguments,
         environment,
         deadline,
         maximum,
         operations
       ) do
    started = System.monotonic_time(:millisecond)

    result =
      operations.command(guardian, executable, arguments, workspace,
        timeout: remaining(deadline, maximum),
        output: 16_777_216,
        cleanup: 1_000,
        env: environment
      )

    case record_result(workspace, id, started, result) do
      {:ok, record} -> {:ok, record, elem(result, 1).output}
      error -> error
    end
  end

  defp record_result(workspace, id, started, result) do
    elapsed = System.monotonic_time(:millisecond) - started

    details =
      case result do
        {:ok, value} -> value
        {:error, _, value} -> value
      end

    with :ok <- write_log(workspace, id, details.output),
         {:ok, digest} <- Workspace.digest(Path.join([workspace, "logs", id <> ".log"])) do
      record = %{
        "id" => id,
        "elapsed_ms" => elapsed,
        "exit_status" => details.exit_status,
        "log" => "logs/#{id}.log",
        "output_bytes" => byte_size(details.output),
        "output_sha256" => digest
      }

      case result do
        {:ok, _} -> {:ok, record}
        {:error, code, _} -> {:error, Map.put(record, "code", Atom.to_string(code))}
      end
    end
  end

  defp write_log(workspace, id, bytes) do
    case File.write(Path.join([workspace, "logs", id <> ".log"]), bytes, [:exclusive]) do
      :ok -> :ok
      _ -> {:error, :native_build_log_failed}
    end
  end

  defp feature(output) do
    case Jason.decode(output) do
      {:ok, %{"backend" => "libcoap", "version" => "libcoap 4.3.5", "oscore" => true} = value}
      when map_size(value) == 3 ->
        {:ok, value}

      _ ->
        {:error, :native_feature_probe_failed}
    end
  end

  defp ready(output) do
    case Jason.decode(output) do
      {:ok,
       %{
         "version" => 1,
         "event" => "ready",
         "backend" => "libcoap",
         "revision" => @revision
       } = value}
      when map_size(value) == 4 ->
        {:ok, value}

      _ ->
        {:error, :native_worker_probe_failed}
    end
  end

  defp dependency_list(output) when is_binary(output) do
    dependencies =
      output
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)

    if String.valid?(output) and dependencies != [],
      do: {:ok, dependencies},
      else: {:error, :native_dependency_probe_failed}
  end

  defp cleanup(workspace) do
    Enum.reduce_while(~w(sources build probe), :ok, fn directory, :ok ->
      case File.rm_rf(Path.join(workspace, directory)) do
        {:ok, _} -> {:cont, :ok}
        _ -> {:halt, {:error, :native_build_cleanup_failed}}
      end
    end)
  end

  defp verify_reuse(%{reused: false} = result, _, _, _), do: {:ok, result}

  defp verify_reuse(result, workspace, tools, operations) do
    deadline = System.monotonic_time(:millisecond) + 60_000

    with {:ok, versions} <-
           versions(
             Path.join(workspace, "bin/build-command"),
             workspace,
             tools,
             environment(tools),
             deadline,
             operations,
             false
           ),
         true <- versions == get_in(result.manifest, ["build", "tools", "versions"]) do
      {:ok, result}
    else
      {:error, _} = error -> error
      _ -> {:error, :build_manifest_mismatch}
    end
  end

  defp remaining(deadline, maximum) do
    value = min(deadline - System.monotonic_time(:millisecond), maximum)
    if value > 0, do: value, else: 1
  end

  defp environment(tools) do
    path =
      tools.paths
      |> Map.values()
      |> Enum.map(&Path.dirname/1)
      |> Kernel.++(["/usr/bin", "/bin"])
      |> Enum.uniq()
      |> Enum.join(":")

    safe = %{
      "CC" => tools.paths.cc,
      "CMAKE" => tools.paths.cmake,
      "LC_ALL" => "C",
      "OPENSSL_ROOT_DIR" => tools.openssl_root,
      "PATH" => path,
      "PKG_CONFIG" => tools.paths.pkg_config
    }

    System.get_env()
    |> Map.new(fn {name, _} -> {name, false} end)
    |> Map.merge(safe)
    |> Enum.sort()
  end

  defp source_root(workspace), do: Path.join([workspace, "sources", @archive_root])
  defp probe_path(workspace), do: Path.join(workspace, "probe/native-feature-probe")
  defp worker_probe_path(workspace), do: Path.join(workspace, "probe/native-worker-probe")
  defp worker_path(workspace), do: Path.join(workspace, "bin/wotex-coap-oscore")

  defp json(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), json(item)} end)

  defp json(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> json()
  end

  defp json(value) when is_list(value), do: Enum.map(value, &json/1)
  defp json(value) when value in [true, false, nil], do: value
  defp json(value) when is_atom(value), do: Atom.to_string(value)
  defp json(value), do: value
end
