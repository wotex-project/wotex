defmodule Wotex.BLE.CoreBluetooth.Build do
  @moduledoc """
  Builds the native CoreBluetooth process and guardian in an explicit workspace.

  `run/1` requires macOS and an installed Apple SDK. It selects Apple tools with
  bounded `xcrun` probes, records executable and selected SDK API/header digests,
  then uses the existing workspace and command guardians. Matching completed
  workspaces are verified read-only; changed, unrelated or incomplete inputs
  refuse reuse. The selected tools and SDK must remain immutable during the build.

  The host embeds its Bluetooth usage description and targets macOS 14. Audits
  require the running architecture, only Apple system dependencies and exact
  embedded plist bytes. A closed-input probe emits the pinned ready receipt
  without creating a manager. Build success supplies artifact identity; it
  supplies no permission, peripheral or physical-operation qualification.
  """

  alias Wotex.BLE.Native.{Bootstrap, BuildOperations, Command, Source, Workspace}

  @shared ~w(frame.hpp bytes.hpp output.hpp vendor/json.hpp vendor/LICENSE.MIT custody.c build_command.c)
  @api ~w(CoreBluetooth.h CBManager.h CBCentralManager.h CBPeripheral.h CBService.h CBCharacteristic.h)
  @host "output/bin/wotex-ble-corebluetooth"
  @guardian "output/bin/wotex-ble-guardian"
  @ids ~w(host guardian host_dependencies guardian_dependencies host_commands host_arch guardian_arch ready_probe)a
  @ready ~s({"backend":"corebluetooth-native","event":"ready","revision":"1","version":1}\n)
  @build_files [
                 __ENV__.file,
                 Path.expand("../../../mix/tasks/wotex.ble.corebluetooth.build.ex", __DIR__)
               ] ++
                 Enum.map(
                   ~w(bootstrap command source workspace build_operations),
                   &Path.expand("../native/#{&1}.ex", __DIR__)
                 )
  for file <- @build_files, do: @external_resource(file)

  @build_hashes Map.new(
                  @build_files,
                  &{Path.basename(&1),
                   Base.encode16(:crypto.hash(:sha256, File.read!(&1)), case: :lower)}
                )

  @doc "Validates the exact explicit workspace argument vector without I/O."
  @spec arguments(term()) :: {:ok, String.t()} | {:error, atom()}
  defdelegate arguments(args), to: Workspace

  @doc "Builds or verifies a complete native CoreBluetooth workspace."
  @spec run(term()) :: {:ok, Workspace.result()} | {:error, term()}
  def run(workspace) do
    with {:ok, ^workspace} <- arguments(["--workspace", workspace]),
         true <- :os.type() == {:unix, :darwin},
         native = Application.app_dir(:wotex_ble, "priv/corebluetooth/native"),
         shared = Application.app_dir(:wotex_ble, "priv/bluez/native"),
         {:ok, tools} <- discover(shared),
         {:ok, sources} <- sources(native, shared) do
      paths = %{
        workspace: workspace,
        native: native,
        shared: shared,
        command: Path.join(workspace, "bin/build-command")
      }

      steps = steps(paths, tools)

      identity = %{
        "source_revision" => digest(Enum.map(Enum.sort(sources), &Tuple.to_list/1)),
        "source_files" => sources,
        "build_sources" => @build_hashes,
        "toolchain" => tools.executables,
        "upstream_sources" => %{"apple_sdk" => tools.sdk},
        "arguments" =>
          Map.put(
            Map.new(steps, &{Atom.to_string(&1.id), [&1.executable | &1.args]}),
            "bootstrap",
            [
              tools.executables["bootstrap_cc"]["path"],
              "-std=c11",
              "-O2",
              "-Wall",
              "-Wextra",
              "-Werror",
              Path.join(paths.shared, "build_command.c"),
              "-o",
              paths.command
            ]
          ),
        "environment_allowlist" => ~w(PATH LC_ALL TMPDIR),
        "build_features" => %{
          "backend" => "corebluetooth-native",
          "revision" => "1",
          "minimum_macos" => "14.0",
          "system_power_observation" => "iokit",
          "architecture" => tools.arch,
          "arc" => true,
          "sanitizers" => false
        }
      }

      artifacts =
        ["bin/build-command", @host, @guardian, "logs/bootstrap.log"] ++
          Enum.map(@ids, &"logs/#{&1}.log")

      Workspace.run(workspace, identity, artifacts, fn -> build(paths, tools, steps) end)
    else
      false -> {:error, :macos_required}
      {:error, _} = error -> error
    end
  rescue
    _ in [File.Error, ErlangError, ArgumentError] -> {:error, :corebluetooth_build_failed}
  end

  defp discover(shared) do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-cb-tools-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    try do
      cc = System.find_executable("cc")
      xcrun = System.find_executable("xcrun")
      command = Path.join(directory, "command")

      with true <- is_binary(cc) and is_binary(xcrun),
           {:ok, _} <-
             Bootstrap.compile(cc, Path.join(shared, "build_command.c"), command, directory),
           {:ok, sdk_path} <-
             capture(command, xcrun, ["--sdk", "macosx", "--show-sdk-path"], directory),
           {:ok, version} <-
             capture(command, xcrun, ["--sdk", "macosx", "--show-sdk-version"], directory),
           {:ok, executables} <- selected_tools(command, xcrun, directory),
           {:ok, xcrun_hash} <- BuildOperations.tool_digest(xcrun),
           {:ok, cc_hash} <- BuildOperations.tool_digest(cc),
           {:ok, settings} <- Source.digest(Path.join(sdk_path, "SDKSettings.json")),
           {:ok, api} <-
             hashes(
               sdk_path,
               Enum.map(@api, &"System/Library/Frameworks/CoreBluetooth.framework/Headers/#{&1}") ++
                 Enum.map(
                   ~w(IOKitLib.h IOMessage.h pwr_mgt/IOPMLib.h),
                   &"System/Library/Frameworks/IOKit.framework/Headers/#{&1}"
                 )
             ),
           {:ok, compiler_version} <-
             capture(command, executables["clang"]["path"], ["--version"], directory),
           {:ok, arch} <- architecture() do
        {:ok,
         %{
           executables:
             executables
             |> Map.put("xcrun", %{"path" => xcrun, "sha256" => xcrun_hash})
             |> Map.put("bootstrap_cc", %{"path" => cc, "sha256" => cc_hash}),
           sdk: %{
             "path" => sdk_path,
             "version" => version,
             "settings_sha256" => settings,
             "api_headers" => api
           },
           compiler_version: compiler_version,
           arch: arch
         }}
      else
        false -> {:error, :missing_apple_toolchain}
        {:error, _, _} -> {:error, :native_tool_probe_failed}
        {:error, _} = error -> error
      end
    after
      File.rm_rf!(directory)
    end
  end

  defp selected_tools(command, xcrun, directory) do
    Enum.reduce_while(~w(clang clang++ ld otool lipo), {:ok, %{}}, fn name, {:ok, tools} ->
      with {:ok, path} <- capture(command, xcrun, ["--sdk", "macosx", "--find", name], directory),
           true <- Path.type(path) == :absolute,
           {:ok, hash} <- BuildOperations.tool_digest(path) do
        {:cont, {:ok, Map.put(tools, name, %{"path" => path, "sha256" => hash})}}
      else
        _ -> {:halt, {:error, :invalid_apple_toolchain}}
      end
    end)
  end

  defp architecture do
    case List.to_string(:erlang.system_info(:system_architecture)) do
      "aarch64" <> _ -> {:ok, "arm64"}
      "arm64" <> _ -> {:ok, "arm64"}
      "x86_64" <> _ -> {:ok, "x86_64"}
      _ -> {:error, :unsupported_native_architecture}
    end
  end

  defp capture(guardian, executable, arguments, directory) do
    case Command.run(guardian, step(:probe, executable, arguments, directory, 15_000)) do
      {:ok, %{output: bytes}} -> {:ok, String.trim(bytes)}
      _ -> {:error, :native_tool_probe_failed}
    end
  end

  defp sources(native, shared) do
    with {:ok, own} <- Source.file_hashes(native), {:ok, shared} <- hashes(shared, @shared) do
      {:ok,
       Map.merge(
         Map.new(own, fn {path, hash} -> {"corebluetooth/" <> path, hash} end),
         Map.new(shared, fn {path, hash} -> {"bluez/" <> path, hash} end)
       )}
    end
  end

  defp hashes(root, names) do
    Enum.reduce_while(names, {:ok, %{}}, fn path, {:ok, hashes} ->
      case Source.digest(Path.join(root, path)) do
        {:ok, hash} -> {:cont, {:ok, Map.put(hashes, path, hash)}}
        error -> {:halt, error}
      end
    end)
  end

  defp digest(value), do: Base.encode16(:crypto.hash(:sha256, Jason.encode!(value)), case: :lower)

  defp step(id, executable, args, directory, timeout \\ 30_000) do
    %{
      id: id,
      executable: executable,
      args: args,
      cwd: directory,
      timeout_ms: timeout,
      output_bytes: 1_048_576,
      cleanup_ms: 1000,
      env: [{"PATH", "/usr/bin:/bin"}, {"LC_ALL", "C"}, {"TMPDIR", directory}]
    }
  end

  defp steps(paths, tools) do
    executable = fn name -> tools.executables[name]["path"] end
    host = Path.join(paths.workspace, @host)
    guardian = Path.join(paths.workspace, @guardian)
    target = ["-isysroot", tools.sdk["path"], "-arch", tools.arch, "-mmacosx-version-min=14.0"]

    [
      step(
        :host,
        executable.("clang++"),
        ~w(-std=c++17 -O2 -Wall -Wextra -Werror -x objective-c++ -fobjc-arc) ++
          target ++
          [
            Path.join(paths.native, "main.cpp"),
            Path.join(paths.native, "sdk.cpp"),
            "-framework",
            "Foundation",
            "-framework",
            "CoreBluetooth",
            "-framework",
            "IOKit",
            "--ld-path=#{executable.("ld")}",
            "-Xlinker",
            "-sectcreate",
            "-Xlinker",
            "__TEXT",
            "-Xlinker",
            "__info_plist",
            "-Xlinker",
            Path.join(paths.native, "Info.plist"),
            "-o",
            host
          ],
        paths.workspace,
        120_000
      ),
      step(
        :guardian,
        executable.("clang"),
        ~w(-std=c11 -O2 -Wall -Wextra -Werror) ++
          target ++
          [Path.join(paths.shared, "custody.c"), "-o", guardian],
        paths.workspace
      ),
      step(:host_dependencies, executable.("otool"), ["-L", host], paths.workspace),
      step(:guardian_dependencies, executable.("otool"), ["-L", guardian], paths.workspace),
      step(:host_commands, executable.("otool"), ["-l", host], paths.workspace),
      step(:host_arch, executable.("lipo"), ["-archs", host], paths.workspace),
      step(:guardian_arch, executable.("lipo"), ["-archs", guardian], paths.workspace),
      step(:ready_probe, host, [], paths.workspace, 2000)
    ]
  end

  defp build(paths, tools, steps) do
    for directory <- ~w(bin output/bin logs tmp),
        do: File.mkdir_p!(Path.join(paths.workspace, directory))

    with {:ok, bootstrap} <-
           Bootstrap.compile(
             tools.executables["bootstrap_cc"]["path"],
             Path.join(paths.shared, "build_command.c"),
             paths.command,
             paths.workspace
           ),
         :ok <- File.write(Path.join(paths.workspace, "logs/bootstrap.log"), bootstrap.output),
         {:ok, outputs} <- run_steps(paths, steps),
         {:ok, host_deps} <- dependencies(outputs.host_dependencies),
         {:ok, guardian_deps} <- dependencies(outputs.guardian_dependencies),
         true <- outputs.host_arch == tools.arch and outputs.guardian_arch == tools.arch,
         true <- Enum.any?(host_deps, &String.contains?(&1, "/CoreBluetooth.framework/")),
         true <- Enum.any?(host_deps, &String.contains?(&1, "/Foundation.framework/")),
         true <- Enum.any?(host_deps, &String.contains?(&1, "/IOKit.framework/")),
         :ok <-
           embedded_plist(
             Path.join(paths.workspace, @host),
             outputs.host_commands,
             Path.join(paths.native, "Info.plist")
           ) do
      {:ok,
       %{
         "toolchain_versions" => %{"clang" => tools.compiler_version, "sdk" => tools.sdk["version"]},
         "target_triple" => tools.arch <> "-apple-macos14.0",
         "ready_probe" => @ready,
         "binaries" => [
           %{
             "path" => @host,
             "format" => "mach-o",
             "architecture" => tools.arch,
             "dependencies" => host_deps
           },
           %{
             "path" => @guardian,
             "format" => "mach-o",
             "architecture" => tools.arch,
             "dependencies" => guardian_deps
           }
         ],
         "embedded_usage_description" => true,
         "bootstrap_descendant_cleanup" => "unverified",
         "advisory_scan" => "not_performed",
         "sdk" => tools.sdk
       }}
    else
      false ->
        {:error, :invalid_native_artifact}

      {:error, reason, %{output: output}} ->
        File.write!(Path.join(paths.workspace, "logs/bootstrap.log"), output)
        {:error, reason}

      error ->
        error
    end
  end

  defp run_steps(paths, steps) do
    Enum.reduce_while(steps, {:ok, %{}}, fn step, {:ok, outputs} ->
      result = Command.run(paths.command, step)

      case result do
        {:ok, %{output: bytes}} when step.id != :ready_probe ->
          File.write!(Path.join(paths.workspace, "logs/#{step.id}.log"), bytes)
          {:cont, {:ok, Map.put(outputs, step.id, String.trim(bytes))}}

        {:error, :command_failed, %{output: @ready, exit_status: 1}} when step.id == :ready_probe ->
          File.write!(Path.join(paths.workspace, "logs/#{step.id}.log"), @ready)
          {:cont, {:ok, Map.put(outputs, step.id, @ready)}}

        {:error, _, %{output: bytes}} ->
          File.write!(Path.join(paths.workspace, "logs/#{step.id}.log"), bytes)
          {:halt, {:error, {:corebluetooth_build_step_failed, step.id}}}

        _ ->
          {:halt, {:error, {:corebluetooth_build_step_failed, step.id}}}
      end
    end)
  end

  defp dependencies(output) do
    dependencies =
      output
      |> String.split("\n")
      |> Enum.drop(1)
      |> Enum.map(fn line ->
        line
        |> String.trim()
        |> String.split(" (", parts: 2)
        |> hd()
      end)

    if dependencies != [] and
         Enum.all?(dependencies, &String.starts_with?(&1, ["/System/Library/", "/usr/lib/"])),
       do: {:ok, dependencies},
       else: {:error, :invalid_native_dependencies}
  end

  defp embedded_plist(host, commands, source) do
    case Regex.scan(
           ~r/sectname __info_plist\s+segname __TEXT\s+addr \S+\s+size 0x([0-9a-fA-F]+)\s+offset ([0-9]+)/,
           commands
         ) do
      [[_, size, offset]] ->
        {size, ""} = Integer.parse(size, 16)

        with true <- size <= 16_384,
             {:ok, expected} <- File.read(source),
             {:ok, file} <- :file.open(String.to_charlist(host), [:read, :binary, :raw]) do
          try do
            if :file.pread(file, String.to_integer(offset), size) == {:ok, expected},
              do: :ok,
              else: {:error, :invalid_embedded_usage_description}
          after
            :file.close(file)
          end
        else
          _ -> {:error, :invalid_embedded_usage_description}
        end

      _ ->
        {:error, :invalid_embedded_usage_description}
    end
  end
end
