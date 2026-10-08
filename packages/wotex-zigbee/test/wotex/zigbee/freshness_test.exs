defmodule Wotex.Zigbee.FreshnessTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{Error, Event, Freshness, Reply, Routes}
  alias Wotex.Zigbee.Freshness.Policy
  alias Wotex.Zigbee.Interview.Result

  doctest Freshness

  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>
  @report <<8, 7, 10, 0::little-16, 0x21, 42::little-16>>
  @max_time 0x7FFFFFFFFFFFFFFF
  @max_sequence 0xFFFFFFFFFFFFFFFF

  test "policies require exact consumer selectors and distinguish periodic, on-change and disabled" do
    before = Process.info(self(), :messages)
    assert {:ok, periodic} = Policy.report(report_options())
    assert periodic.expected_interval_ms == 100
    assert periodic.grace_ms == 20
    assert periodic.direction == :server_to_client
    assert periodic.manufacturer == nil
    assert periodic.full_range == false

    for type <- [0x10, 0x20, 0x21, 0x23, 0x28, 0x29, 0x41, 0x42] do
      assert {:ok, policy} = Policy.report(report_options(type: type))
      assert Policy.valid?(policy)
    end

    for mode <- [:on_change, :disabled] do
      assert {:ok, policy} = Policy.report(report_options(expected_interval_ms: mode, grace_ms: 0))
      assert Policy.valid?(policy)
    end

    assert {:ok, disabled} = Policy.checkin(checkin_options(expected_interval_ms: :disabled))
    assert disabled.cluster == 32
    assert {:ok, maximum} = Policy.checkin(checkin_options(expected_interval_ms: 31_536_000_000))
    assert Policy.valid?(maximum)
    assert Policy.key(periodic) == Policy.key(report_policy(type: 0x29, full_range: true))
    assert Policy.key(nil) == nil
    assert Process.info(self(), :messages) == before
  end

  test "malformed policies and copied structs fail without leaking input" do
    for replacement <- [
          [peer_ieee: <<0::64>>],
          [peer_ieee: <<0xFFFFFFFFFFFFFFFF::64>>],
          [peer_ieee: <<1, 2>>],
          [remote_endpoint: 0],
          [local_endpoint: 241],
          [cluster: 65_536],
          [attribute_id: -1],
          [type: 0xFE],
          [direction: :unknown],
          [manufacturer: "malformed-canary"],
          [full_range: 1],
          [type: 0x10, full_range: true],
          [type: 0x42, full_range: true],
          [expected_interval_ms: 0],
          [expected_interval_ms: 31_536_000_001],
          [expected_interval_ms: 1.0],
          [grace_ms: -1],
          [grace_ms: 31_536_000_001],
          [expected_interval_ms: :on_change, grace_ms: 1],
          [expected_interval_ms: :disabled, grace_ms: 1]
        ] do
      assert {:error, %Error{kind: :invalid_value} = error} =
               Policy.report(report_options(replacement))

      refute inspect(error) =~ "malformed-canary"
    end

    for options <- [
          nil,
          %{},
          [{:peer_ieee, @ieee}, :bad],
          [{:type, 0x21} | report_options()],
          [{:key, "malformed-canary"} | report_options()],
          Keyword.delete(report_options(), :type)
        ],
        do: assert({:error, _} = Policy.report(options))

    for options <- [
          checkin_options(expected_interval_ms: :on_change),
          checkin_options(cluster: 32),
          checkin_options(expected_interval_ms: 0),
          checkin_options(grace_ms: 1, expected_interval_ms: :disabled)
        ],
        do: assert({:error, _} = Policy.checkin(options))

    policy = report_policy()

    for copied <- [
          Map.delete(policy, :type),
          Map.put(policy, :key, "malformed-canary"),
          %{policy | type: 0xFE},
          %{policy | kind: :checkin},
          %{policy | kind: :other},
          Map.delete(policy, :type) |> Map.put(:key, 0)
        ] do
      refute Policy.valid?(copied)
      assert Policy.key(copied) == nil
    end
  end

  test "long and per-stream intervals use exact grace boundaries without an offline state" do
    epoch = make_ref()
    {:ok, table} = Freshness.new(epoch)
    long = report_policy(expected_interval_ms: 172_800_000, grace_ms: 60_000)
    short = report_policy(attribute_id: 1, expected_interval_ms: 100, grace_ms: 20)
    {:ok, table} = Freshness.arm(table, long, 10)
    {:ok, table} = Freshness.arm(table, short, 10)
    assert {:ok, %{table: table, rows: [long_row, short_row]}} = Freshness.snapshot(table, 129)
    assert long_row.state == :awaiting
    assert long_row.due_at_ms == 172_860_010
    assert short_row.state == :awaiting
    assert short_row.due_at_ms == 130
    assert {:ok, %{rows: [_, %{state: :late}]}} = Freshness.snapshot(table, 130)

    assert {:ok, %{rows: [%{state: :awaiting}, %{state: :late}]}} =
             Freshness.snapshot(table, 86_400_000)

    assert {:ok, %{rows: [%{state: :late}, _]}} = Freshness.snapshot(table, 172_860_010)
    refute Map.has_key?(long_row, :online)
    refute Map.has_key?(long_row, :reachable)
  end

  test "receipt deadlines use owner observation time rather than delayed consumer time" do
    {table, routes, epoch} = context()
    event = event(epoch, 2, 11, @report)

    assert {:ok, %{table: table, matched: [%{receipt: receipt}], event: ^event}} =
             Freshness.observe(table, routes, event, 60)

    assert receipt.disposition == :value
    assert receipt.records == [%{id: 0, type: 0x21, status: :success, value: 42, raw: <<42, 0>>}]
    assert receipt.event.security_used == false

    assert {:ok, %{table: table, rows: [%{state: :within_window, due_at_ms: 131}]}} =
             Freshness.snapshot(table, 130)

    assert {:ok, %{rows: [%{state: :late}]}} = Freshness.snapshot(table, 131)
    delayed = event(epoch, 3, 12, @report)
    assert {:ok, %{table: table}} = Freshness.observe(table, routes, delayed, 140)

    assert {:ok, %{rows: [%{state: :late, due_at_ms: 132, eligible: %{event: ^delayed}}]}} =
             Freshness.snapshot(table, 140)

    assert Freshness.valid?(table)
  end

  test "null renews packet cadence while full-range interpretation remains explicit" do
    {table, routes, epoch} = context()
    null = event(epoch, 2, 11, <<8, 7, 10, 0::16, 0x21, 0xFFFF::16>>)

    assert {:ok, %{table: table, matched: [%{receipt: receipt}]}} =
             Freshness.observe(table, routes, null, 11)

    assert receipt.disposition == :null
    assert [%{value: :null, raw: <<255, 255>>}] = receipt.records

    assert {:ok, %{rows: [%{state: :within_window, eligible: ^receipt}]}} =
             Freshness.snapshot(table, 12)

    assert Freshness.valid?(table)

    {:ok, table} = Freshness.new(epoch)
    {:ok, table} = Freshness.arm(table, report_policy(full_range: true), 10)

    assert {:ok, %{table: table, matched: [%{receipt: receipt}]}} =
             Freshness.observe(table, routes, null, 11)

    assert receipt.disposition == :value
    assert [%{value: 65_535, raw: <<255, 255>>}] = receipt.records
    assert Freshness.valid?(table)
  end

  test "ambiguous, wrong-type and opaque evidence never renews a previously eligible window" do
    {table, routes, epoch} = context()
    first = event(epoch, 2, 11, @report)

    {:ok, %{table: table, matched: [%{receipt: eligible}]}} =
      Freshness.observe(table, routes, first, 11)

    cases = [
      {:ambiguous, <<8, 8, 10, 0::16, 0x21, 1::little-16, 0::16, 0x21, 2::little-16>>},
      {:wrong_type, <<8, 8, 10, 0::16, 0x20, 1>>},
      {:unsupported, <<8, 8, 10, 0::16, 0xFE, 0, 1, 0, 0>>},
      {:opaque_tail, <<8, 8, 10, 0::16, 0x21, 1::little-16, 9::little-16, 0xFE, 0, 1>>}
    ]

    for {expected, payload} <- cases do
      observed = event(epoch, 3, 100, payload)

      assert {:ok, %{table: updated, matched: [%{receipt: receipt}]}} =
               Freshness.observe(table, routes, observed, 100)

      assert receipt.disposition == expected
      assert receipt.event == observed

      assert {:ok,
              %{rows: [%{state: :late, due_at_ms: 131, latest: ^receipt, eligible: ^eligible}]}} =
               Freshness.snapshot(updated, 131)

      assert Freshness.valid?(updated)
    end

    opaque = event(epoch, 3, 100, <<8, 8, 10, 9::little-16, 0xFE, 0::16, 0x21, 42::little-16>>)

    assert {:ok, %{table: updated, matched: [], message: %{attributes: [record]}}} =
             Freshness.observe(table, routes, opaque, 100)

    assert record.id == 9
    assert record.raw == <<0::16, 0x21, 42::little-16>>

    assert {:ok, %{rows: [%{due_at_ms: 131, latest: ^eligible, eligible: ^eligible}]}} =
             Freshness.snapshot(updated, 131)
  end

  test "on-change and disabled streams retain observations without a periodic deadline" do
    {_, routes, epoch} = context()
    {:ok, table} = Freshness.new(epoch)

    {:ok, table} =
      Freshness.arm(table, report_policy(expected_interval_ms: :on_change, grace_ms: 0), 10)

    {:ok, table} = Freshness.arm(table, checkin_policy(expected_interval_ms: :disabled), 10)
    {:ok, %{table: table}} = Freshness.observe(table, routes, event(epoch, 2, 11, @report), 11)
    checkin = event(epoch, 3, 12, <<25, 7, 0>>, cluster: 32, security_used: nil)

    {:ok, %{table: table, matched: [%{receipt: receipt}]}} =
      Freshness.observe(table, routes, checkin, 12)

    assert receipt.disposition == :checkin
    assert receipt.event.security_used == nil
    assert receipt.records == []

    assert {:ok,
            %{rows: [%{state: :disabled, due_at_ms: nil}, %{state: :on_change, due_at_ms: nil}]}} =
             Freshness.snapshot(table, @max_time)

    assert Freshness.valid?(table)
  end

  test "only actual Check-in renews its cadence; a response cannot stand in for it" do
    {_, routes, epoch} = context()
    {:ok, table} = Freshness.new(epoch)

    {:ok, table} =
      Freshness.arm(table, checkin_policy(expected_interval_ms: 60_000, grace_ms: 1_000), 10)

    checkin = event(epoch, 2, 11, <<25, 7, 0>>, cluster: 32)

    assert {:ok, %{table: table, matched: [%{receipt: receipt}]}} =
             Freshness.observe(table, routes, checkin, 12)

    assert receipt.event == checkin

    assert {:ok, %{rows: [%{due_at_ms: 61_011, state: :within_window}]}} =
             Freshness.snapshot(table, 61_010)

    assert {:ok, %{rows: [%{state: :late}]}} = Freshness.snapshot(table, 61_011)

    for payload <- [<<1, 7, 0, 1, 40, 0>>, <<8, 7, 11, 0, 0>>, <<25, 7, 0, 0>>] do
      assert {:error, %Error{kind: :invalid_frame}} =
               Freshness.observe(table, routes, event(epoch, 3, 12, payload, cluster: 32), 12)
    end
  end

  test "selectors keep peers, endpoints, clusters, attributes and ZCL headers independent" do
    {table, routes, epoch} = context()
    qualified = report_policy(manufacturer: 0x1234, direction: :client_to_server, full_range: true)
    {:ok, table} = Freshness.arm(table, qualified, 10)
    {:ok, table} = Freshness.arm(table, report_policy(attribute_id: 1), 10)

    for {fields, payload} <- [
          {[source_endpoint: 3], @report},
          {[endpoint: 3], @report},
          {[cluster: 7], @report},
          {[], <<0, 7, 10, 0::16, 0x21, 42::little-16>>},
          {[], <<12, 0x9999::little-16, 7, 10, 0::16, 0x21, 42::little-16>>}
        ] do
      assert {:ok, %{matched: []}} =
               Freshness.observe(table, routes, event(epoch, 2, 11, payload, fields), 11)
    end

    manufacturer = event(epoch, 2, 11, <<4, 0x1234::little-16, 7, 10, 0::16, 0x21, 0xFFFF::16>>)

    assert {:ok, %{table: table, matched: [matched]}} =
             Freshness.observe(table, routes, manufacturer, 11)

    assert matched.policy == qualified
    assert matched.receipt.disposition == :value

    multiple =
      event(epoch, 3, 12, <<8, 8, 10, 1::little-16, 0x21, 7::little-16, 0::16, 0x21, 9::little-16>>)

    assert {:ok, %{table: table, matched: [zero, one]}} =
             Freshness.observe(table, routes, multiple, 12)

    assert zero.policy.attribute_id == 0
    assert one.policy.attribute_id == 1
    assert [%{value: 9}] = zero.receipt.records
    assert [%{value: 7}] = one.receipt.records
    assert Freshness.valid?(table)
  end

  test "watermarks reject repeat events, reordered observations and clock rewind" do
    {table, routes, epoch} = context()
    first = event(epoch, 2, 11, @report)
    {:ok, %{table: table}} = Freshness.observe(table, routes, first, 11)
    assert {:error, %Error{kind: :stale_observation}} = Freshness.observe(table, routes, first, 12)

    assert {:error, %Error{kind: :stale_observation}} =
             Freshness.observe(table, routes, event(epoch, 3, 10, @report), 12)

    {:ok, %{table: table}} = Freshness.snapshot(table, 50)
    assert {:error, %Error{kind: :stale_observation}} = Freshness.snapshot(table, 49)
    assert {:error, %Error{kind: :stale_observation}} = Freshness.arm(table, report_policy(), 49)
    assert {:error, %Error{kind: :stale_observation}} = Freshness.forget(table, report_policy(), 49)
    assert {:error, %Error{kind: :stale_observation}} = Freshness.rebind(table, make_ref(), 49)

    assert {:error, %Error{kind: :stale_observation}} =
             Freshness.observe(table, routes, event(epoch, 3, 12, @report), 49)

    # Repeated radio bytes with a new owner observation are not a radio replay proof.
    assert {:ok, %{table: table}} =
             Freshness.observe(table, routes, event(epoch, 3, 12, @report), 50)

    assert Freshness.valid?(table)
    exhausted = %{table | last_owner_sequence: @max_sequence}
    assert Freshness.valid?(exhausted)

    assert {:error, %Error{kind: :stale_observation}} =
             Freshness.observe(exhausted, routes, event(epoch, @max_sequence, 13, @report), 50)

    assert {:error, %Error{kind: :invalid_value}} =
             Freshness.observe(exhausted, routes, event(epoch, @max_sequence + 1, 13, @report), 50)
  end

  test "explicit policy replacement preserves prior interpretation and excludes earlier observations" do
    {table, routes, epoch} = context()
    first = event(epoch, 2, 11, @report)

    {:ok, %{table: table, matched: [%{receipt: previous}]}} =
      Freshness.observe(table, routes, first, 11)

    changed = report_policy(type: 0x29, expected_interval_ms: 1_000, grace_ms: 0)
    {:ok, table} = Freshness.arm(table, changed, 50)

    assert {:ok,
            %{
              rows: [
                %{state: :awaiting, due_at_ms: 1_050, latest: nil, eligible: nil, previous: history}
              ]
            }} =
             Freshness.snapshot(table, 50)

    assert history.receipt == previous
    assert history.policy.type == 0x21

    assert {:ok, %{table: table, matched: []}} =
             Freshness.observe(
               table,
               routes,
               event(epoch, 3, 49, <<8, 7, 10, 0::16, 0x29, 1::16>>),
               51
             )

    assert {:ok, %{table: table, matched: [_]}} =
             Freshness.observe(
               table,
               routes,
               event(epoch, 4, 52, <<8, 7, 10, 0::16, 0x29, 1::16>>),
               52
             )

    assert Freshness.valid?(table)
    {:ok, table} = Freshness.arm(table, changed, 53)
    {:ok, table} = Freshness.arm(table, changed, 54)
    assert Freshness.valid?(table)

    assert {:ok,
            %{rows: [%{previous: %{policy: ^changed, receipt: %{event: %{owner_sequence: 4}}}}]}} =
             Freshness.snapshot(table, 54)
  end

  test "capacity refusal retains existing streams and explicit forgetting returns evidence" do
    epoch = make_ref()
    {:ok, table} = Freshness.new(epoch, 1)
    original = report_policy()
    {:ok, table} = Freshness.arm(table, original, 10)

    assert {:error, %Error{kind: :overload}} =
             Freshness.arm(table, report_policy(attribute_id: 1), 10)

    assert map_size(table.entries) == 1
    {:ok, table} = Freshness.arm(table, report_policy(expected_interval_ms: 1_000), 11)
    assert {:ok, %{table: table, forgotten: entry}} = Freshness.forget(table, original, 12)
    assert entry.policy.expected_interval_ms == 1_000
    assert table.entries == %{}
    assert {:error, _} = Freshness.forget(table, original, 12)
    assert {:error, _} = Freshness.forget(table, nil, 12)
    assert {:ok, _} = Freshness.arm(table, report_policy(attribute_id: 1), 12)
    assert {:ok, maximum} = Freshness.new(epoch, 1_024)
    assert Freshness.valid?(maximum)

    for capacity <- [0, 1_025, 1.0, nil], do: assert({:error, _} = Freshness.new(epoch, capacity))
    assert {:error, _} = Freshness.new(nil)
  end

  test "rejoin changes the checked route without changing durable stream identity" do
    {table, routes, epoch} = context()
    {:ok, %{table: table}} = Freshness.observe(table, routes, event(epoch, 2, 11, @report), 11)
    {:ok, routes} = Routes.adopt(routes, proof(epoch, @ieee, 0x2345, 3, 12), 12, 1_000)

    assert {:error, %Error{kind: :unknown_route}} =
             Freshness.observe(table, routes, event(epoch, 4, 13, @report), 13)

    current = event(epoch, 4, 13, @report, source_address: 0x2345)

    assert {:ok, %{table: table, matched: [%{receipt: %{peer_ieee: @ieee}}]}} =
             Freshness.observe(table, routes, current, 13)

    assert Freshness.valid?(table)

    {:error, _, conflicted} =
      Routes.adopt(routes, proof(epoch, <<9::64>>, 0x2345, 5, 14), 14, 1_000)

    assert {:error, %Error{kind: :route_conflict}} =
             Freshness.observe(
               table,
               conflicted,
               event(epoch, 6, 15, @report, source_address: 0x2345),
               15
             )
  end

  test "owner replacement preserves bounded history but requires new route custody and observations" do
    {table, routes, epoch} = context()
    first = event(epoch, 2, 11, @report)

    {:ok, %{table: table, matched: [%{receipt: previous}]}} =
      Freshness.observe(table, routes, first, 11)

    new_epoch = make_ref()
    {:ok, table} = Freshness.rebind(table, new_epoch, 50)
    assert Freshness.valid?(table)
    assert table.last_owner_sequence == 0
    assert table.last_received_at_ms == nil

    assert {:ok, %{rows: [%{state: :awaiting, eligible: nil, previous: %{receipt: ^previous}}]}} =
             Freshness.snapshot(table, 50)

    assert {:error, %Error{kind: :stale_epoch}} = Freshness.observe(table, routes, first, 50)
    {:ok, routes} = Routes.rebind(routes, new_epoch)
    current = event(new_epoch, 2, 52, @report)
    assert {:error, %Error{kind: :stale_epoch}} = Freshness.observe(table, routes, current, 52)
    {:ok, routes} = Routes.adopt(routes, proof(new_epoch, @ieee, 0x1234, 1, 51), 51, 1_000)
    assert {:ok, %{table: table}} = Freshness.observe(table, routes, current, 52)
    assert Freshness.valid?(table)
    assert {:error, _} = Freshness.rebind(table, new_epoch, 53)
    assert {:error, _} = Freshness.rebind(table, nil, 53)
  end

  test "malformed events, nonreports and expired or wrong-owner custody cannot refresh" do
    {table, routes, epoch} = context()
    event = event(epoch, 2, 11, @report)

    for copied <- [
          nil,
          Map.delete(event, :payload) |> Map.put(:key, "malformed-canary"),
          Map.put(event, :key, "malformed-canary"),
          %{event | kind: :unknown_indication},
          %{event | subsystem: 5},
          %{event | id: 0x80},
          %{event | payload: :binary.copy(<<0>>, 129)},
          %{event | status: "malformed-canary"},
          %{event | zdo: %{key: "malformed-canary"}},
          %{event | transaction: 256},
          %{event | link_quality: -1},
          %{event | security_used: "malformed-canary"},
          %{event | source_address: 0xFFF8},
          %{event | source_endpoint: 0},
          %{event | endpoint: 241},
          %{event | cluster: 65_536},
          %{event | owner_sequence: 0},
          %{event | received_at_ms: nil},
          %{event | received_at_ms: @max_time + 1},
          %{event | payload: <<8, 7, 10, 0::16, 0x21, 1>>}
        ] do
      assert {:error, %Error{} = error} = Freshness.observe(table, routes, copied, 11)
      refute inspect(error) =~ "malformed-canary"
    end

    read = %{event | payload: <<8, 7, 1, 0::16, 0, 0x21, 42::little-16>>}
    assert {:error, %Error{kind: :unsupported_profile}} = Freshness.observe(table, routes, read, 11)

    assert {:error, %Error{kind: :stale_observation}} =
             Freshness.observe(table, routes, %{event | received_at_ms: 12}, 11)

    assert {:error, %Error{kind: :unknown_route}} =
             Freshness.observe(table, routes, %{event | source_address: 0x9999}, 11)

    assert {:error, %Error{kind: :stale_epoch}} =
             Freshness.observe(table, routes, %{event | owner_epoch: make_ref()}, 11)

    assert {:error, %Error{kind: :route_expired}} = Freshness.observe(table, routes, event, 1_010)
    assert {:error, _} = Freshness.observe(table, nil, event, 11)
    assert {:ok, %{rows: [%{state: :late}]}} = Freshness.snapshot(table, 1_010)
  end

  test "copied table and nested evidence are revalidated instead of trusting summary fields" do
    {table, routes, epoch} = context()
    {:ok, %{table: table}} = Freshness.observe(table, routes, event(epoch, 2, 11, @report), 11)
    key = Policy.key(report_policy())
    entry = table.entries[key]
    receipt = entry.latest

    entries = [
      Map.delete(entry, :armed_at_ms),
      Map.put(entry, :key, "malformed-canary"),
      %{entry | policy: %{entry.policy | type: 0xFE}},
      %{entry | latest: %{receipt | disposition: :null}},
      %{entry | latest: Map.put(receipt, :key, "malformed-canary")},
      %{entry | latest: %{receipt | peer_ieee: <<9::64>>}},
      %{entry | latest: %{receipt | records: []}},
      %{entry | latest: %{receipt | event: %{receipt.event | owner_epoch: make_ref()}}},
      %{entry | latest: %{receipt | event: %{receipt.event | received_at_ms: 9}}},
      %{entry | latest: %{receipt | event: %{receipt.event | received_at_ms: 12}}},
      %{entry | latest: %{receipt | event: %{receipt.event | owner_sequence: 3}}},
      %{entry | latest: %{receipt | event: Map.delete(receipt.event, :payload)}},
      %{entry | latest: nil},
      %{entry | eligible: nil},
      %{entry | armed_at_ms: 12},
      %{
        entry
        | previous: %{
            policy: entry.policy,
            receipt: %{receipt | event: %{receipt.event | received_at_ms: 12}}
          }
      },
      %{entry | previous: %{policy: report_policy(attribute_id: 1), receipt: receipt}},
      %{
        entry
        | previous: %{policy: entry.policy, receipt: Map.put(receipt, :key, "malformed-canary")}
      },
      %{entry | previous: []}
    ]

    copies = [
      nil,
      Map.delete(table, :entries),
      Map.put(table, :key, "malformed-canary"),
      %{table | capacity: 0},
      %{table | entries: []},
      %{table | last_now_ms: nil},
      %{table | last_received_at_ms: nil},
      %{table | last_received_at_ms: 12},
      %{table | last_owner_sequence: -1},
      %{table | last_owner_sequence: 0},
      %{table | epoch: nil},
      %{table | entries: %{nil => entry}}
    ]

    for copied <- copies ++ Enum.map(entries, &%{table | entries: %{key => &1}}) do
      refute Freshness.valid?(copied)
      assert {:error, %Error{kind: :invalid_value} = error} = Freshness.snapshot(copied, 20)
      refute inspect(error) =~ "malformed-canary"
    end
  end

  test "signed host times and deadline arithmetic refuse overflow without wrapping" do
    epoch = make_ref()
    {:ok, table} = Freshness.new(epoch)
    assert {:ok, negative} = Freshness.arm(table, report_policy(), -@max_time)
    assert Freshness.valid?(negative)
    assert {:error, _} = Freshness.arm(table, report_policy(), @max_time)
    assert {:error, _} = Freshness.arm(table, report_policy(), -@max_time - 1)
    assert {:error, _} = Freshness.snapshot(table, 1.0)
    assert {:error, _} = Freshness.arm(table, nil, 10)
    {:ok, high} = Freshness.arm(table, report_policy(grace_ms: 0), @max_time - 100)

    assert {:ok, %{rows: [%{due_at_ms: @max_time, state: :late}]}} =
             Freshness.snapshot(high, @max_time)

    assert {:error, _} = Freshness.rebind(high, make_ref(), @max_time)

    routes = routes(epoch, @max_time - 150)
    observed = event(epoch, 2, @max_time - 99, @report)

    assert {:error, %Error{kind: :invalid_value}} =
             Freshness.observe(high, routes, observed, @max_time - 99)
  end

  defp context do
    epoch = make_ref()
    {:ok, table} = Freshness.new(epoch)
    {:ok, table} = Freshness.arm(table, report_policy(), 10)
    {table, routes(epoch, 10), epoch}
  end

  defp routes(epoch, time) do
    {:ok, routes} = Routes.new(epoch)
    lifetime = if time > @max_time - 1_000, do: 150, else: 1_000
    {:ok, routes} = Routes.adopt(routes, proof(epoch, @ieee, 0x1234, 1, time), time, lifetime)
    routes
  end

  defp proof(epoch, ieee, route, sequence, time),
    do: %Result{
      peer_ieee: ieee,
      route_address: route,
      owner_epoch: epoch,
      outcome: :complete,
      identity_matches: true,
      steps: [
        %{
          stage: :identity,
          issues: [],
          admission: %Reply{subsystem: 5, id: 1, status: 0, payload: <<0>>},
          response: %Event{
            kind: :zdo_ieee_address,
            subsystem: 5,
            id: 0x81,
            payload: <<>>,
            owner_epoch: epoch,
            owner_sequence: sequence,
            received_at_ms: time,
            status: 0,
            zdo: %{status: 0, peer_ieee: ieee, network_address: route}
          }
        }
      ]
    }

  defp event(epoch, sequence, time, payload, options \\ []),
    do:
      struct!(
        Event,
        Keyword.merge(
          [
            kind: :af_incoming,
            subsystem: 4,
            id: 0x81,
            payload: payload,
            owner_epoch: epoch,
            owner_sequence: sequence,
            received_at_ms: time,
            source_address: 0x1234,
            source_endpoint: 1,
            endpoint: 2,
            cluster: 6,
            security_used: false,
            link_quality: 200,
            transaction: 0
          ],
          options
        )
      )

  defp report_policy(options \\ []) do
    {:ok, policy} = Policy.report(report_options(options))
    policy
  end

  defp checkin_policy(options) do
    {:ok, policy} = Policy.checkin(checkin_options(options))
    policy
  end

  defp report_options(options \\ []),
    do:
      Keyword.merge(
        [
          peer_ieee: @ieee,
          remote_endpoint: 1,
          local_endpoint: 2,
          cluster: 6,
          attribute_id: 0,
          type: 0x21,
          expected_interval_ms: 100,
          grace_ms: 20
        ],
        options
      )

  defp checkin_options(options),
    do:
      Keyword.merge(
        [peer_ieee: @ieee, remote_endpoint: 1, local_endpoint: 2, expected_interval_ms: 60_000],
        options
      )
end
