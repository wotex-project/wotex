defmodule Wotex.Workspace.AffectedTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.Affected
  alias WotexWorkspace.Fixtures

  setup do
    %{manifest: Fixtures.manifest()}
  end

  describe "affected/3" do
    test "a package path selects the package and its transitive dependents", %{manifest: m} do
      assert Affected.affected(m, ["packages/runtime/lib/runtime.ex"]) == ~w(runtime coap http lab)
      assert Affected.affected(m, ["packages/coap/test/x_test.exs"]) == ~w(coap)
      assert Affected.affected(m, ["packages/conformance/README.md"]) == ~w(conformance lab)
    end

    test "several paths merge in topological order", %{manifest: m} do
      paths = ["packages/lab/mix.exs", "packages/conformance/lib/c.ex", "packages/coap/lib/a.ex"]
      assert Affected.affected(m, paths) == ~w(conformance coap lab)
    end

    test "documentation paths select nothing unless docs: true", %{manifest: m} do
      assert Affected.affected(m, ["docs/packages/runtime/specs/WRT.01.md"]) == []

      assert Affected.affected(m, ["docs/packages/runtime/specs/WRT.01.md"], docs: true) ==
               ~w(runtime coap http lab)
    end

    test "select_all_on globs select every package", %{manifest: m} do
      all = ~w(conformance core runtime coap http lab)
      assert Affected.affected(m, ["mix.exs"]) == all
      assert Affected.affected(m, ["lib/wotex/workspace.ex"]) == all
      assert Affected.affected(m, ["tooling/packages.yaml"]) == all
      assert Affected.affected(m, [".github/workflows/ci.yml"]) == all
      assert Affected.affected(m, [".tool-versions"]) == all
      assert Affected.affected(m, ["packages/coap/lib/a.ex", "mix.exs"]) == all
    end

    test "unrelated and unknown paths select nothing", %{manifest: m} do
      assert Affected.affected(m, []) == []
      assert Affected.affected(m, ["README.md", "docs/README.md", "packages/unknown/x.ex"]) == []
      assert Affected.affected(m, ["packages", "packages/"]) == []
      assert Affected.affected(m, ["mix.lock", "test/x_test.exs", "library/x.ex"]) == []
    end

    test "leading ./ and whitespace are tolerated", %{manifest: m} do
      assert Affected.affected(m, ["./packages/coap/lib/a.ex\n"]) == ~w(coap)
    end
  end

  describe "glob_match?/2" do
    test "double star spans directories and matches the directory itself" do
      assert Affected.glob_match?("lib/**", "lib/a/b/c.ex")
      assert Affected.glob_match?("lib/**", "lib/x.ex")
      assert Affected.glob_match?("lib/**", "lib")
      refute Affected.glob_match?("lib/**", "library/x.ex")
      refute Affected.glob_match?("lib/**", "packages/a/lib/x.ex")
    end

    test "single star stays within a segment" do
      assert Affected.glob_match?("*.md", "README.md")
      refute Affected.glob_match?("*.md", "docs/README.md")
      assert Affected.glob_match?("packages/*/mix.exs", "packages/a/mix.exs")
      refute Affected.glob_match?("packages/*/mix.exs", "packages/a/b/mix.exs")
      assert Affected.glob_match?("**/mix.exs", "packages/a/b/mix.exs")
    end

    test "literals are escaped and ? matches one character" do
      assert Affected.glob_match?(".tool-versions", ".tool-versions")
      refute Affected.glob_match?(".tool-versions", "xtool-versions")
      assert Affected.glob_match?("a?c", "abc")
      refute Affected.glob_match?("a?c", "a/c")
    end
  end

  describe "porcelain_paths/1" do
    test "parses modified, untracked and renamed entries" do
      output = " M lib/a.ex\n?? tooling/new.yaml\nR  old.ex -> new.ex\nA  \"sp ace.ex\"\n"

      assert Affected.porcelain_paths(output) == [
               "lib/a.ex",
               "tooling/new.yaml",
               "new.ex",
               "sp ace.ex"
             ]

      assert Affected.porcelain_paths("") == []
    end
  end

  describe "changed_paths/2 against a real repository" do
    setup context do
      root = Fixtures.tmp_dir(context)
      git!(root, ["init", "-q", "-b", "trunk"])
      Fixtures.write!(root, "README.md", "one\n")
      git!(root, ["add", "."])
      git!(root, ["commit", "-q", "-m", "root"])
      {base, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: root, env: [])
      Fixtures.write!(root, "packages/a/lib/a.ex", "defmodule A do\nend\n")
      git!(root, ["add", "."])
      git!(root, ["commit", "-q", "-m", "add a"])
      Fixtures.write!(root, "tooling/extra.yaml", "x: 1\n")
      Fixtures.write!(root, "README.md", "two\n")
      %{root: root, base: String.trim(base)}
    end

    test "combines the committed range with the working tree", %{root: root, base: base} do
      assert {:ok, paths} = Affected.changed_paths(base, root)
      assert paths == ["README.md", "packages/a/lib/a.ex", "tooling/extra.yaml"]
    end

    test "falls back to the root commit when neither origin/main nor main exists", %{
      root: root,
      base: base
    } do
      assert Affected.default_base(root) == {:ok, base}
      assert {:ok, paths} = Affected.changed_paths(nil, root)
      assert "packages/a/lib/a.ex" in paths
    end

    test "prefers main over the root commit", %{root: root} do
      git!(root, ["branch", "main"])
      assert Affected.default_base(root) == {:ok, "main"}
    end

    test "reports an unknown base", %{root: root} do
      assert {:error, message} = Affected.changed_paths("no-such-ref", root)
      assert message =~ "git diff"
    end

    defp git!(root, args) do
      identity = ["-c", "user.name=test", "-c", "user.email=test@example.invalid"]

      {_output, 0} =
        System.cmd("git", identity ++ args, cd: root, env: [], stderr_to_stdout: true)

      :ok
    end
  end
end
