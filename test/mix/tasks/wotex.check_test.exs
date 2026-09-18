defmodule Mix.Tasks.Wotex.CheckTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Check
  alias Wotex.Workspace.CLI

  test "accepts the selection switches, --lane and --env" do
    opts = Check.parse_args(~w(--package wotex --package wotex-nx --lane minimum --env test))

    assert Keyword.get_values(opts, :package) == ~w(wotex wotex-nx)
    assert opts[:lane] == "minimum"
    assert opts[:env] == "test"

    assert CLI.selection_opts(opts) == [
             all: false,
             packages: ~w(wotex wotex-nx),
             base: nil,
             docs: false
           ]

    assert CLI.selection_opts(Check.parse_args(~w(--all --base origin/main))) ==
             [all: true, packages: [], base: "origin/main", docs: false]
  end

  test "rejects an unknown lane" do
    assert_raise Mix.Error, ~r/--lane must be minimum or current/, fn ->
      Check.parse_args(~w(--lane nightly))
    end
  end

  test "passes a lane's skipped tools to mix check" do
    assert Check.commands() == [
             {"deps.get", ["deps.get", "--check-locked"]},
             {"check", ["check", "--no-retry"]}
           ]

    assert Check.commands(["formatter", "dialyzer"]) == [
             {"deps.get", ["deps.get", "--check-locked"]},
             {"check", ["check", "--no-retry", "--except", "formatter", "--except", "dialyzer"]}
           ]
  end
end
