defmodule Mix.Tasks.Wotex.Lint do
  @shortdoc "Runs credo --strict in the changed packages"

  @moduledoc """
  Runs `mix credo --strict` in each selected package with
  `WOTEX_PATH_DEPS=1`. Every package runs; a summary table follows and the
  task fails when any package has findings. The root alias is `mix lint`.

      mix wotex.lint [--package NAME]... [--base REF] [--all]

  The default selection is the changed packages (without their dependents).
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

    {rows, failed?} =
      names
      |> Enum.map(&Steps.target(&1, manifest, [{"credo", ["credo", "--strict"], []}]))
      |> Steps.run(halt: false)

    Mix.shell().info("\n" <> Report.table(rows))
    if failed?, do: CLI.fail("credo failed")
    :ok
  end

  @doc "Parses the task's options."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args), do: CLI.parse_options(args, @switches)
end
