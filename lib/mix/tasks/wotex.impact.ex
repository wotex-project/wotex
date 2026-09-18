defmodule Mix.Tasks.Wotex.Impact do
  @shortdoc "Lists (and runs) the test files a change to a module or function affects"

  @moduledoc """
  The test files to run for a change to `MODULE` or `MODULE.FUN`, grouped
  by package, from the Dexter index (refreshed first with `dexter
  reindex`). The root alias is `mix impact`.

      mix wotex.impact MODULE [FUN] [--run]

  Selection (see `Wotex.Workspace.Impact`):

    * test files that reference the target;
    * one hop: test files that reference the module enclosing each library
      or test-support reference;
    * a package with library references (or the definition) but no
      selected test file falls back to `mix test --stale`, and says so.

  `--run` runs `mix test FILES...` (or `mix test --stale`) in each package
  with `WOTEX_PATH_DEPS=1`. Every package runs; a summary table with the
  elapsed time follows and the task fails when any run failed.
  """

  use Mix.Task

  alias Mix.Tasks.Wotex.Def
  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Dexter
  alias Wotex.Workspace.Impact
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Report
  alias Wotex.Workspace.Steps

  @switches [run: :boolean]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {module, fun, opts} = parse_args(args)
    manifest = Manifest.load!()

    plan =
      with :ok <- Dexter.reindex(),
           {:ok, plan} <- Impact.plan(module, fun, manifest) do
        plan
      else
        {:error, message} -> CLI.fail(message)
      end

    Mix.shell().info(Impact.render(plan))
    if opts[:run], do: run_plan(plan, manifest)
    :ok
  end

  @doc "Parses `MODULE [FUN]` and `--run`."
  @spec parse_args([String.t()]) :: {String.t(), String.t() | nil, keyword()}
  def parse_args(args) do
    {opts, rest} = CLI.parse(args, @switches)
    {module, fun} = Def.target!(rest, "mix impact MODULE [FUN] [--run]")
    {module, fun, opts}
  end

  defp run_plan(%{packages: []}, _manifest), do: Mix.shell().info("nothing to run")

  defp run_plan(plan, manifest) do
    {{rows, failed?}, seconds} =
      CLI.timed(fn -> Steps.run(Impact.targets(plan, manifest), halt: false) end)

    Mix.shell().info("\n" <> Report.table(rows, [:package, :gate, :result, :seconds]))
    Mix.shell().info("total #{Report.seconds(seconds)} s")
    if failed?, do: CLI.fail("impacted tests failed")
  end
end
