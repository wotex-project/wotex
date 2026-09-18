defmodule Mix.Tasks.Wotex.Bench do
  @shortdoc "Runs the Elixir benchmarks of the selected packages"

  @moduledoc """
  Runs every `bench/*_bench.exs` script of each selected package with
  `mix run` in the `dev` environment and `WOTEX_PATH_DEPS=1`. Each script
  writes its Markdown report to `bench/output/<topic>.md`, which the
  package's documentation includes. The root alias is `mix bench`.

      mix wotex.bench [--package NAME]... [--base REF] [--all]

  The default selection is the changed packages. Every package runs; a
  package without a benchmark script fails. A summary table follows. The
  C, C++ and Rust benchmarks run with `mix native.bench`.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Report
  alias Wotex.Workspace.Steps

  @switches CLI.selection_switches()

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()
    names = CLI.select!(manifest, opts, :changed)
    if names == [], do: Mix.shell().info("no changed packages")

    {missing, present} =
      Enum.split_with(names, &(scripts(Manifest.absolute_path(&1, manifest)) == []))

    {rows, failed?} =
      present
      |> Enum.map(fn name ->
        Steps.target(name, manifest, steps(scripts(Manifest.absolute_path(name, manifest))))
      end)
      |> Steps.run(halt: false)

    missing_rows = Enum.map(missing, &%{package: &1, result: "no bench/*_bench.exs", seconds: 0.0})

    Mix.shell().info("\n" <> Report.table(rows ++ missing_rows))
    if failed? or missing != [], do: CLI.fail("benchmarks failed")
    :ok
  end

  @doc "Parses the task's options."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args), do: CLI.parse_options(args, @switches)

  @doc "The benchmark scripts of a package directory, relative to it and sorted."
  @spec scripts(Path.t()) :: [String.t()]
  def scripts(path) do
    path
    |> Path.join("bench/*_bench.exs")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, path))
    |> Enum.sort()
  end

  @doc "One `mix run` step in the `dev` environment per benchmark script."
  @spec steps([String.t()]) :: [Steps.step()]
  def steps(scripts) do
    Enum.map(scripts, fn script ->
      {Path.basename(script, "_bench.exs"), ["run", script], [mix_env: "dev"]}
    end)
  end
end
