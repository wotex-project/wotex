defmodule Wotex.Zigbee.FreshnessOwnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee
  alias Wotex.Zigbee.{Config, Error, Freshness, Interview, Routes, TestSerialPeer}
  alias Wotex.Zigbee.Freshness.Policy
  alias Wotex.Zigbee.ZCL.PollControl

  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>
  @route 0x1234

  test "independently framed reports and Check-in preserve cadence, partial values and trust" do
    {handle, peer, routes} = interviewed_peer()
    report = report_policy()
    checkin = checkin_policy()
    {:ok, table} = Freshness.new(handle.epoch)
    {:ok, table} = Freshness.arm(table, report, now())
    {:ok, table} = Freshness.arm(table, checkin, now())
    send(peer, {:inject, incoming(6, <<8, 7, 10, 0::little-16, 0x21, 42::little-16>>)})
    first = drain_one(handle)
    assert first.owner_epoch == handle.epoch
    assert first.security_used == false

    assert {:ok, %{table: table, matched: [%{receipt: eligible}]}} =
             Freshness.observe(table, routes, first, now())

    assert eligible.event == first
    assert [%{value: 42, raw: <<42, 0>>}] = eligible.records

    send(peer, {:inject, incoming(6, <<8, 8, 10, 0::little-16, 0x20, 99>>)})
    partial = drain_one(handle)
    assert partial.owner_sequence > first.owner_sequence

    assert {:ok, %{table: table, matched: [%{receipt: latest}]}} =
             Freshness.observe(table, routes, partial, now())

    assert latest.disposition == :wrong_type
    assert [%{value: 99, raw: <<99>>}] = latest.records

    send(peer, {:inject, incoming(32, <<25, 9, 0>>)})
    checkin_event = drain_one(handle)
    assert {:ok, checked} = PollControl.observe_checkin(routes, checkin_event, now())

    assert {:ok, %{table: table, matched: [%{receipt: checkin_receipt}]}} =
             Freshness.observe(table, routes, checkin_event, now())

    assert checkin_receipt.event == checked.event
    assert checkin_receipt.disposition == :checkin
    assert checkin_receipt.event.security_used == false
    assert checked.response_deadline_ms == checkin_event.received_at_ms + 7_680

    assert {:error, %Error{kind: :stale_observation}} =
             Freshness.observe(table, routes, first, now())

    send(peer, {:inject, incoming(6, <<8, 10, 10, 0::16, 0x21, 100::little-16>>, 0x2345)})
    unrelated = drain_one(handle)

    assert {:error, %Error{kind: :unknown_route}} =
             Freshness.observe(table, routes, unrelated, now())

    assert {:ok, %{rows: [checkin_row, report_row]}} =
             Freshness.snapshot(table, first.received_at_ms + 61_000)

    assert report_row.state == :late
    assert report_row.eligible == eligible
    assert report_row.latest == latest
    assert report_row.due_at_ms == first.received_at_ms + 61_000
    assert checkin_row.state == :within_window
    assert checkin_row.due_at_ms == checkin_event.received_at_ms + 172_860_000
    refute_receive {:serial_write, _}, 10
    assert :ok = Zigbee.close(handle)
  end

  test "a new serial owner cannot inherit old cadence observations through copied source context" do
    {first, first_peer, routes} = interviewed_peer()
    {:ok, table} = Freshness.new(first.epoch)
    {:ok, table} = Freshness.arm(table, report_policy(), now())
    send(first_peer, {:inject, incoming(6, <<8, 7, 10, 0::16, 0x21, 42::little-16>>)})
    old = drain_one(first)

    {:ok, %{table: table, matched: [%{receipt: previous}]}} =
      Freshness.observe(table, routes, old, now())

    :ok = Zigbee.close(first)
    {next, next_peer, next_routes} = interviewed_peer()
    {:ok, table} = Freshness.rebind(table, next.epoch, now())

    assert {:error, %Error{kind: :stale_epoch}} =
             Freshness.observe(table, next_routes, old, now())

    send(next_peer, {:inject, incoming(6, <<8, 7, 10, 0::16, 0x21, 0xFFFF::16>>)})
    current = drain_one(next)

    assert {:ok, %{table: table, matched: [%{receipt: receipt}]}} =
             Freshness.observe(table, next_routes, current, now())

    assert receipt.disposition == :null
    assert [%{value: :null}] = receipt.records

    assert {:ok, %{rows: [%{eligible: ^receipt, previous: %{receipt: ^previous}}]}} =
             Freshness.snapshot(table, now())

    assert Freshness.valid?(table)
    refute_receive {:serial_write, _}, 10
    assert :ok = Zigbee.close(next)
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

  defp incoming(cluster, data, source \\ @route),
    do:
      wire(
        0x44,
        0x81,
        <<0::16, cluster::little-16, source::little-16, 1, 2, 0, 200, 0, 0::32, 0, byte_size(data),
          data::binary>>
      )

  defp wire(command, id, payload) do
    body = <<byte_size(payload), command, id, payload::binary>>
    checksum = Enum.reduce(:binary.bin_to_list(body), 0, &Bitwise.bxor/2)
    <<0xFE, body::binary, checksum>>
  end

  defp report_policy do
    {:ok, policy} =
      Policy.report(
        peer_ieee: @ieee,
        remote_endpoint: 1,
        local_endpoint: 2,
        cluster: 6,
        attribute_id: 0,
        type: 0x21,
        expected_interval_ms: 60_000,
        grace_ms: 1_000
      )

    policy
  end

  defp checkin_policy do
    {:ok, policy} =
      Policy.checkin(
        peer_ieee: @ieee,
        remote_endpoint: 1,
        local_endpoint: 2,
        expected_interval_ms: 172_800_000,
        grace_ms: 60_000
      )

    policy
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp drain_one(handle) do
    wait_events(handle.owner)
    assert {:ok, %{events: [event], dropped: 0}} = Zigbee.drain_events(handle, 32)
    event
  end

  defp wait_events(owner, attempts \\ 100)

  defp wait_events(owner, attempts) when attempts > 0 do
    if :sys.get_state(owner).event_count > 0 do
      :ok
    else
      Process.sleep(1)
      wait_events(owner, attempts - 1)
    end
  end

  defp wait_events(_, 0), do: flunk("freshness indication was not queued")
end
