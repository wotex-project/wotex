defmodule Mix.Tasks.Wotex.Opcua.Software.Run do
  @shortdoc "Runs the OPC UA software acceptance lanes from a verified workspace"

  @moduledoc """
  Runs the interop, software stress, CTest, sanitizer and audit lanes.

  Invoke

      mix wotex.opcua.software.run --workspace ABSOLUTE_PATH \\
        --core-archive ABSOLUTE_WOTEX_TAR --runtime-archive ABSOLUTE_WOTEX_RUNTIME_TAR

  after `mix wotex.opcua.software.build`; the package project also supplies the
  alias `mix wotex.software.run`. The two archives are the exact `wotex` and
  `wotex_runtime` packages the archive consumer lane depends on. See
  `Wotex.OPCUA.Native.Software.run/2` for the lanes, the peer lifecycle and the
  recorded report. Any failed lane fails the task.
  """

  use Mix.Task

  alias Wotex.OPCUA.Native.Software

  @doc "Runs every software lane and reports the run report path."
  @spec run([String.t()]) :: :ok
  @impl Mix.Task
  def run(arguments) do
    {options, rest, invalid} =
      OptionParser.parse(arguments,
        strict: [workspace: :string, core_archive: :string, runtime_archive: :string]
      )

    with [] <- rest ++ invalid,
         [core_archive: core, runtime_archive: runtime, workspace: workspace] <-
           Enum.sort(options) do
      Mix.Task.run("compile")
      report(workspace, Software.run(workspace, archives: %{core: core, runtime: runtime}))
    else
      _ -> usage()
    end
  end

  defp report(workspace, result) do
    case result do
      {:ok, _} ->
        Mix.shell().info("Software lanes passed: #{Path.join(workspace, "software-run.json")}")

      {:error, reason} ->
        Mix.raise("OPC UA software run failed: #{inspect(reason)}")
    end
  end

  @spec usage() :: no_return()
  defp usage do
    Mix.raise(
      "usage: mix wotex.opcua.software.run --workspace ABSOLUTE_PATH " <>
        "--core-archive ABSOLUTE_WOTEX_TAR --runtime-archive ABSOLUTE_WOTEX_RUNTIME_TAR"
    )
  end
end
