defmodule Wotex.BACnet.COVCacheTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.BACnet.COVCache

  test "WBA-S04 WBA-V07 duplicate window expires without refresh and full cache evicts oldest" do
    key = {:source, 7, :crypto.hash(:sha256, <<1>>)}
    assert {false, entries} = COVCache.touch([], key, 0, 60_000)
    assert {true, ^entries} = COVCache.touch(entries, key, 59_999, 60_000)
    assert {false, [{^key, 120_000}]} = COVCache.touch(entries, key, 60_000, 60_000)

    assert {false, _} =
             COVCache.touch(entries, {:source, 7, :crypto.hash(:sha256, <<2>>)}, 1, 60_000)

    entries =
      Enum.reduce(0..1023, [], fn key, acc ->
        {false, next} = COVCache.touch(acc, key, 0, 60_000)
        next
      end)

    assert length(entries) == 1024
    assert {false, next} = COVCache.touch(entries, :fresh, 0, 60_000)
    refute List.keymember?(next, 0, 0)
    assert hd(next) == {1, 60_000}
    assert length(next) == 1024
    assert {false, [{:after_expiry, 60_001}]} = COVCache.touch(next, :after_expiry, 60_000, 1)
  end
end
