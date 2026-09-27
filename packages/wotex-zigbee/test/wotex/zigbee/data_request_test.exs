defmodule Wotex.Zigbee.DataRequestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee
  alias Wotex.Zigbee.{Config, DataRequest, Error, Reply, TestSerialPeer}

  @peer <<0x00, 0x12, 0x4B, 0x00, 0x23, 0x45, 0x67, 0x89>>
  @options [
    peer_ieee: @peer,
    route_address: 0x1234,
    destination_endpoint: 2,
    source_endpoint: 1,
    cluster: 0x0006,
    transaction: 7,
    correlation_id: "caller-7",
    data: <<1, 2>>
  ]

  test "the request carries durable identity and caller correlation outside the wire payload" do
    assert {:ok, %DataRequest{} = request} = DataRequest.new(@options)
    assert DataRequest.valid?(request)
    assert request.peer_ieee == @peer
    assert request.correlation_id == "caller-7"
    assert request.aps_ack and request.aps_security

    assert {:ok, config} =
             Config.new(
               serial: TestSerialPeer,
               device_id: "simulated-coordinator",
               expected_version: {2, 0, 3, 2, 0},
               serial_options: [test_pid: self()]
             )

    assert {:ok, handle} = Zigbee.open(config)
    assert_receive {:serial_open, _, _}
    assert_receive {:serial_write, <<0xFE, 0, 0x21, 2, 0x23>>}

    assert {:ok, %Reply{subsystem: 4, id: 1, status: 0}} =
             Zigbee.send_data(handle, request, 100)

    assert_receive {:serial_write, <<0xFE, _, 0x24, 1, frame::binary>>}
    assert <<0x34, 0x12, 2, 1, 6, 0, 7, 0x50, 5, 2, 1, 2, _>> = frame
    assert :nomatch == :binary.match(frame, @peer)
    assert :nomatch == :binary.match(frame, "caller-7")
    assert :ok = Zigbee.close(handle)
  end

  test "invalid identities, routes, correlation and payload fail before serial I/O" do
    assert {:error, %Error{kind: :invalid_command}} = DataRequest.new([])
    assert {:error, %Error{kind: :invalid_command}} = DataRequest.new(:invalid)

    assert {:error, %Error{kind: :invalid_command}} =
             DataRequest.new([{:route_address, 1} | @options])

    for change <- [
          [peer_ieee: <<0::64>>],
          [peer_ieee: :binary.copy(<<255>>, 8)],
          [peer_ieee: <<1, 2>>],
          [route_address: 0xFFFF],
          [destination_endpoint: 0],
          [source_endpoint: 241],
          [cluster: 0x10000],
          [transaction: 256],
          [correlation_id: <<>>],
          [correlation_id: :binary.copy("x", 65)],
          [data: :binary.copy(<<1>>, 129)],
          [aps_security: :unknown],
          [radius: 31],
          [credential_bytes: <<1, 2, 3>>]
        ] do
      assert {:error, %Error{kind: :invalid_command}} =
               DataRequest.new(Keyword.merge(@options, change))
    end

    assert {:ok, request} = DataRequest.new(@options)
    refute DataRequest.valid?(%DataRequest{request | route_address: 0xFFFF})
    refute DataRequest.valid?(:not_a_request)

    assert {:error, %Error{kind: :invalid_command}} =
             Zigbee.send_data(:no_owner, %DataRequest{request | route_address: 0xFFFF}, 100)
  end
end
