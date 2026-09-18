defmodule Wotex.Workspace.SelectionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Affected, as: AffectedTask
  alias Wotex.Workspace.Selection
  alias WotexWorkspace.Fixtures

  setup context do
    root = Fixtures.tmp_dir(context)
    git!(root, ["init", "-q", "-b", "trunk"])
    Fixtures.write!(root, "README.md", "one\n")
    git!(root, ["add", "."])
    git!(root, ["commit", "-q", "-m", "root"])
    {base, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: root, env: [])
    Fixtures.write!(root, "packages/runtime/lib/runtime.ex", "defmodule Runtime do\nend\n")
    %{root: root, base: String.trim(base), manifest: Fixtures.manifest()}
  end

  test "classify/2 marks the affected set from git", %{root: root, base: base, manifest: m} do
    assert Selection.classify(m, root: root, base: base) ==
             {:ok,
              [
                {"runtime", :changed},
                {"coap", :dependent},
                {"http", :dependent},
                {"lab", :dependent}
              ]}
  end

  test "select/2 with only: keeps one mark", %{root: root, base: base, manifest: m} do
    assert Selection.select(m, root: root, base: base) == {:ok, ~w(runtime coap http lab)}
    assert Selection.select(m, root: root, base: base, only: :changed) == {:ok, ~w(runtime)}

    assert Selection.select(m, root: root, base: base, only: :dependent) ==
             {:ok, ~w(coap http lab)}
  end

  test "--all and --package mark their packages changed", %{manifest: m} do
    assert {:ok, marked} = Selection.classify(m, all: true)
    assert Enum.all?(marked, &match?({_name, :changed}, &1))
    assert length(marked) == 6

    assert Selection.classify(m, packages: ~w(lab runtime)) ==
             {:ok, [{"runtime", :changed}, {"lab", :changed}]}

    assert Selection.select(m, packages: ~w(lab runtime), only: :changed) ==
             {:ok, ~w(runtime lab)}

    assert Selection.classify(m, packages: ~w(nope)) == {:error, "unknown package(s): nope"}
  end

  describe "mix wotex.affected output" do
    setup do
      %{marked: [{"runtime", :changed}, {"coap", :dependent}]}
    end

    test "names only, as lines or a flat JSON list", %{marked: marked} do
      assert AffectedTask.render(marked, []) == "runtime\ncoap"
      assert AffectedTask.render(marked, json: true) == ~s(["runtime","coap"])
      assert AffectedTask.render([], json: true) == "[]"
      assert AffectedTask.render([], []) == ""
    end

    test "--detail keeps the marks", %{marked: marked} do
      assert AffectedTask.render(marked, detail: true) == "runtime  changed\ncoap     dependent"

      assert JSON.decode!(AffectedTask.render(marked, detail: true, json: true)) == [
               %{"name" => "runtime", "status" => "changed"},
               %{"name" => "coap", "status" => "dependent"}
             ]
    end
  end

  defp git!(root, args) do
    identity = ["-c", "user.name=test", "-c", "user.email=test@example.invalid"]
    {_, 0} = System.cmd("git", identity ++ args, cd: root, env: [], stderr_to_stdout: true)
    :ok
  end
end
