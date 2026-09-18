defmodule Mix.Tasks.Wotex.Check.Affected do
  @shortdoc "Pre-commit gate: full gate for changed packages, fast gate for dependents"

  @moduledoc """
  The pre-commit gate over the affected set, in topological order:

    * a `changed` package runs its full gate (`mix deps.get --check-locked`
      and `mix check --no-retry`, as `mix wotex.check`);
    * a `dependent` package runs the fast gate (`mix wotex.check.fast`).

  Every command runs with `WOTEX_PATH_DEPS=1`. The task stops at the first
  failure and prints a summary table. The root alias is `mix
  check.affected`.

      mix wotex.check.affected [--base REF] [--docs]
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Report
  alias Wotex.Workspace.Steps

  @switches [base: :string, docs: :boolean]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()
    marked = CLI.classify!(manifest, opts)

    if marked == [], do: Mix.shell().info("no affected packages")

    {rows, failed?} = Steps.run(targets(marked, manifest))
    Mix.shell().info("\n" <> Report.table(rows, [:package, :gate, :result, :seconds]))
    if failed?, do: CLI.fail("affected gate failed")
    :ok
  end

  @doc "Parses the task's options."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args), do: CLI.parse_options(args, @switches)

  @doc "The gate of each marked package: full when changed, fast when dependent."
  @spec targets([{String.t(), :changed | :dependent}], Manifest.t()) :: [Steps.target()]
  def targets(marked, %Manifest{} = manifest) do
    Enum.map(marked, fn
      {name, :changed} -> Steps.target(name, manifest, Steps.full_gate(), %{gate: "full"})
      {name, :dependent} -> Steps.target(name, manifest, Steps.fast_gate(), %{gate: "fast"})
    end)
  end
end
