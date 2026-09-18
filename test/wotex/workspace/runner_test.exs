defmodule Wotex.Workspace.RunnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Workspace.Report
  alias Wotex.Workspace.Runner
  alias Wotex.Workspace.Selection
  alias WotexWorkspace.Fixtures

  describe "Runner.env/1" do
    test "exports WOTEX_PATH_DEPS=1 by default and MIX_ENV when given" do
      assert Runner.env() == [{"WOTEX_PATH_DEPS", "1"}]
      assert Runner.env(mix_env: "test") == [{"WOTEX_PATH_DEPS", "1"}, {"MIX_ENV", "test"}]
    end

    test "path_deps: false unsets the switch" do
      assert Runner.env(path_deps: false, mix_env: "dev") == [
               {"WOTEX_PATH_DEPS", nil},
               {"MIX_ENV", "dev"}
             ]
    end

    test "extra variables override earlier ones" do
      assert Runner.env(mix_env: "dev", env: [{"MIX_ENV", "prod"}, {"X", "1"}]) ==
               [{"WOTEX_PATH_DEPS", "1"}, {"MIX_ENV", "prod"}, {"X", "1"}]
    end

    test "describe/3 shows exports and unsets" do
      assert Runner.describe(
               "/repo/packages/wotex",
               ["check", "--no-retry"],
               Runner.env(path_deps: false, mix_env: "dev")
             ) =~
               "-u WOTEX_PATH_DEPS MIX_ENV=dev mix check --no-retry"
    end
  end

  describe "Runner.run/3" do
    test "runs mix in the directory and returns the exit status" do
      root = Fixtures.tmp_dir("runner")

      Fixtures.write!(root, "mix.exs", """
      defmodule RunnerFixture.MixProject do
        use Mix.Project
        def project, do: [app: :runner_fixture, version: "0.1.0", deps: []]
      end
      """)

      Fixtures.write!(root, "lib/mix/tasks/env.probe.ex", """
      defmodule Mix.Tasks.Env.Probe do
        use Mix.Task
        def run(_args) do
          File.write!("probe.txt", "\#{System.get_env("WOTEX_PATH_DEPS")}|\#{Mix.env()}")
          if System.get_env("PROBE_FAIL") == "1", do: exit({:shutdown, 3})
        end
      end
      """)

      assert Runner.run(root, ["env.probe"], mix_env: "test", quiet: true) == 0
      assert File.read!(Path.join(root, "probe.txt")) == "1|test"

      assert Runner.run(root, ["env.probe"],
               path_deps: false,
               env: [{"PROBE_FAIL", "1"}],
               quiet: true
             ) == 3

      assert File.read!(Path.join(root, "probe.txt")) == "|dev"

      # cd: runs the command in another directory than the target path.
      File.rm!(Path.join(root, "probe.txt"))
      assert Runner.run(Path.join(root, "missing"), ["env.probe"], cd: root, quiet: true) == 0
      assert File.read!(Path.join(root, "probe.txt")) == "1|dev"

      # A relative cd: is a directory inside the target path, such as a host.
      File.rm!(Path.join(root, "probe.txt"))

      assert Runner.run(Path.dirname(root), ["env.probe"], cd: Path.basename(root), quiet: true) ==
               0

      assert File.read!(Path.join(root, "probe.txt")) == "1|dev"
    end

    test "directory/2 resolves cd: against the target path" do
      assert Runner.directory("/repo/packages/lab") == "/repo/packages/lab"
      assert Runner.directory("/repo/packages/lab", cd: "/repo") == "/repo"

      assert Runner.directory("/repo/packages/lab", cd: "hosts/nerves") ==
               "/repo/packages/lab/hosts/nerves"
    end
  end

  describe "Report.table/1" do
    test "aligns columns and formats seconds" do
      rows = [
        %{package: "wotex", result: "ok", seconds: 12.345},
        %{package: "wotex-runtime", result: "check failed (1)", seconds: 3}
      ]

      assert Report.table(rows) == """
             package       | result           | seconds
             --------------+------------------+--------
             wotex         | ok               | 12.3
             wotex-runtime | check failed (1) | 3.0
             """
    end
  end

  describe "Selection.select/2" do
    setup do
      %{manifest: Fixtures.manifest()}
    end

    test "--all selects everything in order", %{manifest: manifest} do
      assert Selection.select(manifest, all: true) ==
               {:ok, ~w(conformance core runtime coap http lab)}
    end

    test "named packages are ordered and validated", %{manifest: manifest} do
      assert Selection.select(manifest, packages: ~w(lab core)) == {:ok, ~w(core lab)}

      assert Selection.select(manifest, packages: ~w(core nope)) ==
               {:error, "unknown package(s): nope"}
    end

    test "the affected set comes from git", %{manifest: manifest} do
      root = Fixtures.tmp_dir("selection")
      assert {:error, message} = Selection.select(manifest, root: root)
      assert message =~ "git"
    end
  end
end
