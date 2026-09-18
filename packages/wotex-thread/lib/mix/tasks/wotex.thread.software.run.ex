defmodule Mix.Tasks.Wotex.Thread.Software.Run do
  @shortdoc "Runs the Thread software acceptance lanes"

  @moduledoc """
  Runs the Thread software acceptance lanes against a verified fixture workspace.

  Invoke `mix wotex.thread.software.run --workspace ABSOLUTE_PATH`, or use the
  package alias `mix wotex.software.run --workspace ABSOLUTE_PATH`, after
  `mix wotex.software.build` completed that workspace. The task requires Linux,
  never builds, and writes `software-run/result.json` on success or failure.
  """

  use Mix.Task
  alias Wotex.Thread.Software.Run

  @doc "Runs the explicit software lanes and reports the result path."
  @spec run([String.t()], Run.environment()) :: :ok
  @impl Mix.Task
  def run(args, environment \\ Run.environment()) do
    unless Mix.Project.config()[:app] == :wotex_thread,
      do: Mix.raise("Thread software run requires its root project")

    case Run.arguments(args) do
      {:ok, workspace} ->
        case Run.run(workspace, environment) do
          {:ok, %{path: path}} ->
            Mix.shell().info("Software run passed: #{path}")

          {:error, reason} ->
            Mix.raise("Thread software run failed: #{inspect(reason)}")
        end

      {:error, _} ->
        Mix.raise("usage: mix wotex.thread.software.run --workspace ABSOLUTE_PATH")
    end
  end
end
