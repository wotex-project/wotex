defmodule Mix.Tasks.Wotex.Workspace do
  @shortdoc "Root self-check: compile, format, credo, tests, catalogue, links, boundary"

  @moduledoc """
  The root project's self-check. The root alias is `mix workspace`.

      mix wotex.workspace [--base REF] [--all]

  Steps, each reported in a summary table:

    1. `mix compile --warnings-as-errors`, `mix format --check-formatted`,
       `mix credo --strict` and `mix test` in the root project, each in its
       own OS process;
    2. the family catalogue is current (`mix wotex.catalogue --check`);
    3. every relative link in tracked Markdown resolves (`mix
       wotex.docs.check`);
    4. the sibling-API boundary (`mix wotex.boundary`) of the changed
       packages, or of every package with `--all`.

  Every step runs; the task fails at the end when any step failed.
  """

  use Mix.Task

  alias Mix.Tasks.Wotex.Docs.Check
  alias Wotex.Workspace
  alias Wotex.Workspace.Boundary
  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Report
  alias Wotex.Workspace.Steps

  @switches [base: :string, all: :boolean]

  @root_steps [
    {"compile", ["compile", "--warnings-as-errors"], [path_deps: false]},
    {"format", ["format", "--check-formatted"], [path_deps: false]},
    {"credo", ["credo", "--strict"], [path_deps: false]},
    # Unset MIX_ENV so that Mix picks the test environment, as a plain
    # `mix test` in the root would.
    {"test", ["test"], [path_deps: false, env: [{"MIX_ENV", nil}]]}
  ]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()

    {root_rows, _} =
      @root_steps
      |> Enum.map(fn {label, _, _} = step ->
        %{step: "root #{label}", path: Workspace.root(), steps: [step]}
      end)
      |> Steps.run(halt: false)

    rows =
      root_rows ++
        [
          timed_row("catalogue", &Check.catalogue/0),
          timed_row("docs links", fn -> Check.links() end),
          timed_row("boundary", fn -> boundary(manifest, opts) end)
        ]

    Mix.shell().info("\n" <> Report.table(rows, [:step, :result, :seconds]))
    if Enum.any?(rows, &(&1.result != "ok")), do: CLI.fail("workspace check failed")
    :ok
  end

  @doc "Parses the task's options."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args), do: CLI.parse_options(args, @switches)

  @doc "The root-project steps, in order."
  @spec root_steps() :: [Steps.step()]
  def root_steps, do: @root_steps

  defp timed_row(step, fun) do
    {result, seconds} = CLI.timed(fun)
    %{step: step, result: if(result == :ok, do: "ok", else: "failed"), seconds: seconds}
  end

  defp boundary(manifest, opts) do
    names = CLI.select!(manifest, opts, if(opts[:all], do: nil, else: :changed))

    if names == [] do
      Mix.shell().info("boundary: no changed packages")
      :ok
    else
      failures = Enum.count(names, &(boundary_package(&1, manifest) != :ok))
      if failures == 0, do: :ok, else: :error
    end
  end

  defp boundary_package(name, manifest) do
    case Boundary.run(name, manifest) do
      {:ok, []} ->
        Mix.shell().info("#{name}: no boundary findings")
        :ok

      {:ok, findings} ->
        Enum.each(findings, &Mix.shell().error(Boundary.format(&1)))
        Mix.shell().error("#{name}: #{length(findings)} boundary finding(s)")
        :error

      {:error, message} ->
        Mix.shell().error(message)
        :error
    end
  end
end
