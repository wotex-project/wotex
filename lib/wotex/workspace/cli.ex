defmodule Wotex.Workspace.CLI do
  @moduledoc """
  Option parsing and exit handling shared by the `mix wotex.*` tasks.
  """

  alias Wotex.Workspace.Affected
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

  @doc """
  Parses `args` strictly against `switches` and refuses positional
  arguments.
  """
  @spec parse_options([String.t()], keyword()) :: keyword()
  def parse_options(args, switches) do
    {opts, rest} = parse(args, switches)
    if rest != [], do: Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")
    opts
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

  @doc """
  Selects packages or fails the task with the selection error. `only:
  :changed` keeps the changed packages of the affected set and drops their
  dependents.
  """
  @spec select!(Manifest.t(), keyword(), Affected.mark() | nil) :: [String.t()]
  def select!(%Manifest{} = manifest, opts, only \\ nil) do
    case Selection.select(manifest, [only: only] ++ selection_opts(opts)) do
      {:ok, names} -> names
      {:error, message} -> fail(message)
    end
  end

  @doc "Selects packages with their marks or fails the task."
  @spec classify!(Manifest.t(), keyword()) :: [{String.t(), Affected.mark()}]
  def classify!(%Manifest{} = manifest, opts) do
    case Selection.classify(manifest, selection_opts(opts)) do
      {:ok, marked} -> marked
      {:error, message} -> fail(message)
    end
  end

  @doc "Checks that `name` is a manifest package or fails the task."
  @spec package!(Manifest.t(), String.t()) :: String.t()
  def package!(%Manifest{} = manifest, name) do
    if Manifest.package?(name, manifest),
      do: name,
      else: fail("unknown package #{inspect(name)}; known: #{Enum.join(manifest.order, ", ")}")
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
