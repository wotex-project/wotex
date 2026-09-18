defmodule Mix.Tasks.Wotex.OptionsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.CLI

  describe "wotex.affected" do
    test "accepts --base, --docs, --all, --json and --detail" do
      assert Mix.Tasks.Wotex.Affected.parse_args(~w(--base main --docs --all --json)) ==
               [base: "main", docs: true, all: true, json: true]

      assert Mix.Tasks.Wotex.Affected.parse_args(~w(--detail)) == [detail: true]

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

    test "passes a lane's skipped tools to mix check" do
      assert Mix.Tasks.Wotex.Check.commands() == [
               {"deps.get", ["deps.get", "--check-locked"]},
               {"check", ["check", "--no-retry"]}
             ]

      assert Mix.Tasks.Wotex.Check.commands(["formatter", "dialyzer"]) == [
               {"deps.get", ["deps.get", "--check-locked"]},
               {"check", ["check", "--no-retry", "--except", "formatter", "--except", "dialyzer"]}
             ]
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

  describe "wotex.setup and wotex.index" do
    test "setup takes --no-index, index takes --force" do
      assert Mix.Tasks.Wotex.Setup.parse_args([]) == []
      assert Mix.Tasks.Wotex.Setup.parse_args(~w(--no-index)) == [index: false]
      assert_raise Mix.Error, fn -> Mix.Tasks.Wotex.Setup.parse_args(~w(--all)) end

      assert Mix.Tasks.Wotex.Index.parse_args(~w(--force)) == [force: true]
      assert Mix.Tasks.Wotex.Index.parse_args([]) == []

      assert_raise Mix.Error, ~r/unexpected arguments: x/, fn ->
        Mix.Tasks.Wotex.Index.parse_args(~w(x))
      end
    end
  end

  describe "wotex.pkg, wotex.dialyzer and wotex.docs" do
    test "pkg passes every argument after the name through" do
      assert Mix.Tasks.Wotex.Pkg.parse_args(~w(wotex-coap test test/a_test.exs --seed 0)) ==
               {"wotex-coap", ~w(test test/a_test.exs --seed 0)}

      assert Mix.Tasks.Wotex.Pkg.parse_args(~w(wotex --version)) == {"wotex", ~w(--version)}

      assert_raise Mix.Error, ~r/usage: mix pkg NAME TASK/, fn ->
        Mix.Tasks.Wotex.Pkg.parse_args(~w(wotex))
      end

      assert_raise Mix.Error, fn -> Mix.Tasks.Wotex.Pkg.parse_args(~w(--all test)) end
    end

    test "dialyzer and docs take a name and extra arguments" do
      assert Mix.Tasks.Wotex.Dialyzer.parse_args(~w(wotex --format short)) ==
               {"wotex", ~w(--format short)}

      assert_raise Mix.Error, fn -> Mix.Tasks.Wotex.Dialyzer.parse_args([]) end
      assert_raise Mix.Error, fn -> Mix.Tasks.Wotex.Dialyzer.parse_args(~w(--package wotex)) end

      assert Mix.Tasks.Wotex.Docs.parse_args(~w(wotex-nx --warnings-as-errors)) ==
               {"wotex-nx", ~w(--warnings-as-errors)}

      assert_raise Mix.Error, fn -> Mix.Tasks.Wotex.Docs.parse_args([]) end
    end

    test "docs builds in the docs environment only when the package declares one" do
      assert Mix.Tasks.Wotex.Docs.docs_env(~s|{:ex_doc, "~> 0.38", only: [:dev, :docs]}|) == "docs"
      assert Mix.Tasks.Wotex.Docs.docs_env(~s|{:ex_doc, "~> 0.38", only: :dev}|) == nil
    end
  end

  describe "wotex.def, wotex.refs and wotex.impact" do
    test "take MODULE [FUN] in either spelling" do
      assert Mix.Tasks.Wotex.Def.parse_args(~w(Wotex.Runtime.Request from_selection)) ==
               {"Wotex.Runtime.Request", "from_selection", []}

      assert Mix.Tasks.Wotex.Def.parse_args(~w(Wotex.Runtime.Request.from_selection/2 --strict)) ==
               {"Wotex.Runtime.Request", "from_selection", [strict: true]}

      assert Mix.Tasks.Wotex.Def.parse_args(~w(Wotex.CoAP.Block)) == {"Wotex.CoAP.Block", nil, []}

      assert Mix.Tasks.Wotex.Refs.parse_args(~w(Wotex.CoAP.Block encode/1)) ==
               {"Wotex.CoAP.Block", "encode"}

      assert Mix.Tasks.Wotex.Refs.parse_args(~w(Wotex.CoAP.Block.encode)) ==
               {"Wotex.CoAP.Block", "encode"}

      assert Mix.Tasks.Wotex.Impact.parse_args(~w(Wotex.CoAP.Block --run)) ==
               {"Wotex.CoAP.Block", nil, [run: true]}

      assert_raise Mix.Error, ~r/usage: mix def MODULE/, fn ->
        Mix.Tasks.Wotex.Def.parse_args([])
      end

      assert_raise Mix.Error, ~r/usage: mix refs/, fn ->
        Mix.Tasks.Wotex.Refs.parse_args(~w(A b c))
      end

      assert_raise Mix.Error, fn -> Mix.Tasks.Wotex.Refs.parse_args(~w(A --run)) end

      assert_raise Mix.Error, ~r/usage: mix impact/, fn ->
        Mix.Tasks.Wotex.Impact.parse_args(~w(--run))
      end
    end
  end

  describe "wotex.test.affected" do
    test "takes files or a selection, not both" do
      assert Mix.Tasks.Wotex.Test.Affected.parse_args(~w(packages/wotex/test/a_test.exs)) ==
               {[], ~w(packages/wotex/test/a_test.exs)}

      assert Mix.Tasks.Wotex.Test.Affected.parse_args(~w(--base main --package wotex)) ==
               {[base: "main", package: "wotex"], []}

      assert_raise Mix.Error, ~r/not both/, fn ->
        Mix.Tasks.Wotex.Test.Affected.parse_args(~w(--package wotex packages/wotex/test/a_test.exs))
      end

      assert_raise Mix.Error, fn -> Mix.Tasks.Wotex.Test.Affected.parse_args(~w(--all)) end
    end

    test "groups repository-relative files by package, keeping line suffixes" do
      manifest = WotexWorkspace.Fixtures.manifest()

      files = [
        "packages/http/test/http_test.exs:12",
        "packages/core/test/core_test.exs",
        "packages/http/test/form_test.exs",
        "packages/core/test/deep"
      ]

      assert Mix.Tasks.Wotex.Test.Affected.group_files(files, manifest, "/repo") ==
               {:ok,
                [
                  {"core", ["test/core_test.exs", "test/deep"]},
                  {"http", ["test/http_test.exs:12", "test/form_test.exs"]}
                ]}

      assert Mix.Tasks.Wotex.Test.Affected.group_files(
               ["/repo/packages/core/test/a_test.exs"],
               manifest,
               "/repo"
             ) ==
               {:ok, [{"core", ["test/a_test.exs"]}]}

      assert {:error, message} =
               Mix.Tasks.Wotex.Test.Affected.group_files(
                 ["test/a_test.exs", "packages/nope/test/a_test.exs"],
                 manifest,
                 "/repo"
               )

      assert message ==
               "not inside a package directory: test/a_test.exs, packages/nope/test/a_test.exs"
    end
  end

  describe "gates, format, lint and workspace" do
    test "check.fast and lint take the selection switches" do
      assert Mix.Tasks.Wotex.Check.Fast.parse_args(~w(--package wotex --package wotex-nx)) ==
               [package: "wotex", package: "wotex-nx"]

      assert Mix.Tasks.Wotex.Lint.parse_args(~w(--all)) == [all: true]
      assert_raise Mix.Error, fn -> Mix.Tasks.Wotex.Check.Fast.parse_args(~w(--lane current)) end
    end

    test "check.affected takes --base and --docs only; check.all takes nothing" do
      assert Mix.Tasks.Wotex.Check.Affected.parse_args(~w(--base main --docs)) ==
               [base: "main", docs: true]

      assert_raise Mix.Error, fn ->
        Mix.Tasks.Wotex.Check.Affected.parse_args(~w(--package wotex))
      end

      assert Mix.Tasks.Wotex.Check.All.parse_args([]) == []
      assert_raise Mix.Error, fn -> Mix.Tasks.Wotex.Check.All.parse_args(~w(--all)) end
    end

    test "format.all takes --check and the selection switches" do
      assert Mix.Tasks.Wotex.Format.All.parse_args(~w(--check --all)) == [check: true, all: true]

      assert Mix.Tasks.Wotex.Format.All.step(true) ==
               {"format", ["format", "--check-formatted"], []}

      assert Mix.Tasks.Wotex.Format.All.step(false) == {"format", ["format"], []}
    end

    test "workspace takes --base and --all and runs the root checks in order" do
      assert Mix.Tasks.Wotex.Workspace.parse_args(~w(--base main --all)) == [
               base: "main",
               all: true
             ]

      assert_raise Mix.Error, fn -> Mix.Tasks.Wotex.Workspace.parse_args(~w(--package wotex)) end

      assert Enum.map(Mix.Tasks.Wotex.Workspace.root_steps(), &elem(&1, 1)) == [
               ["compile", "--warnings-as-errors"],
               ["format", "--check-formatted"],
               ["credo", "--strict"],
               ["test"]
             ]
    end

    test "docs.check takes no options" do
      assert_raise Mix.Error, fn -> Mix.Tasks.Wotex.Docs.Check.run(~w(--all)) end
    end
  end

  @tasks ~w(affected check archive catalogue boundary native.build native.sources
            native.advisories new setup index pkg def refs impact test.affected check.fast
            check.affected check.all workspace format.all lint dialyzer docs docs.check)

  test "every task has a shortdoc and a moduledoc" do
    for task <- @tasks do
      module = Mix.Task.get("wotex.#{task}")
      assert module, "mix wotex.#{task} not found"
      assert is_binary(Mix.Task.shortdoc(module))
      assert is_binary(Mix.Task.moduledoc(module))
    end
  end

  test "the root aliases are the design's command set and name existing tasks" do
    aliases = Mix.Project.config()[:aliases]

    assert Enum.sort(Enum.map(Keyword.keys(aliases), &Atom.to_string/1)) ==
             Enum.sort(~w(setup affected pkg def refs impact test.affected check.fast
                          check.affected check.all workspace format.all lint dialyzer.pkg
                          docs.check docs.pkg index native.build native.sources
                          native.advisories))

    for {name, tasks} <- aliases, task <- List.wrap(tasks) do
      [task_name | _args] = String.split(task)
      assert Mix.Task.get(task_name), "alias #{name}: task #{task_name} not found"
    end

    # Mix appends alias arguments to the last task: it must be a wotex task.
    for {name, tasks} <- aliases do
      assert String.starts_with?(List.last(List.wrap(tasks)), "wotex."),
             "alias #{name} must end in a wotex.* task"
    end
  end
end
