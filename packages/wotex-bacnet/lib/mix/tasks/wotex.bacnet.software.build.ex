defmodule Mix.Tasks.Wotex.Bacnet.Software.Build do
  @shortdoc "Builds the explicitly owned BACnet software peer"
  @moduledoc """
  Builds or verifies the independent BACnet software fixture in an explicit workspace.

  Invoke `mix pkg wotex-bacnet wotex.bacnet.software.build --workspace /absolute/disposable/workspace`
  from the repository root, or `mix wotex.bacnet.software.build` inside
  `packages/wotex-bacnet` with `WOTEX_PATH_DEPS=1`; the package also defines the
  alias `mix wotex.software.build`. The task loads only the checked-in fixture
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
    unless Mix.Project.config()[:app] == :wotex_bacnet,
      do: Mix.raise("software_fixture_wrong_project")

    runner = Path.expand("test/support/software/fixture.exs")
    unless File.regular?(runner), do: Mix.raise("software_fixture_source_required")
    Code.require_file(runner)
    implementation = Module.safe_concat([Wotex.BACnet, SoftwareFixture])
    implementation.main(:build, arguments)
  end
end
