defmodule Wotex.Workspace.ReferencesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.References
  alias WotexWorkspace.Fixtures

  defp entry(file, line \\ 1), do: References.classify(%{file: file, line: line})

  test "classify/1 derives the package and the kind" do
    assert %{package: "core", package_file: "lib/core.ex", kind: :lib} =
             entry("packages/core/lib/core.ex")

    assert %{kind: :test, package_file: "test/core_test.exs"} =
             entry("packages/core/test/core_test.exs")

    assert %{kind: :support} = entry("packages/core/test/support/factory.ex")
    assert %{kind: :support} = entry("packages/core/test/test_helper.exs")
    assert %{kind: :dependency} = entry("packages/core/deps/jason/lib/jason.ex")
    assert %{kind: :dependency} = entry("packages/core/_build/test/lib/x.ex")
    assert %{kind: :other} = entry("packages/core/mix.exs")
    assert %{kind: :other} = entry("packages/core/bin/check.exs")
    assert %{package: nil, kind: :lib} = entry("lib/wotex/workspace.ex")
    assert %{package: nil, kind: :dependency} = entry("deps/credo/lib/credo.ex")
    assert %{package: nil, kind: :dependency} = entry("/home/user/.hex/x.ex")
  end

  test "split_package/1" do
    assert References.split_package("packages/a/lib/x.ex") == {"a", "lib/x.ex"}
    assert References.split_package("packages/a") == {nil, "packages/a"}
    assert References.split_package("docs/a.md") == {nil, "docs/a.md"}
  end

  test "group/2 orders packages topologically, root last, and drops dependencies" do
    entries = [
      entry("lib/wotex/workspace.ex", 3),
      entry("packages/http/test/http_test.exs", 9),
      entry("packages/http/lib/http.ex", 2),
      entry("packages/core/lib/core.ex", 1),
      entry("packages/core/deps/x/lib/x.ex", 1)
    ]

    {groups, dependencies} = References.group(entries, Fixtures.manifest())
    assert dependencies == 1

    assert Enum.map(groups, fn {package, entries} -> {package, Enum.map(entries, & &1.kind)} end) ==
             [{"core", [:lib]}, {"http", [:lib, :test]}, {nil, [:lib]}]

    text = References.render("Core.new", entries, Fixtures.manifest())
    assert text =~ "Core.new: 4 reference(s)"

    assert text =~
             "http\n  lib     packages/http/lib/http.ex:2\n  test    packages/http/test/http_test.exs:9"

    assert text =~ "(workspace root)\n  lib     lib/wotex/workspace.ex:3"
    assert text =~ "1 reference(s) in dependencies"
  end
end
