defmodule Wotex.Zigbee.CommandTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{Command, Error, Frame}

  test "identity and node queries have exact non-administrative request bytes" do
    assert {:ok, identity} = Command.ieee_address(0x1234)
    assert {:ok, <<0xFE, 4, 0x25, 1, 0x34, 0x12, 0, 0, 6>>} = Frame.encode(identity)
    assert {:ok, node} = Command.node_descriptor(0x1234)
    assert {:ok, <<0xFE, 4, 0x25, 2, 0x34, 0x12, 0x34, 0x12, 0x23>>} = Frame.encode(node)

    for address <- [0, 0xFFF7] do
      assert {:ok, frame} = Command.ieee_address(address)
      assert Command.admitted?(frame)
      assert {:ok, frame} = Command.node_descriptor(address)
      assert Command.admitted?(frame)
    end

    for address <- [-1, 0xFFF8, 0xFFFE, 0xFFFF, "route"] do
      assert {:error, %Error{kind: :invalid_command}} = Command.ieee_address(address)
      assert {:error, %Error{kind: :invalid_command}} = Command.node_descriptor(address)
    end
  end

  test "the owner command profile accepts only canonical declared commands" do
    {:ok, active} = Command.active_endpoints(0x1234)
    {:ok, simple} = Command.simple_descriptor(0x1234, 1)
    {:ok, data} = Command.data_request(0x1234, 1, 2, 6, 9, <<0, 255>>)
    assert Command.admitted?(active)
    assert Command.admitted?(simple)
    assert Command.admitted?(data)

    for frame <- [
          nil,
          Command.version(),
          %Frame{active | id: 0x36},
          %Frame{active | payload: <<0x1234::little-16, 0x5678::little-16>>},
          %Frame{simple | payload: <<0x1234::little-16, 0x1234::little-16, 0>>},
          %Frame{data | payload: <<0x1234::little-16, 1, 2, 6::little-16, 9, 0x51, 5, 2, 0, 255>>},
          %Frame{data | payload: <<0x1234::little-16, 1, 2, 6::little-16, 9, 0x50, 5, 3, 0, 255>>},
          Map.put(active, :secret, "frame-canary")
        ] do
      refute Command.admitted?(frame)
    end
  end
end
