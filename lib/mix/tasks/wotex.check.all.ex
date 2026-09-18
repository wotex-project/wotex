defmodule Mix.Tasks.Wotex.Check.All do
  @shortdoc "CI-equivalent: workspace checks plus every package's full gate"

  @moduledoc """
  The CI-equivalent gate: `mix wotex.workspace --all` (root checks, family
  catalogue, documentation links, sibling-API boundary of every package)
  followed by `mix wotex.check --all` (every package's full gate). The
  root alias is `mix check.all`.

      mix wotex.check.all

  Heavy. Run it only for repository-wide changes or on explicit request;
  a bounded change uses `mix check.affected`. Native lanes are not part of
  it.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    parse_args(args)
    Mix.Task.run("wotex.workspace", ["--all"])
    Mix.Task.run("wotex.check", ["--all"])
    :ok
  end

  @doc "Parses the task's options (it takes none)."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args), do: CLI.parse_options(args, [])
end
