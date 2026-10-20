defmodule Mix.Tasks.Wotex.Ble.Corebluetooth.Build do
  @shortdoc "Builds the native macOS CoreBluetooth host and guardian"
  @moduledoc """
  Builds the CoreBluetooth process in an explicit disposable workspace.

  Invoke `mix wotex.ble.corebluetooth.build --workspace ABSOLUTE_PATH` on macOS.
  No Bluetooth permission request or peripheral operation occurs during the build.
  Matching workspaces are verified read-only. See `Wotex.BLE.CoreBluetooth.Build`.
  """

  use Mix.Task

  alias Wotex.BLE.CoreBluetooth.Build

  @impl Mix.Task
  @doc "Builds or verifies the explicit workspace and reports its manifest."
  @spec run([String.t()]) :: :ok
  def run(args) do
    with {:ok, workspace} <- Build.arguments(args), {:ok, result} <- Build.run(workspace) do
      Mix.shell().info(
        "CoreBluetooth build #{if result.reused, do: "verified", else: "completed"}: #{workspace}"
      )

      Mix.shell().info("Manifest: #{Path.join(workspace, "native-manifest.json")}")
      :ok
    else
      {:error, reason} -> Mix.raise("CoreBluetooth build failed: #{inspect(reason)}")
    end
  end
end
