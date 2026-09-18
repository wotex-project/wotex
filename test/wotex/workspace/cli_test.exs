defmodule Wotex.Workspace.CLITest do
  @moduledoc false

  # fail/1, and every function that fails through it, prints with
  # Mix.shell(), which is global: the module swaps in Mix.Shell.Process and
  # runs synchronously.
  use ExUnit.Case, async: false

  alias Wotex.Workspace.CLI
  alias WotexWorkspace.Fixtures

  @order ~w(conformance core runtime coap http lab)

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    %{manifest: Fixtures.manifest()}
  end

  describe "parse/2" do
    test "returns the options and the positional arguments" do
      args = ~w(--all --package a x --package b --base main --docs y)

      assert CLI.parse(args, CLI.selection_switches()) ==
               {[all: true, package: "a", package: "b", base: "main", docs: true], ~w(x y)}

      assert CLI.parse([], CLI.selection_switches()) == {[], []}
    end

    test "negates boolean switches and stops at --" do
      assert CLI.parse(~w(--no-all --no-docs), CLI.selection_switches()) ==
               {[all: false, docs: false], []}

      assert CLI.parse(~w(--all -- --docs x), CLI.selection_switches()) ==
               {[all: true], ~w(--docs x)}
    end

    test "an unknown switch is a Mix.Error naming it" do
      assert_raise Mix.Error, ~r/--nope : Unknown option/, fn ->
        CLI.parse(~w(--all --nope), CLI.selection_switches())
      end
    end

    test "a missing or mistyped value is a Mix.Error" do
      assert_raise Mix.Error, ~r/--base : Missing argument of type string/, fn ->
        CLI.parse(~w(--base), CLI.selection_switches())
      end

      assert_raise Mix.Error, ~r/--jobs : Expected type integer, got "many"/, fn ->
        CLI.parse(~w(--jobs many), jobs: :integer)
      end
    end
  end

  describe "parse_options/2" do
    test "returns the options alone" do
      assert CLI.parse_options(~w(--json --all), json: :boolean, all: :boolean) ==
               [json: true, all: true]

      assert CLI.parse_options([], json: :boolean) == []
    end

    test "refuses positional arguments and unknown switches" do
      assert_raise Mix.Error, "unexpected arguments: a b", fn ->
        CLI.parse_options(~w(a --all b), CLI.selection_switches())
      end

      assert_raise Mix.Error, ~r/--json/, fn ->
        CLI.parse_options(~w(--json), CLI.selection_switches())
      end
    end
  end

  describe "selection_opts/1" do
    test "fills the defaults when no selection switch is given" do
      assert CLI.selection_opts([]) == [all: false, packages: [], base: nil, docs: false]
    end

    test "collects every --package in order and ignores other options" do
      {opts, []} =
        CLI.parse(
          ~w(--package b --json --package a --docs --base origin/main),
          [json: :boolean] ++ CLI.selection_switches()
        )

      assert CLI.selection_opts(opts) ==
               [all: false, packages: ~w(b a), base: "origin/main", docs: true]
    end
  end

  describe "select!/3" do
    test "--all selects every package in topological order", %{manifest: manifest} do
      assert CLI.select!(manifest, all: true) == @order
      assert CLI.select!(manifest, [all: true], :changed) == @order
    end

    test "named packages come back in topological order", %{manifest: manifest} do
      assert CLI.select!(manifest, package: "lab", package: "core") == ~w(core lab)
    end

    test "only: keeps the packages with that mark", %{manifest: manifest} do
      # Named packages are all changed; none is a dependent.
      assert CLI.select!(manifest, [package: "lab"], :changed) == ~w(lab)
      assert CLI.select!(manifest, [package: "lab"], :dependent) == []
    end

    test "an unknown package fails the task with the selection error", %{manifest: manifest} do
      assert catch_exit(CLI.select!(manifest, package: "core", package: "nope")) ==
               {:shutdown, 1}

      assert_received {:mix_shell, :error, ["unknown package(s): nope"]}
    end
  end

  describe "classify!/2" do
    test "marks --all and named packages changed", %{manifest: manifest} do
      assert CLI.classify!(manifest, all: true) == Enum.map(@order, &{&1, :changed})

      assert CLI.classify!(manifest, package: "http", package: "runtime") ==
               [{"runtime", :changed}, {"http", :changed}]
    end

    test "unknown packages fail the task", %{manifest: manifest} do
      assert catch_exit(CLI.classify!(manifest, package: "a", package: "b")) == {:shutdown, 1}
      assert_received {:mix_shell, :error, ["unknown package(s): a, b"]}
    end
  end

  describe "package!/2" do
    test "returns a manifest package's name", %{manifest: manifest} do
      assert CLI.package!(manifest, "coap") == "coap"
    end

    test "fails the task and lists the known packages", %{manifest: manifest} do
      assert catch_exit(CLI.package!(manifest, "wotex-nope")) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message == ~s(unknown package "wotex-nope"; known: #{Enum.join(@order, ", ")})
    end
  end

  describe "fail/1" do
    test "prints the message as an error and exits with status 1" do
      assert catch_exit(CLI.fail("something broke")) == {:shutdown, 1}
      assert_received {:mix_shell, :error, ["something broke"]}
      refute_received {:mix_shell, :info, _}
    end
  end

  describe "timed/1" do
    test "returns the function's result and the elapsed seconds" do
      assert {{:done, 42}, seconds} =
               CLI.timed(fn ->
                 send(self(), :ran)
                 Process.sleep(20)
                 {:done, 42}
               end)

      assert is_float(seconds)
      assert seconds >= 0.02
      assert_received :ran
      refute_received :ran
    end
  end
end
