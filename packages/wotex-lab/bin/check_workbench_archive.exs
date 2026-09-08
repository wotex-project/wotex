# Workbench archive gate: a source artifact for the explicit host resolves the
# full profile from admitted package archives with Git unavailable, compiles in
# production and emits an executable release. Runs through Mix:
# `mix run --no-start bin/check_workbench_archive.exs`.

Code.require_file("support/work_directory.exs", __DIR__)
Code.require_file("support/archive_repository.exs", __DIR__)

defmodule Wotex.Lab.Check.WorkbenchArchive do
  @moduledoc false

  alias Wotex.Lab.Check.ArchiveRepository
  alias Wotex.Lab.Evidence.{Digest, Record}

  @packages [
    {:wotex, "wotex"},
    {:wotex_nx, "wotex-nx"},
    {:wotex_runtime, "wotex-runtime"},
    {:wotex_directory, "wotex-directory"},
    {:wotex_continuum, "wotex-continuum"},
    {:wotex_binding_http, "wotex-binding-http"},
    {:wotex_binding_mqtt, "wotex-binding-mqtt"},
    {:wotex_lab, "wotex-lab"}
  ]
  @source_entries ~w(config lib mix_tasks priv/static README.md mix.exs mix.lock)
  @native_packages ~w(baml_elixir ex_maude explorer)a
  @deadline_ms 900_000
  @cohort ~w(hosts/workbench/config/**/* hosts/workbench/lib/**/*
             hosts/workbench/mix_tasks/**/* hosts/workbench/priv/static/**/*
             hosts/workbench/README.md hosts/workbench/mix.exs hosts/workbench/mix.lock
             bin/check_workbench_archive.exs bin/support/archive_repository.exs
             bin/support/work_directory.exs docs/specs/WLB.08-distribution-and-compatibility.md)

  def run do
    root = Path.expand("..", __DIR__)
    host_source = Path.join(root, "hosts/workbench")
    work = Wotex.Lab.Check.WorkDirectory.create!(root, :workbench_archive)
    tarballs = Path.join(work, "tarballs")
    File.mkdir!(tarballs)
    started = System.monotonic_time()

    local = ArchiveRepository.build_archives!(root, @packages, tarballs)
    local_names = MapSet.new(local, & &1.name)

    public =
      ArchiveRepository.copy_public_archives!(
        [Path.join(host_source, "mix.lock")],
        tarballs,
        local_names
      )

    admitted = local ++ public
    native = admit_native_artifacts(work, host_source)
    source_archive = build_source_archive(work, host_source)
    consumer = extract_source_archive(work, source_archive)
    registry = ArchiveRepository.build_registry!(work, tarballs)
    {httpd, port} = ArchiveRepository.serve!(work, registry)

    try do
      bin = ArchiveRepository.restricted_path!(work)

      env =
        ArchiveRepository.environment(work, port, bin) ++
          [{"RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH", Path.join(work, "native_cache")}]

      run!(consumer, env, ["deps.get", "--only", "prod"], "Workbench dependency resolution")
      tree = run!(consumer, env, ["deps.tree", "--only", "prod"], "Workbench dependency graph")
      check_tree!(tree)
      resolved = inspect_graph(consumer, admitted, tree)
      run!(consumer, env, ["compile", "--warnings-as-errors"], "Workbench compilation")
      run!(consumer, env, ["release", "--overwrite"], "Workbench release")
      checks = release_smoke(consumer, env)
      elapsed = elapsed_ms(started)
      evidence = record(root, work, source_archive, admitted, native, resolved, checks, elapsed)
      cleanup(work, source_archive, tarballs, consumer, registry)

      IO.puts(
        "workbench archive: production release built from #{length(resolved)} admitted archives without Git"
      )

      IO.puts("evidence retained at #{evidence}")
    after
      :inets.stop(:httpd, httpd)
    end
  end

  defp build_source_archive(work, host_source) do
    archive = Path.join(work, "wotex-lab-workbench-source.tar")

    {output, status} =
      System.cmd("tar", ["-cf", archive | @source_entries],
        cd: host_source,
        stderr_to_stdout: true
      )

    status == 0 || abort("Workbench source archive failed (#{status}):\n#{output}")
    File.regular?(archive) || abort("Workbench source archive was not created")
    archive
  end

  defp extract_source_archive(work, archive) do
    consumer = Path.join(work, "consumer")
    File.mkdir!(consumer)

    case :erl_tar.extract(String.to_charlist(archive), cwd: String.to_charlist(consumer)) do
      :ok -> :ok
      {:error, reason} -> abort("Workbench source extraction failed: #{inspect(reason)}")
    end

    Enum.each(@source_entries, fn entry ->
      File.exists?(Path.join(consumer, entry)) || abort("source artifact omitted #{entry}")
    end)

    consumer
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.each(fn path ->
      match?({:ok, %File.Stat{type: :symlink}}, File.lstat(path)) &&
        abort("source artifact contains a symlink: #{Path.relative_to(path, consumer)}")
    end)

    consumer
  end

  defp admit_native_artifacts(work, host_source) do
    lock = ArchiveRepository.read_lock!(Path.join(host_source, "mix.lock"))
    source = native_cache()
    target = Path.join(work, "native_cache")
    File.mkdir!(target)

    Enum.map(@native_packages, fn package ->
      version =
        case Map.fetch!(lock, package) do
          {:hex, _package, version, _checksum, _managers, _deps, "hexpm", _outer_checksum} ->
            version

          other ->
            abort("unsupported native package lock entry for #{package}: #{inspect(other)}")
        end

      system_architecture = List.to_string(:erlang.system_info(:system_architecture))

      matches =
        Path.wildcard(
          Path.join(source, "*#{package}*-v#{version}-*-#{system_architecture}.*.tar.gz")
        )

      case matches do
        [path] ->
          copy = Path.join(target, Path.basename(path))
          File.cp!(path, copy)
          %{name: Atom.to_string(package), version: version, path: copy, origin: :native_cache}

        [] ->
          abort("precompiled artifact for #{package} #{version} is absent from the local cache")

        many ->
          abort("ambiguous precompiled artifacts for #{package} #{version}: #{inspect(many)}")
      end
    end)
  end

  defp native_cache do
    System.get_env("RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH") ||
      :user_cache
      |> :filename.basedir("rustler_precompiled/precompiled_nifs")
      |> to_string()
  end

  defp inspect_graph(consumer, admitted, tree) do
    lock = ArchiveRepository.read_lock!(Path.join(consumer, "mix.lock"))
    lock_by_name = Map.new(lock, fn {name, entry} -> {Atom.to_string(name), entry} end)
    archives = Map.new(admitted, &{{&1.name, &1.version}, &1})
    active = active_packages(tree)

    resolved =
      Enum.map(active, fn name ->
        entry = Map.fetch!(lock_by_name, name)

        (is_tuple(entry) and elem(entry, 0) == :hex) ||
          abort("#{name} did not resolve to a Hex archive")

        version = elem(entry, 2)
        key = {name, version}
        Map.has_key?(archives, key) || abort("#{name} #{version} is not an admitted archive")

        %{name: name, version: version, archive: Digest.file!(archives[key].path)}
      end)

    names = MapSet.new(resolved, & &1.name)

    Enum.each(@packages, fn {app, _directory} ->
      name = Atom.to_string(app)
      MapSet.member?(names, name) || abort("Workbench closure omitted #{name}")
    end)

    resolved
  end

  defp active_packages(tree) do
    tree
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> Enum.map(fn line ->
      case Regex.run(~r/([a-z][a-z0-9_]*)\s+(?:==|~>|>=|<=|>|<|\d)/, line) do
        [_line, name] -> name
        nil -> abort("Workbench dependency tree line is malformed: #{inspect(line)}")
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp check_tree!(tree) do
    String.contains?(tree, "path:") &&
      abort("Workbench dependency graph contains a path dependency")

    String.contains?(tree, "git:") && abort("Workbench dependency graph contains a Git dependency")
    :ok
  end

  defp release_smoke(consumer, env) do
    release = Path.join(consumer, "_build/prod/rel/wotex_lab_workbench/bin/wotex_lab_workbench")
    File.regular?(release) || abort("Workbench release launcher is absent")

    script = ~S'''
    checks = %{
      git_absent: System.find_executable("git") == nil,
      workbench: Code.ensure_loaded?(WotexLabWorkbench),
      endpoint: Code.ensure_loaded?(WotexLabWorkbenchWeb.Endpoint),
      lab: Code.ensure_loaded?(Wotex.Lab),
      runtime: Code.ensure_loaded?(Wotex.Runtime),
      http: Code.ensure_loaded?(Wotex.Binding.HTTP),
      mqtt: Code.ensure_loaded?(Wotex.Binding.MQTT),
      directory: Code.ensure_loaded?(Wotex.Directory),
      continuum: Code.ensure_loaded?(WotexContinuum),
      explorer: Code.ensure_loaded?(Explorer.DataFrame),
      beamlens: Code.ensure_loaded?(Beamlens)
    }

    IO.puts("WORKBENCH_ARCHIVE_CHECKS " <> Enum.map_join(Enum.sort(checks), ",", fn {k, v} -> "#{k}=#{v}" end))
    '''

    release_env =
      env ++
        [
          {"SECRET_KEY_BASE", String.duplicate("a", 64)},
          {"PHX_HOST", "localhost"},
          {"PORT", "4199"}
        ]

    {output, status} =
      System.cmd(release, ["eval", script], env: release_env, stderr_to_stdout: true)

    status == 0 || abort("Workbench release smoke failed (#{status}):\n#{output}")

    case Regex.run(~r/WORKBENCH_ARCHIVE_CHECKS (\S+)/, output) do
      [_line, encoded] ->
        encoded
        |> String.split(",")
        |> Map.new(fn pair ->
          [key, value] = String.split(pair, "=")
          {key, value == "true"}
        end)
        |> tap(fn checks ->
          Enum.all?(checks, fn {_key, passed?} -> passed? end) ||
            abort("Workbench release checks failed: #{inspect(checks)}")
        end)

      nil ->
        abort("Workbench release emitted no checks:\n#{output}")
    end
  end

  defp run!(consumer, env, args, label) do
    ArchiveRepository.run!(consumer, env, args, label, @deadline_ms)
  end

  defp record(root, work, source_archive, admitted, native, resolved, checks, elapsed) do
    {:ok, source_tree_digest} = Digest.tree(root, @cohort)
    {:ok, lock_digest} = Digest.file(Path.join(root, "hosts/workbench/mix.lock"))

    dependencies =
      resolved ++
        Enum.map(native, fn item ->
          %{name: "native:#{item.name}", version: item.version, archive: Digest.file!(item.path)}
        end)

    assertions =
      Enum.map(checks, fn {key, passed?} ->
        %{id: "WLB-C10:workbench-archive:#{key}", status: if(passed?, do: :pass, else: :fail)}
      end)

    {:ok, record} =
      Record.new(
        scenario_id: "workbench-archive:full-host",
        revision: ArchiveRepository.revision(root),
        attempt: 1,
        source_tree_digest: source_tree_digest,
        lock_digest: lock_digest,
        dependencies: dependencies,
        fixtures: %{},
        seed: 0,
        toolchain: Digest.toolchain(Nx.BinaryBackend),
        budgets: %{deadline_ms: @deadline_ms},
        inputs:
          ["source:#{Digest.file!(source_archive)}"] ++
            Enum.map(admitted, &"archive:#{&1.name}-#{&1.version}:#{&1.origin}"),
        assertions: assertions,
        outcomes: %{
          profile: :full_host,
          git_on_path: false,
          source_artifact: true,
          release_built: true,
          resolved_packages: length(resolved)
        },
        durations: %{gate_ms: elapsed},
        cleanup: %{status: :ok, details: %{retained: "evidence.json"}}
      )

    {:ok, bytes} = Record.encode(record)
    path = Path.join(work, "evidence.json")
    File.write!(path, bytes)
    path
  end

  defp cleanup(work, source_archive, tarballs, consumer, registry) do
    String.contains?(work, ".archive-check.workbench-") ||
      abort("refusing unsafe Workbench archive cleanup")

    Enum.each(
      [
        source_archive,
        tarballs,
        consumer,
        registry,
        Path.join(work, "bin"),
        Path.join(work, "hex_home"),
        Path.join(work, "native_cache")
      ],
      &File.rm_rf!/1
    )

    File.rm(Path.join(work, "registry_key.pem"))
  end

  defp elapsed_ms(started) do
    System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Wotex.Lab.Check.WorkbenchArchive.run()
