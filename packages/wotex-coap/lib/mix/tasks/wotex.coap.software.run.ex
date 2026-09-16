defmodule Mix.Tasks.Wotex.Coap.Software.Run do
  @shortdoc "Runs the manifest-bound CoAP software interop suite"

  @moduledoc """
  Verifies a completed software-build workspace and runs the owned interop suite.

  Invoke `mix wotex.coap.software.run --workspace ABSOLUTE_PATH`; the root
  project alias is `mix wotex.software.run`.
  """

  use Mix.Task

  alias Wotex.CoAP.Native.Build
  alias Wotex.CoAP.Software.Run

  @doc "Runs the explicit software suite and prints its retained result path."
  @spec run([String.t()]) :: :ok
  @impl Mix.Task
  def run(arguments), do: execute(arguments, Run)

  @doc false
  @spec execute(term(), module()) :: :ok
  def execute(arguments, run_module) do
    case Build.arguments(arguments) do
      {:ok, workspace} -> execute_run(workspace, run_module)
      {:error, _} -> Mix.raise("usage: mix wotex.coap.software.run --workspace ABSOLUTE_PATH")
    end
  end

  defp execute_run(workspace, run_module) do
    case run_module.run(workspace) do
      {:ok, %{path: path}} ->
        Mix.shell().info("Software suite passed: #{path}")
        :ok

      {:error, {:software_suite_failed, path, reason}} ->
        Mix.raise("CoAP software suite failed (#{reason}); inspect #{path}")

      {:error, reason} ->
        Mix.raise("CoAP software run failed: #{inspect(reason)}")
    end
  end
end
