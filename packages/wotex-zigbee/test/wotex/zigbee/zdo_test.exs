defmodule Wotex.Zigbee.ZDOTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{Error, Event, Frame, ZDO}

  test "IEEE identity responses preserve raw byte order and bounded association pages" do
    ieee = <<8, 7, 6, 5, 4, 3, 2, 1>>
    payload = <<0, ieee::binary, 0x1234::little-16, 1, 3, 0x5678::little-16, 0x1234::little-16>>

    assert {:ok,
            %{
              peer_ieee: ^ieee,
              network_address: 0x1234,
              start_index: 1,
              associated_count: 3,
              associated_devices: [0x5678, 0x1234]
            }} = ZDO.ieee_address(payload)

    assert %Event{kind: :zdo_ieee_address, source_address: nil, zdo: %{peer_ieee: ^ieee}} =
             Event.from_frame(%Frame{type: :areq, subsystem: 5, id: 0x81, payload: payload})

    assert {:ok, %{status: 0x81, associated_devices: []}} =
             ZDO.ieee_address(<<0x81, ieee::binary, 0x1234::little-16, 0, 0>>)

    routes = :binary.copy(<<0x1234::little-16>>, 35)

    assert {:ok, %{associated_devices: devices}} =
             ZDO.ieee_address(<<0, ieee::binary, 0x1234::little-16, 0, 35, routes::binary>>)

    assert length(devices) == 35
  end

  test "node responses preserve reserved flags and failed descriptors remain unavailable" do
    raw =
      <<0xFA, 0xF1, 0x8E, 0x1234::little-16, 80, 128::little-16, 0xABCD::little-16, 256::little-16,
        0xF3>>

    payload = <<0x1234::little-16, 0, 0x1234::little-16, raw::binary>>
    assert {:ok, %{descriptor: descriptor, raw_descriptor: ^raw}} = ZDO.node_descriptor(payload)
    assert descriptor.logical_type == 2
    assert descriptor.logical_flags == 0xFA
    assert descriptor.aps_flags_frequency == 0xF1
    assert descriptor.mac_capabilities == 0x8E
    assert descriptor.manufacturer_code == 0x1234
    assert descriptor.max_buffer_bytes == 80
    assert descriptor.max_incoming_transfer_bytes == 128
    assert descriptor.server_mask == 0xABCD
    assert descriptor.max_outgoing_transfer_bytes == 256
    assert descriptor.descriptor_capabilities == 0xF3

    assert %Event{kind: :zdo_node_descriptor, zdo: %{descriptor: ^descriptor}} =
             Event.from_frame(%Frame{type: :areq, subsystem: 5, id: 0x82, payload: payload})

    assert {:ok, %{status: 0x89, descriptor: nil, raw_descriptor: ^raw}} =
             ZDO.node_descriptor(<<0x1234::little-16, 0x89, 0x1234::little-16, raw::binary>>)
  end

  test "truncation, excessive association pages and contradictory counts are malformed" do
    identity = <<0, 8, 7, 6, 5, 4, 3, 2, 1, 0x34, 0x12>>

    for payload <- [
          identity,
          identity <> <<0, 0, 1, 0>>,
          identity <> <<0, 1, 1>>,
          identity <> <<2, 2, 1, 0>>,
          identity <> <<0, 36>> <> :binary.copy(<<1, 0>>, 36),
          nil
        ] do
      assert {:error, %Error{kind: :invalid_frame}} = ZDO.ieee_address(payload)
    end

    for {id, payload} <- [{0x81, identity}, {0x82, <<0::136>>}, {0x82, <<0::152>>}] do
      assert %Event{kind: :malformed_indication, payload: ^payload} =
               Event.from_frame(%Frame{type: :areq, subsystem: 5, id: id, payload: payload})
    end
  end

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
