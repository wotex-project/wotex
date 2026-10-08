defmodule Wotex.Zigbee.RoutesOwnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee
  alias Wotex.Zigbee.{Config, DataRequest, Error, Interview, Routes, TestSerialPeer}

  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>
  @route 0x1234

  test "independent peer interview establishes adopted custody and incoming source resolution" do
    {handle, peer, result} = inspect_peer()
    {:ok, routes} = Routes.new(result.owner_epoch)
    {:ok, routes} = Routes.adopt(routes, result, now(), 5_000)
    call = Task.async(fn -> Zigbee.send_routed_data(handle, routes, request(), 1_000) end)

    assert_receive {:serial_write,
                    <<0xFE, 11, 0x24, 1, @route::little-16, 1, 2, 6::little-16, 7, 0x50, 5, 1, 0,
                      _>>}

    send(peer, {:inject, wire(0x64, 1, <<0>>) <> incoming()})
    assert {:ok, %{status: 0}} = Task.await(call)
    assert {:ok, %{events: [event]}} = Zigbee.drain_events(handle, 10)
    assert event.owner_epoch == result.owner_epoch
    assert is_integer(event.received_at_ms)

    assert {:ok, %{entry: %{peer_ieee: @ieee}, event: ^event}} =
             Routes.resolve(routes, event, now())

    assert event.security_used == false
  end

  test "receiver refuses identity mismatch, copied table and another epoch before serial I/O" do
    {handle, _, result} = inspect_peer()
    {:ok, routes} = Routes.new(result.owner_epoch)
    {:ok, routes} = Routes.adopt(routes, result, now(), 5_000)

    assert {:error, %Error{kind: :route_mismatch}} =
             Zigbee.send_routed_data(handle, routes, %{request() | route_address: 1}, 1_000)

    assert {:error, %Error{kind: :unknown_route}} =
             Zigbee.send_routed_data(
               handle,
               routes,
               %{request() | peer_ieee: <<1, 2, 3, 4, 5, 6, 7, 8>>},
               1_000
             )

    assert {:error, %Error{kind: :invalid_value} = error} =
             Zigbee.send_routed_data(
               handle,
               Map.put(routes, :key, "credential-canary"),
               request(),
               1_000
             )

    refute inspect(error) =~ "credential-canary"
    {:ok, other} = Routes.new(make_ref())

    assert {:error, %Error{kind: :stale_epoch}} =
             Zigbee.send_routed_data(handle, other, request(), 1_000)

    assert {:error, %Error{kind: :invalid_value}} =
             Zigbee.send_routed_data(handle, routes, nil, 1_000)

    assert {:error, %Error{kind: :stale_handle}} =
             Zigbee.send_routed_data(%{handle | epoch: make_ref()}, routes, request(), 1_000)

    refute_receive {:serial_write, _}, 10
  end

  test "a queued guarded send rechecks custody expiry and leaves the owner usable" do
    {handle, _, result} = inspect_peer()
    {:ok, routes} = Routes.new(result.owner_epoch)
    {:ok, routes} = Routes.adopt(routes, result, now(), 250)
    :ok = :sys.suspend(handle.owner)
    call = Task.async(fn -> Zigbee.send_routed_data(handle, routes, request(), 1_000) end)
    wait_queued(handle.owner)
    Process.sleep(260)
    :ok = :sys.resume(handle.owner)
    assert {:error, %Error{kind: :route_expired}} = Task.await(call)
    assert {:ok, _} = Zigbee.handle(handle.owner)
    refute_receive {:serial_write, _}, 10
  end

  test "an admitted guarded send cannot wait beyond custody expiry" do
    {handle, _, result} = inspect_peer()
    {:ok, routes} = Routes.new(result.owner_epoch)
    {:ok, routes} = Routes.adopt(routes, result, now(), 250)
    call = Task.async(fn -> Zigbee.send_routed_data(handle, routes, request(), 1_000) end)
    assert_receive {:serial_write, <<0xFE, 11, 0x24, 1, _::binary>>}
    assert {:error, %Error{kind: :timeout}} = Task.await(call, 500)
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.handle(handle.owner)
  end

  test "source metadata from a prior serial owner cannot resolve under a replacement owner" do
    {first, first_peer, result} = inspect_peer()
    {:ok, routes} = Routes.new(result.owner_epoch)
    {:ok, routes} = Routes.adopt(routes, result, now(), 5_000)
    send(first_peer, {:inject, incoming()})
    :sys.get_state(first.owner)
    wait_event(first.owner)
    {:ok, %{events: [old]}} = Zigbee.drain_events(first, 10)
    :ok = Zigbee.close(first)
    {next, _, next_result} = inspect_peer()
    {:ok, routes} = Routes.rebind(routes, next_result.owner_epoch)
    assert {:error, %Error{kind: :stale_epoch}} = Routes.resolve(routes, old, now())

    assert {:error, %Error{kind: :stale_epoch}} =
             Zigbee.send_routed_data(next, routes, request(), 1_000)

    {:ok, routes} = Routes.adopt(routes, next_result, now(), 5_000)
    assert {:ok, _} = Routes.check_request(routes, request(), next_result.owner_epoch, now())
    refute_receive {:serial_write, _}, 10
  end

  test "owner observation sequence exhaustion fences the epoch without wrapping" do
    {handle, peer, _} = inspect_peer()

    :sys.replace_state(handle.owner, fn state ->
      %{state | observation_sequence: 0xFFFFFFFFFFFFFFFF}
    end)

    monitor = Process.monitor(handle.owner)
    send(peer, {:inject, incoming()})
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.handle(handle.owner)
  end

  defp inspect_peer do
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

    assert {:ok, result} = Task.await(call)
    assert result.outcome == :complete
    {handle, peer, result}
  end

  defp request do
    {:ok, request} =
      DataRequest.new(
        peer_ieee: @ieee,
        route_address: @route,
        destination_endpoint: 1,
        source_endpoint: 2,
        cluster: 6,
        transaction: 7,
        correlation_id: "request",
        data: <<0>>
      )

    request
  end

  defp incoming,
    do:
      wire(0x44, 0x81, <<0::16, 6::little-16, @route::little-16, 1, 2, 0, 200, 0, 0::32, 0, 1, 0>>)

  defp wire(command, id, payload) do
    body = <<byte_size(payload), command, id, payload::binary>>
    checksum = Enum.reduce(:binary.bin_to_list(body), 0, &Bitwise.bxor/2)
    <<0xFE, body::binary, checksum>>
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp wait_queued(owner, attempts \\ 100)

  defp wait_queued(owner, attempts) when attempts > 0 do
    if elem(Process.info(owner, :message_queue_len), 1) > 0 do
      :ok
    else
      Process.sleep(1)
      wait_queued(owner, attempts - 1)
    end
  end

  defp wait_queued(_, 0), do: flunk("guarded send was not queued")
  defp wait_event(owner, attempts \\ 100)

  defp wait_event(owner, attempts) when attempts > 0 do
    if :sys.get_state(owner).event_count > 0 do
      :ok
    else
      Process.sleep(1)
      wait_event(owner, attempts - 1)
    end
  end

  defp wait_event(_, 0), do: flunk("source event was not received")
end
