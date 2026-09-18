defmodule Mix.Tasks.Wotex.New do
  @shortdoc "Scaffolds a new package under packages/ and docs/packages/"

  @moduledoc """
  Scaffolds `packages/NAME` (a Mix project with the `WOTEX_PATH_DEPS`
  sibling switch, the family's gate configuration and governance files),
  `docs/packages/NAME/{specs,plans,provenance}` with a catalogue skeleton
  and a manifest entry in `tooling/packages.yaml`.

      mix wotex.new NAME [--depends-on wotex,wotex-runtime]

  `--depends-on` lists the sibling packages the new package requires;
  it defaults to `wotex`. The task refuses to touch an existing package.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Scaffold

  @switches [depends_on: :string]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {name, opts} = parse_args(args)

    case Scaffold.create(name, depends_on: opts[:depends_on]) do
      {:ok, paths} ->
        Enum.each(paths, &Mix.shell().info("* created #{&1}"))

        Mix.shell().info(
          "scaffolded packages/#{name}; run its gate with WOTEX_PATH_DEPS=1 mix check"
        )

      {:error, message} ->
        CLI.fail(message)
    end

    :ok
  end

  @doc "Parses `NAME` and the options; `depends_on` is a list of names."
  @spec parse_args([String.t()]) :: {String.t(), keyword()}
  def parse_args(args) do
    {opts, rest} = CLI.parse(args, @switches)

    name =
      case rest do
        [name] -> name
        _other -> Mix.raise("usage: mix wotex.new NAME [--depends-on a,b]")
      end

    depends_on =
      opts
      |> Keyword.get(:depends_on, "wotex")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    {name, depends_on: depends_on}
  end
end
