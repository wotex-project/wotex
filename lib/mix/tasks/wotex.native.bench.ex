defmodule Mix.Tasks.Wotex.Native.Bench do
  @shortdoc "Runs the native benchmarks of one package"

  @moduledoc """
  Runs the C, C++ and Rust benchmarks of one package, declared under
  `native_bench` in `tooling/packages.yaml` (`Wotex.Workspace.NativeBench`),
  and writes one Markdown report per benchmark to the package's
  `bench/output/native-<id>.md`, which its documentation includes. The root
  alias is `mix native.bench`.

      mix wotex.native.bench --package NAME [--bench ID]... [--workspace /abs/dir]
                             [--output /abs/dir]

    * `nanobench` benchmarks compile a C++ driver and the package sources it
      names with the LLVM of the native checks and nanobench, and run it;
    * `criterion` benchmarks run `cargo bench` in a benchmark crate;
    * `elixir` benchmarks run a script with `mix run` after the package's
      native build task built `--workspace /abs/dir`. Without `--workspace`
      they are skipped, and the task says so.

  `--bench ID` selects benchmarks (default: all of the package's).
  `--output /abs/dir` writes the reports there instead; the Linux container
  uses it for a benchmark that requires Linux on another host
  (`Wotex.Workspace.NativeBenchRunner`). Benchmarks run only when invoked;
  no gate runs them. Every benchmark runs; a summary table follows and the
  task fails when any benchmark failed. The Elixir benchmarks run with
  `mix bench`.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeBenchRunner
  alias Wotex.Workspace.Report

  @switches [package: :string, bench: :keep, workspace: :string, output: :string]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()
    name = CLI.package!(manifest, opts[:package])
    context = NativeBenchRunner.context(name, manifest)

    benches =
      case select(context.benches, Keyword.get_values(opts, :bench)) do
        {:ok, benches} -> benches
        {:error, message} -> CLI.fail("package #{name}: #{message}")
      end

    if skipped = skip_notice(benches, opts[:workspace]), do: Mix.shell().info(skipped)

    rows =
      NativeBenchRunner.run_all(context, benches,
        workspace: opts[:workspace],
        output: opts[:output]
      )

    Mix.shell().info("\n" <> Report.table(rows, [:package, :bench, :kind, :result, :seconds]))
    if Enum.any?(rows, &(&1.result == "error")), do: CLI.fail("native benchmarks failed")
    :ok
  end

  @doc """
  Parses the task's options: `--package` is required; `--workspace` and
  `--output` must be absolute.
  """
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    opts = CLI.parse_options(args, @switches)

    cond do
      opts[:package] in [nil, ""] ->
        Mix.raise("--package NAME is required")

      opts[:workspace] && Path.type(opts[:workspace]) != :absolute ->
        Mix.raise("--workspace must be an absolute directory")

      opts[:output] && Path.type(opts[:output]) != :absolute ->
        Mix.raise("--output must be an absolute directory")

      true ->
        opts
    end
  end

  @doc """
  The benchmarks named by `ids` (all when empty), in manifest order; an
  unknown id or a package without benchmarks is an error.
  """
  @spec select([Wotex.Workspace.NativeBench.t()], [String.t()]) ::
          {:ok, [Wotex.Workspace.NativeBench.t()]} | {:error, String.t()}
  def select([], _), do: {:error, "no native_bench in tooling/packages.yaml"}
  def select(benches, []), do: {:ok, benches}

  def select(benches, ids) do
    known = Enum.map(benches, & &1.id)

    case Enum.uniq(ids) -- known do
      [] ->
        {:ok, Enum.filter(benches, &(&1.id in ids))}

      unknown ->
        {:error,
         "unknown native_bench #{Enum.join(unknown, ", ")}; known: #{Enum.join(known, ", ")}"}
    end
  end

  @doc """
  The notice printed when `elixir` benchmarks are selected without a
  workspace, or `nil`.
  """
  @spec skip_notice([Wotex.Workspace.NativeBench.t()], Path.t() | nil) :: String.t() | nil
  def skip_notice(benches, nil) do
    case Enum.count(benches, &(&1.kind == :elixir)) do
      0 ->
        nil

      count ->
        "#{count} elixir benchmark(s) need the package's native build: pass --workspace /abs/dir; " <>
          "running the nanobench and criterion benchmarks only"
    end
  end

  def skip_notice(_, _), do: nil
end
