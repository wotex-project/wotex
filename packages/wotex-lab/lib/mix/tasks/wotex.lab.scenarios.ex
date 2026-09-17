defmodule Mix.Tasks.Wotex.Lab.Scenarios do
  @shortdoc "Prints the admitted Lab scenario descriptors as JSON"

  @moduledoc """
  Prints the admitted scenario descriptors as JSON on standard output.

      mix wotex.lab.scenarios
      mix wotex.lab.scenarios smart-room

  Without an argument the task prints `{"scenarios": [...]}`, the same document
  the MCP `wotex-lab://scenarios` resource and the Workbench control API
  return. With one scenario identifier it prints that descriptor alone. Both
  read `Wotex.Lab.Scenario.admitted/0`. The task compiles the project, reads
  inert data and starts no Lab process, network client or engine. An unknown or
  malformed identifier, or any other argument shape, raises a `Mix.Error`
  naming the stable error code.
  """

  use Mix.Task

  alias Wotex.Lab.Scenario

  @requirements ["compile"]

  @impl Mix.Task
  def run([]),
    do: print(%{"scenarios" => Enum.map(Scenario.admitted(), &Scenario.to_map/1)})

  def run([id]) do
    case Scenario.fetch_admitted(id) do
      {:ok, scenario} -> print(Scenario.to_map(scenario))
      {:error, error} -> Mix.raise("#{error.code}: #{error.message}")
    end
  end

  def run(_), do: Mix.raise("usage: mix wotex.lab.scenarios [SCENARIO_ID]")

  defp print(map) do
    {:ok, json} = Wotex.JSON.encode(map)
    Mix.shell().info(json)
  end
end
