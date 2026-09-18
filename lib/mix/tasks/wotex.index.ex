defmodule Mix.Tasks.Wotex.Index do
  @shortdoc "Builds or refreshes the Dexter index of the repository"

  @moduledoc """
  Builds the Dexter code index in `.dexter/` (ignored) with `dexter init .`,
  or refreshes an existing index with `dexter reindex`, which re-reads only
  changed files. The root alias is `mix index`.

      mix wotex.index [--force]

  `--force` deletes the index and rebuilds it from scratch
  (`dexter init . --force`). Dexter is pinned in `mise.toml`; when it is
  missing the task fails and names `mise install`.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Dexter

  @switches [force: :boolean]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)

    case Dexter.index(Keyword.get(opts, :force, false)) do
      :ok -> :ok
      {:error, message} -> CLI.fail(message)
    end
  end

  @doc "Parses the task's options."
  @spec parse_args([String.t()]) :: keyword()
  def parse_args(args), do: CLI.parse_options(args, @switches)
end
