defmodule Mix.Tasks.Wotex.Opcua.Native.Build do
  @shortdoc "Builds the explicitly owned pinned OPC UA native executable"

  @moduledoc """
  Builds the pinned OPC UA native executable in an explicit disposable workspace.

  Invoke `mix wotex.opcua.native.build --workspace ABSOLUTE_PATH`; this repository
  also supplies the root-project alias `mix wotex.native.build`. The qualified
  task module is unique to this dependency so a consumer can compile multiple
  Wotex protocol packages without Mix task module conflicts.

  The task downloads only reviewed archives, verifies source and tool identities,
  runs bounded commands and writes a content-bound completion receipt. An existing
  complete workspace is reusable only after fresh artifact and tool-version
  verification. Invalid arguments and unrelated directories fail without repair.
  Build completion does not imply native Session or interoperability acceptance.
  """

  use Mix.Task

  alias Wotex.OPCUA.Native.Build

  @doc "Runs the explicit native build and reports its executable and receipt paths."
  @spec run([String.t()]) :: :ok
  @impl Mix.Task
  def run(args) do
    case Build.arguments(args) do
      {:ok, workspace} ->
        case Build.run(workspace) do
          {:ok, result} ->
            Mix.shell().info(
              "Native build #{if result.reused, do: "verified", else: "completed"}: #{workspace}"
            )

            Mix.shell().info("Executable: #{Path.join(workspace, "output/bin/wotex_opcua_native")}")
            Mix.shell().info("Receipt: #{Path.join(workspace, "wotex-native-build.json")}")

          {:error, reason} ->
            Mix.raise("OPC UA native build failed: #{inspect(reason)}")
        end

      {:error, _} ->
        Mix.raise("usage: mix wotex.opcua.native.build --workspace ABSOLUTE_PATH")
    end
  end
end
