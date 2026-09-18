defmodule Mix.Tasks.Wotex.BoundaryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Boundary

  test "takes the selection switches" do
    assert Boundary.parse_args(~w(--package wotex-coap --base main)) ==
             [package: "wotex-coap", base: "main"]

    assert Boundary.parse_args(~w(--all)) == [all: true]
    assert_raise Mix.Error, fn -> Boundary.parse_args(~w(--check)) end
  end
end
