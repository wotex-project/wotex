defmodule Mix.Tasks.Wotex.Refs do
  @shortdoc "Prints references to a module or function, grouped by package"

  @moduledoc """
  Prints every reference to `MODULE` or `MODULE.FUN` from the Dexter
  index, grouped by package and by kind (`lib`, `support`, `test`,
  `other`), as repository-relative `path:line`. The index is refreshed
  first (`dexter reindex`, changed files only). References in dependencies
  are counted, not listed. The root alias is `mix refs`.

      mix wotex.refs MODULE [FUN]

  `MODULE.fun` and `MODULE.fun/arity` are accepted too.
  """

  use Mix.Task

  alias Mix.Tasks.Wotex.Def
  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Dexter
  alias Wotex.Workspace.Impact
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.References

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {module, fun} = parse_args(args)

    with :ok <- Dexter.reindex(),
         {:ok, locations} <- Dexter.references(module, fun) do
      entries = Enum.map(locations, &References.classify/1)
      Mix.shell().info(References.render(Impact.target(module, fun), entries, Manifest.load!()))
    else
      {:error, message} -> CLI.fail(message)
    end

    :ok
  end

  @doc "Parses `MODULE [FUN]`."
  @spec parse_args([String.t()]) :: {String.t(), String.t() | nil}
  def parse_args(args) do
    {_, rest} = CLI.parse(args, [])
    Def.target!(rest, "mix refs MODULE [FUN]")
  end
end
