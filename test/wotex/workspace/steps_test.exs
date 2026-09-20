defmodule Wotex.Workspace.StepsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Check.Affected, as: CheckAffected
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.Manifest.Host
  alias Wotex.Workspace.Manifest.Package
  alias Wotex.Workspace.Report
  alias Wotex.Workspace.Steps
  alias WotexWorkspace.Fixtures

  # Records every command and fails the ones listed in `failing` ({dir, task}).
  defp recording_runner(failing) do
    test = self()

    fn path, [task | _] = args, opts ->
      send(test, {:ran, Path.basename(path), args, opts})
      if {Path.basename(path), task} in failing, do: 1, else: 0
    end
  end

  defp ran do
    receive do
      {:ran, dir, args, _} -> [{dir, Enum.join(args, " ")} | ran()]
    after
      0 -> []
    end
  end

  # The directory (`cd:`), arguments and extra environment of every command.
  defp received do
    receive do
      {:ran_in, cd, args, env} -> [{cd, args, env} | received()]
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

  test "the fast gate of a native package ends with native.lint in the root" do
    package = %Package{name: "coap", app: "coap", native: true}
    gate = Steps.fast_gate(package)
    assert Enum.drop(gate, -1) == Steps.fast_gate()

    assert List.last(gate) ==
             {"native", ["native.lint", "--package", "coap"],
              [cd: Wotex.Workspace.root(), path_deps: false]}

    assert Steps.fast_gate(%{package | native: false}) == Steps.fast_gate()
  end

  test "the fast gate of a package with hosts repeats the Mix steps in each host" do
    host = %Host{path: "hosts/nerves", env: [{"MIX_TARGET", "host"}]}

    package = %Package{
      name: "lab",
      app: "lab",
      native: true,
      hosts: [%Host{path: "hosts/workbench"}, %Host{path: "hosts/storybook"}, host]
    }

    gate = Steps.fast_gate(package)
    {package_steps, host_steps} = Enum.split(gate, 5)
    assert package_steps == Steps.fast_gate(%{package | hosts: []})
    assert List.last(package_steps) == Steps.native_step("lab")

    assert host_steps == [
             {"hosts/workbench compile", ["compile", "--warnings-as-errors"],
              [mix_env: "test", cd: "hosts/workbench", env: []]},
             {"hosts/workbench format", ["format", "--check-formatted"],
              [mix_env: "test", cd: "hosts/workbench", env: []]},
             {"hosts/workbench credo", ["credo", "--strict"],
              [mix_env: "test", cd: "hosts/workbench", env: []]},
             {"hosts/workbench test", ["test"], [mix_env: "test", cd: "hosts/workbench", env: []]},
             {"hosts/storybook compile", ["compile", "--warnings-as-errors"],
              [mix_env: "test", cd: "hosts/storybook", env: []]},
             {"hosts/storybook format", ["format", "--check-formatted"],
              [mix_env: "test", cd: "hosts/storybook", env: []]},
             {"hosts/storybook credo", ["credo", "--strict"],
              [mix_env: "test", cd: "hosts/storybook", env: []]},
             {"hosts/storybook test", ["test"], [mix_env: "test", cd: "hosts/storybook", env: []]},
             {"hosts/nerves compile", ["compile", "--warnings-as-errors"],
              [mix_env: "test", cd: "hosts/nerves", env: [{"MIX_TARGET", "host"}]]},
             {"hosts/nerves format", ["format", "--check-formatted"],
              [mix_env: "test", cd: "hosts/nerves", env: [{"MIX_TARGET", "host"}]]},
             {"hosts/nerves credo", ["credo", "--strict"],
              [mix_env: "test", cd: "hosts/nerves", env: [{"MIX_TARGET", "host"}]]},
             {"hosts/nerves test", ["test"],
              [mix_env: "test", cd: "hosts/nerves", env: [{"MIX_TARGET", "host"}]]}
           ]

    assert Steps.host_steps(nil, Steps.fast_gate()) == []
    assert Steps.host_steps(%{package | hosts: []}, Steps.fast_gate()) == []
  end

  test "a failing host step names the host and stops the package's target" do
    manifest = Fixtures.manifest()

    package = %{
      Manifest.fetch!("http", manifest)
      | hosts: [%Host{path: "hosts/demo", env: [{"X", "1"}]}]
    }

    test = self()

    runner = fn _, args, opts ->
      send(test, {:ran_in, opts[:cd], args, opts[:env]})
      if args == ["credo", "--strict"] and opts[:cd] == "hosts/demo", do: 1, else: 0
    end

    target = Steps.target("http", manifest, Steps.fast_gate(package))

    assert {[%{package: "http", result: "hosts/demo credo failed (1)"}], true} =
             Steps.run([target], runner: runner)

    assert [
             {nil, ["compile", "--warnings-as-errors"], nil},
             {nil, ["format", "--check-formatted"], nil},
             {nil, ["credo", "--strict"], nil},
             {nil, ["test"], nil},
             {"hosts/demo", ["compile", "--warnings-as-errors"], [{"X", "1"}]},
             {"hosts/demo", ["format", "--check-formatted"], [{"X", "1"}]},
             {"hosts/demo", ["credo", "--strict"], [{"X", "1"}]}
           ] == received()
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

    {_, failed?} = Steps.run(targets, halt: false, runner: recording_runner([]))
    refute failed?
  end

  test "check.affected runs the full gate for changed and the fast gate for dependents" do
    manifest = Fixtures.manifest()
    targets = CheckAffected.targets([{"runtime", :changed}, {"http", :dependent}], manifest)

    assert Enum.map(targets, &{&1.package, &1.gate}) == [{"runtime", "full"}, {"http", "fast"}]
    assert hd(targets).steps == Steps.full_gate()
    assert List.last(targets).steps == Steps.fast_gate()

    {rows, _} = Steps.run(targets, runner: recording_runner([]))

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
