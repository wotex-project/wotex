defmodule Mix.Tasks.Wotex.Setup do
  @shortdoc "Fetches every package's dependencies and builds the Dexter index"

  @moduledoc """
  Prepares a checkout: `mix deps.get` in every package directory and in
  each of its host applications (`hosts:` in `tooling/packages.yaml`, with
  the host's environment), with `WOTEX_PATH_DEPS=1` and in topological
  order, then the Dexter index (see `mix wotex.index`).

      mix wotex.setup [--no-index]

  The root alias `mix setup` runs `mix deps.get` for the root project first.
  Every package is attempted; the task fails at the end when any `deps.get`
  or the index build failed. `--no-index` skips the index.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Dexter
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Report
  alias Wotex.Workspace.Steps

  @switches [index: :boolean]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)
    manifest = Manifest.load!()

    {rows, failed?} =
      manifest.order
      |> Enum.map(&Steps.target(&1, manifest, deps_steps(Manifest.fetch!(&1, manifest))))
      |> Steps.run(halt: false)

    {index, seconds} =
      if Keyword.get(opts, :index, true),
        do: CLI.timed(fn -> Dexter.index() end),
        else: {:skipped, 0}

    index_row = %{package: "(dexter index)", result: index_result(index), seconds: seconds}
    Mix.shell().info("\n" <> Report.table(Enum.concat(rows, [index_row])))

    cond do
      failed? -> CLI.fail("setup failed")
      match?({:error, _}, index) -> CLI.fail(elem(index, 1))
      true -> :ok
    end
  end

  @doc "Parses the task's options."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args), do: CLI.parse_options(args, @switches)

  @doc "`mix deps.get` in the package directory and then in each of its hosts."
  @spec deps_steps(Manifest.Package.t()) :: [Steps.step()]
  def deps_steps(package) do
    steps = [{"deps.get", ["deps.get"], []}]
    steps ++ Steps.host_steps(package, steps)
  end

  defp index_result(:ok), do: "ok"
  defp index_result(:skipped), do: "skipped"
  defp index_result({:error, _message}), do: "failed"
end
