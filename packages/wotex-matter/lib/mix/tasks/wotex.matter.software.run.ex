defmodule Mix.Tasks.Wotex.Matter.Software.Run do
  @shortdoc "Runs the owned Matter software-peer acceptance lane"
  @moduledoc """
  Runs the Matter software acceptance suite from a verified explicit workspace.

  Invoke `mix wotex.software.run --workspace /absolute/disposable/workspace`
  after the software build. The runner owns its controller and peer processes,
  finite test budgets, result files and cleanup. A missing fixture, failed
  assertion or unverified cleanup is a task failure.
  """

  use Mix.Task

  @impl Mix.Task
  def run(arguments) do
    unless Mix.Project.config()[:app] == :wotex_matter,
      do: Mix.raise("software_fixture_wrong_project")

    runner = Path.expand("test/support/software/fixture.exs")
    unless File.regular?(runner), do: Mix.raise("software_fixture_source_required")
    Code.require_file(runner)
    fixture = Module.concat([Wotex, Matter, SoftwareFixture])
    apply(fixture, :main, [:run, arguments])
  end
end
