defmodule Mix.Tasks.Wotex.OptionsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.CLI

  describe "wotex.affected" do
    test "accepts --base, --docs, --all and --json" do
      assert Mix.Tasks.Wotex.Affected.parse_args(~w(--base main --docs --all --json)) ==
               [base: "main", docs: true, all: true, json: true]

      assert Mix.Tasks.Wotex.Affected.parse_args([]) == []
    end

    test "rejects unknown switches and stray arguments" do
      assert_raise Mix.Error, ~r/--nope/, fn -> Mix.Tasks.Wotex.Affected.parse_args(~w(--nope)) end

      assert_raise Mix.Error, ~r/unexpected arguments: extra/, fn ->
        Mix.Tasks.Wotex.Affected.parse_args(~w(extra))
      end
    end
  end

  describe "wotex.check" do
    test "accepts the selection switches, --lane and --env" do
      opts =
        Mix.Tasks.Wotex.Check.parse_args(
          ~w(--package wotex --package wotex-nx --lane minimum --env test)
        )

      assert Keyword.get_values(opts, :package) == ~w(wotex wotex-nx)
      assert opts[:lane] == "minimum"
      assert opts[:env] == "test"

      assert CLI.selection_opts(opts) == [
               all: false,
               packages: ~w(wotex wotex-nx),
               base: nil,
               docs: false
             ]

      assert CLI.selection_opts(Mix.Tasks.Wotex.Check.parse_args(~w(--all --base origin/main))) ==
               [all: true, packages: [], base: "origin/main", docs: false]
    end

    test "rejects an unknown lane" do
      assert_raise Mix.Error, ~r/--lane must be minimum or current/, fn ->
        Mix.Tasks.Wotex.Check.parse_args(~w(--lane nightly))
      end
    end
  end

  describe "wotex.archive" do
    test "detects a package alias but not the package project key" do
      alias_form =
        ~s|  defp aliases do\n    [package: "cmd env -u WOTEX_PATH_DEPS mix hex.build"]\n  end\n|

      list_form = ~s|      package: ["hex.build"],\n|
      quoted_form = ~s|      "package": "run bin/check_archive.exs",\n|
      project_key = ~s|      package: package(),\n      docs: docs(),\n|

      assert Mix.Tasks.Wotex.Archive.package_alias?(alias_form)
      assert Mix.Tasks.Wotex.Archive.package_alias?(list_form)
      assert Mix.Tasks.Wotex.Archive.package_alias?(quoted_form)
      refute Mix.Tasks.Wotex.Archive.package_alias?(project_key)
    end

    test "finds the archive check script" do
      root = WotexWorkspace.Fixtures.tmp_dir("archive")
      assert Mix.Tasks.Wotex.Archive.check_script(root) == nil
      WotexWorkspace.Fixtures.write!(root, "bin/check_package.exs", "")
      assert Mix.Tasks.Wotex.Archive.check_script(root) == "bin/check_package.exs"
      WotexWorkspace.Fixtures.write!(root, "bin/check_archive.exs", "")
      assert Mix.Tasks.Wotex.Archive.check_script(root) == "bin/check_archive.exs"
    end

    test "parses the selection switches" do
      assert Mix.Tasks.Wotex.Archive.parse_args(~w(--all)) == [all: true]
      assert_raise Mix.Error, fn -> Mix.Tasks.Wotex.Archive.parse_args(~w(--json)) end
    end
  end

  describe "wotex.catalogue and wotex.boundary" do
    test "parse their switches" do
      assert Mix.Tasks.Wotex.Catalogue.parse_args(~w(--check)) == [check: true]
      assert Mix.Tasks.Wotex.Catalogue.parse_args([]) == []
      assert_raise Mix.Error, fn -> Mix.Tasks.Wotex.Catalogue.parse_args(~w(--all)) end

      assert Mix.Tasks.Wotex.Boundary.parse_args(~w(--package wotex-coap --base main)) ==
               [package: "wotex-coap", base: "main"]
    end
  end

  describe "wotex.native.*" do
    test "build requires --package and an absolute --workspace at run time" do
      assert Mix.Tasks.Wotex.Native.Build.parse_args(~w(--package wotex-coap --workspace /tmp/ws)) ==
               [package: "wotex-coap", workspace: "/tmp/ws"]

      assert_raise Mix.Error, ~r/--package NAME is required/, fn ->
        Mix.Tasks.Wotex.Native.Build.parse_args(~w(--workspace /tmp/ws))
      end

      assert_raise Mix.Error, ~r/--workspace/, fn ->
        Mix.Tasks.Wotex.Native.Build.parse_args(~w(--package wotex-coap))
      end
    end

    test "sources takes no options and advisories takes --offline" do
      assert Mix.Tasks.Wotex.Native.Sources.parse_args([]) == []
      assert_raise Mix.Error, fn -> Mix.Tasks.Wotex.Native.Sources.parse_args(~w(--offline)) end
      assert Mix.Tasks.Wotex.Native.Advisories.parse_args(~w(--offline)) == [offline: true]
    end
  end

  describe "wotex.new" do
    test "takes a name and an optional dependency list" do
      assert Mix.Tasks.Wotex.New.parse_args(~w(wotex-demo)) == {"wotex-demo", depends_on: ["wotex"]}

      assert Mix.Tasks.Wotex.New.parse_args(~w(wotex-demo --depends-on wotex,wotex-runtime)) ==
               {"wotex-demo", depends_on: ["wotex", "wotex-runtime"]}

      assert_raise Mix.Error, ~r/usage: mix wotex.new NAME/, fn ->
        Mix.Tasks.Wotex.New.parse_args([])
      end

      assert_raise Mix.Error, fn -> Mix.Tasks.Wotex.New.parse_args(~w(a b)) end
    end
  end

  test "every task has a shortdoc and a moduledoc" do
    for task <-
          ~w(affected check archive catalogue boundary native.build native.sources native.advisories new) do
      module = Mix.Task.get("wotex.#{task}")
      assert module, "mix wotex.#{task} not found"
      assert is_binary(Mix.Task.shortdoc(module))
      assert is_binary(Mix.Task.moduledoc(module))
    end
  end
end
