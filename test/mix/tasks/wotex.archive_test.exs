defmodule Mix.Tasks.Wotex.ArchiveTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Archive
  alias WotexWorkspace.Fixtures

  test "detects a package alias but not the package project key" do
    alias_form =
      ~s|  defp aliases do\n    [package: "cmd env -u WOTEX_PATH_DEPS mix hex.build"]\n  end\n|

    list_form = ~s|      package: ["hex.build"],\n|
    quoted_form = ~s|      "package": "run bin/check_archive.exs",\n|
    project_key = ~s|      package: package(),\n      docs: docs(),\n|

    assert Archive.package_alias?(alias_form)
    assert Archive.package_alias?(list_form)
    assert Archive.package_alias?(quoted_form)
    refute Archive.package_alias?(project_key)
  end

  test "finds the archive check script, preferring check_archive.exs" do
    root = Fixtures.tmp_dir("archive")
    assert Archive.check_script(root) == nil
    Fixtures.write!(root, "bin/check_package.exs", "")
    assert Archive.check_script(root) == "bin/check_package.exs"
    Fixtures.write!(root, "bin/check_archive.exs", "")
    assert Archive.check_script(root) == "bin/check_archive.exs"
  end

  test "parses the selection switches and rejects anything else" do
    assert Archive.parse_args(~w(--all)) == [all: true]
    assert Archive.parse_args(~w(--package wotex --base main)) == [package: "wotex", base: "main"]
    assert_raise Mix.Error, fn -> Archive.parse_args(~w(--json)) end
    assert_raise Mix.Error, ~r/unexpected arguments: x/, fn -> Archive.parse_args(~w(x)) end
  end
end
