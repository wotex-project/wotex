defmodule Mix.Tasks.Wotex.Thread.Software.Build do
  @shortdoc "Builds the manifest-bound Thread software fixtures"

  @moduledoc """
  Builds or verifies the Thread software fixtures in an explicit disposable workspace.

  Invoke `mix wotex.thread.software.build --workspace ABSOLUTE_PATH`, or use the
  root-project alias `mix wotex.software.build --workspace ABSOLUTE_PATH`. The
  task requires Linux and the repository test sources. It builds normal and
  sanitizer native hosts, the pinned simulation RCP and native test executables.
  No build, download or fixture starts while loading the library.
  """

  use Mix.Task
  alias Wotex.Thread.Software.Build

  @doc "Runs the explicit software fixture build and reports its manifest."
  @spec run([String.t()], Build.environment()) :: :ok
  @impl Mix.Task
  def run(args, environment \\ Build.environment()) do
    unless Mix.Project.config()[:app] == :wotex_thread,
      do: Mix.raise("Thread software build requires its root project")

    case Build.arguments(args) do
      {:ok, workspace} ->
        case Build.run(workspace, environment) do
          {:ok, result} ->
            Mix.shell().info(
              "Software build #{if(result.reused, do: "verified", else: "completed")}: #{workspace}"
            )

            Mix.shell().info("Manifest: #{Path.join(workspace, "software-manifest.json")}")

          {:error, reason} ->
            Mix.raise("Thread software build failed: #{inspect(reason)}")
        end

      {:error, _} ->
        Mix.raise("usage: mix wotex.thread.software.build --workspace ABSOLUTE_PATH")
    end
  end
end
