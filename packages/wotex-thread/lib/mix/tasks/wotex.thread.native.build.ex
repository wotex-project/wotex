defmodule Mix.Tasks.Wotex.Thread.Native.Build do
  @shortdoc "Builds the pinned first-party Thread native host"

  @moduledoc """
  Builds or verifies the Thread native host in an explicit disposable workspace.

  Invoke `mix wotex.thread.native.build --workspace ABSOLUTE_PATH`, or use the
  root-project alias `mix wotex.native.build --workspace ABSOLUTE_PATH`. An optional
  `--sanitizers` enables address and undefined-behavior instrumentation.
  No build or download occurs while loading the library.
  """

  use Mix.Task
  alias Wotex.Thread.Native.{Build, Workspace}

  @doc "Runs the explicit native build and reports its verified executable."
  @spec run([String.t()], Build.environment()) :: :ok
  @impl Mix.Task
  def run(args, environment \\ Build.environment()) do
    unless Mix.Project.config()[:app] == :wotex_thread,
      do: Mix.raise("Thread native build requires its root project")

    case Workspace.arguments(args) do
      {:ok, workspace, sanitizers} ->
        case Build.run(workspace, sanitizers, environment) do
          {:ok, result} ->
            Mix.shell().info(
              "Native build #{if(result.reused, do: "verified", else: "completed")}: #{workspace}"
            )

            Mix.shell().info("Executable: #{Path.join(workspace, "build/wotex-thread-host")}")
            Mix.shell().info("Manifest: #{Path.join(workspace, "native-manifest.json")}")

          {:error, reason} ->
            Mix.raise("Thread native build failed: #{inspect(reason)}")
        end

      {:error, _} ->
        Mix.raise("usage: mix wotex.thread.native.build --workspace ABSOLUTE_PATH [--sanitizers]")
    end
  end
end
