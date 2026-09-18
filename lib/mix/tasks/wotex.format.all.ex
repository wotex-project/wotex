defmodule Mix.Tasks.Wotex.Format.All do
  @shortdoc "Formats the root project and the changed packages"

  @moduledoc """
  Runs `mix format` in the root project and in each selected package (with
  `WOTEX_PATH_DEPS=1`), or `mix format --check-formatted` with `--check`.
  Every directory runs; a summary table follows and the task fails when any
  run failed. The root alias is `mix format.all`.

      mix wotex.format.all [--check] [--all] [--package NAME]... [--base REF]

  The default selection is the changed packages; `--all` formats every
  package.
  """

  use Mix.Task

  alias Wotex.Workspace
  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Report
  alias Wotex.Workspace.Steps

  @switches [check: :boolean] ++ CLI.selection_switches()

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()
    names = CLI.select!(manifest, opts, :changed)
    step = step(Keyword.get(opts, :check, false))

    root = %{package: "(workspace root)", path: Workspace.root(), steps: [root_step(step)]}
    targets = [root | Enum.map(names, &Steps.target(&1, manifest, [step]))]

    {rows, failed?} = Steps.run(targets, halt: false)
    Mix.shell().info("\n" <> Report.table(rows))
    if failed?, do: CLI.fail("format failed")
    :ok
  end

  @doc "Parses the task's options."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args), do: CLI.parse_options(args, @switches)

  @doc "The format step: `mix format`, or `mix format --check-formatted`."
  @spec step(boolean()) :: Steps.step()
  def step(true), do: {"format", ["format", "--check-formatted"], []}
  def step(false), do: {"format", ["format"], []}

  defp root_step({label, args, _}), do: {label, args, [path_deps: false]}
end
