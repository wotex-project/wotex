defmodule Wotex.BLE.Native.Build do
  @moduledoc """
  Builds the first-party BlueZ SDK host from pinned sources in an explicit workspace.

  `run/1` is invoked only by `mix wotex.native.build --workspace ABSOLUTE_PATH`.
  It requires Linux, resolves `cmake`, `ninja`, `pkg-config`, `cc`, `c++`, `readelf` and `xz`
  from the caller's `PATH`, and records each executable's path and SHA-256 before
  touching the workspace. The target architecture reported by the C compiler
  must match the running BEAM; this task does not cross compile.

  The builder downloads libdbus 1.16.2 over verified HTTPS, checks its pinned
  archive digest, admits only its regular-file source tree and builds the shared
  `libdbus-1.so.3` library plus a private-bus `dbus-daemon` with CMake and Ninja.
  It compiles `wotex-ble-host` from the packaged C++17 sources against that
  library with runpath `$ORIGIN/../lib`, and `wotex-ble-guardian` from the
  packaged C11 runtime guardian. Every command after guardian bootstrap runs in
  its own bounded process group and writes a retained log.

  The audit reads ELF machine, needed libraries, runpath and soname for each
  output, rejects a Python runtime dependency, and runs the host once with
  closed input. That probe must emit exactly the pinned ready frame and exit
  with status 1 for input loss. `native-manifest.json` then binds sources, pins,
  tools, arguments, binaries, logs and probe output. Advisory scanning is not
  performed and is recorded as such. Build success establishes artifact
  identity only; D-Bus, BlueZ and GATT behavior require separate execution.
  """

  alias Wotex.BLE.Native.{BuildOperations, Source, Workspace}

  @tools ~w(cmake ninja pkg-config cc c++ readelf xz)
  @version_steps [
    :version_cmake,
    :version_ninja,
    :version_pkg_config,
    :version_cc,
    :version_cxx,
    :version_readelf,
    :version_xz,
    :target
  ]
  @host "output/bin/wotex-ble-host"
  @guardian "output/bin/wotex-ble-guardian"
  @daemon "output/bin/dbus-daemon"
  @library "output/lib/libdbus-1.so.3"
  @ready ~s({"backend":"bluez-native","event":"ready","revision":"2123ab772fbe97d1369fc9e179ea87c3469cf98f","version":1}\n)
  @build_sources [
                   Path.expand("../../../mix/tasks/wotex.ble.native.build.ex", __DIR__)
                   | Path.wildcard(Path.join(__DIR__, "*.ex"))
                 ]
                 |> Enum.sort()
  for file <- @build_sources, do: @external_resource(file)

  @build_hashes Map.new(@build_sources, fn file ->
                  {Path.basename(file),
                   Base.encode16(:crypto.hash(:sha256, File.read!(file)), case: :lower)}
                end)

  @doc "Validates the exact task argument vector before any build I/O."
  @spec arguments(term()) :: {:ok, String.t()} | {:error, :invalid_native_build_arguments}
  defdelegate arguments(args), to: Workspace

  @doc "Builds or read-only verifies one native workspace."
  @spec run(term()) :: {:ok, Workspace.result()} | {:error, term()}
  def run(workspace), do: run(workspace, BuildOperations)

  @doc false
  @spec run(term(), module()) :: {:ok, Workspace.result()} | {:error, term()}
  def run(workspace, operations) when is_binary(workspace) and is_atom(operations) do
    native = Application.app_dir(:wotex_ble, "priv/bluez/native")

    with {:ok, architecture} <- operations.platform(),
         {:ok, tools} <- tools(operations),
         {:ok, pin} <- Source.pin(native, "libdbus"),
         {:ok, files} <- Source.file_hashes(native),
         {:ok, revision} <- Source.tree_digest(native) do
      paths = paths(workspace, native, pin)
      identity = identity(paths, tools, pin, files, revision)

      Workspace.run(workspace, identity, artifacts(), fn ->
        build(paths, tools, pin, architecture, operations)
      end)
    end
  end

  def run(_, _), do: {:error, :invalid_build_workspace}

  @doc false
  @spec paths(String.t(), String.t(), Source.pin()) :: map()
  def paths(workspace, native, pin) do
    %{
      workspace: workspace,
      native: native,
      command: Path.join(workspace, "bin/build-command"),
      archive: Path.join(workspace, "downloads/#{pin["root"]}.tar.xz"),
      tar: Path.join(workspace, "downloads/#{pin["root"]}.tar"),
      sources: Path.join(workspace, "sources/libdbus"),
      source: Path.join([workspace, "sources/libdbus", pin["root"]]),
      build: Path.join(workspace, "build/libdbus"),
      tmp: Path.join(workspace, "tmp"),
      host: Path.join(workspace, @host),
      guardian: Path.join(workspace, @guardian),
      daemon: Path.join(workspace, @daemon),
      library: Path.join(workspace, @library)
    }
  end

  @doc false
  @spec steps(map(), map()) :: [map()]
  def steps(paths, tools) do
    versions(tools) ++
      [
        step(:decompress, tools, "xz", paths.tmp, 60_000, [
          "--decompress",
          "--keep",
          "--threads=1",
          "--memlimit-decompress=64MiB",
          paths.archive
        ]),
        step(:configure, tools, "cmake", paths.tmp, 300_000, configure(paths, tools)),
        step(:compile, tools, "cmake", paths.tmp, 600_000, [
          "--build",
          paths.build,
          "--target",
          "dbus-1",
          "dbus-daemon",
          "--parallel",
          "6"
        ]),
        step(:host, tools, "c++", paths.tmp, 600_000, host(paths)),
        step(:guardian, tools, "cc", paths.tmp, 120_000, [
          "-std=c11",
          "-O2",
          "-Wall",
          "-Wextra",
          "-Werror",
          Path.join(paths.native, "custody.c"),
          "-o",
          paths.guardian
        ])
      ]
  end

  @doc false
  @spec elf(binary()) :: {:ok, map()} | {:error, :invalid_native_artifact}
  def elf(output) when is_binary(output) do
    case Regex.run(~r/^\s*Machine:\s*(.+)$/m, output) do
      [_, machine] ->
        {:ok,
         %{
           "elf_machine" => String.trim(machine),
           "needed_libraries" =>
             Enum.map(
               Regex.scan(~r/\(NEEDED\)\s+Shared library: \[([^\]]+)\]/, output),
               &Enum.at(&1, 1)
             ),
           "runpath" =>
             single(~r/\((?:RUNPATH|RPATH)\)\s+Library r(?:un)?path: \[([^\]]+)\]/, output),
           "soname" => single(~r/\(SONAME\)\s+Library soname: \[([^\]]+)\]/, output)
         }}

      _ ->
        {:error, :invalid_native_artifact}
    end
  end

  def elf(_), do: {:error, :invalid_native_artifact}

  defp single(pattern, output) do
    case Regex.scan(pattern, output) do
      [[_, value]] -> value
      _ -> nil
    end
  end

  defp tools(operations) do
    Enum.reduce_while(@tools, {:ok, %{}}, fn name, {:ok, found} ->
      with path when is_binary(path) <- operations.find_executable(name),
           {:ok, digest} <- operations.tool_digest(path) do
        {:cont, {:ok, Map.put(found, name, %{"path" => path, "sha256" => digest})}}
      else
        nil -> {:halt, {:error, {:missing_native_tool, name}}}
        error -> {:halt, error}
      end
    end)
  end

  defp identity(paths, tools, pin, files, revision) do
    %{
      "source_revision" => revision,
      "source_files" => files,
      "build_sources" => @build_hashes,
      "upstream_sources" => %{"libdbus" => pin},
      "toolchain" => tools,
      "arguments" =>
        Map.new(steps(paths, tools), fn step ->
          {Atom.to_string(step.id), [step.executable | step.args]}
        end),
      "environment_allowlist" => ~w(HOME LC_ALL PATH TMPDIR),
      "build_features" => %{
        "libdbus" => "shared",
        "private_bus_daemon" => true,
        "sanitizers" => false,
        "runpath" => "$ORIGIN/../lib"
      }
    }
  end

  defp artifacts do
    [
      "bin/build-command",
      "downloads/dbus-1.16.2.tar.xz",
      "downloads/dbus-1.16.2.tar",
      "sources",
      @host,
      @guardian,
      @daemon,
      @library
    ] ++ Enum.map(log_ids(), &"logs/#{&1}.log")
  end

  defp log_ids do
    ~w(bootstrap version_cmake version_ninja version_pkg_config version_cc version_cxx version_readelf version_xz
      target decompress configure compile host guardian audit_host audit_guardian audit_daemon
      audit_library ready_probe)
  end

  defp versions(tools) do
    [
      {:version_cmake, "cmake", ["--version"]},
      {:version_ninja, "ninja", ["--version"]},
      {:version_pkg_config, "pkg-config", ["--version"]},
      {:version_cc, "cc", ["--version"]},
      {:version_cxx, "c++", ["--version"]},
      {:version_readelf, "readelf", ["--version"]},
      {:version_xz, "xz", ["--version"]},
      {:target, "cc", ["-dumpmachine"]}
    ]
    |> Enum.map(fn {id, tool, args} -> step(id, tools, tool, nil, 30_000, args) end)
  end

  defp step(id, tools, tool, cwd, timeout, args) do
    %{
      id: id,
      tool: tool,
      cwd: cwd,
      executable: tools[tool]["path"],
      args: args,
      timeout_ms: timeout
    }
  end

  defp configure(paths, tools) do
    [
      "-G",
      "Ninja",
      "-S",
      paths.source,
      "-B",
      paths.build,
      "-DCMAKE_MAKE_PROGRAM=#{tools["ninja"]["path"]}",
      "-DCMAKE_C_COMPILER=#{tools["cc"]["path"]}",
      "-DPKG_CONFIG_EXECUTABLE=#{tools["pkg-config"]["path"]}",
      "-DCMAKE_BUILD_TYPE=Release",
      "-DCMAKE_BUILD_RPATH_USE_ORIGIN=ON",
      "-DDBUS_BUILD_TESTS=OFF",
      "-DDBUS_ENABLE_DOXYGEN_DOCS=OFF",
      "-DDBUS_ENABLE_XML_DOCS=OFF",
      "-DDBUS_ENABLE_PKGCONFIG=OFF",
      "-DDBUS_WITH_GLIB=OFF",
      "-DENABLE_SYSTEMD=OFF",
      "-DDBUS_BUILD_X11=OFF"
    ]
  end

  defp host(paths) do
    [
      "-std=c++17",
      "-O2",
      "-Wall",
      "-Wextra",
      "-Werror",
      "-pedantic",
      "-I",
      paths.native,
      "-I",
      paths.source,
      "-I",
      paths.build,
      Path.join(paths.native, "main.cpp"),
      paths.library,
      "-Wl,-rpath,$ORIGIN/../lib",
      "-o",
      paths.host
    ]
  end

  defp build(paths, tools, pin, architecture, operations) do
    with :ok <- directories(paths.workspace),
         {:ok, bootstrap} <-
           bootstrap(paths, tools, operations),
         {:ok, logs} <- log(paths.workspace, "bootstrap", bootstrap.output, 0, 0, %{}),
         run = &run_steps(select(steps(paths, tools), &1), paths, tools, operations, &2),
         {:ok, versions, logs} <- run.(@version_steps, logs),
         :ok <- architecture(versions["target"], architecture),
         :ok <- operations.fetch(pin, paths.archive),
         {:ok, _, logs} <- run.([:decompress], logs),
         :ok <- operations.extract(paths.tar, paths.sources, pin["root"]),
         {:ok, _, logs} <- run.([:configure, :compile], logs),
         :ok <- install_libraries(paths),
         {:ok, _, logs} <- run.([:host, :guardian], logs),
         {:ok, binaries, logs} <- audit(paths, tools, operations, logs),
         {:ok, probe, logs} <- probe(paths, tools, operations, logs) do
      {:ok,
       %{
         "toolchain_versions" => Map.delete(versions, "target"),
         "target_triple" => versions["target"],
         "binaries" => binaries,
         "ready_probe" => probe,
         "libdbus" => %{"version" => pin["version"], "archive_sha256" => pin["sha256"]},
         "advisory_scan" => "not_performed",
         "python_runtime_dependency" => false,
         "logs" => logs
       }}
    end
  end

  defp select(steps, ids), do: Enum.map(ids, fn id -> Enum.find(steps, &(&1.id == id)) end)

  defp directories(workspace) do
    ~w(bin downloads sources build output/bin output/lib logs tmp)
    |> Enum.map(&File.mkdir_p(Path.join(workspace, &1)))
    |> Enum.find(:ok, &(&1 != :ok))
  end

  defp bootstrap(paths, tools, operations) do
    source = Path.join(paths.native, "build_command.c")

    case operations.bootstrap(tools["cc"]["path"], source, paths.command, paths.tmp) do
      {:ok, result} -> {:ok, result}
      {:error, code, _} -> {:error, {code, :bootstrap}}
    end
  end

  defp run_steps(steps, paths, tools, operations, logs) do
    Enum.reduce_while(steps, {:ok, %{}, logs}, fn step, {:ok, outputs, logs} ->
      case execute(paths, tools, operations, step, logs, 0) do
        {:ok, output, logs} ->
          {:cont, {:ok, Map.put(outputs, Atom.to_string(step.id), String.trim(output)), logs}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp execute(paths, tools, operations, step, logs, expected_status) do
    command = %{
      id: step.id,
      executable: step.executable,
      args: step.args,
      cwd: step.cwd || paths.tmp,
      env: environment(paths, tools),
      timeout_ms: step.timeout_ms,
      output_bytes: 16_777_216,
      cleanup_ms: 5000
    }

    started = System.monotonic_time(:millisecond)
    result = operations.command(paths.command, command)
    elapsed = System.monotonic_time(:millisecond) - started

    {output, status} =
      case result do
        {:ok, details} -> {details.output, details.exit_status}
        {:error, _, details} -> {details.output, details.exit_status}
      end

    with {:ok, logs} <- log(paths.workspace, Atom.to_string(step.id), output, status, elapsed, logs) do
      if status == expected_status,
        do: {:ok, output, logs},
        else: {:error, {:native_build_step_failed, step.id, status}}
    end
  end

  defp environment(paths, tools) do
    directories =
      tools
      |> Map.values()
      |> Enum.map(&Path.dirname(&1["path"]))
      |> Kernel.++(["/usr/bin", "/bin"])
      |> Enum.uniq()
      |> Enum.join(":")

    [{"PATH", directories}, {"LC_ALL", "C"}, {"HOME", paths.tmp}, {"TMPDIR", paths.tmp}]
  end

  defp log(workspace, id, output, status, elapsed, logs) do
    path = Path.join(workspace, "logs/#{id}.log")

    with :ok <- File.write(path, output, [:exclusive]),
         {:ok, digest} <- Source.digest(path) do
      {:ok,
       Map.put(logs, id, %{
         "sha256" => digest,
         "bytes" => byte_size(output),
         "exit_status" => status,
         "elapsed_ms" => elapsed
       })}
    else
      _ -> {:error, :native_build_filesystem}
    end
  end

  defp architecture(triple, running) do
    [target | _] = String.split(triple, "-")
    [current | _] = String.split(running, "-")
    if target == current, do: :ok, else: {:error, :target_architecture_mismatch}
  end

  defp install_libraries(paths) do
    library_directory = Path.join(paths.build, "lib")

    with {:ok, names} <- File.ls(library_directory),
         [name] <- Enum.filter(names, &Regex.match?(~r/\Alibdbus-1\.so\.3\.[0-9]+\.[0-9]+\z/, &1)),
         {:ok, %File.Stat{type: :regular}} <- File.lstat(Path.join(library_directory, name)),
         {:ok, %File.Stat{type: :regular}} <- File.lstat(Path.join(paths.build, "bin/dbus-daemon")),
         :ok <- File.cp(Path.join(library_directory, name), paths.library),
         :ok <- File.chmod(paths.library, 0o644),
         :ok <- File.cp(Path.join(paths.build, "bin/dbus-daemon"), paths.daemon),
         :ok <- File.chmod(paths.daemon, 0o755) do
      :ok
    else
      _ -> {:error, :invalid_native_artifact}
    end
  end

  defp audit(paths, tools, operations, logs) do
    [
      {:audit_host, @host, "sdk_host"},
      {:audit_guardian, @guardian, "runtime_guardian"},
      {:audit_daemon, @daemon, "private_bus_fixture"},
      {:audit_library, @library, "runtime_library"}
    ]
    |> Enum.reduce_while({:ok, [], logs}, fn {id, relative, purpose}, {:ok, binaries, logs} ->
      path = Path.join(paths.workspace, relative)
      step = step(id, tools, "readelf", nil, 30_000, ["-h", "-d", path])

      with {:ok, output, logs} <- execute(paths, tools, operations, step, logs, 0),
           {:ok, elf} <- elf(output),
           {:ok, digest} <- Source.digest(path) do
        binary = Map.merge(elf, %{"path" => relative, "purpose" => purpose, "sha256" => digest})
        {:cont, {:ok, [binary | binaries], logs}}
      else
        error -> {:halt, error}
      end
    end)
    |> admitted_binaries()
  end

  defp admitted_binaries({:ok, binaries, logs}) do
    binaries = Enum.reverse(binaries)
    by_purpose = Map.new(binaries, &{&1["purpose"], &1})
    host = by_purpose["sdk_host"]

    cond do
      Enum.any?(binaries, fn binary ->
        Enum.any?(binary["needed_libraries"], &String.contains?(&1, "python"))
      end) ->
        {:error, :python_runtime_dependency}

      not Enum.all?(binaries, &relative_runpath?(&1["runpath"])) ->
        {:error, :absolute_runpath}

      "libdbus-1.so.3" not in host["needed_libraries"] or host["runpath"] != "$ORIGIN/../lib" ->
        {:error, :invalid_native_artifact}

      by_purpose["runtime_library"]["soname"] != "libdbus-1.so.3" ->
        {:error, :invalid_native_artifact}

      true ->
        {:ok, binaries, logs}
    end
  end

  defp admitted_binaries(error), do: error

  # Build-tree absolute runpaths would let a deployed library resolve from the
  # build machine's paths. Only origin-relative search entries are admitted.
  defp relative_runpath?(nil), do: true

  defp relative_runpath?(runpath) do
    runpath
    |> String.split(":", trim: true)
    |> Enum.all?(&String.starts_with?(&1, "$ORIGIN"))
  end

  defp probe(paths, tools, operations, logs) do
    step = %{
      id: :ready_probe,
      tool: nil,
      cwd: nil,
      executable: paths.host,
      args: [],
      timeout_ms: 10_000
    }

    with {:ok, output, logs} <- execute(paths, tools, operations, step, logs, 1),
         true <- output == @ready || {:error, :invalid_ready_probe},
         {:ok, frame} <- Jason.decode(output) do
      {:ok,
       %{
         "exit_status" => 1,
         "frame" => frame,
         "output_sha256" => Base.encode16(:crypto.hash(:sha256, output), case: :lower)
       }, logs}
    end
  end
end
