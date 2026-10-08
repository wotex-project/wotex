defmodule Wotex.Zigbee.DownlinksTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{DataRequest, Downlinks, Error, Event, Reply, Routes}
  alias Wotex.Zigbee.Interview.Result

  @first <<8, 7, 6, 5, 4, 3, 2, 1>>
  @second <<1, 2, 3, 4, 5, 6, 7, 8>>

  test "construction is inert, finite and refuses unknown or copied fields" do
    before = Process.info(self(), :messages)
    assert {:ok, queue} = Downlinks.new(make_ref())
    assert Downlinks.valid?(queue)
    assert queue.entries == []
    assert Process.info(self(), :messages) == before

    for options <- [
          nil,
          [capacity: 0],
          [capacity: 1_025],
          [per_peer: 129],
          [max_bytes: 0],
          [max_bytes: 131_073],
          [capacity: 1, capacity: 2],
          [key: "credential-canary"]
        ] do
      assert {:error, %Error{kind: :invalid_value} = error} = Downlinks.new(make_ref(), options)
      refute inspect(error) =~ "credential-canary"
    end

    assert {:error, _} = Downlinks.new(nil)
    refute Downlinks.valid?(nil)
    refute Downlinks.valid?(Map.put(queue, :secret, "credential-canary"))

    copied =
      queue
      |> Map.delete(:epoch)
      |> Map.put(:secret, "credential-canary")

    refute Downlinks.valid?(copied)
    assert {:error, _} = Downlinks.enqueue(copied, request(), 10, 100)
  end

  test "global, per-peer and byte exhaustion refuse new entries without dropping old requests" do
    {:ok, queue} = Downlinks.new(make_ref(), capacity: 2, per_peer: 1)
    {:ok, %{queue: queue, ticket: 1}} = Downlinks.enqueue(queue, request(), 10, 100)

    assert {:error, %Error{kind: :overload}} =
             Downlinks.enqueue(queue, request(@first, "second"), 10, 100)

    {:ok, %{queue: queue}} = Downlinks.enqueue(queue, request(@second), 10, 100)

    assert {:error, %Error{kind: :overload}} =
             Downlinks.enqueue(queue, request(<<2::64>>), 10, 100)

    assert Enum.map(queue.entries, & &1.request.peer_ieee) == [@first, @second]

    {:ok, queue} = Downlinks.new(make_ref(), max_bytes: 4)
    first = %{request() | data: <<1, 2, 3, 4>>}
    {:ok, %{queue: queue}} = Downlinks.enqueue(queue, first, 10, 100)

    assert {:error, %Error{kind: :overload}} =
             Downlinks.enqueue(queue, request(@first, "second"), 10, 100)

    assert [entry] = queue.entries
    assert entry.request == first
  end

  test "pending correlation identity is peer scoped and tickets never wrap" do
    {:ok, queue} = Downlinks.new(make_ref())
    {:ok, %{queue: queue}} = Downlinks.enqueue(queue, request(), -100, 200)
    assert {:error, %Error{kind: :invalid_value}} = Downlinks.enqueue(queue, request(), -99, 200)
    assert {:ok, %{ticket: 2}} = Downlinks.enqueue(queue, request(@second), -99, 200)

    saturated = %{queue | generation: 0xFFFFFFFFFFFFFFFF}
    assert Downlinks.valid?(saturated)

    assert {:error, %Error{kind: :correlation_exhausted}} =
             Downlinks.enqueue(saturated, request(@first, "new"), 0, 200)
  end

  test "expiry is explicit, exact at the boundary and never declares a peer offline" do
    {:ok, queue} = Downlinks.new(make_ref(), capacity: 2)
    {:ok, %{queue: queue}} = Downlinks.enqueue(queue, request(), 10, 20)
    {:ok, %{queue: queue}} = Downlinks.enqueue(queue, request(@second), 10, 10)
    assert {:ok, %{expired: [], queue: current}} = Downlinks.expire(queue, 19)
    assert length(current.entries) == 2

    assert {:error, %Error{kind: :overload}} =
             Downlinks.enqueue(queue, request(@first, "new"), 20, 100)

    assert {:ok, %{expired: [second], queue: current}} = Downlinks.expire(queue, 20)
    assert second.ticket == 2
    assert {:ok, %{expired: [first], queue: current}} = Downlinks.expire(current, 30)
    assert first.ticket == 1
    assert current.entries == []
    refute Map.has_key?(first, :offline)
  end

  test "admission refuses clock rewind, malformed lifetimes and copied AF fields" do
    {:ok, queue} = Downlinks.new(make_ref())
    {:ok, %{queue: queue}} = Downlinks.enqueue(queue, request(), 10, 100)

    assert {:error, %Error{kind: :stale_observation}} =
             Downlinks.enqueue(queue, request(@second), 9, 100)

    assert {:error, %Error{kind: :stale_observation}} = Downlinks.expire(queue, 9)

    for lifetime <- [0, 86_400_001, nil, "credential-canary"] do
      assert {:error, %Error{kind: :invalid_value}} =
               Downlinks.enqueue(queue, request(@second), 10, lifetime)
    end

    assert {:error, _} = Downlinks.enqueue(queue, request(@second), 0x7FFFFFFFFFFFFFFF, 1)
    assert {:error, _} = Downlinks.enqueue(queue, nil, 10, 10)
    assert {:error, _} = Downlinks.expire(queue, nil)
  end

  test "selection keeps per-peer FIFO order and clamps deadlines to current custody" do
    epoch = make_ref()
    routes = routes(epoch)
    {:ok, queue} = Downlinks.new(epoch)
    {:ok, %{queue: queue}} = Downlinks.enqueue(queue, request(), 10, 1_000)
    {:ok, %{queue: queue}} = Downlinks.enqueue(queue, request(@second), 10, 1_000)
    {:ok, %{queue: queue}} = Downlinks.enqueue(queue, request(@first, "third"), 11, 20)

    assert {:ok, %{ready: [first, third], refused: [], expired: [], queue: current}} =
             Downlinks.take(queue, routes, @first, 12, 2)

    assert first.entry.ticket == 1
    assert first.deadline_ms == 110
    assert third.entry.ticket == 3
    assert third.deadline_ms == 31
    assert Enum.map(current.entries, & &1.ticket) == [2]
    assert {:ok, %{ready: [], queue: unchanged}} = Downlinks.take(current, routes, @first, 12)
    assert unchanged == current
  end

  test "expired entries of every peer are returned separately before bounded selection" do
    epoch = make_ref()
    {:ok, queue} = Downlinks.new(epoch)
    {:ok, %{queue: queue}} = Downlinks.enqueue(queue, request(@second), 10, 1)
    {:ok, %{queue: queue}} = Downlinks.enqueue(queue, request(), 10, 10)
    {:ok, %{queue: queue}} = Downlinks.enqueue(queue, request(@first, "third"), 10, 20)

    assert {:ok, %{expired: [expired], ready: [ready], queue: current}} =
             Downlinks.take(queue, routes(epoch), @first, 11)

    assert expired.ticket == 1
    assert ready.entry.ticket == 2
    assert Enum.map(current.entries, & &1.ticket) == [3]
  end

  test "rejoin, route expiry and conflicts refuse and remove commands without retargeting" do
    epoch = make_ref()
    original = routes(epoch)
    {:ok, moved} = Routes.adopt(original, proof(epoch, @first, 0x3456, 20), 20, 100)
    {:error, _, conflicted} = Routes.adopt(original, proof(epoch, @second, 0x1234, 20), 20, 100)

    for {routes, now, reason} <- [
          {moved, 21, :route_mismatch},
          {original, 110, :route_expired},
          {conflicted, 21, :route_conflict}
        ] do
      {:ok, queue} = Downlinks.new(epoch)
      {:ok, %{queue: queue}} = Downlinks.enqueue(queue, request(), 10, 1_000)

      assert {:ok, %{ready: [], refused: [refusal], queue: current}} =
               Downlinks.take(queue, routes, @first, now)

      assert refusal.reason == reason
      assert refusal.entry.request == request()
      assert current.entries == []
      assert {:ok, %{refused: [], ready: []}} = Downlinks.take(current, routes, @first, now)
    end
  end

  test "epoch mismatch and malformed selection refuse before modifying the queue" do
    epoch = make_ref()
    {:ok, queue} = Downlinks.new(epoch)
    {:ok, %{queue: queue}} = Downlinks.enqueue(queue, request(), 10, 100)

    assert {:error, %Error{kind: :stale_epoch}} =
             Downlinks.take(queue, routes(make_ref()), @first, 11)

    for {peer, limit} <- [{nil, 1}, {<<0::64>>, 1}, {@first, 0}, {@first, 9}] do
      assert {:error, %Error{kind: :invalid_value}} =
               Downlinks.take(queue, routes(epoch), peer, 11, limit)
    end

    assert {:error, _} = Downlinks.take(queue, nil, @first, 11)
    assert {:error, _} = Downlinks.take(nil, nil, @first, 11)
    assert length(queue.entries) == 1
  end

  test "cancellation and rebind retain explicit removal receipts and ticket history" do
    epoch = make_ref()
    {:ok, queue} = Downlinks.new(epoch)
    {:ok, %{queue: queue}} = Downlinks.enqueue(queue, request(), 10, 100)
    {:ok, %{queue: queue}} = Downlinks.enqueue(queue, request(@second), 10, 100)
    assert {:ok, %{queue: current, cancelled: %{ticket: 1}}} = Downlinks.cancel(queue, 1)
    assert {:error, _} = Downlinks.cancel(current, 1)
    assert {:error, _} = Downlinks.cancel(nil, 1)
    assert {:error, _} = Downlinks.cancel(current, nil)

    new_epoch = make_ref()

    assert {:ok, %{queue: rebound, invalidated: [%{ticket: 2}]}} =
             Downlinks.rebind(current, new_epoch)

    assert rebound.epoch == new_epoch
    assert rebound.entries == []
    assert {:ok, %{ticket: 3}} = Downlinks.enqueue(rebound, request(), 11, 100)
    assert {:error, _} = Downlinks.rebind(current, epoch)
    assert {:error, _} = Downlinks.rebind(nil, new_epoch)
  end

  test "copied queues revalidate nested requests, FIFO tickets and aggregate budgets" do
    {:ok, queue} = Downlinks.new(make_ref())
    {:ok, %{queue: queue}} = Downlinks.enqueue(queue, request(), 10, 100)
    [entry] = queue.entries

    for entries <- [
          [nil],
          [Map.put(entry, :key, "credential-canary")],
          [%{entry | request: Map.put(entry.request, :key, "credential-canary")}],
          [%{entry | enqueued_at_ms: 11}],
          [%{entry | expires_at_ms: 10}],
          [%{entry | ticket: 2}],
          [entry, entry]
        ] do
      copied = %{queue | entries: entries}
      refute Downlinks.valid?(copied)
      assert {:error, %Error{kind: :invalid_value} = error} = Downlinks.expire(copied, 20)
      refute inspect(error) =~ "credential-canary"
    end

    refute Downlinks.valid?(%{queue | max_bytes: 0})
    refute Downlinks.valid?(%{queue | last_now_ms: nil})
  end

  defp request(peer \\ @first, correlation \\ "queued") do
    {:ok, request} =
      DataRequest.new(
        peer_ieee: peer,
        route_address: if(peer == @first, do: 0x1234, else: 0x5678),
        destination_endpoint: 1,
        source_endpoint: 2,
        cluster: 6,
        transaction: 1,
        correlation_id: correlation,
        data: <<1>>
      )

    request
  end

  defp routes(epoch) do
    {:ok, routes} = Routes.new(epoch)
    {:ok, routes} = Routes.adopt(routes, proof(epoch, @first, 0x1234, 10), 10, 100)
    {:ok, routes} = Routes.adopt(routes, proof(epoch, @second, 0x5678, 10), 10, 100)
    routes
  end

  defp proof(epoch, peer, route, now) do
    %Result{
      peer_ieee: peer,
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
            owner_sequence: now,
            received_at_ms: now,
            status: 0,
            zdo: %{status: 0, peer_ieee: peer, network_address: route}
          }
        }
      ]
    }
  end
end
