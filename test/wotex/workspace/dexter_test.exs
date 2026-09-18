defmodule Wotex.Workspace.DexterTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.Dexter
  alias WotexWorkspace.Fixtures

  # A stand-in `dexter` executable: prints `$FAKE_OUTPUT`-like fixed output
  # per subcommand and exits with the given status.
  defp fake_dexter(root, script) do
    path = Fixtures.write!(root, "bin/dexter", "#!/bin/sh\n" <> script)
    File.chmod!(path, 0o755)
    fn "dexter" -> path end
  end

  setup context do
    root = Fixtures.tmp_dir(context)
    Fixtures.write!(root, ".dexter/dexter.db", "")
    %{root: root}
  end

  test "command/1 prefers dexter on PATH, then mise x, else names mise install" do
    assert Dexter.command(fn "dexter" -> "/bin/dexter" end) == {:ok, {"/bin/dexter", []}}

    assert Dexter.command(fn
             "dexter" -> nil
             "mise" -> "/bin/mise"
           end) == {:ok, {"/bin/mise", ["x", "--", "dexter"]}}

    assert {:error, message} = Dexter.command(fn _ -> nil end)
    assert message =~ "mise install"
  end

  test "parse_locations/2 makes paths repository-relative and drops noise" do
    output = """
    /repo/packages/a/lib/a.ex:12
    /repo/packages/a/lib/a.ex:12
    /elsewhere/deps/x.ex:3
    Reindexed 0 files
    /canonical/repo/packages/a/test/a_test.exs:4
    """

    assert Dexter.parse_locations(output, ["/repo", "/canonical/repo"]) == [
             %{file: "packages/a/lib/a.ex", line: 12},
             %{file: "/elsewhere/deps/x.ex", line: 3},
             %{file: "packages/a/test/a_test.exs", line: 4}
           ]
  end

  test "references/3 treats no references as an empty result", %{root: root} do
    finder =
      fake_dexter(root, """
      case "$1" in
        references) echo "No references found for $2" >&2; exit 1 ;;
        lookup) echo "$PWD/packages/a/lib/a.ex:7"; exit 0 ;;
      esac
      """)

    assert Dexter.references("Nope", nil, root: root, finder: finder) == {:ok, []}

    assert {:ok, [%{file: "packages/a/lib/a.ex", line: 7}]} =
             Dexter.lookup("A", "run", root: root, finder: finder)
  end

  test "a failing dexter is an error that names mise install", %{root: root} do
    finder =
      fake_dexter(root, ~s(echo "mise ERROR No version is set for shim: dexter" >&2; exit 2\n))

    assert {:error, message} = Dexter.references("A", nil, root: root, finder: finder)
    assert message =~ "dexter references A exited with 2"
    assert message =~ "mise install"

    assert {:error, message} = Dexter.reindex(root: root, finder: finder)
    assert message =~ "dexter reindex exited with 2"
  end

  test "reindex/1 requires an index", %{root: root} do
    File.rm!(Dexter.index_path(root))
    refute Dexter.indexed?(root)
    assert {:error, message} = Dexter.reindex(root: root, finder: fn _ -> nil end)
    assert message =~ "no Dexter index at .dexter/dexter.db; run `mix index`"
  end
end
