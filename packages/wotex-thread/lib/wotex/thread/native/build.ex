defmodule Wotex.Thread.Native.Build do
  @moduledoc """
  Builds the pinned Linux OpenThread host in an explicit disposable workspace.

  Source transfer, extraction, reviewed SDK fixes, process supervision and
  artifact verification are owned by this Mix-invoked builder. An incomplete
  build is retained for diagnosis and cannot be reused. Build completion does
  not establish native service or software-network acceptance.
  """

  alias Wotex.Thread.Native.{Bootstrap, Command, Source, Workspace}

  @source_names ~w(openthread mbedtls mbedtls-framework)
  @tools ~w(cmake ninja cc c++ readelf)
  @build_modules [
    __MODULE__,
    Source,
    Workspace,
    Bootstrap,
    Command,
    Mix.Tasks.Wotex.Thread.Native.Build
  ]
  @json_url "https://raw.githubusercontent.com/nlohmann/json/v3.11.3/single_include/nlohmann/json.hpp"
  @log_names ~w(bootstrap version_cmake version_ninja version_cc version_cxx
    version_readelf target configure compile elf needed)

  @typedoc """
  The explicit outside world of one build.

  `platform` is the running operating system, `native` the pinned
  `priv/openthread` sources, `search_path` the directories searched for build
  tools, and `fetch` the pinned-source transfer. Production callers use the
  defaults; a verification build supplies its own recorded tools and sources
  instead of reaching the network.
  """
  @type environment :: %{
          platform: {atom(), atom()},
          native: Path.t(),
          search_path: String.t() | nil,
          fetch: (String.t(), Path.t(), String.t() -> :ok | {:error, atom()})
        }

  @doc "Returns the production build environment."
  @spec environment() :: environment()
  def environment do
    %{
      platform: :os.type(),
      native: Application.app_dir(:wotex_thread, "priv/openthread"),
      search_path: nil,
      fetch: &Source.fetch/3
    }
  end

  @doc "Builds or verifies the pinned host; Linux and required tools are checked before workspace mutation."
  @spec run(Path.t(), boolean(), environment()) :: {:ok, Workspace.result()} | {:error, term()}
  def run(workspace, sanitizers \\ false, environment \\ environment())

  def run(workspace, sanitizers, environment)
      when is_binary(workspace) and is_boolean(sanitizers) and is_map(environment) do
    native = environment.native

    with :ok <- platform(environment),
         {:ok, tools} <- tools(environment),
         {:ok, pins} <- pins(native),
         {:ok, files} <- Source.file_hashes(native),
         {:ok, modules} <- build_modules(),
         {:ok, revision} <- Source.tree_digest(native) do
      identity = identity(workspace, sanitizers, tools, pins, files, modules, revision, native)

      Workspace.run(workspace, identity, artifacts(pins), fn ->
        build(workspace, sanitizers, native, tools, pins, environment)
      end)
    end
  end

  def run(_, _, _), do: {:error, :invalid_build_workspace}

  defp platform(%{platform: platform}) do
    if platform == {:unix, :linux}, do: :ok, else: {:error, :linux_required}
  end

  defp tools(environment) do
    Enum.reduce_while(@tools, {:ok, %{}}, fn name, {:ok, found} ->
      case Source.executable(name, environment.search_path) do
        path when is_binary(path) ->
          case tool_hash(path) do
            {:ok, hash} -> {:cont, {:ok, Map.put(found, name, %{path: path, sha256: hash})}}
            error -> {:halt, error}
          end

        _ ->
          {:halt, {:error, {:missing_native_tool, name}}}
      end
    end)
  end

  defp tool_hash(path) do
    with {:ok, %File.Stat{type: :regular, size: size}} when size <= 100_000_000 <-
           File.stat(path),
         {:ok, bytes} <- File.read(path) do
      {:ok, Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)}
    else
      _ -> {:error, :invalid_native_tool}
    end
  end

  defp pins(native) do
    with {:ok, bytes} <- File.read(Path.join(native, "dependencies.json")),
         {:ok, %{"sources" => sources, "json" => json} = pins} <- Jason.decode(bytes),
         true <- is_map(sources) and is_map(json),
         true <- Enum.all?(@source_names, &is_map(sources[&1])),
         true <- is_binary(json["sha256"]) do
      {:ok, pins}
    else
      _ -> {:error, :invalid_native_pins}
    end
  end

  defp build_modules do
    Enum.reduce_while(@build_modules, {:ok, %{}}, fn module, {:ok, hashes} ->
      case Source.module_digest(module) do
        {:ok, hash} -> {:cont, {:ok, Map.put(hashes, Atom.to_string(module), hash)}}
        _ -> {:halt, {:error, :missing_native_build_module}}
      end
    end)
  end

  defp identity(workspace, sanitizers, tools, pins, files, modules, revision, native) do
    sdk =
      Path.join([
        workspace,
        "sources",
        "openthread",
        "openthread-#{pins["sources"]["openthread"]["commit"]}"
      ])

    upstream =
      Map.new(@source_names, fn name ->
        pin = pins["sources"][name]

        {name,
         Map.put(
           pin,
           "url",
           "https://codeload.github.com/#{pin["repository"]}/tar.gz/#{pin["commit"]}"
         )}
      end)

    %{
      "source_revision" => revision,
      "source_files" => files,
      "build_modules" => modules,
      "upstream_sources" => upstream,
      "json_header" => pins["json"],
      "toolchain" => tools,
      "build_features" => %{"sanitizers" => sanitizers},
      "arguments" => %{
        "configure" => configure_args(workspace, native, tools, sanitizers, sdk),
        "compile" => [
          "--build",
          Path.join(workspace, "build"),
          "--target",
          "wotex-thread-host",
          "-j4"
        ]
      },
      "environment_allowlist" => ~w(HOME LC_ALL PATH TMPDIR)
    }
  end

  defp artifacts(pins) do
    [
      "bin/build-command",
      "downloads/json.hpp",
      "sources",
      "build/wotex-thread-host",
      "build/include/nlohmann/json.hpp",
      "build/CMakeCache.txt"
    ] ++
      Enum.map(@source_names, fn name ->
        "archives/#{name}-#{pins["sources"][name]["commit"]}.tar.gz"
      end) ++ Enum.map(@log_names, &"logs/#{&1}.log")
  end

  defp build(workspace, sanitizers, native, tools, pins, environment) do
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
         {:ok, sdk} <- sources(workspace, pins, environment),
         :ok <-
           environment.fetch.(
             @json_url,
             Path.join(workspace, "downloads/json.hpp"),
             pins["json"]["sha256"]
           ),
         :ok <- configure_and_compile(guardian, workspace, native, sdk, tools, sanitizers),
         {:ok, audit} <- audit(guardian, workspace, tools, pins, versions) do
      {:ok, audit}
    else
      {:error, code, result} -> {:error, {code, result}}
      {:error, _} = error -> error
      _ -> {:error, :native_build_failed}
    end
  end

  defp directories(workspace) do
    Enum.reduce_while(~w(bin downloads archives sources build logs tmp), :ok, fn name, :ok ->
      case File.mkdir_p(Path.join(workspace, name)) do
        :ok -> {:cont, :ok}
        _ -> {:halt, {:error, :native_build_filesystem}}
      end
    end)
  end

  defp versions(guardian, workspace, tools) do
    steps = [
      {:version_cmake, "cmake", ["--version"]},
      {:version_ninja, "ninja", ["--version"]},
      {:version_cc, "cc", ["--version"]},
      {:version_cxx, "c++", ["--version"]},
      {:version_readelf, "readelf", ["--version"]},
      {:target, "cc", ["-dumpmachine"]}
    ]

    Enum.reduce_while(steps, {:ok, %{}}, fn {id, name, args}, {:ok, found} ->
      case command(guardian, workspace, id, tools[name].path, args, 10_000) do
        {:ok, output} -> {:cont, {:ok, Map.put(found, Atom.to_string(id), String.trim(output))}}
        error -> {:halt, error}
      end
    end)
  end

  defp sources(workspace, pins, environment) do
    result =
      Enum.reduce_while(@source_names, {:ok, %{}}, fn name, {:ok, roots} ->
        pin = pins["sources"][name]
        root = "#{name}-#{pin["commit"]}"
        archive = Path.join(workspace, "archives/#{root}.tar.gz")
        destination = Path.join(workspace, "sources/#{name}")
        url = "https://codeload.github.com/#{pin["repository"]}/tar.gz/#{pin["commit"]}"

        with :ok <- environment.fetch.(url, archive, pin["archive_sha256"]),
             :ok <- Source.extract(archive, destination, root) do
          {:cont, {:ok, Map.put(roots, name, Path.join(destination, root))}}
        else
          error -> {:halt, error}
        end
      end)

    with {:ok, roots} <- result,
         sdk = roots["openthread"],
         :ok <- Source.patch_spinel(sdk, pins["spinel_unsigned_shift_fix"]),
         :ok <- Source.patch_discerner(sdk, pins["discerner_full_width_fix"]),
         :ok <-
           Source.copy_tree(roots["mbedtls-framework"], Path.join(roots["mbedtls"], "framework")),
         :ok <- Source.copy_tree(roots["mbedtls"], Path.join(sdk, "third_party/mbedtls/repo")) do
      {:ok, sdk}
    end
  end

  defp configure_and_compile(guardian, workspace, native, sdk, tools, sanitizers) do
    with {:ok, _} <-
           command(
             guardian,
             workspace,
             :configure,
             tools["cmake"].path,
             configure_args(workspace, native, tools, sanitizers, sdk),
             300_000
           ),
         {:ok, _} <-
           command(
             guardian,
             workspace,
             :compile,
             tools["cmake"].path,
             ["--build", Path.join(workspace, "build"), "--target", "wotex-thread-host", "-j4"],
             1_800_000
           ) do
      :ok
    end
  end

  defp configure_args(workspace, native, tools, sanitizers, sdk) do
    [
      "-G",
      "Ninja",
      "-S",
      native,
      "-B",
      Path.join(workspace, "build"),
      "-DCMAKE_BUILD_TYPE=RelWithDebInfo",
      "-DWOTEX_OPENTHREAD_SOURCE=#{sdk}",
      "-DWOTEX_JSON_HEADER=#{Path.join(workspace, "downloads/json.hpp")}",
      "-DCMAKE_C_COMPILER=#{tools["cc"].path}",
      "-DCMAKE_CXX_COMPILER=#{tools["c++"].path}",
      "-DWOTEX_NATIVE_SANITIZERS=#{if(sanitizers, do: "ON", else: "OFF")}"
    ]
  end

  defp audit(guardian, workspace, tools, pins, versions) do
    executable = Path.join(workspace, "build/wotex-thread-host")
    header = Path.join(workspace, "build/include/nlohmann/json.hpp")

    with {:ok, executable_hash} <- Source.digest(executable),
         {:ok, header_hash} <- Source.digest(header),
         true <- header_hash == pins["json"]["sha256"],
         {:ok, source_hash} <- Source.tree_digest(Path.join(workspace, "sources")),
         {:ok, elf} <-
           command(guardian, workspace, :elf, tools["readelf"].path, ["-h", executable], 10_000),
         {:ok, needed} <-
           command(guardian, workspace, :needed, tools["readelf"].path, ["-d", executable], 10_000),
         [_, machine] <- Regex.run(~r/Machine:\s*([^\n]+)/, elf) do
      {:ok,
       %{
         "toolchain_versions" => versions,
         "target_triple" => versions["target"],
         "sdk_sources_sha256" => source_hash,
         "binary" => %{
           "path" => "build/wotex-thread-host",
           "sha256" => executable_hash,
           "elf_machine" => String.trim(machine),
           "needed_libraries" =>
             Enum.map(Regex.scan(~r/Shared library: \[([^]]+)\]/, needed), &Enum.at(&1, 1))
         },
         "json_header_sha256" => header_hash,
         "native_runtime_started" => false
       }}
    else
      _ -> {:error, :invalid_native_artifact}
    end
  end

  defp command(guardian, workspace, id, executable, args, timeout_ms) do
    path =
      [Path.dirname(executable), "/usr/bin", "/bin"]
      |> Enum.uniq()
      |> Enum.join(":")

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

    log = Path.join(workspace, "logs/#{id}.log")

    with :ok <- File.write(log, output, [:exclusive]) do
      case result do
        {:ok, _} -> {:ok, output}
        {:error, code, details} -> {:error, {code, id, details.exit_status}}
      end
    end
  end
end
