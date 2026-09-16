defmodule Wotex.OPCUA.Native.Build do
  @moduledoc """
  Builds the packaged native executable from its reviewed source archives.

  `run/1` is an explicit build operation for a disposable absolute workspace.
  It identifies the host toolchain, owns the workspace, verifies source downloads,
  executes the fixed static OpenSSL/open62541 recipe and retains bounded command
  logs. A completion receipt binds source, tool, recipe and artifact hashes.
  Existing receipts are read-only: changed inputs, output or tool version probes
  reject reuse. Failed builds retain diagnostic files and require a new workspace.
  A failed version command retains its finite step, command code and exit status;
  it is not reported as a content mismatch without that evidence.

  Build success proves source and artifact identity only; secure Session and
  service behavior require separate executable and independent-peer evidence.
  Download curl must be at least 8.4.0 so its 100 MiB limit also bounds responses
  without a declared Content-Length. Python is used by the upstream SDK generator
  during this explicit build, independently of the production process contract.
  """

  alias Wotex.OPCUA.Native.{
    Archive,
    Bootstrap,
    Command,
    Recipe,
    Source,
    Toolchain,
    Vendor,
    Workspace
  }

  @native_files ~w(CMakeLists.txt main.c build_command.c custody.c custody_check.c README.md runtime-guardian.md
    json_codec.c json_codec.h json_check.c json-codec.md ipc.c ipc.h ipc_check.c
    security.c security.h security_check.c session_config.c session_config.h
    session_probe.c session_open.c session_open.h browse_check.c paged_peer.c
    security.md patch-sdk.cmake sdk_revision_check.c
    value_codec.c value_codec.h value_check.c value_fault_check.c
    native_contract_check.c
    value-codec.md fixtures/value-v1.json vendor/yyjson/yyjson.c vendor/yyjson/yyjson.h vendor/yyjson/LICENSE)
  @native_contract Path.expand("../../../../docs/specs/fixtures/native-contract-v1.json", __DIR__)
  @build_sources [
    Path.expand("../../../mix/tasks/wotex.opcua.native.build.ex", __DIR__)
    | Path.wildcard(Path.join(__DIR__, "*.ex"))
  ]
  for file <- @build_sources, do: @external_resource(file)
  @external_resource @native_contract

  @build_hashes Map.new(@build_sources, fn file ->
                  {Path.basename(file),
                   Base.encode16(:crypto.hash(:sha256, File.read!(file)), case: :lower)}
                end)
  @artifacts ~w(bin/build-command downloads/open62541.tar.gz downloads/openssl.tar.gz
    openssl-prefix/lib/libssl.a openssl-prefix/lib/libcrypto.a sdk-prefix/lib/libopen62541.a
    output/bin/wotex_opcua_native output/bin/wotex_opcua_custody output/share/licenses/yyjson/LICENSE) ++
               Enum.map(
                 ~w(ua_client.c ua_client_connect.c ua_client_internal.h),
                 &("sources/open62541/open62541-1.5.7/src/client/" <> &1)
               ) ++
               Enum.map(
                 ~w(openssl open62541 openssl_configure openssl_compile openssl_install
      sdk_patch sdk_configure sdk_compile sdk_install native_configure native_compile native_test native_install),
                 &("logs/" <> &1 <> ".log")
               )

  @doc "Builds or verifies one content-bound native workspace; it never downloads during dependency loading."
  @spec run(term()) :: {:ok, Workspace.result()} | {:error, term()}
  def run(workspace) when is_binary(workspace) do
    native = Application.app_dir(:wotex_opcua, "priv/native")

    with :ok <- Vendor.verify(native),
         {:ok, tools} <- Toolchain.resolve(),
         {:ok, recipe} <- Recipe.new(workspace, native, tools.recipe, tools.target),
         {:ok, identity} <- identity(native, tools, recipe),
         {:ok, result} <-
           Workspace.run(workspace, identity, @artifacts, fn ->
             build(workspace, native, tools, recipe, identity)
           end) do
      verify_reuse(result, workspace, tools)
    end
  end

  def run(_), do: {:error, :invalid_build_workspace}

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

  defp identity(native, tools, recipe) do
    result =
      Enum.reduce_while(@native_files, {:ok, %{}}, fn file, {:ok, hashes} ->
        case Workspace.digest(Path.join(native, file)) do
          {:ok, digest} -> {:cont, {:ok, Map.put(hashes, file, digest)}}
          error -> {:halt, error}
        end
      end)

    with {:ok, hashes} <- result,
         {:ok, native_contract_sha256} <- Workspace.digest(@native_contract) do
      {:ok,
       json(%{
         format_version: 1,
         build_sources: @build_hashes,
         source_manifest_sha256: Source.manifest_digest(),
         native_contract_sha256: native_contract_sha256,
         native_sources: hashes,
         tool_paths: tools.paths,
         tool_hashes: tools.hashes,
         target: tools.target,
         os_version: :os.version(),
         recipe: recipe
       })}
    end
  end

  defp build(workspace, native, tools, recipe, expected) do
    for directory <- ~w(bin downloads sources logs),
        do: File.mkdir_p!(Path.join(workspace, directory))

    guardian = Path.join(workspace, "bin/build-command")

    with {:ok, bootstrap} <-
           Bootstrap.compile(
             tools.paths.cc,
             Path.join(native, "build_command.c"),
             guardian,
             workspace
           ),
         {:ok, versions} <- versions(guardian, tools, workspace),
         :ok <- supported_curl(versions["curl"]),
         :ok <- sources(guardian, tools, workspace),
         {:ok, steps} <- execute_recipe(guardian, workspace, recipe),
         {:ok, current_tools} <- Toolchain.identify(tools.paths, tools.target),
         {:ok, ^expected} <- identity(native, current_tools, recipe) do
      {:ok,
       %{
         "tool_versions" => versions,
         "steps" => steps,
         "bootstrap" => json(bootstrap),
         "native_service_acceptance" => false
       }}
    else
      {:error, reason, details} -> {:error, %{code: reason, details: details}}
      {:error, _} = error -> error
      _ -> {:error, :native_build_inputs_changed}
    end
  rescue
    error in File.Error -> {:error, %{code: :native_build_filesystem, reason: error.reason}}
  end

  defp versions(guardian, tools, workspace) do
    tools
    |> Toolchain.version_steps(workspace)
    |> Enum.reduce_while({:ok, %{}}, fn step, {:ok, versions} ->
      case Command.run(guardian, step) do
        {:ok, %{output: bytes}} ->
          {:cont, {:ok, Map.put(versions, Atom.to_string(step.id), bytes)}}

        {:error, code, result} ->
          {:halt, {:error, %{code: code, step: step.id, exit_status: result.exit_status}}}
      end
    end)
  end

  defp supported_curl(bytes) when is_binary(bytes) do
    case Regex.run(~r/\Acurl ([0-9]+\.[0-9]+\.[0-9]+) /, bytes) do
      [_, version] ->
        if Version.compare(version, "8.4.0") != :lt,
          do: :ok,
          else: {:error, :unsupported_download_tool}

      _ ->
        {:error, :unsupported_download_tool}
    end
  end

  defp sources(guardian, tools, workspace) do
    Enum.reduce_while([:openssl, :open62541], :ok, fn name, :ok ->
      {:ok, source} = Source.fetch(name)
      archive = Path.join([workspace, "downloads", source.name <> ".tar.gz"])
      destination = Path.join([workspace, "sources", source.name])

      step = %{
        id: name,
        executable: tools.paths.curl,
        cwd: workspace,
        args: [
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
          "104857600",
          "--output",
          archive,
          source.url
        ],
        env: [{"PATH", "/usr/bin:/bin"}, {"LC_ALL", "C"}],
        timeout_ms: 120_000,
        output_bytes: 65_536,
        cleanup_ms: 1000
      }

      with {:ok, _} <- command(guardian, workspace, step),
           :ok <- Archive.extract(archive, destination, source) do
        {:cont, :ok}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp execute_recipe(guardian, workspace, recipe) do
    result =
      Enum.reduce_while(recipe, {:ok, []}, fn step, {:ok, results} ->
        case command(guardian, workspace, step) do
          {:ok, result} -> {:cont, {:ok, [result | results]}}
          error -> {:halt, error}
        end
      end)

    case result do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  defp command(guardian, workspace, step) do
    started = System.monotonic_time(:millisecond)
    result = Command.run(guardian, step)
    elapsed = System.monotonic_time(:millisecond) - started

    details =
      case result do
        {:ok, details} -> details
        {:error, _, details} -> details
      end

    log = Path.join([workspace, "logs", Atom.to_string(step.id) <> ".log"])
    File.write!(log, details.output, [:exclusive])
    {:ok, digest} = Workspace.digest(log)

    record = %{
      id: step.id,
      elapsed_ms: elapsed,
      exit_status: details.exit_status,
      log: Path.relative_to(log, workspace),
      output_sha256: digest,
      output_bytes: byte_size(details.output)
    }

    case result do
      {:ok, _} -> {:ok, json(record)}
      {:error, code, _} -> {:error, Map.put(record, :code, code)}
    end
  end

  defp verify_reuse(%{reused: false} = result, _, _), do: {:ok, result}

  defp verify_reuse(result, workspace, tools) do
    with {:ok, versions} <- versions(Path.join(workspace, "bin/build-command"), tools, workspace),
         true <- versions == result.receipt["evidence"]["tool_versions"] do
      {:ok, result}
    else
      {:error, _} = error -> error
      _ -> {:error, :build_manifest_mismatch}
    end
  end

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
