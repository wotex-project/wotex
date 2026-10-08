defmodule Wotex.Zigbee.RoutesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{DataRequest, Error, Event, Reply, Routes}
  alias Wotex.Zigbee.Interview.Result

  @first <<8, 7, 6, 5, 4, 3, 2, 1>>
  @second <<1, 2, 3, 4, 5, 6, 7, 8>>

  test "construction is inert, bounded and rejects copied fields" do
    epoch = make_ref()
    before = Process.info(self(), :messages)
    assert {:ok, table} = Routes.new(epoch)
    assert Routes.valid?(table)
    assert {:ok, []} = Routes.entries(table)
    assert Process.info(self(), :messages) == before
    assert {:ok, _} = Routes.new(epoch, 1_024)

    for capacity <- [0, 1_025, nil, "capacity"] do
      assert {:error, %Error{kind: :invalid_value}} = Routes.new(epoch, capacity)
    end

    assert {:error, _} = Routes.new("epoch")

    for change <- [
          capacity: 0,
          epoch: nil,
          generation: -1,
          entries: [],
          generation: 0x10000000000000000
        ] do
      refute Routes.valid?(Map.put(table, elem(change, 0), elem(change, 1)))
    end

    refute Routes.valid?(Map.put(table, :secret, "credential-canary"))
    refute Routes.valid?(nil)
    assert {:error, _} = Routes.entries(:invalid)
    assert {:error, _, nil} = Routes.adopt(nil, proof(epoch), 10, 30)
  end

  test "adoption retains identity while a rejoin replaces its transient route" do
    epoch = make_ref()
    {:ok, table} = Routes.new(epoch)
    assert {:ok, table} = Routes.adopt(table, proof(epoch), 10, 30)
    report = event(epoch, 0x1234, 11)

    assert {:ok, %{event: ^report, entry: %{peer_ieee: @first, generation: 1}}} =
             Routes.resolve(table, report, 11)

    assert {:ok, 40} = Routes.check_request(table, request(), epoch, 12)
    assert {:ok, table} = Routes.adopt(table, proof(epoch, @first, 0x5678, 20), 20, 30)

    assert {:ok, [%{route_address: 0x5678, peer_ieee: @first, generation: 2}]} =
             Routes.entries(table)

    assert {:error, %Error{kind: :unknown_route}} = Routes.resolve(table, report, 21)

    assert {:error, %Error{kind: :route_mismatch}} =
             Routes.check_request(table, request(), epoch, 21)

    assert {:ok, 50} = Routes.check_request(table, request(@first, 0x5678), epoch, 21)

    assert {:error, %Error{kind: :stale_observation}, ^table} =
             Routes.adopt(table, proof(epoch), 21, 30)
  end

  test "different raw identities stay separate without a label key" do
    epoch = make_ref()
    {:ok, table} = Routes.new(epoch)
    {:ok, table} = Routes.adopt(table, proof(epoch), 10, 30)
    {:ok, table} = Routes.adopt(table, proof(epoch, @second, 0x5678), 10, 30)
    assert {:ok, entries} = Routes.entries(table)
    assert Enum.map(entries, & &1.peer_ieee) == [@second, @first]

    assert {:ok, %{entry: %{peer_ieee: @second}}} =
             Routes.resolve(table, event(epoch, 0x5678, 11), 11)

    assert {:error, _} = Routes.forget(table, "sensor-label")
  end

  test "route conflicts quarantine both identities and forgetting one cannot promote the other" do
    epoch = make_ref()
    {:ok, table} = Routes.new(epoch)
    {:ok, table} = Routes.adopt(table, proof(epoch), 10, 30)

    assert {:error, %Error{kind: :route_conflict}, table} =
             Routes.adopt(table, proof(epoch, @second), 10, 30)

    assert Routes.valid?(table)
    assert {:ok, entries} = Routes.entries(table)
    assert Enum.all?(entries, &(&1.status == :conflicted))

    assert {:error, %Error{kind: :route_conflict}} =
             Routes.resolve(table, event(epoch, 0x1234, 11), 11)

    assert {:error, %Error{kind: :route_conflict}} =
             Routes.check_request(table, request(), epoch, 11)

    {:ok, table} = Routes.forget(table, @second)

    assert {:error, %Error{kind: :route_conflict}, ^table} =
             Routes.adopt(table, proof(epoch), 11, 30)

    {:ok, table} = Routes.adopt(table, proof(epoch, @first, 0x5678, 12), 12, 30)
    assert {:ok, _} = Routes.resolve(table, event(epoch, 0x5678, 13), 13)
  end

  test "capacity refusal still quarantines an occupied route and retains the conflicting claim" do
    epoch = make_ref()
    {:ok, table} = Routes.new(epoch, 1)
    {:ok, table} = Routes.adopt(table, proof(epoch), 10, 30)

    assert {:error, %Error{kind: :overload}, ^table} =
             Routes.adopt(table, proof(epoch, @second, 0x5678), 10, 30)

    assert {:error, %Error{kind: :route_conflict}, table} =
             Routes.adopt(table, proof(epoch, @second), 10, 30)

    assert {:ok, [%{last_conflict: @second, status: :conflicted}]} = Routes.entries(table)

    assert {:error, %Error{kind: :route_conflict}} =
             Routes.resolve(table, event(epoch, 0x1234, 11), 11)
  end

  test "old result adoption cannot refresh expiry and source security disposition stays unchanged" do
    epoch = make_ref()
    {:ok, table} = Routes.new(epoch)
    {:ok, table} = Routes.adopt(table, proof(epoch), 20, 30)
    {:ok, table} = Routes.adopt(table, proof(epoch), 30, 30)
    report = %{event(epoch, 0x1234, 31) | security_used: false, payload: "untrusted-report"}
    assert {:ok, %{event: ^report, entry: %{expires_at_ms: 40}}} = Routes.resolve(table, report, 31)
    assert {:error, %Error{kind: :route_expired}} = Routes.resolve(table, report, 40)

    assert {:error, %Error{kind: :route_expired}} =
             Routes.check_request(table, request(), epoch, 40)

    assert {:error, %Error{kind: :invalid_value}, ^table} =
             Routes.adopt(table, proof(epoch), 40, 30)

    assert {:error, %Error{kind: :invalid_value}} = Routes.resolve(table, report, 9)

    assert {:error, %Error{kind: :stale_observation}} =
             Routes.resolve(table, event(epoch, 0x1234, 9), 20)

    assert {:error, %Error{kind: :stale_observation}} =
             Routes.resolve(table, event(epoch, 0x1234, 21), 20)
  end

  test "a new owner epoch retains peer records but requires a new interview" do
    epoch = make_ref()
    next = make_ref()
    {:ok, table} = Routes.new(epoch)
    {:ok, table} = Routes.adopt(table, proof(epoch), 10, 30)
    assert {:ok, table} = Routes.rebind(table, next)
    assert {:ok, [%{status: :unverified, owner_epoch: ^epoch}]} = Routes.entries(table)

    assert {:error, %Error{kind: :stale_epoch}} =
             Routes.resolve(table, event(epoch, 0x1234, 11), 11)

    assert {:error, %Error{kind: :stale_epoch}} = Routes.resolve(table, event(next, 0x1234, 11), 11)
    assert {:error, %Error{kind: :stale_epoch}, ^table} = Routes.adopt(table, proof(epoch), 11, 30)
    assert {:ok, table} = Routes.adopt(table, proof(next, @first, 0x5678, 12), 12, 30)
    assert {:ok, _} = Routes.resolve(table, event(next, 0x5678, 13), 13)
    assert {:error, _} = Routes.rebind(table, next)
    assert {:error, _} = Routes.rebind(table, "epoch")
  end

  test "partial, forged status, missing provenance and malformed evidence cannot establish custody" do
    epoch = make_ref()
    {:ok, table} = Routes.new(epoch)
    good = proof(epoch)
    [identity] = good.steps

    for candidate <- [
          nil,
          %{good | outcome: :partial},
          %{good | identity_matches: false},
          %{good | peer_ieee: <<0::64>>},
          %{good | route_address: 0xFFF8},
          %{good | steps: []},
          %{
            good
            | steps: [
                %{identity | admission: %Reply{subsystem: 5, id: 1, status: 1, payload: <<1>>}}
              ]
          },
          %{good | steps: [%{identity | response: %{identity.response | owner_epoch: nil}}]}
        ] do
      assert {:error, %Error{} = error, ^table} = Routes.adopt(table, candidate, 10, 30)
      refute inspect(error) =~ "credential-canary"
    end

    for {now, ttl} <- [{nil, 30}, {9, 30}, {10, 0}, {10, 86_400_001}, {10, "ttl"}] do
      assert {:error, _, ^table} = Routes.adopt(table, good, now, ttl)
    end

    assert {:error, _} = Routes.resolve(table, nil, 10)

    assert {:error, %Error{kind: :unknown_route}} =
             Routes.check_request(table, request(), epoch, 10)

    assert {:error, _} = Routes.check_request(table, nil, epoch, 10)

    assert {:error, %Error{kind: :stale_epoch}} =
             Routes.check_request(table, request(), make_ref(), 10)
  end

  test "copied entries and generation exhaustion are checked without unbounded authority" do
    epoch = make_ref()
    {:ok, table} = Routes.new(epoch)
    {:ok, table} = Routes.adopt(table, proof(epoch), 10, 30)
    entry = table.entries[@first]
    missing_field = Map.delete(entry, :last_conflict)

    for changed <- [
          nil,
          Map.put(entry, :key, "credential-canary"),
          Map.put(missing_field, :key, "credential-canary"),
          %{entry | status: :conflicted},
          %{entry | generation: 0},
          %{entry | expires_at_ms: 100_000_000},
          %{entry | peer_ieee: @second}
        ] do
      refute Routes.valid?(%{table | entries: %{@first => changed}})
    end

    table = %{table | generation: 0xFFFFFFFFFFFFFFFF}
    assert Routes.valid?(table)

    assert {:error, %Error{kind: :correlation_exhausted}, ^table} =
             Routes.adopt(table, proof(epoch), 11, 30)

    assert {:error, %Error{kind: :correlation_exhausted}} = Routes.rebind(table, make_ref())
    assert {:error, %Error{kind: :correlation_exhausted}} = Routes.forget(table, @first)
  end

  test "owner sequence fences different routes observed in the same millisecond" do
    epoch = make_ref()
    {:ok, table} = Routes.new(epoch)
    {:ok, table} = Routes.adopt(table, proof(epoch), 10, 30)
    same_time = proof(epoch, @first, 0x5678)

    assert {:error, %Error{kind: :stale_observation}, ^table} =
             Routes.adopt(table, same_time, 10, 30)

    [step] = same_time.steps
    newer = %{same_time | steps: [%{step | response: %{step.response | owner_sequence: 11}}]}
    assert {:ok, table} = Routes.adopt(table, newer, 10, 30)
    report = %{event(epoch, 0x5678, 10) | owner_sequence: 12}
    assert {:ok, _} = Routes.resolve(table, report, 10)

    assert {:error, %Error{kind: :stale_observation}} =
             Routes.resolve(table, %{report | owner_sequence: 10}, 10)
  end

  defp proof(epoch, ieee \\ @first, route \\ 0x1234, observed \\ 10) do
    response = %Event{
      kind: :zdo_ieee_address,
      subsystem: 5,
      id: 0x81,
      payload: <<>>,
      owner_epoch: epoch,
      received_at_ms: observed,
      owner_sequence: observed,
      status: 0,
      zdo: %{status: 0, peer_ieee: ieee, network_address: route}
    }

    step = %{
      stage: :identity,
      issues: [],
      admission: %Reply{subsystem: 5, id: 1, status: 0, payload: <<0>>},
      response: response,
      confirmation: nil,
      attributes: nil
    }

    %Result{
      peer_ieee: ieee,
      route_address: route,
      owner_epoch: epoch,
      outcome: :complete,
      identity_matches: true,
      steps: [step]
    }
  end

  defp event(epoch, route, received),
    do: %Event{
      kind: :af_incoming,
      subsystem: 4,
      id: 0x81,
      payload: <<>>,
      owner_epoch: epoch,
      received_at_ms: received,
      owner_sequence: received,
      source_address: route,
      security_used: true
    }

  defp request(ieee \\ @first, route \\ 0x1234) do
    {:ok, request} =
      DataRequest.new(
        peer_ieee: ieee,
        route_address: route,
        destination_endpoint: 1,
        source_endpoint: 2,
        cluster: 6,
        transaction: 7,
        correlation_id: "request",
        data: <<0>>
      )

    request
  end
end
