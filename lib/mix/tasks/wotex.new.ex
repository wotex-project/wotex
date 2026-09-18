defmodule Mix.Tasks.Wotex.New do
  @shortdoc "Scaffolds a new package under packages/ and docs/packages/"

  @moduledoc """
  Scaffolds `packages/NAME` (a Mix library with the `WOTEX_PATH_DEPS`
  sibling switch, HexDocs extras and source links, the standard full gate
  with archive, application-free and boundary scripts, a `CLAUDE.md` package
  contract and a `README.md`), `docs/packages/NAME/{specs,plans,provenance}`
  with a catalogue skeleton and a completion contract, and a manifest entry
  in `tooling/packages.yaml`; then re-renders `docs/catalogue.yaml`.

      mix wotex.new NAME [--depends-on wotex,wotex-runtime]

  `--depends-on` lists the sibling packages the new package requires;
  it defaults to `wotex`. The task refuses to touch an existing package.
  """

  use Mix.Task

  alias Wotex.Workspace.Catalogue
  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Scaffold

  @switches [depends_on: :string]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {name, opts} = parse_args(args)

    case Scaffold.create(name, depends_on: opts[:depends_on]) do
      {:ok, paths} ->
        Enum.each(paths, &Mix.shell().info("* #{action(&1)} #{&1}"))
        render_catalogue()

        Mix.shell().info("""
        scaffolded packages/#{name}. Next:
          mix pkg #{name} deps.get
          mix pkg #{name} check --no-retry
        and describe the package in its README.md, CLAUDE.md and mix.exs, the
        package table of the root README.md and, with its specification
        prefix, docs/README.md.\
        """)

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
        _ -> Mix.raise("usage: mix wotex.new NAME [--depends-on a,b]")
      end

    depends_on =
      opts
      |> Keyword.get(:depends_on, "wotex")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    {name, depends_on: depends_on}
  end

  defp action("tooling/packages.yaml"), do: "updated"
  defp action(_), do: "created"

  defp render_catalogue do
    case Catalogue.write() do
      {:ok, _, []} -> Mix.shell().info("* updated #{Catalogue.output()}")
      {:ok, _, problems} -> Enum.each(problems, &Mix.shell().error(elem(&1, 1)))
      {:error, message} -> CLI.fail(message)
    end
  end
end
