defmodule Mix.Tasks.Wotex.Check.AffectedTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Check.Affected

  test "takes --base and --docs only" do
    assert Affected.parse_args(~w(--base main --docs)) == [base: "main", docs: true]
    assert_raise Mix.Error, fn -> Affected.parse_args(~w(--package wotex)) end
  end
end
