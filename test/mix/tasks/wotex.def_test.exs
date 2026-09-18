defmodule Mix.Tasks.Wotex.DefTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Def

  test "takes MODULE [FUN] in either spelling" do
    assert Def.parse_args(~w(Wotex.Runtime.Request from_selection)) ==
             {"Wotex.Runtime.Request", "from_selection", []}

    assert Def.parse_args(~w(Wotex.Runtime.Request.from_selection/2 --strict)) ==
             {"Wotex.Runtime.Request", "from_selection", [strict: true]}

    assert Def.parse_args(~w(Wotex.CoAP.Block)) == {"Wotex.CoAP.Block", nil, []}
    assert_raise Mix.Error, ~r/usage: mix def MODULE/, fn -> Def.parse_args([]) end
  end
end
