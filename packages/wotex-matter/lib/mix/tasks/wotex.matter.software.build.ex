defmodule Mix.Tasks.Wotex.Matter.Software.Build do
  @shortdoc "Builds the pinned Matter controller and software peers"
  @moduledoc """
  Builds or verifies the Matter software fixture in an explicit workspace.

  Invoke `mix wotex.matter.software.build --workspace /absolute/disposable/workspace`
  inside `packages/wotex-matter` (alias `mix wotex.software.build`); from the
  repository root run
  `mix pkg wotex-matter wotex.software.build --workspace /absolute/disposable/workspace`.
  The task builds the first-party native controller and the pinned Linux no-BLE
  lighting, all-clusters and bridge peers. Missing tools, changed inputs and
  incomplete workspaces are task failures.
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
    fixture.main(:software_build, arguments)
  end
end
