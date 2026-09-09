defmodule Wotex.BACnet.IngressLifecycleTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias BACnet.Protocol.{APDU, ObjectIdentifier, Services}
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.{BACstack, IngressTransport, IPv4, StackClient}
  alias Wotex.BACnet.Test.{BlockingClient, DiscoveryPeer}

  @moduletag :capture_log
  @fixture Jason.decode!(
             File.read!(Path.expand("../../../docs/specs/fixtures/ingress-v1.json", __DIR__))
           )
  @read %{type: :read_property, object_type: 1, instance: 0, property: 85}

  test "WBA-IG01 WBA-S03a the real full pipeline stops receiving until consumption" do
    row = fixture("WBA-IG01")
    {handle, group, peer, destination} = stack()
    :ok = :sys.suspend(group.client)

    for _ <- 1..row["input"]["credit_limit"],
        do: :ok = :gen_udp.send(peer, destination, packet(1536))

    stats = await_full(group.transport)
    assert stats.outstanding == row["expectation"]["value"]["max_outstanding"]
    assert stats.armed == row["expectation"]["value"]["rearms_after_credit_exhaustion"]
    assert_receive {:ingress_stop, measurements, %{reason: :slow_consumer}}, 1100
    assert measurements.peak == 8
    assert_closed(handle, group, destination)
    refute_receive {:ingress_stop, _, _}, 10
  end

  test "WBA-IG02 WBA-S03a forwarding does not grant credit and consumption grants it once" do
    row = fixture("WBA-IG02")
    {handle, group, peer, destination} = stack()
    :ok = :sys.suspend(group.client)
    :ok = :gen_udp.send(peer, destination, packet(8))
    assert eventually(fn -> IngressTransport.stats(group.transport).outstanding == 1 end)
    %{window: window} = :sys.get_state(group.transport)
    [receipt] = MapSet.to_list(window.outstanding)

    assert {:messages, [{:wotex_bacnet_datagram, _, ^receipt, _}]} =
             Process.info(group.client, :messages)

    assert IngressTransport.stats(group.transport).outstanding == 1
    :ok = :sys.resume(group.client)
    assert eventually(fn -> IngressTransport.stats(group.transport).outstanding == 0 end)

    for {generation, reference} <- [
          {window.generation, receipt},
          {make_ref(), receipt},
          {window.generation, make_ref()}
        ],
        do: send(group.transport, {:wotex_bacnet_consumed, generation, reference})

    stats = IngressTransport.stats(group.transport)
    assert stats.counters.ignored_ack == row["expectation"]["value"]["ignored_ack_count"]
    assert stats.outstanding == row["expectation"]["value"]["outstanding"]
    refute_receive {:ingress_stop, _, _}, 10
    assert :ok = IPv4.disconnect(handle)
  end

  test "WBA-IG03 WBA-S03a actual transport handlers discard oversize input before decoding" do
    row = fixture("WBA-IG03")
    {handle, group, _, _} = stack()

    :sys.replace_state(group.transport, fn state ->
      put_in(state.window.counters.oversize, row["input"]["counters"]["oversize"])
    end)

    [socket] = :sys.get_state(group.transport).sockets

    for event <- row["input"]["events"] do
      send(
        group.transport,
        {:udp, socket, {127, 0, 0, 1}, 47_808, :binary.copy(<<0>>, event["byte_length"])}
      )
    end

    stats = IngressTransport.stats(group.transport)
    assert stats.counters.oversize == row["expectation"]["value"]["counters"]["oversize"]
    assert stats.peak == row["expectation"]["value"]["delivered_messages"]
    assert :ok = IPv4.disconnect(handle)
  end

  test "WBA-IG04 WBA-S03a unsupported or forged bounded policy acquires no listener" do
    row = fixture("WBA-IG04")

    for capability <- [
          {:wotex_client, 2, [:cov, :discovery]},
          {:wotex_client, 3, [:cov, :discovery, :bounded_ingress]}
        ] do
      client = start_supervised!({DiscoveryPeer, [owner: self(), capabilities: capability]})

      assert {:error, error} =
               BACstack.connect(
                 stack_client: client,
                 stack_client_kind: :wotex,
                 destination: {{127, 0, 0, 1}, 47_808},
                 receive_policy: :wotex_bounded
               )

      assert Atom.to_string(error.code) == row["expectation"]["value"]["error"]["code"]
      assert Atom.to_string(error.effect) == row["expectation"]["value"]["error"]["effect"]
      state = DiscoveryPeer.snapshot(client)
      assert map_size(state.listeners) == row["expectation"]["value"]["listener_registrations"]
      assert length(state.sent) == row["expectation"]["value"]["native_requests"]
      assert Process.alive?(client) == row["expectation"]["value"]["borrowed_client_alive"]
      stop_supervised!(DiscoveryPeer)
    end
  end

  test "WBA-IG05 WBA-S03a raw borrowed read preserves its typed value and consumer ownership" do
    row = fixture("WBA-IG05")
    client = start_supervised!({BlockingClient, self()})
    {:ok, handle} = BACstack.connect(stack_client: client, destination: {{127, 0, 0, 1}, 47_808})
    refute Map.has_key?(handle, :ingress)
    assert handle.receive_policy == :consumer_managed
    task = Task.async(fn -> BACstack.request(handle, @read, 1000) end)
    assert_receive {:pending_apdu, from, _, %APDU.ConfirmedServiceRequest{}, _}
    value = Encoding.create!({:real, row["input"]["peer_reply"]["value"]})

    ack = %Services.Ack.ReadPropertyAck{
      object_identifier: %ObjectIdentifier{type: :analog_output, instance: 0},
      property_identifier: :present_value,
      property_array_index: nil,
      property_value: value
    }

    {:ok, apdu} = Services.Ack.ReadPropertyAck.to_apdu(ack, 0)
    GenServer.reply(from, {:ok, apdu})
    assert {:ok, ^value} = Task.await(task)
    assert value.value == row["expectation"]["value"]["typed_value"]["value"]
    refute_receive {:pending_apdu, _, _, _, _}, 10
    assert :ok = BACstack.disconnect(handle)
    refute Process.alive?(handle.owner)
    assert Process.alive?(client)
  end

  test "WBA-IG06 WBA-V14 sustained maximum-size UDP remains bounded with each owner suspended" do
    row = fixture("WBA-IG06")

    for suspended <- [:stack_owner, :stack_client] do
      {handle, group, peer, destination} = stack()
      task = Task.async(fn -> IPv4.request(handle, @read, 5000) end)
      assert eventually(fn -> :sys.get_state(group.client).sdk.apdu_timers != %{} end)
      owner = if suspended == :stack_owner, do: handle.owner, else: group.client
      :ok = :sys.suspend(owner)
      packet = packet(row["input"]["datagram_bytes"])
      started = System.monotonic_time(:millisecond)

      for _ <- 1..row["input"]["datagram_count"] do
        assert :ok = :gen_udp.send(peer, destination, packet)
      end

      assert_receive {:ingress_stop, measurements, %{reason: :slow_consumer}}, 1100
      assert measurements.peak == row["expectation"]["value"]["max_admitted_packet_references"]
      assert measurements.outstanding == 8
      assert measurements.armed == 0
      assert measurements.kernel_drops == :unavailable
      assert Enum.all?(measurements.receive_buffers, &(is_integer(&1) and &1 > 0))
      assert {:error, %{code: :slow_consumer, effect: :none}} = Task.await(task, 1100)
      assert_closed(handle, group, destination)
      assert System.monotonic_time(:millisecond) - started < 1200
      refute_receive {:ingress_stop, _, _}, 10
    end
  end

  test "WBA-S03a a live transport proof is bound to its actual client and generation" do
    {handle, group, _, _} = stack()
    assert {:ok, [:cov, :discovery, :bounded_ingress]} = StackClient.capabilities(group.client, 100)
    assert {:ok, proof} = StackClient.ingress(group.client, 100)
    assert :ok = IngressTransport.verify(proof.pid, group.client, proof.generation, 100)

    assert {:error, %{code: :unbounded_receive_policy}} =
             IngressTransport.verify(proof.pid, self(), proof.generation, 100)

    assert {:error, %{code: :unbounded_receive_policy}} =
             IngressTransport.verify(proof.pid, group.client, make_ref(), 100)

    assert {:error, %{code: :invalid_stack_client}} = IngressTransport.attach(proof.pid, self())

    assert {:ok, borrowed} =
             BACstack.connect(
               stack_client: group.client,
               stack_client_kind: :wotex,
               destination: {{127, 0, 0, 1}, 47_808},
               receive_policy: :wotex_bounded
             )

    assert :ok = BACstack.disconnect(borrowed)
    assert Process.alive?(group.client)
    assert :ok = IPv4.disconnect(handle)

    assert {:error, %{code: :unbounded_receive_policy}} =
             IngressTransport.verify(proof.pid, group.client, proof.generation, 100)
  end

  test "WBA-S03a malformed frames and unrelated local messages do not replenish credits" do
    {handle, group, peer, destination} = stack()
    assert IngressTransport.max_apdu_length() == 1476
    assert IngressTransport.max_npdu_length() == 1462
    assert IngressTransport.bacnet_protocol() == :bacnet_ipv4

    assert IngressTransport.get_local_address(group.transport) ==
             {{0, 0, 0, 0}, elem(destination, 1)}

    assert IngressTransport.get_broadcast_address(group.transport) ==
             {{255, 255, 255, 255}, elem(destination, 1)}

    assert IngressTransport.is_destination_routed(group.transport, destination)
    refute IngressTransport.is_valid_destination(:bad)

    for bytes <- [<<0>>, <<0x82, 1, 0, 4>>, :binary.copy(<<0>>, 1537), <<0x81, 0, 0, 6, 0, 0>>],
        do: :ok = :gen_udp.send(peer, destination, bytes)

    assert eventually(fn -> IngressTransport.stats(group.transport).counters.oversize == 1 end)
    assert eventually(fn -> IngressTransport.stats(group.transport).counters.rejected == 1 end)
    assert eventually(fn -> IngressTransport.stats(group.transport).outstanding == 0 end)
    before = IngressTransport.stats(group.transport)
    assert before.counters.malformed == 2
    send(group.transport, {:udp, peer, {127, 0, 0, 1}, 47_808, packet(8)})
    send(group.transport, {:udp_error, peer, :closed})
    send(group.transport, {:DOWN, make_ref(), :port, peer, :closed})
    send(group.transport, {:DOWN, make_ref(), :process, self(), :normal})
    send(group.transport, {:starved, make_ref(), 0})
    send(group.transport, :unrelated)
    send(group.client, {:wotex_bacnet_datagram, make_ref(), make_ref(), :invalid})
    send(group.transport, {:wotex_bacnet_consumed, make_ref(), make_ref()})
    after_state = IngressTransport.stats(group.transport)
    assert after_state.peak == before.peak
    assert after_state.counters.ignored_ack == before.counters.ignored_ack + 1
    assert :ok = IPv4.disconnect(handle)
  end

  test "WBA-S03a the last consumption cancels a full-window timer before it can terminate a live stack" do
    {handle, group, peer, destination} = stack()
    :ok = :sys.suspend(group.client)
    for _ <- 1..8, do: :ok = :gen_udp.send(peer, destination, packet(8))
    assert await_full(group.transport).armed == 0
    old = :sys.get_state(group.transport)
    :ok = :sys.resume(group.client)
    assert eventually(fn -> IngressTransport.stats(group.transport).outstanding == 0 end)
    assert :sys.get_state(group.transport).timer == nil
    assert Process.read_timer(old.timer) == false
    send(group.transport, {:starved, old.window.generation, old.window.starved_at})
    assert IngressTransport.stats(group.transport).outstanding == 0
    assert Process.alive?(group.client)
    assert :ok = IPv4.disconnect(handle)
  end

  test "WBA-S03a actual owned socket closure terminates the stack without waiting for a request timeout" do
    {handle, group, _, destination} = stack()
    task = Task.async(fn -> IPv4.request(handle, @read, 5000) end)
    assert eventually(fn -> :sys.get_state(group.client).sdk.apdu_timers != %{} end)
    {socket, _} = IngressTransport.get_portal(group.transport)
    :gen_udp.close(socket)

    assert_receive {:ingress_stop, %{counters: %{socket_error: 1}}, %{reason: :transport_exit}},
                   1000

    assert {:error, %{code: :transport_exit}} = Task.await(task, 1100)
    assert_closed(handle, group, destination)
  end

  test "WBA-S03a an expired acknowledgment cannot outrun a queued starvation timer" do
    {handle, group, peer, destination} = stack()
    :ok = :sys.suspend(group.client)
    for _ <- 1..8, do: :ok = :gen_udp.send(peer, destination, packet(8))
    assert await_full(group.transport).armed == 0
    :ok = :sys.suspend(group.transport)
    window = :sys.get_state(group.transport).window
    [receipt | _] = MapSet.to_list(window.outstanding)
    send(group.transport, {:wotex_bacnet_consumed, window.generation, receipt})
    Process.sleep(110)
    :ok = :sys.resume(group.transport)
    assert_receive {:ingress_stop, %{outstanding: 8}, %{reason: :slow_consumer}}, 1100
    assert_closed(handle, group, destination)
  end

  test "WBA-S03a transport watches are bounded, idempotent and released on borrower death" do
    {handle, group, _, _} = stack()
    {:ok, proof} = StackClient.ingress(group.client, 100)
    receiver = self()

    watchers =
      for _ <- 1..63 do
        spawn(fn ->
          send(
            receiver,
            {:watching, self(), IngressTransport.watch(proof.pid, group.client, proof.generation)}
          )

          receive do: (:stop -> :ok)
        end)
      end

    on_exit(fn -> Enum.each(watchers, &Process.exit(&1, :kill)) end)
    for watcher <- watchers, do: assert_receive({:watching, ^watcher, :ok}, 1000)
    assert map_size(:sys.get_state(group.transport).watchers) == 64

    assert {:error, %{code: :busy, effect: :none}} =
             BACstack.connect(
               stack_client: group.client,
               stack_client_kind: :wotex,
               receive_policy: :wotex_bounded,
               destination: {{127, 0, 0, 1}, 47_808}
             )

    assert {:error, %{code: :busy}} =
             IngressTransport.watch(proof.pid, group.client, proof.generation)

    assert {:error, %{code: :unbounded_receive_policy}} =
             IngressTransport.watch(proof.pid, self(), proof.generation)

    send(hd(watchers), :stop)
    assert eventually(fn -> map_size(:sys.get_state(group.transport).watchers) == 63 end)
    assert :ok = IngressTransport.watch(proof.pid, group.client, proof.generation)
    assert :ok = IngressTransport.watch(proof.pid, group.client, proof.generation)
    assert map_size(:sys.get_state(group.transport).watchers) == 64
    assert :ok = IPv4.disconnect(handle)
  end

  defp stack do
    port = unused_port()
    {:ok, peer} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])

    {:ok, handle} =
      IPv4.connect(local_ip: :none, local_port: port, destination: {{127, 0, 0, 1}, 47_808})

    group = :sys.get_state(handle.owner)
    identifier = make_ref()

    :ok =
      :telemetry.attach(
        identifier,
        [:wotex, :bacnet, :ingress, :stop],
        fn _, measurements, metadata, {receiver, transport} ->
          if self() == transport do
            send(receiver, {:ingress_stop, measurements, metadata})
            send(receiver, {:ingress_cleanup, metadata.cleanup_worker})
          end
        end,
        {self(), group.transport}
      )

    on_exit(fn ->
      :telemetry.detach(identifier)
      IPv4.disconnect(handle)
      :gen_udp.close(peer)
    end)

    {handle, group, peer, {{127, 0, 0, 1}, port}}
  end

  defp unused_port do
    port = 58_000 + :rand.uniform(6000)

    case :gen_udp.open(port, [:binary]) do
      {:ok, socket} ->
        :gen_udp.close(socket)
        port

      {:error, :eaddrinuse} ->
        unused_port()
    end
  end

  defp packet(bytes), do: <<0x81, 0x0A, bytes::16, 1, 0, 0x10, 0x08, 0::size((bytes - 8) * 8)>>

  defp await_full(transport) do
    assert eventually(fn -> IngressTransport.stats(transport).outstanding == 8 end)
    IngressTransport.stats(transport)
  end

  defp assert_closed(handle, group, {_, port}) do
    assert_receive {:ingress_cleanup, cleanup_worker}, 1100
    assert eventually(fn -> not Process.alive?(cleanup_worker) end, 1100)

    pids = [
      handle.owner,
      handle.stack.owner
      | Enum.map([:client, :transport, :segmentator, :segments_store], &group[&1])
    ]

    assert eventually(fn -> Enum.all?(pids, &(not Process.alive?(&1))) end, 1100)
    assert {:ok, socket} = :gen_udp.open(port, [:binary])
    :gen_udp.close(socket)
  end

  defp eventually(predicate, budget \\ 100),
    do: await(predicate, System.monotonic_time(:millisecond) + budget)

  defp await(predicate, deadline) do
    cond do
      predicate.() ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(1)
        await(predicate, deadline)
    end
  end

  defp fixture(id), do: Enum.find(@fixture["cases"], &(&1["id"] == id))
end
