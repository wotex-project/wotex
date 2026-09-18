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
  (`Wotex.Workspace.NativeCache`) unless `workspace:` names one. A suite
  whose host requirements (`linux`, `docker`) are not met fails with a
  message; nothing is skipped silently.
  """

  alias Wotex.Workspace
  alias Wotex.Workspace.Affected
  alias Wotex.Workspace.ChangedLines
  alias Wotex.Workspace.CompileDb
  alias Wotex.Workspace.Exec
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeCache
  alias Wotex.Workspace.NativeFiles
  alias Wotex.Workspace.NativeFormat
  alias Wotex.Workspace.NativeSuite
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
  """
  @spec tidy(context(), [option()]) :: :ok | :error
  def tidy(context, opts) do
    tool = Keyword.fetch!(opts, :tool)
    units = Enum.filter(context.sources, &NativeFiles.translation_unit?/1)

    {entries, failures} =
      context.suites
      |> Enum.filter(&(&1.compile_commands != [] or &1.compile != []))
      |> Enum.reduce({[], 0}, fn suite, {entries, failures} ->
        case run_suite(context, suite, :tidy, opts) do
          {:ok, suite_entries} -> {[suite_entries | entries], failures}
          :error -> {entries, failures + 1}
        end
      end)

    merged = CompileDb.merge(Enum.reverse(entries))
    covered = CompileDb.files(merged)
    uncovered = Enum.reject(units, &MapSet.member?(covered, real(context, &1)))
    database = CompileDb.write!(Path.join([context.cache, context.name, "tidy"]), merged)

    missing_ok? = report_uncovered(context, uncovered, failures)
    analysed = Enum.filter(units, &MapSet.member?(covered, real(context, &1)))
    tidy_ok? = run_tidy(context, tool, Path.dirname(database), analysed)

    if missing_ok? and tidy_ok? and failures == 0, do: :ok, else: :error
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

  defp probe("linux") do
    case :os.type() do
      {:unix, :linux} -> :ok
      {_family, os} -> {:error, "requires Linux (this host is #{os})"}
    end
  end

  defp probe("docker") do
    with docker when is_binary(docker) <- System.find_executable("docker"),
         {_output, 0} <-
           System.cmd(docker, ["info", "--format", "{{.ServerVersion}}"],
             env: tool_env(),
             stderr_to_stdout: true
           ) do
      :ok
    else
      _other -> {:error, "requires a running Docker daemon"}
    end
  end

  defp run_suite(context, suite, mode, opts) do
    label = "#{context.name} suite #{suite.name}"

    with [] <- unmet(suite),
         {:ok, values} <- ensure_build(context, suite, opts),
         :ok <- prepare(context, suite, values) do
      case mode do
        :tidy -> compile_entries(context, suite, values)
        :test -> run_tests(context, suite, values)
      end
    else
      reasons when is_list(reasons) ->
        error("#{label} #{Enum.join(reasons, "; ")}: not run on this host")
        :error

      {:error, message} ->
        error("#{label}: #{message}")
        :error
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

      _status when cached? and existed? ->
        info("#{context.name}: the cached workspace #{workspace} did not verify; building it again")
        File.rm_rf!(workspace)
        File.rm_rf!(workspace <> ".lock")
        build(context, suite, workspace, cached?, values)

      status ->
        {:error, "#{suite.build} --workspace #{workspace} failed (#{status})"}
    end
  end

  defp prepare(_context, %NativeSuite{prepare: []}, values) do
    NativeCache.reset!(values["scratch"])
    :ok
  end

  defp prepare(context, suite, values) do
    NativeCache.reset!(values["scratch"])
    run_commands(context, suite.prepare, values, "prepare")
  end

  defp run_tests(context, suite, _values) when suite.test == [] do
    if suite.build,
      do:
        info(
          "#{context.name} suite #{suite.name}: #{suite.build} passed; no separate test commands"
        ),
      else: info("#{context.name} suite #{suite.name}: no native test commands")

    :ok
  end

  defp run_tests(context, suite, values) do
    case run_commands(context, suite.test, values, "test") do
      :ok ->
        info("#{context.name} suite #{suite.name}: native tests passed")
        :ok

      {:error, message} ->
        error("#{context.name} suite #{suite.name}: #{message}")
        :error
    end
  end

  defp run_commands(context, commands, values, phase) do
    Enum.reduce_while(commands, :ok, fn command, :ok ->
      command = NativeSuite.expand_command(command, values)
      cd = command.cd || context.dir

      case Exec.run(command.run, cd: cd, env: command.env, stdout: command.stdout) do
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
    else
      {:error, message} ->
        error("#{context.name} suite #{suite.name}: #{message}")
        :error
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

  defp report_uncovered(_context, [], _failures), do: true

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

  defp run_tidy(_context, _tool, _database_dir, []), do: true

  defp run_tidy(context, tool, database_dir, units) do
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

    results =
      units
      |> Task.async_stream(
        fn unit ->
          {unit,
           System.cmd(tool.path, [unit | args],
             cd: context.root,
             env: tool_env(),
             stderr_to_stdout: true
           )}
        end,
        max_concurrency: System.schedulers_online(),
        timeout: :infinity,
        ordered: true
      )
      |> Enum.map(fn {:ok, result} -> result end)

    failed =
      for {unit, {output, status}} <- results,
          status != 0 or String.contains?(output, "warning:") do
        error(String.trim(output))
        unit
      end

    if failed == [] do
      info(
        "#{context.name}: clang-tidy #{tool.version}: #{length(units)} translation unit(s), no findings"
      )

      true
    else
      error(
        "#{context.name}: clang-tidy findings in #{length(failed)} of #{length(units)} translation unit(s)"
      )

      false
    end
  end

  defp sysroot_args do
    with {:unix, :darwin} <- :os.type(),
         xcrun when is_binary(xcrun) <- System.find_executable("xcrun"),
         {path, 0} <-
           System.cmd(xcrun, ["--show-sdk-path"], env: tool_env(), stderr_to_stdout: true) do
      ["--extra-arg-before=-isysroot" <> String.trim(path)]
    else
      _other -> []
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
