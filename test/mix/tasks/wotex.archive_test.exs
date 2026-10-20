defmodule Mix.Tasks.Wotex.ArchiveTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Archive
  alias Wotex.Workspace
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

  test "runs the owning checker once with its source dependencies" do
    root = Fixtures.tmp_dir("archive-owner")
    source = Workspace.root()
    File.cp_r!(Path.join(source, "lib"), Path.join(root, "lib"))

    for name <- ["mix.exs", "mix.lock"],
        do: File.cp!(Path.join(source, name), Path.join(root, name))

    Fixtures.write!(root, "tooling/packages.yaml", JSON.encode!(Fixtures.manifest_map()))

    Fixtures.write!(root, "packages/core/mix.exs", ~S"""
    defmodule CoreFixture.MixProject do
      @moduledoc false

      use Mix.Project
      def project do
        [
          app: :core,
          version: "0.1.0",
          deps: [],
          aliases: [package: "run --no-start --no-compile bin/check_archive.exs"]
        ]
      end
    end
    """)

    Fixtures.write!(root, "packages/core/bin/check_archive.exs", ~S"""
    unless System.get_env("WOTEX_PATH_DEPS") == "1",
      do: Mix.raise("the owning checker requires explicit sibling sources")

    File.write!("checks.txt", "checked\n", [:append])
    """)

    {output, status} =
      System.cmd("mix", ["do", "compile", "+", "wotex.archive", "--package", "core"],
        cd: root,
        env: [{"MIX_ENV", "test"}, {"MIX_DEPS_PATH", Path.join(source, "deps")}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert File.read!(Path.join(root, "packages/core/checks.txt")) == "checked\n"
  end
end
