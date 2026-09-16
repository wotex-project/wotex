defmodule Mix.Tasks.Wotex.Coap.Native.Build do
  @shortdoc "Builds the explicitly owned pinned CoAP OSCORE executable"

  @moduledoc """
  Builds the pinned CoAP OSCORE executable in an explicit disposable workspace.

  Invoke `mix wotex.coap.native.build --workspace ABSOLUTE_PATH`; this repository
  also supplies the root-project alias `mix wotex.native.build`. The qualified
  task module remains unique when several Wotex protocol packages are compiled.
  """

  use Mix.Task

  alias Wotex.CoAP.Native.Build

  @doc "Runs the native build and prints its verified executable and manifest paths."
  @spec run([String.t()]) :: :ok
  @impl Mix.Task
  def run(arguments), do: execute(arguments, Build)

  @doc false
  @spec execute(term(), module()) :: :ok
  def execute(arguments, build_module) do
    case Build.arguments(arguments) do
      {:ok, workspace} -> build(workspace, build_module)
      {:error, _} -> Mix.raise("usage: mix wotex.coap.native.build --workspace ABSOLUTE_PATH")
    end
  end

  defp build(workspace, build_module) do
    case build_module.run(workspace) do
      {:ok, result} ->
        state = if result.reused, do: "verified", else: "completed"
        Mix.shell().info("Native build #{state}: #{workspace}")
        Mix.shell().info("Executable: #{Path.join(workspace, "bin/wotex-coap-oscore")}")
        Mix.shell().info("Manifest: #{Path.join(workspace, "native-manifest.json")}")
        :ok

      {:error, reason} ->
        Mix.raise("CoAP native build failed: #{inspect(reason)}")
    end
  end
end
