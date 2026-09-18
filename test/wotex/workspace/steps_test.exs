defmodule Wotex.Workspace.StepsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Check.Affected, as: CheckAffected
  alias Wotex.Workspace.Report
  alias Wotex.Workspace.Steps
  alias WotexWorkspace.Fixtures

  # Records every command and fails the ones listed in `failing` ({dir, task}).
  defp recording_runner(failing) do
    test = self()

    fn path, [task | _rest] = args, opts ->
      send(test, {:ran, Path.basename(path), args, opts})
      if {Path.basename(path), task} in failing, do: 1, else: 0
    end
  end

  defp ran do
    receive do
      {:ran, dir, args, _opts} -> [{dir, Enum.join(args, " ")} | ran()]
    after
      0 -> []
    end
  end

  test "the fast gate compiles, checks format, runs credo and tests in MIX_ENV=test" do
    assert Enum.map(Steps.fast_gate(), fn {label, args, opts} -> {label, args, opts} end) == [
             {"compile", ["compile", "--warnings-as-errors"], [mix_env: "test"]},
             {"format", ["format", "--check-formatted"], [mix_env: "test"]},
             {"credo", ["credo", "--strict"], [mix_env: "test"]},
             {"test", ["test"], [mix_env: "test"]}
           ]
  end

  test "a target stops at its first failing step and halt stops the run" do
    manifest = Fixtures.manifest()
    targets = Enum.map(~w(core runtime http), &Steps.target(&1, manifest, Steps.fast_gate()))

    {rows, failed?} = Steps.run(targets, runner: recording_runner([{"runtime", "credo"}]))

    assert failed?

    assert Enum.map(rows, &{&1.package, &1.result}) == [
             {"core", "ok"},
             {"runtime", "credo failed (1)"}
           ]

    assert ran() == [
             {"core", "compile --warnings-as-errors"},
             {"core", "format --check-formatted"},
             {"core", "credo --strict"},
             {"core", "test"},
             {"runtime", "compile --warnings-as-errors"},
             {"runtime", "format --check-formatted"},
             {"runtime", "credo --strict"}
           ]
  end

  test "halt: false runs every target and still reports the failure" do
    manifest = Fixtures.manifest()
    step = {"test", ["test"], []}
    targets = Enum.map(~w(core runtime http), &Steps.target(&1, manifest, [step]))

    {rows, failed?} =
      Steps.run(targets, halt: false, runner: recording_runner([{"core", "test"}]))

    assert failed?
    assert Enum.map(rows, & &1.result) == ["test failed (1)", "ok", "ok"]
    assert length(ran()) == 3

    {_rows, failed?} = Steps.run(targets, halt: false, runner: recording_runner([]))
    refute failed?
  end

  test "check.affected runs the full gate for changed and the fast gate for dependents" do
    manifest = Fixtures.manifest()
    targets = CheckAffected.targets([{"runtime", :changed}, {"http", :dependent}], manifest)

    assert Enum.map(targets, &{&1.package, &1.gate}) == [{"runtime", "full"}, {"http", "fast"}]
    assert hd(targets).steps == Steps.full_gate()
    assert List.last(targets).steps == Steps.fast_gate()

    {rows, _failed?} = Steps.run(targets, runner: recording_runner([]))

    assert Report.table(rows, [:package, :gate, :result]) == """
           package | gate | result
           --------+------+-------
           runtime | full | ok
           http    | fast | ok
           """

    assert ran() == [
             {"runtime", "deps.get --check-locked"},
             {"runtime", "check --no-retry"},
             {"http", "compile --warnings-as-errors"},
             {"http", "format --check-formatted"},
             {"http", "credo --strict"},
             {"http", "test"}
           ]
  end

  test "full_gate/1 passes skipped tools to mix check" do
    assert [{"deps.get", _, []}, {"check", ["check", "--no-retry", "--except", "credo"], []}] =
             Steps.full_gate(["credo"])
  end
end
