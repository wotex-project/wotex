defmodule Mix.Tasks.Wotex.Pkg do
  @shortdoc "Runs a Mix task inside one package directory"

  @moduledoc """
  Runs `mix ARGS...` inside `packages/NAME` with `WOTEX_PATH_DEPS=1`, in a
  separate OS process, and exits with its status. The root alias is
  `mix pkg`.

      mix wotex.pkg NAME ARGS...

  Examples:

      mix pkg wotex-coap test test/wotex/coap/blockwise_test.exs
      mix pkg wotex-runtime test --stale
      mix pkg wotex credo --strict

  Every argument after `NAME` is passed through unparsed. `MIX_ENV` is
  inherited; Mix picks the task's preferred environment (`test` for `mix
  test`) when it is unset.
  """

  use Mix.Task

  alias Wotex.Workspace.CLI
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Runner

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {name, command} = parse_args(args)
    manifest = Manifest.load!()
    CLI.package!(manifest, name)

    case Runner.run(Manifest.absolute_path(name, manifest), command) do
      0 -> :ok
      status -> CLI.fail("packages/#{name}: mix #{Enum.join(command, " ")} exited with #{status}")
    end
  end

  @doc "Splits the arguments into the package name and the Mix command."
  @spec parse_args([String.t()]) :: {String.t(), [String.t()]}
  def parse_args([name, task | rest]) when name != "" do
    if String.starts_with?(name, "-"), do: usage!()
    {name, [task | rest]}
  end

  def parse_args(_args), do: usage!()

  @spec usage!() :: no_return()
  defp usage!, do: Mix.raise("usage: mix pkg NAME TASK [ARGS...]")
end
