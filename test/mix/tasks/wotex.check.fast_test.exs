defmodule Mix.Tasks.Wotex.Check.FastTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Check.Fast

  test "takes the selection switches" do
    assert Fast.parse_args(~w(--package wotex --package wotex-nx)) ==
             [package: "wotex", package: "wotex-nx"]

    assert_raise Mix.Error, fn -> Fast.parse_args(~w(--lane current)) end
  end
end
