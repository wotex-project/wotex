defmodule Mix.Tasks.Wotex.Affected do
  @shortdoc "Prints the packages affected by the current changes"

  @moduledoc """
  Prints the names of the packages affected by the changes since a base
  revision, one per line, in topological order. The root alias is
  `mix affected`.

      mix wotex.affected [--base REF] [--docs] [--all] [--json] [--detail]

    * `--base REF`: compare against `REF` (`REF...HEAD` plus the working
      tree). Defaults to `origin/main`, else `main`, else the root commit.
    * `--docs`: a change under `docs/packages/<name>/` selects that package
      (documentation-only changes select nothing by default).
    * `--all`: every package in topological order; CI uses it for scheduled
      and manual runs.
    * `--json`: print a flat JSON list of names instead of lines (CI reads
      this form).
    * `--detail`: mark each package `changed` (a changed path selects it) or
      `dependent` (selected only as a transitive dependent). With `--json`
      the output is a list of `{"name": ..., "status": ...}` objects.

  A path under `packages/<name>/` selects that package and every transitive
  dependent; a path matching the manifest's `select_all_on` globs selects
  every package, and marks each `changed`.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest

  @switches [base: :string, docs: :boolean, all: :boolean, json: :boolean, detail: :boolean]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)
    output = render(CLI.classify!(Manifest.load!(), opts), opts)
    if output != "", do: Mix.shell().info(output)
    :ok
  end

  @doc "Parses the task's options."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args), do: CLI.parse_options(args, @switches)

  @doc """
  Renders marked packages as lines or JSON; `detail: true` keeps the marks.
  """
  @spec render([{String.t(), atom()}], keyword()) :: String.t()
  def render(marked, opts) do
    case {Keyword.get(opts, :json, false), Keyword.get(opts, :detail, false)} do
      {true, false} ->
        JSON.encode!(Enum.map(marked, &elem(&1, 0)))

      {true, true} ->
        JSON.encode!(Enum.map(marked, fn {name, mark} -> %{name: name, status: mark} end))

      {false, false} ->
        Enum.map_join(marked, "\n", &elem(&1, 0))

      {false, true} ->
        width =
          Enum.reduce(marked, 0, fn {name, _}, width -> max(width, String.length(name)) end)

        Enum.map_join(marked, "\n", fn {name, mark} ->
          "#{String.pad_trailing(name, width)}  #{mark}"
        end)
    end
  end
end
