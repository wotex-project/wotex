defmodule Mix.Tasks.Wotex.Catalogue do
  @shortdoc "Renders or checks the family catalogue docs/catalogue.yaml"

  @moduledoc """
  Renders `docs/catalogue.yaml` from every package's
  `docs/packages/<name>/specs/catalogue.yaml`, or checks that the committed
  file is current.

      mix wotex.catalogue [--check]

  Without `--check` the file is written and every specification path that
  does not resolve is reported; the task fails when any is missing. With
  `--check` the task fails when the committed file differs from the
  rendering or a path is missing, and writes nothing.
  """

  use Mix.Task

  alias Wotex.Workspace.Catalogue
  alias Wotex.Workspace.CLI

  @switches [check: :boolean]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    opts = parse_args(args)

    if opts[:check] do
      case Catalogue.check() do
        :ok -> Mix.shell().info("#{Catalogue.output()} is current")
        {:error, message} -> CLI.fail(message)
      end
    else
      case Catalogue.write() do
        {:ok, count, []} ->
          Mix.shell().info("rendered #{Catalogue.output()} with #{count} specifications")

        {:ok, count, problems} ->
          Mix.shell().info("rendered #{Catalogue.output()} with #{count} specifications")
          Enum.each(problems, fn {_package, message} -> Mix.shell().error(message) end)
          CLI.fail("#{length(problems)} specification path(s) do not resolve")

        {:error, message} ->
          CLI.fail(message)
      end
    end

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
