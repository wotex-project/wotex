defmodule Mix.Tasks.Wotex.Docs.Check do
  @shortdoc "Checks links in tracked Markdown and the family catalogue"

  @moduledoc """
  Checks the links of every Markdown file Git tracks (`git ls-files
  '*.md'`) and that `docs/catalogue.yaml` is current (`mix wotex.catalogue
  --check`). The root alias is `mix docs.check`.

      mix wotex.docs.check

  Reported as `file:line: target`:

    * a relative link whose target does not exist;
    * a `https://github.com/wotex-project/wotex/blob/main/...` (or
      `/tree/main/...`) URL whose path does not exist in the working tree;
    * in `docs/packages/<p>/**` and `packages/<p>/README.md` (published on
      HexDocs), a relative link to a `.md` file outside `docs/packages/<p>/`
      and `packages/<p>/`; the report names the main-branch URL to use.

  Other URLs and anchor-only targets are skipped; anchors are stripped and
  not checked. See `Wotex.Workspace.Links`.
  """

  use Mix.Task

  alias Wotex.Workspace
  alias Wotex.Workspace.Catalogue
  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Links

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    CLI.parse_options(args, [])

    problems =
      Enum.reject([links(), catalogue()], &(&1 == :ok))

    if problems != [], do: CLI.fail("documentation check failed")
    :ok
  end

  @doc "Checks the links of every tracked Markdown file and prints the result."
  @spec links(Path.t()) :: :ok | :error
  def links(root \\ Workspace.root()) do
    case Links.tracked_markdown(root) do
      {:ok, files} ->
        case Links.check(root, files) do
          [] ->
            Mix.shell().info("#{length(files)} Markdown files: every link resolves")
            :ok

          broken ->
            Enum.each(broken, &Mix.shell().error(Links.format(&1)))
            {missing, crossing} = Enum.split_with(broken, &(&1.problem == :missing))

            Mix.shell().error(
              "#{length(missing)} broken link(s), " <>
                "#{length(crossing)} relative link(s) leaving package documentation"
            )

            :error
        end

      {:error, message} ->
        Mix.shell().error(message)
        :error
    end
  end

  @doc "Checks the family catalogue and prints the result."
  @spec catalogue() :: :ok | :error
  def catalogue do
    case Catalogue.check() do
      :ok ->
        Mix.shell().info("#{Catalogue.output()} is current")
        :ok

      {:error, message} ->
        Mix.shell().error(message)
        :error
    end
  end
end
