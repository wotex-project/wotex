defmodule Mix.Tasks.Wotex.Ble.Software.Build do
  @shortdoc "Builds the BlueZ virtual-controller software fixture"

  @moduledoc """
  Builds the explicit BlueZ virtual-controller software fixture.

  Invoke `mix wotex.ble.software.build --workspace ABSOLUTE_PATH` from
  `packages/wotex-ble` in a repository checkout; the package also defines the
  alias `mix wotex.software.build`. The task accepts exactly one absolute workspace
  and runs only when explicitly invoked. See `Wotex.BLE.Software.Build` for
  its inputs, bounds and evidence contract.
  """

  use Mix.Task

  alias Wotex.BLE.Software.Build

  @doc "Runs the explicit software build task and reports its evidence path."
  @spec run([String.t()]) :: :ok
  @impl Mix.Task
  def run(args), do: run(args, File.cwd!(), Wotex.BLE.Software.Operations)

  @doc false
  @spec run([String.t()], String.t(), module()) :: :ok
  def run(args, root, operations) do
    case Build.arguments(args) do
      {:ok, workspace} -> report(workspace, Build.run(workspace, root, operations))
      {:error, _} -> Mix.raise("usage: mix wotex.ble.software.build --workspace ABSOLUTE_PATH")
    end
  end

  defp report(workspace, {:ok, result}) do
    status = if result.reused, do: "verified", else: "completed"
    Mix.shell().info("Software build #{status}: #{workspace}")
    Mix.shell().info("Manifest: #{Path.join(workspace, "software-manifest.json")}")
  end

  defp report(_, {:error, reason}), do: Mix.raise("BLE software build failed: #{inspect(reason)}")
end
