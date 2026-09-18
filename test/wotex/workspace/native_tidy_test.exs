defmodule Wotex.Workspace.NativeTidyTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Workspace.NativeTidy
  alias WotexWorkspace.Fixtures

  setup context do
    root = Fixtures.tmp_dir(context)
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    # A stand-in for clang-tidy: logs each unit and reports a finding for any
    # unit whose content contains "bad".
    tool =
      Fixtures.write!(root, "bin/tidy", """
      #!/bin/sh
      echo "$1" >> "$0.log"
      if grep -q bad "$1"; then echo "$1:1:1: warning: finding [check]"; fi
      exit 0
      """)

    File.chmod!(tool, 0o755)
    %{root: root, tool: tool, results: Path.join(root, "results")}
  end

  defp unit(root, tool, name) do
    path = Path.join(root, name)
    %{path: name, source: path, entry: %{"file" => path}, tidy: [path], argv: [tool, path]}
  end

  defp calls(tool) do
    case File.read(tool <> ".log") do
      {:ok, text} -> length(String.split(text, "\n", trim: true))
      {:error, :enoent} -> 0
    end
  end

  test "reuses clean results until an input changes and never records findings", %{
    root: root,
    tool: tool,
    results: results
  } do
    Fixtures.write!(root, "a.c", "int a;\n")
    Fixtures.write!(root, "b.c", "int bad;\n")
    units = [unit(root, tool, "a.c"), unit(root, tool, "b.c")]
    opts = [results: results, material: {"23.1.2", "config"}]

    assert NativeTidy.run(units, opts) == %{units: 2, reused: 0, failed: ["b.c"]}
    assert calls(tool) == 2
    assert_received {:mix_shell, :error, [message]}
    assert message =~ "b.c:1:1: warning: finding"

    # a.c is clean and unchanged; b.c still has its finding.
    assert NativeTidy.run(units, opts) == %{units: 2, reused: 1, failed: ["b.c"]}
    assert calls(tool) == 3

    File.write!(Path.join(root, "b.c"), "int good;\n")
    assert NativeTidy.run(units, opts) == %{units: 2, reused: 1, failed: []}
    assert NativeTidy.run(units, opts) == %{units: 2, reused: 2, failed: []}
    assert calls(tool) == 4

    # Another tool version, configuration or header set analyses every unit again.
    assert NativeTidy.run(units, results: results, material: {"23.1.3", "config"}).reused == 0
    assert calls(tool) == 6

    # So does another compile command.
    changed = Enum.map(units, &%{&1 | entry: Map.put(&1.entry, "arguments", ["-DX"])})
    assert NativeTidy.run(changed, results: results, material: {"23.1.3", "config"}).reused == 0
  end

  test "the key covers the material, compile command, arguments and content", %{
    root: root,
    tool: tool
  } do
    Fixtures.write!(root, "a.c", "int a;\n")
    base = unit(root, tool, "a.c")
    key = NativeTidy.key(:m, base)

    assert key =~ ~r/^[0-9A-F]{64}$/
    assert NativeTidy.key(:m, %{base | argv: ["docker", "exec", "other"]}) == key
    refute NativeTidy.key(:other, base) == key
    refute NativeTidy.key(:m, %{base | tidy: ["--extra"]}) == key
    refute NativeTidy.key(:m, %{base | entry: %{"file" => "x"}}) == key

    File.write!(base.source, "int changed;\n")
    refute NativeTidy.key(:m, base) == key
  end

  test "a failing command is a finding with its output, rewritten by translate", %{
    root: root,
    results: results
  } do
    Fixtures.write!(root, "a.c", "int a;\n")

    units = [
      %{
        path: "a.c",
        source: Path.join(root, "a.c"),
        entry: %{},
        tidy: [],
        argv: ["sh", "-c", "echo /ctr/a.c: error; exit 1"]
      }
    ]

    translate = fn unit, text -> String.replace(text, "/ctr/", unit.path <> "@") end
    result = NativeTidy.run(units, results: results, material: nil, translate: translate)
    assert result.failed == ["a.c"]
    assert_received {:mix_shell, :error, ["a.c@a.c: error"]}

    missing = [%{hd(units) | argv: [Path.join(root, "absent")]}]
    assert NativeTidy.run(missing, results: results, material: nil).failed == ["a.c"]
  end
end
