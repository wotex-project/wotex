defmodule Mix.Tasks.Wotex.Dialyzer do
  @shortdoc "Runs Dialyzer for one package"

  @moduledoc """
  Runs `mix dialyzer` inside `packages/NAME` with `WOTEX_PATH_DEPS=1`. The
  package keeps its own PLT: in `priv/plts` where its `mix.exs` sets
  `plt_file`, otherwise under its `_build`. Further arguments are passed to
  `mix dialyzer`. The root alias is `mix dialyzer.pkg`.

      mix wotex.dialyzer NAME [ARGS...]

  Dialyzer is explicit: run it when a typespec or an inferred type changed
  (the full gate runs it for changed packages).
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Runner

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {name, extra} = parse_args(args)
    manifest = Manifest.load!()
    CLI.package!(manifest, name)

    case Runner.run(Manifest.absolute_path(name, manifest), ["dialyzer" | extra]) do
      0 -> :ok
      status -> CLI.fail("packages/#{name}: mix dialyzer exited with #{status}")
    end
  end

  @doc "Splits the package name from the extra Dialyzer arguments."
  @spec parse_args([String.t()]) :: {String.t(), [String.t()]}
  def parse_args([name | extra]) do
    if String.starts_with?(name, "-"), do: Mix.raise("usage: mix dialyzer.pkg NAME [ARGS...]")
    {name, extra}
  end

  def parse_args([]), do: Mix.raise("usage: mix dialyzer.pkg NAME [ARGS...]")
end
