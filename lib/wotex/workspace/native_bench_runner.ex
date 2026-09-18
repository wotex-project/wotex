defmodule Wotex.Workspace.NativeBenchRunner do
  @moduledoc """
  Runs the `native_bench` benchmarks of one package
  (`Wotex.Workspace.NativeBench`) and writes one report per benchmark,
  `native-<id>.md`, to the package's `bench/output/` or to `output:`
  (`Wotex.Workspace.BenchReport`).

    * `nanobench`: every translation unit the benchmark's `compile` rules
      match is compiled with the `clang` or `clang++` of the LLVM the native
      checks use (`Wotex.Workspace.NativeTools.compilers/2`), with
      `Wotex.Workspace.NativeBench.default_flags/0` before the rule's flags,
      and linked with nanobench's implementation (compiled from the vendored
      header, whose digests are verified first) and the `link` flags. The
      executable runs in the package directory; the report keeps the
      Markdown tables it prints.
    * `criterion`: `cargo bench --benches --locked` for the benchmark crate,
      with the native cache's target directory and a fresh `CRITERION_HOME`;
      the report tabulates criterion's estimates.
    * `elixir`: the package's `native_task` builds `workspace:` once per
      run, then `mix run bench/native/<id>_bench.exs` runs in the `dev`
      environment with the benchmark's `env` and `WOTEX_BENCH_OUTPUT` (the
      report path), `WOTEX_BENCH_TITLE` and `WOTEX_BENCH_DESCRIPTION`. The
      script writes the report, for example with Benchee's Markdown
      formatter; the runner checks that it starts with `# <title>`. Without
      `workspace:` the benchmark is skipped.

  Each benchmark has a directory `<cache>/<package>/bench/<id>` in the
  native cache (`Wotex.Workspace.NativeCache`) whose `scratch/` (the
  `{scratch}` placeholder) is emptied before each run. Where a benchmark
  runs follows `Wotex.Workspace.NativeCheck.placement/2`: a `nanobench` or
  `elixir` benchmark that requires only Linux runs in the Linux container
  on another host with Docker, as `mix wotex.native.bench --bench ID
  --output DIR` there, and its report is copied back; the container has no
  Rust toolchain, so a `criterion` benchmark that requires Linux runs on
  Linux only. An unmet requirement fails the benchmark with a message.
  """

  alias Wotex.Workspace
  alias Wotex.Workspace.BenchReport
  alias Wotex.Workspace.Exec
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Native
  alias Wotex.Workspace.NativeBench
  alias Wotex.Workspace.NativeCache
  alias Wotex.Workspace.NativeCheck
  alias Wotex.Workspace.NativeContainer
  alias Wotex.Workspace.NativeFiles
  alias Wotex.Workspace.NativeSuite
  alias Wotex.Workspace.NativeTools
  alias Wotex.Workspace.Runner

  @nanobench_main """
  // The nanobench implementation linked into each benchmark driver (mix native.bench).
  #define ANKERL_NANOBENCH_IMPLEMENT
  #include <nanobench.h>
  """

  @type context :: %{
          name: String.t(),
          root: Path.t(),
          dir: Path.t(),
          relative: Path.t(),
          cache: Path.t(),
          native_task: String.t() | nil,
          benches: [NativeBench.t()]
        }

  @type option :: {:workspace, Path.t() | nil} | {:output, Path.t() | nil}

  @type result :: :ok | :error | {:skipped, String.t()}

  @typedoc "The commands of a nanobench benchmark: compile each unit, then link."
  @type nanobench_plan :: %{compile: [[String.t()]], link: [String.t()], executable: Path.t()}

  @typedoc "Replaces a host requirement check (tests)."
  @type probe :: (String.t() -> :ok | {:error, String.t()})

  @doc "The benchmark context of package `name`."
  @spec context(String.t(), Manifest.t(), Path.t()) :: context()
  def context(name, %Manifest{} = manifest, root \\ Workspace.root()) do
    package = Manifest.fetch!(name, manifest)
    relative = Manifest.path(name, manifest)

    %{
      name: name,
      root: root,
      dir: Path.join(root, relative),
      relative: relative,
      cache: NativeCache.root(),
      native_task: package.native_task,
      benches: package.native_bench
    }
  end

  @doc "The directory of benchmark `bench` in the native cache."
  @spec bench_dir(context(), NativeBench.t()) :: Path.t()
  def bench_dir(context, %NativeBench{id: id}),
    do: Path.join([context.cache, context.name, "bench", id])

  @doc "The directory the reports go to: `output:`, else the package's `bench/output`."
  @spec output_dir(context(), [option()]) :: Path.t()
  def output_dir(context, opts),
    do: Keyword.get(opts, :output) || Path.join(context.dir, "bench/output")

  @doc "The placeholder values of a run of `bench`; `{workspace}` only with `workspace:`."
  @spec values(context(), NativeBench.t(), [option()]) :: %{String.t() => String.t()}
  def values(context, bench, opts) do
    values = %{
      "package" => context.dir,
      "root" => context.root,
      "scratch" => Path.join(bench_dir(context, bench), "scratch")
    }

    case Keyword.get(opts, :workspace) do
      nil -> values
      workspace -> Map.put(values, "workspace", workspace)
    end
  end

  @doc """
  Runs `benches` in order and returns one row per benchmark (`:package`,
  `:bench`, `:kind`, `:result`, `:seconds`). The package's `native_task`
  runs once, before the first `elixir` benchmark that runs on this host.
  """
  @spec run_all(context(), [NativeBench.t()], [option()]) :: [map()]
  def run_all(context, benches, opts) do
    {rows, _} =
      Enum.map_reduce(benches, :unbuilt, fn bench, build ->
        started = System.monotonic_time(:millisecond)
        {result, build} = run(context, bench, opts, build)

        row = %{
          package: context.name,
          bench: bench.id,
          kind: Atom.to_string(bench.kind),
          result: label(result),
          seconds: (System.monotonic_time(:millisecond) - started) / 1000
        }

        {row, build}
      end)

    rows
  end

  defp label(:ok), do: "ok"
  defp label(:error), do: "error"
  defp label({:skipped, reason}), do: "skipped (#{reason})"

  defp run(context, bench, opts, build) do
    if bench.kind == :elixir and is_nil(Keyword.get(opts, :workspace)) do
      {{:skipped, "needs --workspace"}, build}
    else
      case placement(bench) do
        :host ->
          run_here(context, bench, opts, build)

        :linux_container ->
          {report(context, bench, run_contained(context, bench, opts)), build}

        {:unmet, reasons} ->
          {report(context, bench, {:error, "#{Enum.join(reasons, "; ")}: not run on this host"}),
           build}
      end
    end
  end

  defp run_here(context, %NativeBench{kind: :elixir} = bench, opts, build) do
    build = ensure_build(context, opts, build)

    result =
      case build do
        :built -> run_script(context, bench, opts)
        {:failed, message} -> {:error, message}
      end

    {report(context, bench, result), build}
  end

  defp run_here(context, bench, opts, build) do
    result =
      case bench.kind do
        :nanobench -> run_nanobench(context, bench, opts)
        :criterion -> run_criterion(context, bench, opts)
      end

    {report(context, bench, result), build}
  end

  defp report(_, _, :ok), do: :ok

  defp report(context, bench, {:error, message}) do
    Mix.shell().error("#{context.name} bench #{bench.id}: #{message}")
    :error
  end

  # Placement

  @doc """
  Where `bench` runs on this host (`Wotex.Workspace.NativeCheck.placement/2`);
  a `criterion` benchmark never runs in the Linux container. `probe`
  replaces the host checks in tests.
  """
  @spec placement(NativeBench.t(), probe() | nil) :: NativeCheck.placement()
  def placement(bench, probe \\ nil)

  def placement(%NativeBench{kind: :criterion} = bench, probe) do
    case if(probe, do: NativeCheck.unmet(bench, probe), else: NativeCheck.unmet(bench)) do
      [] -> :host
      reasons -> {:unmet, Enum.concat(reasons, ["the Linux container has no Rust toolchain"])}
    end
  end

  def placement(bench, nil), do: NativeCheck.placement(bench)
  def placement(bench, probe), do: NativeCheck.placement(bench, probe)

  # The Linux container

  @doc "The arguments of `mix wotex.native.bench` in the Linux container for `bench`."
  @spec container_args(NativeBench.t(), Path.t()) :: [String.t()]
  def container_args(bench, output), do: ["--bench", bench.id, "--output", output]

  defp run_contained(context, bench, opts) do
    output = NativeCache.reset!(Path.join(bench_dir(context, bench), "linux"))
    args = container_args(bench, output)
    workspace = [workspace: Keyword.get(opts, :workspace), requires: bench.requires]

    case NativeContainer.linux_task(
           context,
           "bench #{bench.id}",
           "wotex.native.bench",
           args,
           workspace
         ) do
      {:ok, 0} ->
        destination = Path.join(output_dir(context, opts), NativeBench.report(bench))
        File.mkdir_p!(Path.dirname(destination))
        File.cp!(Path.join(output, NativeBench.report(bench)), destination)
        written(context, destination)

      {:ok, status} ->
        {:error, "the Linux container exited with status #{status}"}

      {:error, message} ->
        {:error, message}
    end
  end

  # nanobench

  @doc """
  Verifies the vendored nanobench (`tooling/native/nanobench`) against the
  digests of its `source.json` and returns the pinned version.
  """
  @spec verify_nanobench(Path.t()) :: {:ok, String.t()} | {:error, String.t()}
  def verify_nanobench(root \\ Workspace.root()) do
    dir = Path.join(root, NativeBench.nanobench_dir())
    manifest = Path.join(dir, "source.json")

    with {:ok, text} <- File.read(manifest),
         {:ok, %{"version" => version, "files" => files}} when is_map(files) <- JSON.decode(text),
         [] <- mismatched(dir, files) do
      {:ok, version}
    else
      [_ | _] = problems -> {:error, Enum.join(problems, "; ")}
      _ -> {:error, "#{Path.relative_to(manifest, root)} is missing or not a source record"}
    end
  end

  defp mismatched(dir, files) do
    for {file, digest} <- Enum.sort(files),
        path = Path.join(dir, file),
        not File.regular?(path) or Native.sha256(path) != digest,
        do: "#{Path.join(NativeBench.nanobench_dir(), file)}: sha256 mismatch or missing"
  end

  @doc """
  The compile and link commands of a `nanobench` benchmark: each
  translation unit its `compile` rules match (in rule order, first rule
  wins), then nanobench's implementation, then the link.
  """
  @spec nanobench_plan(context(), NativeBench.t(), NativeTools.compilers(), %{
          String.t() => String.t()
        }) :: {:ok, nanobench_plan()} | {:error, String.t()}
  def nanobench_plan(context, bench, compilers, values) do
    scratch = values["scratch"]
    objects = Path.join(scratch, "objects")

    with {:ok, units} <- units(context, bench),
         {:ok, defaults} <- NativeCheck.expand_flags(NativeBench.default_flags(), values),
         {:ok, compile} <- compile_commands(units, defaults, compilers, objects, values),
         {:ok, link} <- NativeCheck.expand_flags(bench.link, values, :libs) do
      main = Path.join(scratch, "nanobench.cpp")
      main_object = Path.join(objects, "nanobench.o")
      main_compile = [compilers.cxx | defaults] ++ ["-std=c++17", "-c", main, "-o", main_object]
      executable = Path.join(scratch, bench.id)
      object_files = Enum.concat(Enum.map(compile, &List.last/1), [main_object])

      {:ok,
       %{
         compile: Enum.concat(compile, [main_compile]),
         link: [compilers.cxx | object_files] ++ ["-o", executable | link],
         executable: executable
       }}
    end
  end

  # The package-relative translation units of each rule, in order.
  defp units(context, bench) do
    Enum.reduce_while(bench.compile, {:ok, [], MapSet.new()}, fn rule, {:ok, acc, seen} ->
      files =
        rule.files
        |> Enum.flat_map(&Path.wildcard(Path.join(context.dir, &1)))
        |> Enum.map(&Path.relative_to(&1, context.dir))
        |> Enum.filter(&NativeFiles.translation_unit?/1)
        |> Enum.uniq()
        |> Enum.sort()

      fresh = Enum.reject(files, &MapSet.member?(seen, &1))

      if files == [],
        do: {:halt, {:error, "compile files #{inspect(rule.files)} match no translation unit"}},
        else:
          {:cont,
           {:ok, acc ++ Enum.map(fresh, &{&1, rule.flags}), MapSet.union(seen, MapSet.new(fresh))}}
    end)
    |> then(fn
      {:ok, units, _} -> {:ok, units}
      error -> error
    end)
  end

  defp compile_commands(units, defaults, compilers, objects, values) do
    units
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {{file, flags}, index}, {:ok, acc} ->
      case NativeCheck.expand_flags(flags, values) do
        {:ok, flags} ->
          compiler = if NativeFiles.language(file) == :c, do: compilers.cc, else: compilers.cxx
          object = Path.join(objects, "#{index}-#{Path.rootname(Path.basename(file))}.o")

          command =
            [compiler | defaults] ++
              flags ++ ["-c", Path.join(values["package"], file), "-o", object]

          {:cont, {:ok, [command | acc]}}

        error ->
          {:halt, error}
      end
    end)
    |> then(fn
      {:ok, commands} -> {:ok, Enum.reverse(commands)}
      error -> error
    end)
  end

  defp run_nanobench(context, bench, opts) do
    values = values(context, bench, opts)
    driver = Path.join(context.dir, NativeBench.source(bench))

    with :ok <- exists(driver, context),
         {:ok, version} <- verify_nanobench(context.root),
         {:ok, compilers} <- compilers(),
         {:ok, plan} <- nanobench_plan(context, bench, compilers, values),
         :ok <- prepare_scratch(values["scratch"]),
         :ok <- build_nanobench(context, plan),
         {:ok, output} <- run_driver(context, bench, plan.executable, values) do
      case BenchReport.nanobench_tables(output) do
        "" ->
          {:error, "#{NativeBench.source(bench)} printed no nanobench table"}

        tables ->
          system =
            system() ++
              [
                {"Compiler", compilers.version},
                {"Build",
                 "`#{Enum.join(Enum.take(NativeBench.default_flags(), 2), " ")}`, nanobench #{version}"},
                {"Source", "`#{NativeBench.source(bench)}`"}
              ]

          write(context, bench, opts, system, tables, BenchReport.nanobench_note())
      end
    end
  end

  defp compilers do
    with {:ok, tidy} <- NativeTools.find(:clang_tidy), do: NativeTools.compilers(tidy)
  end

  defp prepare_scratch(scratch) do
    NativeCache.reset!(scratch)
    File.mkdir_p!(Path.join(scratch, "objects"))
    File.write!(Path.join(scratch, "nanobench.cpp"), @nanobench_main)
    :ok
  end

  defp build_nanobench(context, plan) do
    Enum.reduce_while(Enum.concat(plan.compile, [plan.link]), :ok, fn argv, :ok ->
      case Exec.run(argv, cd: context.dir, env: NativeCheck.tool_env()) do
        0 -> {:cont, :ok}
        status -> {:halt, {:error, "`#{Path.basename(hd(argv))}` failed (#{status})"}}
      end
    end)
  end

  defp run_driver(context, bench, executable, values) do
    output = Path.join(values["scratch"], "output.md")
    env = bench_env(bench, values)

    case Exec.run([executable], cd: context.dir, env: env, stdout: output) do
      0 ->
        text = File.read!(output)
        Mix.shell().info(text)
        {:ok, text}

      status ->
        {:error, "#{NativeBench.source(bench)} exited with status #{status}"}
    end
  end

  defp bench_env(bench, values) do
    NativeCheck.tool_env() ++
      Enum.map(bench.env, fn {name, value} -> {name, NativeSuite.expand(value, values)} end)
  end

  # criterion

  @doc """
  The `cargo bench` command of a `criterion` benchmark, run in the
  repository root: the crate manifest is repository-relative and the target
  directory is the one the native checks use for the package.
  """
  @spec criterion_command(context(), NativeBench.t()) :: [String.t()]
  def criterion_command(context, bench) do
    manifest = Path.join(context.relative, NativeBench.source(bench))
    target = Path.join([context.cache, context.name, "cargo"])

    ~w(cargo bench --manifest-path) ++
      [manifest, "--locked", "--benches", "--target-dir", target]
  end

  @doc """
  Runs a `criterion` benchmark: `command` in `cd` with `CRITERION_HOME`
  set to a fresh `<scratch>/criterion`, then reads the estimates.
  """
  @spec criterion_run([String.t()], Path.t(), [{String.t(), String.t() | nil}], Path.t()) ::
          {:ok, [BenchReport.estimate()]} | {:error, String.t()}
  def criterion_run(command, cd, env, scratch) do
    home = Path.join(NativeCache.reset!(scratch), "criterion")

    case Exec.run(command, cd: cd, env: Enum.concat(env, [{"CRITERION_HOME", home}])) do
      0 ->
        case BenchReport.criterion(home) do
          {:ok, []} -> {:error, "cargo bench recorded no criterion benchmark"}
          result -> result
        end

      status ->
        {:error, "cargo bench failed (#{status})"}
    end
  end

  defp run_criterion(context, bench, opts) do
    values = values(context, bench, opts)
    crate = Path.join(context.dir, NativeBench.source(bench))

    with :ok <- exists(crate, context),
         :ok <- cargo(),
         {:ok, estimates} <-
           criterion_run(
             criterion_command(context, bench),
             context.root,
             bench_env(bench, values),
             values["scratch"]
           ) do
      lock = Path.join(Path.dirname(crate), "Cargo.lock")
      criterion = lock_version(read(lock), "criterion") || "unknown"

      system =
        system() ++
          [
            {"Compiler", command_line("rustc", ["--version"], context.root) || "rustc (unknown)"},
            {"Build", "`cargo bench` (bench profile), criterion #{criterion}"},
            {"Source", "`#{Path.dirname(NativeBench.source(bench))}/`"}
          ]

      write(
        context,
        bench,
        opts,
        system,
        BenchReport.criterion_table(estimates),
        BenchReport.criterion_note()
      )
    end
  end

  defp cargo do
    if System.find_executable("cargo"),
      do: :ok,
      else:
        {:error,
         "cargo not found; install the Rust toolchain pinned in rust-toolchain.toml (`mise install`)"}
  end

  @doc "The version of package `name` in the text of a `Cargo.lock`, or `nil`."
  @spec lock_version(String.t() | nil, String.t()) :: String.t() | nil
  def lock_version(nil, _), do: nil

  def lock_version(text, name) do
    case Regex.run(~r/^name = "#{Regex.escape(name)}"\nversion = "([^"]+)"$/m, text) do
      [_, version] -> version
      nil -> nil
    end
  end

  # elixir

  @doc """
  The environment of an `elixir` benchmark script: its `env` with the
  placeholders expanded, then the report path, title and description.
  """
  @spec script_env(NativeBench.t(), %{String.t() => String.t()}, Path.t()) ::
          [{String.t(), String.t()}]
  def script_env(bench, values, report) do
    Enum.map(bench.env, fn {name, value} -> {name, NativeSuite.expand(value, values)} end) ++
      [
        {"WOTEX_BENCH_OUTPUT", report},
        {"WOTEX_BENCH_TITLE", bench.title},
        {"WOTEX_BENCH_DESCRIPTION", bench.description}
      ]
  end

  defp ensure_build(_, _, :built), do: :built
  defp ensure_build(_, _, {:failed, _} = failed), do: failed

  defp ensure_build(context, opts, :unbuilt) do
    workspace = Keyword.fetch!(opts, :workspace)

    case Runner.run(context.dir, [context.native_task, "--workspace", workspace]) do
      0 -> :built
      status -> {:failed, "#{context.native_task} --workspace #{workspace} failed (#{status})"}
    end
  end

  defp run_script(context, bench, opts) do
    values = values(context, bench, opts)
    script = NativeBench.source(bench)
    report = Path.join(output_dir(context, opts), NativeBench.report(bench))
    File.mkdir_p!(Path.dirname(report))
    File.rm(report)
    NativeCache.reset!(values["scratch"])

    with :ok <- exists(Path.join(context.dir, script), context) do
      env = script_env(bench, values, report)

      case Runner.run(context.dir, ["run", script], mix_env: "dev", env: env) do
        0 -> check_script_report(context, bench, report)
        status -> {:error, "mix run #{script} failed (#{status})"}
      end
    end
  end

  defp check_script_report(context, bench, report) do
    case File.read(report) do
      {:ok, "# " <> _ = text} ->
        if String.starts_with?(text, "# #{bench.title}\n"),
          do: written(context, report),
          else: {:error, "#{relative(context, report)} does not start with `# #{bench.title}`"}

      _ ->
        {:error, "#{NativeBench.source(bench)} wrote no report at #{relative(context, report)}"}
    end
  end

  # Reports and the system

  defp write(context, bench, opts, system, results, note) do
    path = Path.join(output_dir(context, opts), NativeBench.report(bench))

    text =
      BenchReport.render(%{
        title: bench.title,
        description: bench.description,
        system: system,
        results: results,
        note: note
      })

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, text)
    written(context, path)
  end

  defp written(context, path) do
    Mix.shell().info("wrote #{relative(context, path)}")
    :ok
  end

  defp relative(context, path) do
    case Path.relative_to(path, context.root) do
      ^path -> path
      relative -> relative
    end
  end

  defp exists(path, context) do
    if File.exists?(path), do: :ok, else: {:error, "#{relative(context, path)} not found"}
  end

  @doc """
  The operating system and CPU of this host, for a report's System section.
  """
  @spec system() :: BenchReport.system()
  def system do
    [{"Operating system", operating_system()}, {"CPU", cpu()}]
  end

  defp operating_system do
    uname = command_line("uname", ["-srm"]) || "unknown"

    name =
      case :os.type() do
        {:unix, :darwin} ->
          [command_line("sw_vers", ["-productName"]), command_line("sw_vers", ["-productVersion"])]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(" ")

        {:unix, :linux} ->
          os_release_name(read("/etc/os-release"))

        _ ->
          nil
      end

    if name in [nil, ""], do: uname, else: "#{name} (#{uname})"
  end

  defp cpu do
    model =
      case :os.type() do
        {:unix, :darwin} ->
          command_line("sysctl", ["-n", "machdep.cpu.brand_string"])

        {:unix, :linux} ->
          cpu_model(read("/proc/cpuinfo")) || cpu_model(command_output("lscpu", []))

        _ ->
          nil
      end

    "#{model || "unknown"}, #{:erlang.system_info(:logical_processors)} logical processors"
  end

  @doc "The `PRETTY_NAME` of an `/etc/os-release` text, or `nil`."
  @spec os_release_name(String.t() | nil) :: String.t() | nil
  def os_release_name(nil), do: nil

  def os_release_name(text) do
    case Regex.run(~r/^PRETTY_NAME="?([^"\n]*)"?$/m, text) do
      [_, name] -> name
      nil -> nil
    end
  end

  @doc """
  The CPU model in `/proc/cpuinfo` (`model name`) or `lscpu` (`Model
  name`) output; else the vendor `lscpu` reports (`Vendor ID`, as on arm64
  hosts that report no model); else `nil`.
  """
  @spec cpu_model(String.t() | nil) :: String.t() | nil
  def cpu_model(nil), do: nil

  def cpu_model(text) do
    field(text, ~r/^model name\s*:\s*(.+)$/mi) || field(text, ~r/^Vendor ID\s*:\s*(.+)$/m)
  end

  defp field(text, pattern) do
    case Regex.run(pattern, text) do
      [_, value] -> if String.trim(value) in ["-", ""], do: nil, else: String.trim(value)
      nil -> nil
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, text} -> text
      {:error, _} -> nil
    end
  end

  defp command_line(executable, args, cd \\ nil) do
    case command_output(executable, args, cd) do
      nil -> nil
      output -> first_line(output)
    end
  end

  defp first_line(output) do
    [line | _] = String.split(output, "\n")
    String.trim(line)
  end

  defp command_output(executable, args, cd \\ nil) do
    with path when is_binary(path) <- System.find_executable(executable),
         {output, 0} <-
           System.cmd(path, args,
             cd: cd || File.cwd!(),
             env: [{"LC_ALL", "C"} | NativeCheck.tool_env()],
             stderr_to_stdout: true
           ) do
      output
    else
      _ -> nil
    end
  end
end
