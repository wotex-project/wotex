defmodule Mix.Tasks.Wotex.AffectedTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Affected

  test "accepts --base, --docs, --all, --json and --detail" do
    assert Affected.parse_args(~w(--base main --docs --all --json)) ==
             [base: "main", docs: true, all: true, json: true]

    assert Affected.parse_args(~w(--detail)) == [detail: true]
    assert Affected.parse_args([]) == []
  end

  test "rejects unknown switches and stray arguments" do
    assert_raise Mix.Error, ~r/--nope/, fn -> Affected.parse_args(~w(--nope)) end

    assert_raise Mix.Error, ~r/unexpected arguments: extra/, fn ->
      Affected.parse_args(~w(extra))
    end
  end
end
