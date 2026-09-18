defmodule Mix.Tasks.Wotex.Modbus.Software.Run do
  @shortdoc "Runs the owned Modbus software fixture and records evidence"
  @moduledoc """
  Runs the Modbus software acceptance suite against its verified native peer.

  Invoke `mix pkg wotex-modbus wotex.modbus.software.run --workspace
  /absolute/disposable/workspace` from the repository root, or
  `mix wotex.modbus.software.run` inside `packages/wotex-modbus` with
  `WOTEX_PATH_DEPS=1`, after the explicit fixture build; the package also
  defines the alias `mix wotex.software.run`. The runner
  owns the disposable peer, test process, finite command budgets and evidence
  directory. Missing fixtures and cleanup failures are task failures.

  The task requires checked-in test sources and a matching ready manifest. It
  does not select an ambient device, publish evidence, or alter Git state.
  Library clients and ordinary dependency loading never invoke this task.
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
    implementation.main(:run, arguments)
  end
end
