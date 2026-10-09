defmodule Wotex.Workspace.GovernanceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace

  setup do
    root = Path.join(System.tmp_dir!(), "wotex-governance-#{System.unique_integer([:positive])}")
    tools = Path.join(root, "tools")
    File.mkdir_p!(tools)
    File.mkdir_p!(Path.join(root, "packages/example"))
    File.cp!(Path.join(Workspace.root(), "LICENSE"), Path.join(root, "LICENSE"))
    File.cp!(Path.join(root, "LICENSE"), Path.join(root, "packages/example/LICENSE"))
    git = Path.join(tools, "git")

    File.write!(git, """
    #!/bin/sh
    test "$1" = ls-files && test "$2" = packages || exit 1
    cat "$WOTEX_GOVERNANCE_FIXTURE"
    """)

    File.chmod!(git, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    workflow = YamlElixir.read_from_file!(Path.join(Workspace.root(), ".github/workflows/ci.yml"))

    step =
      workflow["jobs"]["workspace"]["steps"]
      |> Enum.find(&(&1["name"] == "Governance files are shared"))

    %{root: root, tools: tools, script: step["run"]}
  end

  test "package guidance is admitted while shared governance stays at the root", fixture do
    assert {_, 0} = check(fixture, ["packages/example/AGENTS.md"])

    for path <- [
          "packages/example/CONTRIBUTING.md",
          "packages/example/CODE_OF_CONDUCT.md",
          "packages/example/GOVERNANCE.md",
          "packages/example/SECURITY.md",
          "packages/example/.github/workflows/ci.yml",
          "packages/example/.claude/settings.json",
          "packages/example/docs/spec.md"
        ] do
      assert {output, 1} = check(fixture, ["packages/example/AGENTS.md", path])
      assert output =~ path
    end
  end

  test "package licenses must still match the shared license", fixture do
    File.write!(Path.join(fixture.root, "packages/example/LICENSE"), "different license")
    assert {output, 1} = check(fixture, ["packages/example/AGENTS.md"])
    assert output =~ "differs from the root LICENSE"
  end

  defp check(fixture, paths) do
    inventory = Path.join(fixture.root, "tracked-files")
    File.write!(inventory, Enum.join(paths, "\n") <> "\n")

    System.cmd("bash", ["-c", fixture.script],
      cd: fixture.root,
      env: [
        {"PATH", fixture.tools <> ":" <> System.fetch_env!("PATH")},
        {"WOTEX_GOVERNANCE_FIXTURE", inventory}
      ],
      stderr_to_stdout: true
    )
  end
end
