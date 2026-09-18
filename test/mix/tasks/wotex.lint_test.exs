defmodule Mix.Tasks.Wotex.LintTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Lint

  test "takes the selection switches" do
    assert Lint.parse_args(~w(--all)) == [all: true]
    assert Lint.parse_args(~w(--package wotex)) == [package: "wotex"]
    assert_raise Mix.Error, fn -> Lint.parse_args(~w(--fix)) end
  end
end
