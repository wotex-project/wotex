defmodule Wotex.Zigbee.ZCLConfigurationOwnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee
  alias Wotex.Zigbee.{Config, DataRequest, Interview, Routes, TestSerialPeer}
  alias Wotex.Zigbee.ZCL.Configuration

  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>
  @route 0x1234

  test "scripted peer separates explicit configuration, NCP admission, APS and ZCL outcomes" do
    {:ok, write} =
      Configuration.write_attributes(
        [%{id: 0x10, type: 0x21, value: 0x1234}],
        19,
        :client_to_server,
        0x1234
      )

    {:ok, configure} =
      Configuration.configure_reporting(
        [%{id: 1, report_direction: :receive, timeout_s: 10}],
        19,
        :client_to_server
      )

    {:ok, read} =
      Configuration.read_reporting([%{id: 1, report_direction: :receive}], 19, :client_to_server)

    cases = [
      {write, <<4, 0x34, 0x12, 19, 2, 0x10::little-16, 0x21, 0x34, 0x12>>,
       <<12, 0x34, 0x12, 19, 4, 0>>, :reported_success, :success},
      {configure, <<0, 19, 6, 1, 1::little-16, 10::little-16>>, <<8, 19, 7, 0x86, 1, 1::little-16>>,
       :partial, {:error, 0x86}},
      {read, <<0, 19, 8, 1, 1::little-16>>, <<8, 19, 9, 0, 1, 1::little-16, 10::little-16>>,
       :reported_success, :success}
    ]

    for {request, expected_wire, response, outcome, status} <- cases do
      {handle, peer, routes} = interviewed_peer()
      assert request.payload == expected_wire

      {:ok, af} =
        DataRequest.new(
          peer_ieee: @ieee,
          route_address: @route,
          destination_endpoint: 1,
          source_endpoint: 2,
          cluster: 6,
          transaction: 7,
          correlation_id: "configuration",
          data: request.payload
        )

      call = Task.async(fn -> Zigbee.send_routed_data(handle, routes, af, 1_000) end)
      data_length = byte_size(expected_wire)
      length = data_length + 10

      assert_receive {:serial_write,
                      <<0xFE, ^length, 0x24, 1, @route::little-16, 1, 2, 6::little-16, 7, 0x50, 5,
                        ^data_length, ^expected_wire::binary-size(^data_length), _>>}

      send(peer, {:inject, wire(0x64, 1, <<0>>)})
      assert {:ok, %{status: 0}} = Task.await(call)
      assert {:ok, %{events: []}} = Zigbee.drain_events(handle, 10)
      send(peer, {:inject, wire(0x44, 0x80, <<0, 2, 7>>) <> incoming(response)})
      wait_events(handle.owner, 2)
      assert {:ok, %{events: [confirmation, event]}} = Zigbee.drain_events(handle, 10)
      assert confirmation.kind == :aps_confirm
      assert confirmation.transaction == 7
      assert {:ok, result} = Configuration.observe(request, af, routes, event, now())
      assert result.outcome == outcome
      assert [record] = result.records
      assert record.status == status
      assert result.event == event
      assert event.security_used == false
      refute_receive {:serial_write, _}, 10
      :ok = Zigbee.close(handle)
    end
  end

  defp interviewed_peer do
    {:ok, config} =
      Config.new(
        serial: TestSerialPeer,
        device_id: "simulated-coordinator",
        expected_version: {2, 0, 3, 2, 0},
        timeout_ms: 1_000,
        serial_options: [test_pid: self(), drop_reply: true]
      )

    {:ok, handle} = Zigbee.open(config)
    on_exit(fn -> Zigbee.close(handle) end)
    assert_receive {:serial_open, peer, _}
    assert_receive {:serial_write, <<0xFE, 0, 0x21, 2, _>>}
    {:ok, request} = Interview.new(peer_ieee: @ieee, route_address: @route, source_endpoint: 2)
    call = Task.async(fn -> Zigbee.interview(handle, request, 1_000) end)
    assert_receive {:serial_write, <<0xFE, 4, 0x25, 1, _::binary>>}

    send(
      peer,
      {:inject,
       wire(0x65, 1, <<0>>) <> wire(0x45, 0x81, <<0, @ieee::binary, @route::little-16, 0, 0>>)}
    )

    assert_receive {:serial_write, <<0xFE, 4, 0x25, 2, _::binary>>}

    send(
      peer,
      {:inject,
       wire(0x65, 2, <<0>>) <>
         wire(0x45, 0x82, <<@route::little-16, 0, @route::little-16, 0::104>>)}
    )

    assert_receive {:serial_write, <<0xFE, 4, 0x25, 5, _::binary>>}

    send(
      peer,
      {:inject,
       wire(0x65, 5, <<0>>) <> wire(0x45, 0x85, <<@route::little-16, 0, @route::little-16, 0>>)}
    )

    assert {:ok, %{outcome: :complete} = result} = Task.await(call)
    {:ok, routes} = Routes.new(result.owner_epoch)
    {:ok, routes} = Routes.adopt(routes, result, now(), 5_000)
    {handle, peer, routes}
  end

  defp incoming(data),
    do:
      wire(
        0x44,
        0x81,
        <<0::16, 6::little-16, @route::little-16, 1, 2, 0, 200, 0, 0::32, 0, byte_size(data),
          data::binary>>
      )

  defp wire(command, id, payload) do
    body = <<byte_size(payload), command, id, payload::binary>>
    checksum = Enum.reduce(:binary.bin_to_list(body), 0, &Bitwise.bxor/2)
    <<0xFE, body::binary, checksum>>
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp wait_events(owner, count, attempts \\ 100)

  defp wait_events(owner, count, attempts) when attempts > 0 do
    if :sys.get_state(owner).event_count >= count do
      :ok
    else
      Process.sleep(1)
      wait_events(owner, count, attempts - 1)
    end
  end

  defp wait_events(_, _, 0), do: flunk("configuration indications were not queued")
end
