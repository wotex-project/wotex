defmodule Wotex.CoAP.Software.Build do
  @moduledoc """
  Builds the pinned native helper, upstream peers and native vectors.

  The root workspace contains a complete nested native build, a separately
  compiled `coap-server`, the pinned independent OSCORE peer archive and the
  first-party fault/vector executables. All compiled components use one resolved
  toolchain and the same verified source archive. The independent peer is an
  exact published Java archive admitted by SHA-256 and executed by a
  caller-selected runtime, never a compiled artifact of this repository. The
  outer manifest binds every nested artifact and is published only after the
  peers and every vector execute successfully.
  """

  alias Wotex.CoAP.Native.{Build, BuildOperations, Workspace}

  @revision "7cf7465b784baded4de183290c547d582becfd28"
  @independent_peer %{
    stack: "Eclipse Californium",
    name: "cf-plugtest-server",
    version: "3.14.0",
    artifact: "bin/cf-plugtest-server.jar",
    url:
      "https://repo1.maven.org/maven2/org/eclipse/californium/cf-plugtest-server/3.14.0/" <>
        "cf-plugtest-server-3.14.0.jar",
    sha256: "0bf82d45791eeebbf9d781d0e66f47ddafe67ba36984a432771127f1ee6dd7d5"
  }
  @archive_root "libcoap-#{@revision}"
  @project_root Path.expand("../../../..", __DIR__)
  @native_root Path.join(@project_root, "native/oscore")
  @yyjson_definitions ~w(YYJSON_DISABLE_NON_STANDARD=1 YYJSON_DISABLE_UTILS=1
    YYJSON_DISABLE_INCR_READER=1)
  @faults [
    %{
      id: "json",
      name: "oscore-json",
      definitions: @yyjson_definitions,
      sources: ~w(native/oscore/json.c native/oscore/vendor/yyjson/yyjson.c
        test/native/oscore_json_test.c),
      libcoap: false,
      openssl: true
    },
    %{
      id: "frame",
      name: "oscore-frame",
      definitions: @yyjson_definitions,
      sources: ~w(native/oscore/json.c native/oscore/frame.c
        native/oscore/vendor/yyjson/yyjson.c test/native/oscore_frame_test.c),
      libcoap: false,
      openssl: true
    },
    %{
      id: "body",
      name: "oscore-body",
      definitions: @yyjson_definitions,
      sources: ~w(native/oscore/json.c native/oscore/body.c
        native/oscore/vendor/yyjson/yyjson.c test/native/oscore_body_test.c),
      libcoap: false,
      openssl: true
    },
    %{
      id: "credit",
      name: "oscore-credit",
      definitions: [],
      sources: ~w(native/oscore/credit.c test/native/oscore_credit_test.c),
      libcoap: false,
      openssl: false
    },
    %{
      id: "command",
      name: "oscore-command",
      definitions: @yyjson_definitions,
      sources: ~w(native/oscore/command.c native/oscore/json.c native/oscore/body.c
        native/oscore/vendor/yyjson/yyjson.c test/native/oscore_command_test.c),
      libcoap: false,
      openssl: true
    },
    %{
      id: "identity",
      name: "oscore-identity",
      definitions: [],
      sources: ~w(native/oscore/identity.c test/native/oscore_identity_test.c),
      libcoap: false,
      openssl: true
    },
    %{
      id: "store",
      name: "oscore-store",
      definitions: ["WCO_STORE_TEST"],
      sources: ~w(native/oscore/identity.c native/oscore/store.c
        test/native/oscore_store_test.c),
      libcoap: false,
      openssl: true
    },
    %{
      id: "store-send",
      name: "oscore-store-send",
      definitions: ["WCO_STORE_TEST"],
      sources: ~w(native/oscore/identity.c native/oscore/store.c
        test/native/oscore_store_send_test.c),
      libcoap: true,
      openssl: true
    },
    %{
      id: "sequence",
      name: "oscore-sequence",
      definitions: [],
      sources: ~w(test/native/oscore_sequence_test.c),
      libcoap: true,
      openssl: true
    },
    %{
      id: "block-limit",
      name: "oscore-block-limit",
      definitions: [],
      sources: ~w(test/native/oscore_block_limit_test.c),
      libcoap: true,
      openssl: true
    },
    %{
      id: "protection",
      name: "oscore-protection",
      definitions: [],
      sources: ~w(test/native/oscore_protection_test.c),
      libcoap: true,
      openssl: true
    },
    %{
      id: "worker-exchange",
      name: "oscore-worker-exchange",
      definitions: [],
      sources: ~w(native/oscore/observation.c test/native/oscore_worker_exchange_test.c),
      libcoap: true,
      openssl: true
    }
  ]
  @build_sources [
                   __ENV__.file,
                   Path.join(@project_root, "lib/mix/tasks/wotex.coap.software.build.ex"),
                   Path.join(@project_root, "mix.exs")
                 ] ++
                   Path.wildcard(Path.join(@project_root, "lib/wotex/coap/native/*.ex")) ++
                   Path.wildcard(Path.join(@native_root, "**/*")) ++
                   Enum.map(@faults, &Path.join(@project_root, List.last(&1.sources)))
  @cmake_options [
    "ENABLE_OSCORE=ON",
    "ENABLE_DTLS=ON",
    "DTLS_BACKEND=openssl",
    "BUILD_SHARED_LIBS=OFF",
    "ENABLE_DOCS=OFF",
    "ENABLE_TESTS=OFF",
    "ENABLE_EXAMPLES=ON",
    "CMAKE_BUILD_TYPE=Release"
  ]
  @peer_artifacts ~w(bin/coap-server logs/peer-configure.log logs/peer-build.log
    logs/peer-probe.log bin/cf-plugtest-server.jar logs/independent-peer-download.log
    logs/independent-peer-probe.log)
  @fault_artifacts Enum.flat_map(@faults, fn fault ->
                     [
                       "bin/faults/#{fault.name}",
                       "logs/fault-#{fault.id}-build.log",
                       "logs/fault-#{fault.id}-probe.log"
                     ]
                   end)
  @own_artifacts @peer_artifacts ++ @fault_artifacts
  @timeout 600_000

  for file <- @build_sources, File.regular?(file), do: @external_resource(file)

  @doc "Builds or verifies the manifest-bound native helper and software fixtures."
  @spec run(term()) :: {:ok, Workspace.result()} | {:error, term()}
  def run(workspace), do: run(workspace, BuildOperations, Build)

  @doc false
  @spec run(term(), module(), module()) :: {:ok, Workspace.result()} | {:error, term()}
  def run(workspace, operations, native_build)
      when is_binary(workspace) and is_atom(operations) and is_atom(native_build) do
    with {:ok, tools} <- operations.resolve(),
         {:ok, build_hashes} <- build_hashes(operations) do
      artifacts = artifacts(native_build)
      identity = identity(tools, build_hashes, artifacts)

      Workspace.run(workspace, identity, artifacts, fn ->
        build(workspace, tools, operations, native_build)
      end)
    end
  rescue
    error in [ArgumentError, File.Error, UndefinedFunctionError] ->
      {:error, {:software_build_setup, Exception.message(error)}}
  end

  def run(_, _, _), do: {:error, :invalid_build_workspace}

  @doc "Verifies an existing completed software-build workspace without building it."
  @spec verify(term()) :: {:ok, Workspace.result()} | {:error, term()}
  def verify(workspace), do: verify(workspace, BuildOperations, Build)

  @doc false
  @spec verify(term(), module(), module()) :: {:ok, Workspace.result()} | {:error, term()}
  def verify(workspace, operations, native_build)
      when is_binary(workspace) and is_atom(operations) and is_atom(native_build) do
    case File.lstat(Path.join(workspace, "native-manifest.json")) do
      {:ok, %{type: :regular}} -> verify_reuse(workspace, operations, native_build)
      _ -> {:error, :software_build_required}
    end
  rescue
    error in [ArgumentError, File.Error, UndefinedFunctionError] ->
      {:error, {:software_build_setup, Exception.message(error)}}
  end

  def verify(_, _, _), do: {:error, :invalid_build_workspace}

  @doc false
  @spec artifacts(module()) :: [String.t()]
  def artifacts(native_build) do
    nested = [
      "native/native-manifest.json" | Enum.map(native_build.artifacts(), &("native/" <> &1))
    ]

    nested ++ @own_artifacts
  end

  defp verify_reuse(workspace, operations, native_build) do
    case run(workspace, operations, native_build) do
      {:ok, %{reused: true}} = result -> result
      {:ok, _} -> {:error, :software_build_required}
      {:error, _} = error -> error
    end
  end

  defp build_hashes(operations) do
    @build_sources
    |> Enum.filter(&File.regular?/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.reduce_while({:ok, %{}}, fn path, {:ok, result} ->
      case operations.digest(path) do
        {:ok, digest} ->
          {:cont, {:ok, Map.put(result, Path.relative_to(path, @project_root), digest)}}

        _ ->
          {:halt, {:error, :software_build_input_mismatch}}
      end
    end)
  end

  defp identity(tools, build_hashes, artifacts) do
    json(%{
      format_version: 1,
      profile: :software,
      build_inputs: build_hashes,
      tool_paths: tools.paths,
      tool_hashes: tools.hashes,
      openssl_root: tools.openssl_root,
      target: tools.target,
      os_version: :os.version(),
      peer_cmake_options: @cmake_options,
      independent_peer: Map.delete(@independent_peer, :url),
      artifacts: artifacts,
      faults: Enum.map(@faults, &Map.take(&1, [:definitions, :id, :libcoap, :name, :openssl]))
    })
  end

  defp build(workspace, tools, operations, native_build) do
    deadline = System.monotonic_time(:millisecond) + @timeout
    native_workspace = Path.join(workspace, "native")

    with {:ok, native} <- native_build.run_resolved(native_workspace, tools, operations),
         :ok <- directories(workspace),
         :ok <- extract(workspace, native.manifest, operations),
         guardian = Path.join(native_workspace, "bin/build-command"),
         environment = environment(tools),
         {:ok, configure, _} <-
           step(
             guardian,
             workspace,
             "peer-configure",
             tools.paths.cmake,
             configure_arguments(workspace, tools),
             environment,
             deadline,
             120_000,
             operations
           ),
         {:ok, compile, _} <-
           step(
             guardian,
             workspace,
             "peer-build",
             tools.paths.cmake,
             ["--build", Path.join(workspace, "peer-build"), "--parallel", "2"],
             environment,
             deadline,
             @timeout,
             operations
           ),
         :ok <- copy_peer(workspace),
         {:ok, probe, output} <-
           step(
             guardian,
             workspace,
             "peer-probe",
             Path.join(workspace, "bin/coap-server"),
             ["-h"],
             environment,
             deadline,
             10_000,
             operations
           ),
         {:ok, features} <- features(output),
         {:ok, runtime} <- java_runtime(operations),
         {:ok, download, _} <-
           step(
             guardian,
             workspace,
             "independent-peer-download",
             tools.paths.curl,
             independent_arguments(workspace),
             environment,
             deadline,
             60_000,
             operations
           ),
         {:ok, independent_hash} <- independent_digest(workspace, operations),
         {:ok, runtime_probe, runtime_output} <-
           step(
             guardian,
             workspace,
             "independent-peer-probe",
             runtime.path,
             ["-version"],
             environment,
             deadline,
             60_000,
             operations
           ),
         {:ok, runtime_version} <- runtime_version(runtime_output),
         {:ok, fault_executables} <-
           build_faults(guardian, workspace, tools, environment, deadline, operations),
         {:ok, peer_hash} <- operations.digest(Path.join(workspace, "bin/coap-server")),
         {:ok, helper_hash} <-
           operations.digest(Path.join(native_workspace, "bin/wotex-coap-oscore")),
         :ok <- cleanup(workspace) do
      {:ok,
       native.manifest
       |> Map.put("executables", %{
         "wotex-coap-oscore" => %{
           "path" => "native/bin/wotex-coap-oscore",
           "sha256" => helper_hash
         },
         "coap-server" => %{"path" => "bin/coap-server", "sha256" => peer_hash}
       })
       |> Map.put("software_build", %{
         "profile" => "software",
         "peer" => %{
           "name" => "coap-server",
           "backend" => "libcoap",
           "version" => "4.3.5",
           "revision" => @revision,
           "features" => features
         },
         "independent_peer" => %{
           "name" => @independent_peer.name,
           "stack" => @independent_peer.stack,
           "version" => @independent_peer.version,
           "path" => @independent_peer.artifact,
           "sha256" => independent_hash,
           "runtime" => %{
             "path" => runtime.path,
             "sha256" => runtime.sha256,
             "version" => runtime_version
           },
           "steps" => [download, runtime_probe]
         },
         "cmake_options" => @cmake_options,
         "steps" => [configure, compile, probe],
         "sanitizers" => sanitizers(tools.target),
         "fault_executables" => fault_executables
       })}
    else
      {:error, _} = error -> error
      _ -> {:error, :software_build_failed}
    end
  rescue
    error in File.Error -> {:error, {:software_build_filesystem, error.reason}}
  end

  defp directories(workspace) do
    Enum.reduce_while(~w(bin bin/faults logs), :ok, fn directory, :ok ->
      case File.mkdir_p(Path.join(workspace, directory)) do
        :ok -> {:cont, :ok}
        _ -> {:halt, {:error, :software_build_filesystem}}
      end
    end)
  end

  defp extract(workspace, native_manifest, operations) do
    source = native_manifest["build"]["source"]

    operations.extract(
      Path.join(workspace, "native/downloads/libcoap.tar.gz"),
      Path.join(workspace, "sources"),
      %{root: @archive_root, sha256: source["sha256"]}
    )
  end

  defp configure_arguments(workspace, tools) do
    [
      "-S",
      source_root(workspace),
      "-B",
      Path.join(workspace, "peer-build"),
      "-DCMAKE_C_COMPILER=#{tools.paths.cc}",
      "-DOPENSSL_ROOT_DIR=#{tools.openssl_root}",
      "-DPKG_CONFIG_EXECUTABLE=#{tools.paths.pkg_config}"
      | Enum.map(@cmake_options, &("-D" <> &1))
    ]
  end

  defp copy_peer(workspace) do
    source = Path.join(workspace, "peer-build/coap-server")
    destination = Path.join(workspace, "bin/coap-server")

    with {:ok, %{type: :regular}} <- File.lstat(source),
         :ok <- File.cp(source, destination),
         :ok <- File.chmod(destination, 0o750) do
      :ok
    else
      _ -> {:error, :missing_software_peer}
    end
  end

  defp independent_arguments(workspace) do
    [
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
      "120",
      "--max-filesize",
      "16777216",
      "--output",
      Path.join(workspace, @independent_peer.artifact),
      @independent_peer.url
    ]
  end

  defp independent_digest(workspace, operations) do
    with {:ok, digest} <- operations.digest(Path.join(workspace, @independent_peer.artifact)) do
      if digest == @independent_peer.sha256,
        do: {:ok, digest},
        else: {:error, :independent_peer_mismatch}
    end
  end

  # The independent peer is executed, never compiled here, so its runtime is a
  # caller-selected Java launcher recorded by path, content digest and version.
  defp java_runtime(operations) do
    case operations.runtime(System.get_env("WOTEX_COAP_JAVA") || "java") do
      {:ok, %{path: path, sha256: digest}} when is_binary(path) and is_binary(digest) ->
        {:ok, %{path: path, sha256: digest}}

      _ ->
        {:error, :missing_independent_peer_runtime}
    end
  end

  defp runtime_version(output) when is_binary(output) do
    version =
      output
      |> String.split("\n")
      |> List.first()
      |> to_string()
      |> String.trim()

    if String.valid?(version) and version != "" and byte_size(version) <= 200,
      do: {:ok, version},
      else: {:error, :independent_peer_runtime_probe_failed}
  end

  defp features(output) when is_binary(output) do
    checks = %{
      "version" => String.contains?(output, "coap-server v4.3.5"),
      "dtls" => String.contains?(output, "DTLS and TLS support"),
      "oscore" => String.contains?(output, "(Have OSCORE)")
    }

    if String.valid?(output) and Enum.all?(checks, fn {_, value} -> value end),
      do: {:ok, checks},
      else: {:error, :software_peer_probe_failed}
  end

  defp build_faults(guardian, workspace, tools, environment, deadline, operations) do
    Enum.reduce_while(@faults, {:ok, %{}}, fn fault, {:ok, built} ->
      case build_fault(guardian, workspace, tools, environment, deadline, operations, fault) do
        {:ok, record} -> {:cont, {:ok, Map.put(built, fault.name, record)}}
        error -> {:halt, error}
      end
    end)
  end

  defp build_fault(guardian, workspace, tools, environment, deadline, operations, fault) do
    executable = Path.join([workspace, "bin", "faults", fault.name])

    with {:ok, compile, _} <-
           step(
             guardian,
             workspace,
             "fault-#{fault.id}-build",
             tools.paths.cc,
             fault_arguments(workspace, tools, fault, executable),
             environment,
             deadline,
             120_000,
             operations
           ),
         {:ok, probe, _} <-
           step(
             guardian,
             workspace,
             "fault-#{fault.id}-probe",
             executable,
             fault_probe_arguments(workspace, fault),
             environment,
             deadline,
             300_000,
             operations
           ),
         {:ok, digest} <- operations.digest(executable) do
      {:ok,
       %{
         "path" => Path.relative_to(executable, workspace),
         "sha256" => digest,
         "definitions" => fault.definitions ++ platform_definitions(fault, tools.target),
         "compile" => compile,
         "probe" => probe
       }}
    end
  end

  defp fault_arguments(workspace, tools, fault, executable) do
    definitions = fault.definitions ++ platform_definitions(fault, tools.target)
    sources = Enum.map(fault.sources, &Path.join(@project_root, &1))

    compiler_prefix(workspace, tools) ++
      Enum.map(definitions, &("-D" <> &1)) ++
      sources ++
      static_library(workspace, fault) ++
      openssl_arguments(tools.openssl_root, fault.openssl) ++
      platform_linker_arguments(fault, tools.target) ++ ["-o", executable]
  end

  defp compiler_prefix(workspace, tools) do
    optimization = if elem(tools.target, 0) == :linux, do: ["-O1", "-g"], else: ["-O2"]

    ["-std=c11"] ++
      optimization ++
      [
        "-Wall",
        "-Wextra",
        "-Werror",
        "-I#{@native_root}",
        "-I#{Path.join(workspace, "peer-build/include")}",
        "-I#{Path.join(source_root(workspace), "include")}",
        "-I#{Path.join(tools.openssl_root, "include")}"
      ] ++ sanitizers(tools.target)
  end

  defp static_library(workspace, %{libcoap: true}),
    do: [Path.join(workspace, "native/lib/libcoap-3.a")]

  defp static_library(_, _), do: []

  defp openssl_arguments(_, false), do: []

  defp openssl_arguments(root, true) do
    library =
      if File.dir?(Path.join(root, "lib")),
        do: Path.join(root, "lib"),
        else: Path.join(root, "lib64")

    ["-L#{library}", "-lssl", "-lcrypto"]
  end

  defp platform_definitions(%{id: "block-limit"}, {:linux, _}), do: ["WCO_ALLOCATION_WRAP"]
  defp platform_definitions(_, _), do: []

  defp platform_linker_arguments(%{id: "block-limit"}, {:linux, _}),
    do: ["-Wl,--wrap=coap_new_binary,--wrap=coap_resize_binary"]

  defp platform_linker_arguments(_, _), do: []

  defp fault_probe_arguments(workspace, %{id: "worker-exchange"}),
    do: [Path.join(workspace, "native/bin/wotex-coap-oscore")]

  defp fault_probe_arguments(_, _), do: []

  defp sanitizers({:linux, _}),
    do: ["-fsanitize=address,undefined", "-fno-sanitize-recover=all", "-fno-omit-frame-pointer"]

  defp sanitizers(_), do: []

  defp step(
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

    details =
      case result do
        {:ok, value} -> value
        {:error, _, value} -> value
      end

    log = Path.join([workspace, "logs", id <> ".log"])

    with :ok <- File.write(log, details.output, [:exclusive]),
         {:ok, digest} <- Workspace.digest(log) do
      record = %{
        "id" => id,
        "elapsed_ms" => System.monotonic_time(:millisecond) - started,
        "exit_status" => details.exit_status,
        "log" => "logs/#{id}.log",
        "output_bytes" => byte_size(details.output),
        "output_sha256" => digest
      }

      case result do
        {:ok, _} ->
          {:ok, record, details.output}

        {:error, :build_command_failed, _}
        when id == "peer-probe" and details.exit_status == 1 ->
          {:ok, record, details.output}

        {:error, code, _} ->
          {:error, Map.put(record, "code", Atom.to_string(code))}
      end
    end
  end

  defp cleanup(workspace) do
    Enum.reduce_while(~w(sources peer-build), :ok, fn directory, :ok ->
      case File.rm_rf(Path.join(workspace, directory)) do
        {:ok, _} -> {:cont, :ok}
        _ -> {:halt, {:error, :software_build_cleanup_failed}}
      end
    end)
  end

  defp source_root(workspace), do: Path.join([workspace, "sources", @archive_root])

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
      "LC_ALL" => "C",
      "OPENSSL_ROOT_DIR" => tools.openssl_root,
      "PATH" => path,
      "PKG_CONFIG" => tools.paths.pkg_config
    }

    safe =
      if elem(tools.target, 0) == :linux do
        Map.merge(safe, %{
          "ASAN_OPTIONS" => "detect_leaks=1:halt_on_error=1:abort_on_error=1",
          "UBSAN_OPTIONS" => "halt_on_error=1:print_stacktrace=1"
        })
      else
        safe
      end

    System.get_env()
    |> Map.new(fn {name, _} -> {name, false} end)
    |> Map.merge(safe)
    |> Enum.sort()
  end

  defp json(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), json(item)} end)

  defp json(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> json()
  end

  defp json(value) when is_list(value), do: Enum.map(value, &json/1)
  defp json(value) when is_atom(value), do: Atom.to_string(value)
  defp json(value), do: value
end
