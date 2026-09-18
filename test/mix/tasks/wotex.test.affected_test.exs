defmodule Mix.Tasks.Wotex.Test.AffectedTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Test.Affected
  alias WotexWorkspace.Fixtures

  test "takes files or a selection, not both" do
    assert Affected.parse_args(~w(packages/wotex/test/a_test.exs)) ==
             {[], ~w(packages/wotex/test/a_test.exs)}

    assert Affected.parse_args(~w(--base main --package wotex)) ==
             {[base: "main", package: "wotex"], []}

    assert_raise Mix.Error, ~r/not both/, fn ->
      Affected.parse_args(~w(--package wotex packages/wotex/test/a_test.exs))
    end

    assert_raise Mix.Error, fn -> Affected.parse_args(~w(--all)) end
  end

  test "groups repository-relative files by package, keeping line suffixes" do
    manifest = Fixtures.manifest()

    files = [
      "packages/http/test/http_test.exs:12",
      "packages/core/test/core_test.exs",
      "packages/http/test/form_test.exs",
      "packages/core/test/deep"
    ]

    assert Affected.group_files(files, manifest, "/repo") ==
             {:ok,
              [
                {"core", ["test/core_test.exs", "test/deep"]},
                {"http", ["test/http_test.exs:12", "test/form_test.exs"]}
              ]}

    assert Affected.group_files(["/repo/packages/core/test/a_test.exs"], manifest, "/repo") ==
             {:ok, [{"core", ["test/a_test.exs"]}]}

    assert {:error, message} =
             Affected.group_files(
               ["test/a_test.exs", "packages/nope/test/a_test.exs"],
               manifest,
               "/repo"
             )

    assert message ==
             "not inside a package directory: test/a_test.exs, packages/nope/test/a_test.exs"
  end
end
