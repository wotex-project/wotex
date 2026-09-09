defmodule Wotex.BACnet.InvokeIdsTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.BACnet.InvokeIds

  test "WBA-S02 WBA-V05 cancelled identifiers are unavailable until the finite retry window ends" do
    state = Enum.reduce(0..255, InvokeIds.new(), &InvokeIds.retire(&2, &1, 10))
    assert map_size(state.retired) == 256
    assert :busy = InvokeIds.allocate(state, %{}, 60_009)
    assert {:ok, 0, %{next: 1, retired: %{}}} = InvokeIds.allocate(state, %{}, 60_010)

    assert :busy =
             InvokeIds.allocate(
               InvokeIds.new(),
               Map.new(0..255, &{{:source, nil, &1}, :pending}),
               0
             )

    assert {:ok, 1, %{next: 2}} =
             InvokeIds.allocate(InvokeIds.new(), %{{:source, nil, 0} => :pending}, 0)

    assert {:ok, 255, %{next: 0}} = InvokeIds.allocate(%{InvokeIds.new() | next: 255}, %{}, 0)
  end
end
