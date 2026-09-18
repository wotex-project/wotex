defmodule Wotex.Workspace.NativeCheck do
  @moduledoc """
  The native checks of one package: formatting, static analysis and tests
  of its first-party C, C++ and Rust code.

    * `format/2`: clang-format on the changed lines of the package's C and
      C++ sources (`Wotex.Workspace.NativeFormat`).
    * `rust/3`: `cargo fmt --check`, `cargo clippy --all-targets
      --all-features --locked -- -D warnings` or `cargo test --all-features
      --locked` for each crate, with the target directory in the native cache.
    * `tidy/2`: clang-tidy with the root `.clang-tidy` on every first-party
      translation unit, using the compile commands of the package's
      `native_check` suites (`Wotex.Workspace.NativeSuite`). A translation
      unit that no suite covers fails the check.
    * `test/2`: each suite's build task and test commands.

  Suites run their build task in a cached workspace
  (`Wotex.Workspace.NativeCache`) unless `workspace:` names one. Where a
  suite runs is `placement/2`: on this host; in the Linux container when it
  requires only Linux, this host is not Linux and Docker is available
  (`Wotex.Workspace.NativeContainer`); or nowhere, with a message naming
  what is missing. Nothing is skipped silently. A suite with `container`
  runs its commands and clang-tidy in that container.

  clang-tidy results are cached per translation unit
  (`Wotex.Workspace.NativeTidy`): a unit whose inputs match its last clean
  run is not analysed again.
  """

  alias Wotex.Workspace
  alias Wotex.Workspace.Affected
  alias Wotex.Workspace.ChangedLines
  alias Wotex.Workspace.CompileDb
  alias Wotex.Workspace.Exec
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeCache
  alias Wotex.Workspace.NativeContainer
  alias Wotex.Workspace.NativeFiles
  alias Wotex.Workspace.NativeFormat
  alias Wotex.Workspace.NativeSuite
  alias Wotex.Workspace.NativeTidy
  alias Wotex.Workspace.NativeTools
  alias Wotex.Workspace.Runner

  @type context :: %{
          name: String.t(),
          root: Path.t(),
          dir: Path.t(),
          relative: Path.t(),
          suites: [NativeSuite.t()],
          files: [Path.t()],
          sources: [Path.t()],
          crates: [Path.t()],
          cache: Path.t()
        }

  @type option ::
          {:base, String.t() | nil}
          | {:fix, boolean()}
          | {:workspace, Path.t() | nil}
          | {:tool, NativeTools.found()}
          | {:covered, MapSet.t(Path.t())}

  @typedoc "What a suite analysed elsewhere: real paths of its units and the outcome."
  @type analysed :: {:analysed, MapSet.t(Path.t()), :ok | :error}

  @typedoc "Where a suite runs on this host."
  @type placement :: :host | :linux_container | {:unmet, [String.t()]}

  @doc "The native context of package `name`."
  @spec context(String.t(), Manifest.t(), Path.t()) :: {:ok, context()} | {:error, String.t()}
  def context(name, %Manifest{} = manifest, root \\ Workspace.root()) do
    with {:ok, package} <- fetch(name, manifest),
         relative = Manifest.path(name, manifest),
         {:ok, found} <- NativeFiles.package(relative, root) do
      {:ok,
       %{
         name: name,
         root: root,
         dir: Path.join(root, relative),
         relative: relative,
         suites: package.native_check,
         files: found.files,
         sources: found.sources,
         crates: found.crates,
         cache: NativeCache.root()
       }}
    end
  end

  @doc "Whether the package has C or C++ sources, Rust crates."
  @spec kinds(context()) :: %{c_family: boolean(), rust: boolean()}
  def kinds(context), do: %{c_family: context.sources != [], rust: context.crates != []}

  # Formatting

  @doc """
  Checks (or with `fix: true` formats) the changed lines of the package's C
  and C++ sources. Needs `tool:` (clang-format).
  """
  @spec format(context(), [option()]) :: :ok | :error
  def format(context, opts) do
    tool = Keyword.fetch!(opts, :tool)
    fix? = Keyword.get(opts, :fix, false)

    case ChangedLines.ranges(context.sources, Keyword.get(opts, :base), context.root) do
      {:ok, changes} when map_size(changes) == 0 ->
        info("#{context.name}: no changed C or C++ lines")
        :ok

      {:ok, changes} ->
        formatter = fn args -> System.cmd(tool.path, args, cd: context.root, env: tool_env()) end

        changes
        |> Enum.sort()
        |> Enum.map(fn {file, ranges} ->
          NativeFormat.file(file, ranges, context.root, formatter, fix?)
        end)
        |> report_format(context, map_size(changes), tool)

      {:error, message} ->
        error(message)
        :error
    end
  end

  defp report_format(results, context, count, tool) do
    Enum.each(results, fn
      :ok -> :ok
      {:fixed, file} -> info("formatted #{file}")
      {:changed, diff} -> error(diff)
      {:error, message} -> error(message)
    end)

    failed = Enum.count(results, &match?({tag, _} when tag in [:changed, :error], &1))

    if failed == 0 do
      info(
        "#{context.name}: #{count} changed C/C++ file(s) formatted (clang-format #{tool.version})"
      )

      :ok
    else
      error(
        "#{context.name}: #{failed} file(s) not formatted on changed lines; run `mix native.lint --fix --package #{context.name}`"
      )

      :error
    end
  end

  # Rust

  @doc """
  Runs `step` (`:fmt`, `:clippy` or `:test`) for every crate of the
  package; `fix: true` makes `:fmt` format instead of check.
  """
  @spec rust(context(), :fmt | :clippy | :test, [option()]) :: :ok | :error
  def rust(context, step, opts \\ []) do
    if System.find_executable("cargo") do
      statuses =
        Enum.map(context.crates, &Exec.run(cargo_args(context, step, &1, opts), cd: context.root))

      if Enum.all?(statuses, &(&1 == 0)), do: :ok, else: :error
    else
      error(
        "cargo not found; install the Rust toolchain pinned in rust-toolchain.toml (`mise install`)"
      )

      :error
    end
  end

  @doc "The cargo arguments for `step` on crate manifest `manifest` (repository-relative)."
  @spec cargo_args(context(), :fmt | :clippy | :test, Path.t(), [option()]) :: [String.t()]
  def cargo_args(context, step, manifest, opts \\ []) do
    target = Path.join([context.cache, context.name, "cargo"])

    case step do
      :fmt ->
        ["cargo", "fmt", "--manifest-path", manifest] ++ if(opts[:fix], do: [], else: ["--check"])

      :clippy ->
        [
          "cargo",
          "clippy",
          "--manifest-path",
          manifest,
          "--locked",
          "--all-targets",
          "--all-features",
          "--target-dir",
          target,
          "--",
          "-D",
          "warnings"
        ]

      :test ->
        [
          "cargo",
          "test",
          "--manifest-path",
          manifest,
          "--locked",
          "--all-features",
          "--target-dir",
          target
        ]
    end
  end

  # Suites

  @doc """
  Runs clang-tidy on every first-party translation unit of the package.
  Needs `tool:` (clang-tidy); `workspace:` names the build workspace of the
  package's single suite with a build task.

  Suites run in order and a unit takes the compile command of the first
  suite that has one. The compile commands of suites on this host feed one
  clang-tidy run here; a suite in a container analyses its units there.
  """
  @spec tidy(context(), [option()]) :: :ok | :error
  def tidy(context, opts) do
    tool = Keyword.fetch!(opts, :tool)
    units = Enum.filter(context.sources, &NativeFiles.translation_unit?/1)
    state = tidy_suites(context, opts)

    merged =
      state.entries
      |> CompileDb.merge()
      |> Enum.reject(&MapSet.member?(state.contained, &1["file"]))

    local = CompileDb.files(merged)
    covered = MapSet.union(local, state.contained)
    uncovered = Enum.reject(units, &MapSet.member?(covered, real(context, &1)))
    database = CompileDb.write!(Path.join([context.cache, context.name, "tidy"]), merged)

    missing_ok? = report_uncovered(context, uncovered, state.failures)
    analysed = Enum.filter(units, &MapSet.member?(local, real(context, &1)))
    tidy_ok? = run_tidy(context, tool, merged, Path.dirname(database), analysed)

    if missing_ok? and tidy_ok? and state.ok? and state.failures == 0, do: :ok, else: :error
  end

  defp tidy_suites(context, opts) do
    initial = %{entries: [], contained: MapSet.new(), ok?: true, failures: 0}

    context.suites
    |> Enum.filter(&(&1.compile_commands != [] or &1.compile != []))
    |> Enum.reduce(initial, fn suite, state ->
      covered = MapSet.union(CompileDb.files(CompileDb.merge(state.entries)), state.contained)

      case run_suite(context, suite, :tidy, Keyword.put(opts, :covered, covered)) do
        {:ok, entries} ->
          %{state | entries: Enum.concat(state.entries, [entries])}

        {:analysed, paths, result} ->
          %{
            state
            | contained: MapSet.union(state.contained, paths),
              ok?: state.ok? and result == :ok
          }

        :error ->
          %{state | failures: state.failures + 1}
      end
    end)
  end

  @doc """
  Runs clang-tidy for one suite: on the translation units its compile
  commands cover, less the real paths in `covered:`. Needs `tool:` when the
  suite runs on this host. Returns the real paths of the analysed units
  with the outcome, or `:error` when the suite did not run.
  """
  @spec tidy_suite(context(), NativeSuite.t(), [option()]) :: analysed() | :error
  def tidy_suite(context, suite, opts) do
    covered = Keyword.get(opts, :covered, MapSet.new())

    case run_suite(context, suite, :tidy, opts) do
      {:ok, entries} ->
        merged = Enum.reject(CompileDb.merge([entries]), &MapSet.member?(covered, &1["file"]))
        files = CompileDb.files(merged)

        units =
          Enum.filter(
            context.sources,
            &(NativeFiles.translation_unit?(&1) and MapSet.member?(files, real(context, &1)))
          )

        dir = Path.join(NativeCache.suite_dir(context.cache, context.name, suite), "tidy")
        database = CompileDb.write!(dir, merged)
        ok? = run_tidy(context, Keyword.fetch!(opts, :tool), merged, Path.dirname(database), units)
        {:analysed, MapSet.new(units, &real(context, &1)), if(ok?, do: :ok, else: :error)}

      other ->
        other
    end
  end

  @doc "Runs every suite's build task and test commands."
  @spec test(context(), [option()]) :: :ok | :error
  def test(context, opts \\ []) do
    results = Enum.map(context.suites, &run_suite(context, &1, :test, opts))
    if Enum.all?(results, &(&1 == :ok)), do: :ok, else: :error
  end

  @doc """
  The host requirements of `suite` this host does not meet, each with the
  reason. `probe` replaces the host checks in tests.
  """
  @spec unmet(NativeSuite.t(), (String.t() -> :ok | {:error, String.t()})) :: [String.t()]
  def unmet(%NativeSuite{requires: requires}, probe \\ &probe/1) do
    for requirement <- requires, {:error, reason} <- [probe.(requirement)], do: reason
  end

  @doc """
  Where `suite` runs on this host: `:host` when its requirements are met;
  `:linux_container` when it requires only Linux, this host is not Linux
  and Docker is available; else `{:unmet, reasons}`, which name both ways
  to run a Linux suite. `probe` replaces the host checks in tests.
  """
  @spec placement(NativeSuite.t(), (String.t() -> :ok | {:error, String.t()})) :: placement()
  def placement(%NativeSuite{} = suite, probe \\ &probe/1) do
    case unmet(suite, probe) do
      [] ->
        :host

      [linux] when suite.requires == ["linux"] ->
        case probe.("docker") do
          :ok ->
            :linux_container

          {:error, _} ->
            {:unmet,
             [
               "#{linux} and no Docker daemon is running; run it on Linux, or start Docker " <>
                 "to run it in the Linux container (#{NativeContainer.linux_dockerfile()})"
             ]}
        end

      reasons ->
        {:unmet, reasons}
    end
  end

  defp probe("linux") do
    case :os.type() do
      {:unix, :linux} -> :ok
      {_, os} -> {:error, "requires Linux (this host is #{os})"}
    end
  end

  defp probe("docker") do
    with docker when is_binary(docker) <- System.find_executable("docker"),
         {_, 0} <-
           System.cmd(docker, ["info", "--format", "{{.ServerVersion}}"],
             env: tool_env(),
             stderr_to_stdout: true
           ) do
      :ok
    else
      _ -> {:error, "requires a running Docker daemon"}
    end
  end

  defp run_suite(context, suite, mode, opts) do
    case placement(suite) do
      :host ->
        run_here(context, suite, mode, opts)

      :linux_container ->
        NativeContainer.linux_suite(context, suite, mode, opts)

      {:unmet, reasons} ->
        error(
          "#{context.name} suite #{suite.name} #{Enum.join(reasons, "; ")}: not run on this host"
        )

        :error
    end
  end

  defp run_here(context, suite, mode, opts) do
    with {:ok, values} <- ensure_build(context, suite, opts),
         {:error, message} <- run_prepared(context, suite, mode, values, opts) do
      suite_error(context, suite, message)
    else
      {:error, message} -> suite_error(context, suite, message)
      result -> result
    end
  end

  # A suite with no test commands needs no prepared scratch directory in
  # `:test` mode.
  defp run_prepared(context, suite, :test, _, _) when suite.test == [],
    do: run_tests(context, suite, nil, nil)

  defp run_prepared(context, %NativeSuite{container: nil} = suite, mode, values, _) do
    with :ok <- prepare(context, suite, values) do
      case mode do
        :tidy -> compile_entries(context, suite, values)
        :test -> run_tests(context, suite, values, nil)
      end
    end
  end

  defp run_prepared(context, suite, mode, values, opts) do
    covered = Keyword.get(opts, :covered, MapSet.new())
    run_contained(context, suite, mode, values, covered)
  end

  defp suite_error(context, suite, message) do
    error("#{context.name} suite #{suite.name}: #{message}")
    :error
  end

  defp run_contained(context, suite, mode, values, covered) do
    %{dockerfile: dockerfile, platform: platform} = suite.container
    volumes = NativeContainer.volumes(suite.container, values)
    NativeCache.reset!(values["scratch"])

    with {:ok, image} <- NativeContainer.image(context.root, dockerfile, platform),
         {:ok, session} <-
           NativeContainer.start(image,
             volumes: volumes,
             scratch: values["scratch"],
             platform: platform
           ) do
      try do
        with :ok <- run_commands(context, suite.prepare, values, "prepare", session) do
          case mode do
            :tidy -> contained_tidy(context, suite, values, session, covered)
            :test -> run_tests(context, suite, values, session)
          end
        end
      after
        NativeContainer.stop(session)
      end
    end
  end

  defp ensure_build(context, suite, opts) do
    scratch = Path.join(NativeCache.suite_dir(context.cache, context.name, suite), "scratch")
    values = %{"package" => context.dir, "root" => context.root, "scratch" => scratch}

    if suite.build do
      {workspace, cached?} = workspace(context, suite, opts)
      build(context, suite, workspace, cached?, Map.put(values, "workspace", workspace))
    else
      {:ok, values}
    end
  end

  defp workspace(context, suite, opts) do
    case Keyword.get(opts, :workspace) do
      nil ->
        digests = NativeCache.digests(context.files, context.dir, context.root)
        dir = NativeCache.suite_dir(context.cache, context.name, suite)
        {Path.join(dir, NativeCache.key(suite, digests)), true}

      workspace ->
        {workspace, false}
    end
  end

  defp build(context, suite, workspace, cached?, values) do
    existed? = match?({:ok, [_ | _]}, File.ls(workspace))
    File.mkdir_p!(Path.dirname(workspace))

    case Runner.run(context.dir, [suite.build, "--workspace", workspace]) do
      0 ->
        if cached?, do: NativeCache.prune(Path.dirname(workspace), Path.basename(workspace))
        {:ok, values}

      _ when cached? and existed? ->
        info("#{context.name}: the cached workspace #{workspace} did not verify; building it again")
        File.rm_rf!(workspace)
        File.rm_rf!(workspace <> ".lock")
        build(context, suite, workspace, cached?, values)

      status ->
        {:error, "#{suite.build} --workspace #{workspace} failed (#{status})"}
    end
  end

  defp prepare(context, suite, values) do
    NativeCache.reset!(values["scratch"])
    run_commands(context, suite.prepare, values, "prepare", nil)
  end

  defp run_tests(context, suite, _, _) when suite.test == [] do
    if suite.build,
      do:
        info(
          "#{context.name} suite #{suite.name}: #{suite.build} passed; no separate test commands"
        ),
      else: info("#{context.name} suite #{suite.name}: no native test commands")

    :ok
  end

  defp run_tests(context, suite, values, session) do
    case run_commands(context, suite.test, values, "test", session) do
      :ok ->
        info("#{context.name} suite #{suite.name}: native tests passed")
        :ok

      {:error, message} ->
        error("#{context.name} suite #{suite.name}: #{message}")
        :error
    end
  end

  defp run_commands(context, commands, values, phase, session) do
    Enum.reduce_while(commands, :ok, fn command, :ok ->
      command = NativeSuite.expand_command(command, values)

      {argv, opts} =
        case session do
          nil ->
            {command.run, [cd: command.cd || context.dir, env: command.env]}

          session ->
            {NativeContainer.exec_argv(session, command.run, env: command.env, cd: command.cd),
             [cd: context.dir]}
        end

      case Exec.run(argv, [stdout: command.stdout] ++ opts) do
        0 ->
          {:cont, :ok}

        status ->
          {:halt, {:error, "#{phase} command `#{Enum.join(command.run, " ")}` failed (#{status})"}}
      end
    end)
  end

  defp compile_entries(context, suite, values) do
    with {:ok, databases} <- read_databases(suite, values),
         {:ok, synthesized} <- synthesize(context, suite, values) do
      {:ok, databases ++ synthesized}
    end
  end

  defp read_databases(suite, values) do
    Enum.reduce_while(suite.compile_commands, {:ok, []}, fn path, {:ok, acc} ->
      case CompileDb.read(NativeSuite.expand(path, values)) do
        {:ok, entries} -> {:cont, {:ok, acc ++ entries}}
        error -> {:halt, error}
      end
    end)
  end

  defp synthesize(context, suite, values) do
    Enum.reduce_while(suite.compile, {:ok, []}, fn rule, {:ok, acc} ->
      files = matching(context, rule.files)

      with [_ | _] <- files,
           {:ok, flags} <- expand_flags(rule.flags, values) do
        entries =
          for file <- files, do: CompileDb.entry(Path.join(context.dir, file), flags, context.dir)

        {:cont, {:ok, acc ++ entries}}
      else
        [] ->
          {:halt,
           {:error, "compile files #{inspect(rule.files)} match no first-party translation unit"}}

        error ->
          {:halt, error}
      end
    end)
  end

  @doc """
  The package-relative first-party translation units of `context` that
  match any of `globs` (package-relative).
  """
  @spec matching(context(), [String.t()]) :: [Path.t()]
  def matching(context, globs) do
    for source <- context.sources,
        NativeFiles.translation_unit?(source),
        relative = Path.relative_to(source, context.relative),
        Enum.any?(globs, &Affected.glob_match?(&1, relative)),
        do: relative
  end

  defp expand_flags(flags, values) do
    flags
    |> Enum.reduce_while({:ok, []}, fn
      "pkg-config:" <> name, {:ok, acc} ->
        case System.cmd("pkg-config", ["--cflags", name], env: tool_env(), stderr_to_stdout: true) do
          {output, 0} ->
            {:cont, {:ok, Enum.reverse(String.split(output), acc)}}

          {output, _} ->
            {:halt, {:error, "pkg-config --cflags #{name} failed: #{String.trim(output)}"}}
        end

      flag, {:ok, acc} ->
        {:cont, {:ok, [NativeSuite.expand(flag, values) | acc]}}
    end)
    |> then(fn
      {:ok, expanded} -> {:ok, Enum.reverse(expanded)}
      error -> error
    end)
  rescue
    error in ErlangError -> {:error, "pkg-config: #{Exception.message(error)}"}
  end

  # clang-tidy in a suite container

  defp contained_tidy(context, suite, values, session, covered) do
    with {:ok, entries} <- read_databases(suite, values),
         {:ok, tool} <- container_tool(session) do
      units = contained_units(context, entries, session.volumes, covered)
      dir = Path.join(values["scratch"], "tidy")
      CompileDb.write!(dir, Enum.map(units, & &1.entry))
      config = Path.join(dir, ".clang-tidy")
      File.cp!(Path.join(context.root, ".clang-tidy"), config)

      args = [
        "-p",
        dir,
        "--quiet",
        "--config-file=" <> config,
        "--header-filter=" <> NativeContainer.header_filter(session.volumes, context.root),
        "--exclude-header-filter=/vendor/"
      ]

      tidy_units =
        for unit <- units do
          tidy = ["clang-tidy", unit.file | args]

          Map.merge(unit, %{
            source: unit.real,
            tidy: tidy,
            argv: NativeContainer.exec_argv(session, tidy)
          })
        end

      result =
        NativeTidy.run(tidy_units,
          results: results_dir(context),
          material:
            {tool.version, session.image, session.volumes, config_digest(context),
             headers_digest(context)},
          cd: context.root,
          env: tool_env(),
          concurrency: min(System.schedulers_online(), 8),
          translate: fn unit, text ->
            NativeContainer.to_repository(text, session.volumes,
              root: context.root,
              directory: unit.entry["directory"]
            )
          end
        )

      ok? = report_tidy(context, "clang-tidy #{tool.version} in #{session.image}", result)
      {:analysed, MapSet.new(units, & &1.real), if(ok?, do: :ok, else: :error)}
    end
  end

  # The first-party translation units among container compile commands,
  # first entry per unit, less the units earlier suites cover.
  defp contained_units(context, entries, volumes, covered) do
    first_party =
      for source <- context.sources,
          NativeFiles.translation_unit?(source),
          into: %{},
          do: {real(context, source), source}

    entries
    |> Enum.flat_map(fn entry ->
      file = Path.expand(entry["file"], entry["directory"])
      host = NativeContainer.to_host(volumes, file)
      real = host && NativeCache.real_path(host)

      if (real && Map.has_key?(first_party, real)) and not MapSet.member?(covered, real),
        do: [
          %{path: first_party[real], real: real, file: file, entry: Map.put(entry, "file", file)}
        ],
        else: []
    end)
    |> Enum.uniq_by(& &1.real)
  end

  defp container_tool(session) do
    [executable | args] = NativeContainer.exec_argv(session, ["clang-tidy", "--version"])

    with {output, 0} <- System.cmd(executable, args, env: tool_env(), stderr_to_stdout: true),
         {:ok, version, major} <- NativeTools.parse_version(output),
         true <- major >= NativeTools.minimum_major() do
      {:ok, %{version: version, major: major}}
    else
      _ ->
        {:error, "clang-tidy #{NativeTools.minimum_major()} or later not found in #{session.image}"}
    end
  end

  # Reporting and clang-tidy on this host

  defp report_uncovered(_, [], _), do: true

  defp report_uncovered(context, uncovered, failures) do
    reason =
      if failures > 0,
        do: "a suite above did not run",
        else: "add them to a native_check suite of #{context.name} in tooling/packages.yaml"

    error(
      "#{context.name}: no compile command for #{length(uncovered)} translation unit(s) (#{reason}):"
    )

    Enum.each(uncovered, &error("  " <> &1))
    false
  end

  defp run_tidy(_, _, _, _, []), do: true

  defp run_tidy(context, tool, merged, database_dir, units) do
    args =
      [
        "-p",
        database_dir,
        "--quiet",
        "--config-file=" <> Path.join(context.root, ".clang-tidy"),
        "--header-filter=^" <>
          Regex.escape(NativeCache.real_path(Path.join(context.root, "packages"))) <> "/",
        "--exclude-header-filter=/vendor/"
      ] ++
        sysroot_args()

    by_file = Map.new(merged, &{&1["file"], &1})

    tidy_units =
      for unit <- units do
        %{
          path: unit,
          source: Path.join(context.root, unit),
          entry: by_file[real(context, unit)],
          tidy: [unit | args],
          argv: [tool.path, unit | args]
        }
      end

    result =
      NativeTidy.run(tidy_units,
        results: results_dir(context),
        material: {tool.version, config_digest(context), headers_digest(context)},
        cd: context.root,
        env: tool_env()
      )

    report_tidy(context, "clang-tidy #{tool.version}", result)
  end

  defp report_tidy(context, label, %{units: units, reused: reused, failed: []}) do
    reuse = if reused > 0, do: " (#{reused} unchanged since a clean run)", else: ""
    info("#{context.name}: #{label}: #{units} translation unit(s), no findings#{reuse}")
    true
  end

  defp report_tidy(context, label, %{units: units, failed: failed}) do
    error(
      "#{context.name}: #{label}: findings in #{length(failed)} of #{units} translation unit(s)"
    )

    false
  end

  defp results_dir(context), do: Path.join([context.cache, context.name, "tidy", "results"])

  defp config_digest(context) do
    case File.read(Path.join(context.root, ".clang-tidy")) do
      {:ok, text} -> :crypto.hash(:sha256, text)
      {:error, reason} -> reason
    end
  end

  # Every first-party header of the package: a unit's result depends on the
  # headers it includes.
  defp headers_digest(context) do
    for source <- context.sources,
        not NativeFiles.translation_unit?(source),
        path = Path.join(context.root, source),
        File.regular?(path),
        do: {source, :crypto.hash(:sha256, File.read!(path))}
  end

  defp sysroot_args do
    with {:unix, :darwin} <- :os.type(),
         xcrun when is_binary(xcrun) <- System.find_executable("xcrun"),
         {path, 0} <-
           System.cmd(xcrun, ["--show-sdk-path"], env: tool_env(), stderr_to_stdout: true) do
      ["--extra-arg-before=-isysroot" <> String.trim(path)]
    else
      _ -> []
    end
  end

  # clang tools, pkg-config and Docker need no Mix or path-dependency settings of the caller.
  defp tool_env, do: [{"MIX_ENV", nil}, {"WOTEX_PATH_DEPS", nil}]

  defp real(context, relative), do: NativeCache.real_path(Path.join(context.root, relative))

  defp fetch(name, manifest) do
    case Manifest.fetch(name, manifest) do
      {:ok, package} -> {:ok, package}
      :error -> {:error, "unknown package #{inspect(name)}"}
    end
  end

  defp info(message), do: Mix.shell().info(message)
  defp error(message), do: Mix.shell().error(message)
end
