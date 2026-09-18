defmodule Mix.Tasks.Wotex.Check.Fast do
  @shortdoc "Inner-loop gate: compile, format, credo and tests of changed packages"

  @moduledoc """
  The inner-loop gate. For each selected package, in topological order, it
  runs with `WOTEX_PATH_DEPS=1 MIX_ENV=test`:

    1. `mix compile --warnings-as-errors`
    2. `mix format --check-formatted`
    3. `mix credo --strict`
    4. `mix test`

  stopping at the first failure, then prints a summary table. No Dialyzer,
  documentation, audits, coverage floor or archive check; those run in the
  full gate (`mix wotex.check`, `mix check.affected`). The root alias is
  `mix check.fast`.

      mix wotex.check.fast [--package NAME]... [--base REF] [--all]

  The default selection is the changed packages (without their
  dependents); see `mix wotex.affected --detail`.
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

    if names == [],
      do: Mix.shell().info("no changed packages"),
      else: Mix.shell().info("fast gate of #{Enum.join(names, ", ")}")

    {rows, failed?} =
      names
      |> Enum.map(&Steps.target(&1, manifest, Steps.fast_gate()))
      |> Steps.run()

    Mix.shell().info("\n" <> Report.table(rows))
    if failed?, do: CLI.fail("fast gate failed")
    :ok
  end

  @doc "Parses the task's options."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args), do: CLI.parse_options(args, @switches)
end
