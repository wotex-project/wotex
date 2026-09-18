defmodule Mix.Tasks.Wotex.Opcua.Software.Run do
  @shortdoc "Runs the OPC UA software acceptance lanes from a verified workspace"

  @moduledoc """
  Runs the interop, software stress, CTest, sanitizer and audit lanes.

  Invoke `mix wotex.opcua.software.run --workspace ABSOLUTE_PATH` after
  `mix wotex.opcua.software.build`; the package project also supplies the alias
  `mix wotex.software.run`. See `Wotex.OPCUA.Native.Software.run/2` for the
  lanes, the peer lifecycle and the recorded report. Any failed lane fails the
  task.
  """

  use Mix.Task

  alias Wotex.OPCUA.Native.Software

  @doc "Runs every software lane and reports the run report path."
  @spec run([String.t()]) :: :ok
  @impl Mix.Task
  def run(["--workspace", workspace]) do
    Mix.Task.run("compile")

    case Software.run(workspace) do
      {:ok, _} ->
        Mix.shell().info("Software lanes passed: #{Path.join(workspace, "software-run.json")}")

      {:error, reason} ->
        Mix.raise("OPC UA software run failed: #{inspect(reason)}")
    end
  end

  def run(_), do: Mix.raise("usage: mix wotex.opcua.software.run --workspace ABSOLUTE_PATH")
end
