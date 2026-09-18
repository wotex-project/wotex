defmodule Mix.Tasks.Wotex.Affected do
  @shortdoc "Prints the packages affected by the current changes"

  @moduledoc """
  Prints the names of the packages affected by the changes since a base
  revision, one per line, in topological order.

      mix wotex.affected [--base REF] [--docs] [--all] [--json]

    * `--base REF`: compare against `REF` (`REF...HEAD` plus the working
      tree). Defaults to `origin/main`, else `main`, else the root commit.
    * `--docs`: a change under `docs/packages/<name>/` selects that package
      (documentation-only changes select nothing by default).
    * `--all`: every package in topological order; CI uses it for scheduled
      and manual runs.
    * `--json`: print a JSON list instead of lines.

  A path under `packages/<name>/` selects that package and every transitive
  dependent; a path matching the manifest's `select_all_on` globs selects
  every package.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest

  @switches [base: :string, docs: :boolean, all: :boolean, json: :boolean]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)
    names = CLI.select!(Manifest.load!(), opts)

    if opts[:json],
      do: Mix.shell().info(JSON.encode!(names)),
      else: Enum.each(names, fn name -> Mix.shell().info(name) end)

    :ok
  end

  @doc "Parses the task's options."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args) do
    {opts, rest} = CLI.parse(args, @switches)
    if rest != [], do: Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")
    opts
  end
end
