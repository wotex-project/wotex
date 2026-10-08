defmodule Wotex.Zigbee.PollControlOwnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee
  alias Wotex.Zigbee.{Config, DataRequest, Interview, Routes, TestSerialPeer}
  alias Wotex.Zigbee.ZCL.PollControl

  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>
  @route 0x1234

  test "a scripted check-in and explicit commands keep source, NCP and Default Response distinct" do
    {handle, peer, routes} = interviewed_peer()
    send(peer, {:inject, incoming(<<25, 7, 0>>)})
    wait_events(handle.owner)
    assert {:ok, %{events: [event]}} = Zigbee.drain_events(handle, 32)
    assert {:ok, observation} = PollControl.observe_checkin(routes, event, now())
    assert observation.event == event
    assert observation.event.security_used == false
    assert observation.response_window == :open
    refute_receive {:serial_write, <<0xFE, _, 0x24, 1, _::binary>>}, 10

    cases = [
      {PollControl.checkin_response(7, true, 40), <<1, 7, 0, 1, 40, 0>>, 7, 0},
      {PollControl.fast_poll_stop(8), <<1, 8, 1>>, 8, 1},
      {PollControl.set_long_poll_interval(9, 20), <<1, 9, 2, 20, 0, 0, 0>>, 9, 2},
      {PollControl.set_short_poll_interval(10, 2), <<1, 10, 3, 2, 0>>, 10, 3}
    ]

    for {{:ok, payload}, expected, sequence, command} <- cases do
      assert payload == expected

      {:ok, request} =
        DataRequest.new(
          peer_ieee: @ieee,
          route_address: @route,
          destination_endpoint: 1,
          source_endpoint: 2,
          cluster: 0x0020,
          transaction: sequence,
          correlation_id: <<command>>,
          data: payload
        )

      call = Task.async(fn -> Zigbee.send_routed_data(handle, routes, request, 1_000) end)
      size = byte_size(expected)
      length = size + 10

      assert_receive {:serial_write,
                      <<0xFE, ^length, 0x24, 1, @route::little-16, 1, 2, 0x20::little-16, ^sequence,
                        0x50, 5, ^size, ^expected::binary-size(^size), _>>}

      send(peer, {:inject, wire(0x64, 1, <<0>>)})
      assert {:ok, %{status: 0}} = Task.await(call)
      assert {:ok, %{events: []}} = Zigbee.drain_events(handle, 32)
      response = <<8, sequence, 11, command, 0x87>>
      send(peer, {:inject, incoming(response)})
      wait_events(handle.owner)
      assert {:ok, %{events: [response_event]}} = Zigbee.drain_events(handle, 32)
      assert response_event.security_used == false
      assert {:ok, decoded} = PollControl.decode(response_event.payload)
      assert decoded.command == :default_response
      assert decoded.sequence == sequence
      assert decoded.parameters.status == {:error, 0x87}
      refute_receive {:serial_write, <<0xFE, _, 0x24, 1, _::binary>>}, 10
    end

    assert :ok = Zigbee.close(handle)
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
    {:ok, routes} = Routes.adopt(routes, result, now(), 20_000)
    {handle, peer, routes}
  end

  defp incoming(data),
    do:
      wire(
        0x44,
        0x81,
        <<0::16, 0x20::little-16, @route::little-16, 1, 2, 0, 200, 0, 0::32, 0, byte_size(data),
          data::binary>>
      )

  defp wire(command, id, payload) do
    body = <<byte_size(payload), command, id, payload::binary>>
    checksum = Enum.reduce(:binary.bin_to_list(body), 0, &Bitwise.bxor/2)
    <<0xFE, body::binary, checksum>>
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp wait_events(owner, attempts \\ 100)

  defp wait_events(owner, attempts) when attempts > 0 do
    if :sys.get_state(owner).event_count > 0 do
      :ok
    else
      Process.sleep(1)
      wait_events(owner, attempts - 1)
    end
  end

  defp wait_events(_, 0), do: flunk("Poll Control indication was not queued")
end
