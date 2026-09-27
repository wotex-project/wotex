defmodule Wotex.Zigbee.ZDOTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{Error, Event, Frame, ZDO}

  test "active endpoint responses preserve source, route, status and ordered endpoints" do
    payload = <<0x1234::little-16, 0, 0x5678::little-16, 3, 1, 2, 240>>

    assert {:ok,
            %{source_address: 0x1234, network_address: 0x5678, status: 0, endpoints: [1, 2, 240]}} =
             ZDO.active_endpoints(payload)

    frame = %Frame{type: :areq, subsystem: 5, id: 0x85, payload: payload}

    assert %Event{kind: :zdo_active_endpoints, source_address: 0x1234, status: 0, zdo: response} =
             Event.from_frame(frame)

    assert response.endpoints == [1, 2, 240]

    assert {:ok, %{status: 0x84, endpoints: []}} =
             ZDO.active_endpoints(<<0x1234::little-16, 0x84, 0x5678::little-16, 0>>)
  end

  test "simple descriptor decodes finite input and output clusters" do
    descriptor =
      <<2, 0x0104::little-16, 0x0100::little-16, 0, 2, 0x0006::little-16, 0x0008::little-16, 1,
        0x0019::little-16>>

    payload = <<0x1234::little-16, 0, 0x5678::little-16, byte_size(descriptor), descriptor::binary>>
    assert {:ok, %{descriptor: parsed}} = ZDO.simple_descriptor(payload)
    assert parsed.endpoint == 2
    assert parsed.profile == 0x0104
    assert parsed.device == 0x0100
    assert parsed.input_clusters == [6, 8]
    assert parsed.output_clusters == [0x0019]

    assert %Event{kind: :zdo_simple_descriptor, zdo: %{descriptor: ^parsed}} =
             Event.from_frame(%Frame{type: :areq, subsystem: 5, id: 0x84, payload: payload})

    assert {:ok, %{status: 0x80, descriptor: nil}} =
             ZDO.simple_descriptor(<<0x1234::little-16, 0x80, 0x5678::little-16, 0>>)
  end

  test "bad counts, lengths and truncated descriptors become malformed indications" do
    invalid_active = <<0x1234::little-16, 0, 0x5678::little-16, 2, 1>>
    invalid_simple = <<0x1234::little-16, 0, 0x5678::little-16, 3, 2, 0>>

    for payload <- [invalid_active, <<0, 0, 0, 0, 0, 78>>] do
      assert {:error, %Error{kind: :invalid_frame}} = ZDO.active_endpoints(payload)

      assert %Event{kind: :malformed_indication} =
               Event.from_frame(%Frame{type: :areq, subsystem: 5, id: 0x85, payload: payload})
    end

    for payload <- [invalid_simple, <<0, 0, 0x80, 0, 0, 1, 0>>] do
      assert {:error, %Error{kind: :invalid_frame}} = ZDO.simple_descriptor(payload)

      assert %Event{kind: :malformed_indication} =
               Event.from_frame(%Frame{type: :areq, subsystem: 5, id: 0x84, payload: payload})
    end

    assert {:error, %Error{}} = ZDO.simple_descriptor(<<0, 0, 0, 0, 0, 1, 0>>)
  end
end
