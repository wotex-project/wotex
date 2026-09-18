defmodule Wotex.Workspace.CLI do
  @moduledoc """
  Option parsing and exit handling shared by the `mix wotex.*` tasks.
  """

  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Selection

  @selection_switches [all: :boolean, package: :keep, base: :string, docs: :boolean]

  @doc "Switches shared by every task that selects packages."
  @spec selection_switches() :: keyword()
  def selection_switches, do: @selection_switches

  @doc """
  Parses `args` strictly against `switches`. Unknown switches raise a
  `Mix.Error` with the offending option.
  """
  @spec parse([String.t()], keyword()) :: {keyword(), [String.t()]}
  def parse(args, switches) do
    OptionParser.parse!(args, strict: switches)
  rescue
    error in OptionParser.ParseError -> Mix.raise(Exception.message(error))
  end

  @doc "Turns parsed options into `Wotex.Workspace.Selection` options."
  @spec selection_opts(keyword()) :: keyword()
  def selection_opts(opts) do
    [
      all: Keyword.get(opts, :all, false),
      packages: Keyword.get_values(opts, :package),
      base: Keyword.get(opts, :base),
      docs: Keyword.get(opts, :docs, false)
    ]
  end

  @doc "Selects packages or fails the task with the selection error."
  @spec select!(Manifest.t(), keyword()) :: [String.t()]
  def select!(%Manifest{} = manifest, opts) do
    case Selection.select(manifest, selection_opts(opts)) do
      {:ok, names} -> names
      {:error, message} -> fail(message)
    end
  end

  @doc "Prints `message` as an error and exits with status 1."
  @spec fail(String.t()) :: no_return()
  def fail(message) do
    Mix.shell().error(message)
    exit({:shutdown, 1})
  end

  @doc "Runs `fun` and returns its result with the elapsed seconds."
  @spec timed((-> result)) :: {result, float()} when result: term()
  def timed(fun) do
    started = System.monotonic_time(:millisecond)
    result = fun.()
    {result, (System.monotonic_time(:millisecond) - started) / 1000}
  end
end
