defmodule Mix.Tasks.Wotex.Opcua.Software.Build do
  @shortdoc "Builds the OPC UA software acceptance lanes into an explicit workspace"

  @moduledoc """
  Builds the native, sanitizer and independent-peer lanes from a source checkout.

  Invoke `mix wotex.opcua.software.build --workspace ABSOLUTE_PATH` from the
  repository root; the root project also supplies `mix wotex.software.build`.
  The workspace must be new or empty. See `Wotex.OPCUA.Native.Software.build/2`
  for the recorded manifest. A package consumer without the checkout's test
  fixtures receives `software_fixtures_unavailable`.
  """

  use Mix.Task

  alias Wotex.OPCUA.Native.Software

  @doc "Builds the software lanes and reports the manifest path."
  @spec run([String.t()]) :: :ok
  @impl Mix.Task
  def run(["--workspace", workspace]) do
    Mix.Task.run("compile")

    case Software.build(workspace) do
      {:ok, _} ->
        Mix.shell().info("Software build completed: #{Path.join(workspace, "software-build.json")}")

      {:error, reason} ->
        Mix.raise("OPC UA software build failed: #{inspect(reason)}")
    end
  end

  def run(_), do: Mix.raise("usage: mix wotex.opcua.software.build --workspace ABSOLUTE_PATH")
end
