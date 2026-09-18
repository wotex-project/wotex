defmodule Mix.Tasks.Wotex.RefsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Refs

  test "takes MODULE [FUN] in either spelling" do
    assert Refs.parse_args(~w(Wotex.CoAP.Block encode/1)) == {"Wotex.CoAP.Block", "encode"}
    assert Refs.parse_args(~w(Wotex.CoAP.Block.encode)) == {"Wotex.CoAP.Block", "encode"}
  end

  test "rejects extra arguments and switches" do
    assert_raise Mix.Error, ~r/usage: mix refs/, fn -> Refs.parse_args(~w(A b c)) end
    assert_raise Mix.Error, fn -> Refs.parse_args(~w(A --run)) end
  end
end
