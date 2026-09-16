defmodule Mix.Tasks.Wotex.Coap.Software.Build do
  @shortdoc "Builds the pinned CoAP native helper and software peer"

  @moduledoc """
  Builds the manifest-bound native helper and pinned upstream software peer.

  Invoke `mix wotex.coap.software.build --workspace ABSOLUTE_PATH`; the root
  project alias is `mix wotex.software.build`.
  """

  use Mix.Task

  alias Wotex.CoAP.Native.Build, as: NativeBuild
  alias Wotex.CoAP.Software.Build

  @doc "Runs the explicit software build and prints its peer and manifest paths."
  @spec run([String.t()]) :: :ok
  @impl Mix.Task
  def run(arguments), do: execute(arguments, Build)

  @doc false
  @spec execute(term(), module()) :: :ok
  def execute(arguments, build_module) do
    case NativeBuild.arguments(arguments) do
      {:ok, workspace} -> build(workspace, build_module)
      {:error, _} -> Mix.raise("usage: mix wotex.coap.software.build --workspace ABSOLUTE_PATH")
    end
  end

  defp build(workspace, build_module) do
    case build_module.run(workspace) do
      {:ok, result} ->
        state = if result.reused, do: "verified", else: "completed"
        Mix.shell().info("Software build #{state}: #{workspace}")

        Mix.shell().info(
          "Native executable: #{Path.join(workspace, "native/bin/wotex-coap-oscore")}"
        )

        Mix.shell().info("Peer executable: #{Path.join(workspace, "bin/coap-server")}")
        Mix.shell().info("Manifest: #{Path.join(workspace, "native-manifest.json")}")
        :ok

      {:error, reason} ->
        Mix.raise("CoAP software build failed: #{inspect(reason)}")
    end
  end
end
