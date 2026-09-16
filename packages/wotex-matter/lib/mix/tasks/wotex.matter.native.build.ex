defmodule Mix.Tasks.Wotex.Matter.Native.Build do
  @shortdoc "Builds the pinned first-party Matter native controller"
  @moduledoc """
  Builds or verifies the first-party Matter controller in an explicit workspace.

  Invoke `mix wotex.native.build --workspace /absolute/disposable/workspace`
  from the Wotex Matter source checkout. The task validates its root project and
  checked-in runner before invoking Docker. Loading the library never invokes
  this task or starts a native process.
  """

  use Mix.Task

  @impl Mix.Task
  def run(arguments) do
    unless Mix.Project.config()[:app] == :wotex_matter,
      do: Mix.raise("software_fixture_wrong_project")

    runner = Path.expand("test/support/software/fixture.exs")
    unless File.regular?(runner), do: Mix.raise("software_fixture_source_required")
    Code.require_file(runner)
    fixture = Module.safe_concat([Wotex, Matter, SoftwareFixture])
    fixture.main(:native_build, arguments)
  end
end
