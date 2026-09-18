defmodule Mix.Tasks.Wotex.Ble.Software.Run do
  @shortdoc "Runs the BlueZ virtual-controller software lanes"

  @moduledoc """
  Runs both BEAM software lanes from a built fixture workspace.

  Invoke `mix wotex.ble.software.run --workspace ABSOLUTE_PATH` from
  `packages/wotex-ble` in a repository checkout; the package also defines the
  alias `mix wotex.software.run`. The task accepts exactly one absolute workspace
  and runs only when explicitly invoked. See `Wotex.BLE.Software.Run` for
  its inputs, bounds and evidence contract.
  """

  use Mix.Task

  alias Wotex.BLE.Software.Run

  @doc "Runs the explicit software run task and reports its evidence path."
  @spec run([String.t()]) :: :ok
  @impl Mix.Task
  def run(args), do: run(args, File.cwd!(), Wotex.BLE.Software.Operations)

  @doc false
  @spec run([String.t()], String.t(), module()) :: :ok
  def run(args, root, operations) do
    case Run.arguments(args) do
      {:ok, workspace} -> report(workspace, Run.run(workspace, root, operations))
      {:error, _} -> Mix.raise("usage: mix wotex.ble.software.run --workspace ABSOLUTE_PATH")
    end
  end

  defp report(_, {:ok, result}) do
    Mix.shell().info("Software run passed: #{Path.join(result["directory"], "result.json")}")
  end

  defp report(_, {:error, reason}), do: Mix.raise("BLE software run failed: #{inspect(reason)}")
end
