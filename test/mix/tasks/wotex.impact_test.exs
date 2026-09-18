defmodule Mix.Tasks.Wotex.ImpactTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Mix.Tasks.Wotex.Impact

  test "takes MODULE [FUN] and --run" do
    assert Impact.parse_args(~w(Wotex.CoAP.Block --run)) == {"Wotex.CoAP.Block", nil, [run: true]}
    assert_raise Mix.Error, ~r/usage: mix impact/, fn -> Impact.parse_args(~w(--run)) end
  end
end
