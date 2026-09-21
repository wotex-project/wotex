# Workbench archive gate: a source artifact for the explicit host resolves the
# full profile from admitted package archives with Git unavailable, compiles in
# production and emits an executable release. Runs through Mix:
# `mix run --no-start bin/check_workbench_archive.exs`.

Code.require_file("support/work_directory.exs", __DIR__)
Code.require_file("support/archive_repository.exs", __DIR__)
Code.require_file("support/release_review.exs", __DIR__)
Code.require_file("support/child_environment.exs", __DIR__)

defmodule Wotex.Lab.Check.WorkbenchArchive do
  @moduledoc false

  alias Wotex.Lab.Check.{ArchiveRepository, ChildEnvironment, ReleaseReview}
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
             hosts/workbench/bin/serve_documentation_browser_fixture.exs
             hosts/workbench/mix_tasks/**/* hosts/workbench/priv/static/**/*
             hosts/workbench/README.md hosts/workbench/mix.exs hosts/workbench/mix.lock
             bin/check_workbench_archive.exs bin/support/archive_repository.exs
             bin/support/child_environment.exs bin/support/release_review.exs
             bin/support/work_directory.exs priv/provenance/workbench-bom.cdx.json
             priv/provenance/wotex-lab-api.json
             priv/provenance/wotex-lab-compatibility.json)

  @spec run([String.t()]) :: :ok
  def run(argv) do
    {output, candidates} = options!(argv)
    root = Path.expand("..", __DIR__)
    host_source = Path.join(root, "hosts/workbench")
    work = Wotex.Lab.Check.WorkDirectory.create!(root, :workbench_archive)
    tarballs = Path.join(work, "tarballs")
    File.mkdir!(tarballs)
    started = System.monotonic_time()

    local =
      ArchiveRepository.build_archives!(root, @packages, tarballs) ++
        candidate_archives(candidates, tarballs)

    local_names = MapSet.new(local, & &1.name)

    public =
      ArchiveRepository.copy_public_archives!(
        [Path.join(host_source, "mix.lock")],
        tarballs,
        local_names
      )

    admitted = local ++ public
    native = admit_native_artifacts(work, host_source)
    documentation = build_documentation_fixture!(work, host_source, candidates)
    source_archive = build_source_archive(work, host_source, documentation)
    consumer = extract_source_archive(work, source_archive)
    prepare_candidate_lock(consumer)
    registry = ArchiveRepository.build_registry!(work, tarballs)
    {httpd, port} = ArchiveRepository.serve!(work, registry)

    try do
      bin = ArchiveRepository.restricted_path!(work)

      env = [
        {"RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH", Path.join(work, "native_cache")}
        | ArchiveRepository.environment(work, port, bin)
      ]

      run!(consumer, env, ["deps.get", "--only", "prod"], "Workbench dependency resolution")
      tree = run!(consumer, env, ["deps.tree", "--only", "prod"], "Workbench dependency graph")
      check_tree!(tree)
      resolved = inspect_graph(consumer, admitted, tree)
      check_sbom!(root, ReleaseReview.bom!(consumer, resolved, admitted))
      run!(consumer, env, ["compile", "--warnings-as-errors"], "Workbench compilation")
      run!(consumer, env, ["release", "--overwrite"], "Workbench release")
      checks = release_smoke(consumer, env)
      artifacts = export_artifacts(output, consumer, source_archive)
      elapsed = elapsed_ms(started)

      evidence =
        record(
          root,
          work,
          source_archive,
          admitted,
          native,
          resolved,
          checks,
          artifacts,
          elapsed
        )

      cleanup(work, source_archive, tarballs, consumer, registry)

      IO.puts(
        "workbench archive: production release built from #{length(resolved)} admitted archives without Git"
      )

      IO.puts("evidence retained at #{evidence}")
    after
      :inets.stop(:httpd, httpd)
    end
  end

  defp candidate_archives(candidates, tarballs) do
    [
      ArchiveRepository.build_archive!(
        :doc_shell,
        candidates.doc_shell,
        tarballs
      ),
      ArchiveRepository.build_archive!(
        :phoenix_assets,
        candidates.phoenix_assets,
        tarballs
      )
    ]
  end

  defp build_documentation_fixture!(work, host_source, candidates) do
    destination = Path.join(work, "documentation-fixture")
    pagefind = Path.join(candidates.phoenix_assets, "npm/doc-shell/node_modules/.bin/pagefind")
    File.regular?(pagefind) || abort("Pagefind is absent from the Phoenix Assets candidate")

    environment = [
      {"MIX_ENV", "test"},
      {"WOTEX_PATH_DEPS", "1"},
      {"PHOENIX_ASSETS_CANDIDATE", candidates.phoenix_assets},
      {"DOC_SHELL_CANDIDATE", candidates.doc_shell}
    ]

    {log, status} =
      System.cmd(
        "mix",
        [
          "run",
          "--no-start",
          "bin/serve_documentation_browser_fixture.exs",
          "--destination",
          destination,
          "--pagefind-executable",
          pagefind,
          "--build-only"
        ],
        cd: host_source,
        env: environment,
        stderr_to_stdout: true
      )

    status == 0 || abort("Workbench documentation fixture failed (#{status}):\n#{log}")

    File.regular?(Path.join(destination, ".wotex/site.etf")) ||
      abort("Workbench documentation fixture omitted its hosted site")

    destination
  end

  defp build_source_archive(work, host_source, documentation) do
    archive = Path.join(work, "wotex-lab-workbench-source.tar")
    stage = Path.join(work, "workbench-source")
    File.mkdir!(stage)

    Enum.each(@source_entries, fn entry ->
      source = Path.join(host_source, entry)
      target = Path.join(stage, entry)
      File.mkdir_p!(Path.dirname(target))

      case File.cp_r(source, target) do
        {:ok, _} -> :ok
        {:error, reason, path} -> abort("copying #{path} into the source stage failed: #{reason}")
      end
    end)

    documentation_source = Path.join(documentation, ".wotex")
    documentation_target = Path.join(stage, "priv/documentation")

    case File.cp_r(documentation_source, documentation_target) do
      {:ok, _} -> :ok
      {:error, reason, path} -> abort("copying #{path} into the release failed: #{reason}")
    end

    {output, status} =
      System.cmd("tar", ["-cf", archive, "-C", stage, "."],
        env: ChildEnvironment.scrubbed(),
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

    File.regular?(Path.join(consumer, "priv/documentation/site.etf")) ||
      abort("source artifact omitted built-in documentation")

    consumer
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.each(fn path ->
      match?({:ok, %File.Stat{type: :symlink}}, File.lstat(path)) &&
        abort("source artifact contains a symlink: #{Path.relative_to(path, consumer)}")
    end)

    consumer
  end

  defp prepare_candidate_lock(consumer) do
    path = Path.join(consumer, "mix.lock")

    lock =
      path
      |> ArchiveRepository.read_lock!()
      |> Map.drop([:doc_shell, :phoenix_assets])

    File.write!(
      path,
      inspect(lock,
        pretty: true,
        limit: :infinity,
        printable_limit: :infinity,
        width: 120
      ) <> "\n"
    )
  end

  defp admit_native_artifacts(work, host_source) do
    lock = ArchiveRepository.read_lock!(Path.join(host_source, "mix.lock"))
    source = native_cache()
    target = Path.join(work, "native_cache")
    File.mkdir!(target)

    Enum.map(@native_packages, fn package ->
      version =
        case Map.fetch!(lock, package) do
          {:hex, _, version, _, _, _, "hexpm", _} ->
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

    Enum.each(@packages, fn {app, _} ->
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
        [_, name] -> name
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
    documentation = WotexLabWorkbench.Documentation.site()

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
      beamlens: Code.ensure_loaded?(Beamlens),
      documentation:
        match?({:ok, %{schema_version: "doc-shell-site/v1"}}, documentation) and
          match?({:ok, _, _, _}, WotexLabWorkbench.Documentation.fetch_route("/docs/start/")),
      documentation_search:
        match?(
          {:ok, "text/javascript", _, "sha256:" <> _},
          WotexLabWorkbench.Documentation.search_asset(["pagefind", "pagefind.js"])
        )
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
      [_, encoded] ->
        encoded
        |> String.split(",")
        |> Map.new(fn pair ->
          [key, value] = String.split(pair, "=")
          {key, value == "true"}
        end)
        |> tap(fn checks ->
          Enum.all?(checks, fn {_, passed?} -> passed? end) ||
            abort("Workbench release checks failed: #{inspect(checks)}")
        end)

      nil ->
        abort("Workbench release emitted no checks:\n#{output}")
    end
  end

  defp check_sbom!(root, bom) do
    path = Path.join(root, "priv/provenance/workbench-bom.cdx.json")
    generated = ReleaseReview.encode!(bom)

    if "--update-sbom" in System.argv() do
      File.write!(path, generated)
    else
      File.read(path) == {:ok, generated} ||
        abort("Workbench CycloneDX SBOM is stale; run this gate with --update-sbom")
    end
  end

  defp options!(argv) do
    {options, rest, invalid} =
      OptionParser.parse(argv,
        strict: [
          output: :string,
          update_sbom: :boolean,
          phoenix_assets_source: :string,
          doc_shell_source: :string
        ]
      )

    (rest == [] and invalid == []) || abort("invalid Workbench archive arguments")

    candidates = %{
      phoenix_assets: candidate!(options, :phoenix_assets_source),
      doc_shell: candidate!(options, :doc_shell_source)
    }

    {output_path!(Keyword.get(options, :output)), candidates}
  end

  defp output_path!(nil), do: nil

  defp output_path!(path) do
    (Path.type(path) == :absolute and not File.exists?(path)) ||
      abort("--output must name a new absolute directory")

    File.mkdir_p!(Path.dirname(path))
    File.mkdir!(path)
    File.chmod!(path, 0o700)
    Path.expand(path)
  end

  defp candidate!(options, key) do
    case Keyword.get(options, key) do
      path when is_binary(path) ->
        path = Path.expand(path)
        File.dir?(path) || abort("--#{option_name(key)} is not a directory: #{path}")
        path

      _ ->
        abort("--#{option_name(key)} is required")
    end
  end

  defp option_name(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  defp export_artifacts(nil, _, _), do: []

  defp export_artifacts(output, consumer, source_archive) do
    source_target = Path.join(output, "wotex-lab-workbench-source.tar")
    File.cp!(source_archive, source_target)

    release_root = Path.join(consumer, "_build/prod/rel")
    release = Path.join(release_root, "wotex_lab_workbench")
    architecture = List.to_string(:erlang.system_info(:system_architecture))
    release_target = Path.join(output, "wotex-lab-workbench-#{architecture}.tar.gz")

    {log, status} =
      System.cmd("tar", ["-czf", release_target, "-C", release_root, Path.basename(release)],
        env: ChildEnvironment.scrubbed(),
        stderr_to_stdout: true
      )

    status == 0 || abort("Workbench release artifact failed (#{status}):\n#{log}")

    Enum.map([release_target, source_target], fn path ->
      "artifact:#{Path.basename(path)}:#{Digest.file!(path)}"
    end)
  end

  defp run!(consumer, env, args, label) do
    ArchiveRepository.run!(consumer, env, args, label, @deadline_ms)
  end

  defp record(root, work, source_archive, admitted, native, resolved, checks, artifacts, elapsed) do
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
            artifacts ++
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
        Path.join(work, "documentation-fixture"),
        Path.join(work, "workbench-source"),
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

Wotex.Lab.Check.WorkbenchArchive.run(System.argv())
