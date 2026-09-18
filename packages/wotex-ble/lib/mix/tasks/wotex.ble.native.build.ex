defmodule Mix.Tasks.Wotex.Ble.Native.Build do
  @shortdoc "Builds the pinned native BlueZ SDK host in an explicit workspace"

  @moduledoc """
  Builds the first-party native BlueZ SDK host in a disposable workspace.

  Invoke `mix wotex.ble.native.build --workspace ABSOLUTE_PATH`. The package
  also defines the alias `mix wotex.native.build`. The qualified
  task name stays unique when a consumer compiles several Wotex protocol
  packages. The task accepts exactly one absolute `--workspace` argument and
  runs only when explicitly invoked. A completed matching workspace is verified
  read-only; unrelated, locked or incomplete directories fail without repair.
  See `Wotex.BLE.Native.Build` for the source, toolchain and audit contract.
  """

  use Mix.Task

  alias Wotex.BLE.Native.Build

  @doc "Runs the explicit native build and reports the manifest and executable paths."
  @spec run([String.t()]) :: :ok
  @impl Mix.Task
  def run(args), do: run(args, Wotex.BLE.Native.BuildOperations)

  @doc false
  @spec run([String.t()], module()) :: :ok
  def run(args, operations) do
    case Build.arguments(args) do
      {:ok, workspace} ->
        case Build.run(workspace, operations) do
          {:ok, result} ->
            status = if result.reused, do: "verified", else: "completed"
            Mix.shell().info("Native build #{status}: #{workspace}")
            Mix.shell().info("Manifest: #{Path.join(workspace, "native-manifest.json")}")
            Mix.shell().info("Host: #{Path.join(workspace, "output/bin/wotex-ble-host")}")
            Mix.shell().info("Guardian: #{Path.join(workspace, "output/bin/wotex-ble-guardian")}")

          {:error, reason} ->
            Mix.raise("BLE native build failed: #{inspect(reason)}")
        end

      {:error, _} ->
        Mix.raise("usage: mix wotex.ble.native.build --workspace ABSOLUTE_PATH")
    end
  end
end
