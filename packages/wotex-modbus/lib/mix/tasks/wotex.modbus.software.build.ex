defmodule Mix.Tasks.Wotex.Modbus.Software.Build do
  @shortdoc "Builds the explicitly owned Modbus software peer"
  @moduledoc """
  Builds or verifies the independent Modbus software fixture in an explicit workspace.

  Invoke `mix wotex.software.build --workspace /absolute/disposable/workspace`
  from the Modbus source checkout. The task loads only the checked-in fixture
  runner and rejects another project's application identity before acquisition.
  Native downloads, compiler invocation and Docker builds occur only through
  this explicit task; loading the dependency starts no fixture process.

  The fixture runner validates pinned source and build manifests and reports a
  nonzero Mix failure for unavailable tooling, changed inputs or failed builds.
  This development task requires the source checkout's `test/interop` assets;
  running a protocol client from an installed package does not require them.
  """

  use Mix.Task

  @impl Mix.Task
  def run(arguments) do
    unless Mix.Project.config()[:app] == :wotex_modbus,
      do: Mix.raise("software_fixture_wrong_project")

    runner = Path.expand("test/support/software/fixture.exs")
    unless File.regular?(runner), do: Mix.raise("software_fixture_source_required")
    Code.require_file(runner)
    implementation = Module.safe_concat([Wotex.Modbus, SoftwareFixture])
    implementation.main(:build, arguments)
  end
end
