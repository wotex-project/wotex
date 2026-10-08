defmodule Wotex.Zigbee.BindingOwnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee
  alias Wotex.Zigbee.{Binding, Config, Error, Interview, Owner, Routes, TestBindingSerial}
  alias Wotex.Zigbee.Binding.Result

  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>
  @destination <<1, 2, 3, 4, 5, 6, 7, 8>>
  @route 0x1234

  test "IEEE Bind and group Unbind retain independent NCP admission and peer status in either order" do
    {handle, peer, routes} = interviewed_peer()
    bind = request()
    call = Task.async(fn -> Zigbee.change_binding(handle, routes, bind, 1_000) end)

    expected =
      wire(
        0x25,
        0x21,
        <<@route::little-16, @ieee::binary, 1, 6::little-16, 3, @destination::binary, 2>>
      )

    assert_receive {:serial_write, ^expected}
    send(peer, {:inject, callback(:bind, 0)})
    wait_state(handle.owner, &(&1.binding.flow.response != nil))
    assert Task.yield(call, 10) == nil
    assert {:error, %Error{kind: :overload}} = Zigbee.active_endpoints(handle, @route, 1_000)
    assert {:ok, %{events: []}} = Zigbee.drain_events(handle, 128)
    send(peer, {:inject, wire(0x65, 0x21, <<0>>)})
    assert {:ok, %Result{outcome: :peer_reported_success, issue: nil} = result} = Task.await(call)
    assert result.request == bind
    assert result.owner_epoch == handle.epoch
    assert result.admission.status == 0
    assert result.response.payload == <<@route::little-16, 0>>
    assert result.response.owner_epoch == handle.epoch
    assert result.response.owner_sequence > 3
    assert is_integer(result.response.received_at_ms)
    assert result.response.security_used == nil
    assert result.response.transaction == nil

    unbind = request(operation: :unbind, target: {:group, 0x2345}, correlation_id: "remove")
    call = Task.async(fn -> Zigbee.change_binding(handle, routes, unbind, 1_000) end)
    expected = wire(0x25, 0x22, group_payload())
    assert_receive {:serial_write, ^expected}
    send(peer, {:inject, wire(0x65, 0x22, <<0>>)})
    wait_state(handle.owner, &(&1.binding.flow.admission != nil))
    assert :sys.get_state(handle.owner).pending == nil
    assert Task.yield(call, 10) == nil
    assert {:error, %Error{kind: :overload}} = Zigbee.active_endpoints(handle, @route, 1_000)
    assert {:error, %Error{kind: :overload}} = Zigbee.change_binding(handle, routes, bind, 1_000)
    {:ok, interview} = Interview.new(peer_ieee: @ieee, route_address: @route, source_endpoint: 2)
    assert {:error, %Error{kind: :overload}} = Zigbee.interview(handle, interview, 1_000)
    send(peer, {:inject, callback(:unbind, 0x8C)})
    assert {:ok, %Result{outcome: :peer_reported_failure, issue: nil} = result} = Task.await(call)
    assert result.request == unbind
    assert result.admission.status == 0
    assert result.response.status == 0x8C
    assert result.response.zdo.operation == :unbind
    assert :ok = Zigbee.close(handle)
    assert_receive {:binding_serial_close, ^peer}
    refute_receive {:binding_serial_close, ^peer}, 10
  end

  test "an early successful callback cannot override NCP rejection or invite retry" do
    {handle, peer, routes} = interviewed_peer()
    bind = request()
    call = Task.async(fn -> Zigbee.change_binding(handle, routes, bind, 1_000) end)
    assert_receive {:serial_write, <<0xFE, _, 0x25, 0x21, _::binary>>}
    send(peer, {:inject, callback(:bind, 0) <> wire(0x65, 0x21, <<2>>)})
    assert {:ok, %Result{outcome: :unconfirmed, issue: :ncp_rejected} = result} = Task.await(call)
    assert result.admission.status == 2
    assert result.response.status == 0
    assert {:ok, _} = Zigbee.handle(handle.owner)

    assert {:error, %Error{kind: :correlation_exhausted}} =
             Zigbee.change_binding(
               handle,
               routes,
               %{bind | cluster: 32, correlation_id: "different"},
               1_000
             )

    refute_receive {:serial_write, _}, 10
  end

  test "wrong source, wrong operation, malformed and duplicate indications remain bounded events" do
    {handle, peer, routes} = interviewed_peer()
    call = Task.async(fn -> Zigbee.change_binding(handle, routes, request(), 1_000) end)
    assert_receive {:serial_write, <<0xFE, _, 0x25, 0x21, _::binary>>}

    unrelated =
      callback(:bind, 0, 0x2345) <> callback(:unbind, 0) <> wire(0x45, 0xA1, <<0x34, 0x12>>)

    send(peer, {:inject, unrelated <> callback(:bind, 0) <> callback(:bind, 0)})
    wait_state(handle.owner, &(&1.event_count == 4))
    assert Task.yield(call, 10) == nil
    send(peer, {:inject, wire(0x65, 0x21, <<0>>)})
    assert {:ok, %Result{outcome: :peer_reported_success}} = Task.await(call)
    assert {:ok, %{events: events, dropped: 0}} = Zigbee.drain_events(handle, 128)
    assert Enum.map(events, & &1.kind) == [:zdo_bind, :zdo_unbind, :malformed_indication, :zdo_bind]
    assert Enum.at(events, 0).source_address == 0x2345
    assert Enum.all?(events, &(&1.security_used == nil))

    assert {:error, %Error{kind: :correlation_exhausted}} =
             Zigbee.change_binding(handle, routes, request(operation: :unbind), 1_000)

    refute_receive {:serial_write, _}, 10
  end

  test "an unsolicited observed callback retires its pair before any binding request" do
    {handle, peer, routes} = interviewed_peer()
    send(peer, {:inject, callback(:bind, 0)})
    wait_state(handle.owner, &(&1.event_count == 1))

    assert {:error, %Error{kind: :correlation_exhausted}} =
             Zigbee.change_binding(handle, routes, request(), 1_000)

    assert {:ok, %{events: [%{kind: :zdo_bind}]}} = Zigbee.drain_events(handle, 128)
    refute_receive {:serial_write, _}, 10
  end

  test "raw commands, copied requests, stale handles and absent current custody fail before I/O" do
    {handle, _, routes} = interviewed_peer()
    bind = request()
    {:ok, raw} = Binding.frame(bind)
    assert {:error, %Error{kind: :invalid_command}} = Owner.call(handle, :command, [raw, 1_000])
    {:ok, empty} = Routes.new(handle.epoch)
    {:ok, other_epoch} = Routes.new(make_ref())

    candidates = [
      {routes, nil, :invalid_value},
      {routes, Map.put(bind, :key, "credential-canary"), :invalid_value},
      {routes, Map.delete(bind, :cluster), :invalid_value},
      {routes, %{bind | route_address: 0x2345}, :route_mismatch},
      {routes, %{bind | peer_ieee: @destination}, :unknown_route},
      {empty, bind, :unknown_route},
      {other_epoch, bind, :stale_epoch},
      {nil, bind, :invalid_value}
    ]

    for {table, value, kind} <- candidates do
      assert {:error, %Error{kind: ^kind} = error} =
               Zigbee.change_binding(handle, table, value, 1_000)

      refute inspect(error) =~ "credential-canary"
    end

    for timeout <- [0, 1_001, nil, "credential-canary"] do
      assert {:error, %Error{kind: :invalid_value}} =
               Zigbee.change_binding(handle, routes, bind, timeout)
    end

    assert {:error, %Error{kind: :stale_handle}} =
             Zigbee.change_binding(%{handle | epoch: make_ref()}, routes, bind, 1_000)

    assert {:error, %Error{kind: :stale_handle}} = Zigbee.change_binding(nil, routes, bind, 1_000)
    assert {:ok, _} = Zigbee.handle(handle.owner)
    assert MapSet.size(:sys.get_state(handle.owner).used_bindings) == 0
    refute_receive {:serial_write, _}, 10
  end

  test "mailbox expiry before dispatch leaves the owner and pair usable" do
    {handle, peer, routes} = interviewed_peer()
    :ok = :sys.suspend(handle.owner)
    call = Task.async(fn -> Zigbee.change_binding(handle, routes, request(), 20) end)

    wait_message(handle.owner, fn message ->
      match?({:"$gen_call", _, {:binding, _, _}}, message)
    end)

    Process.sleep(25)
    :ok = :sys.resume(handle.owner)
    assert {:error, %Error{kind: :timeout}} = Task.await(call)
    assert MapSet.size(:sys.get_state(handle.owner).used_bindings) == 0
    refute_receive {:serial_write, _}, 10
    call = Task.async(fn -> Zigbee.change_binding(handle, routes, request(), 1_000) end)
    assert_receive {:serial_write, <<0xFE, _, 0x25, 0x21, _::binary>>}
    send(peer, {:inject, wire(0x65, 0x21, <<0>>) <> callback(:bind, 0)})
    assert {:ok, %Result{outcome: :peer_reported_success}} = Task.await(call)
  end

  test "post-dispatch timeout before or after NCP admission ends the epoch and closes once" do
    for admitted <- [false, true] do
      {handle, peer, routes} = interviewed_peer()
      monitor = Process.monitor(handle.owner)
      call = Task.async(fn -> Zigbee.change_binding(handle, routes, request(), 80) end)
      assert_receive {:serial_write, <<0xFE, _, 0x25, 0x21, _::binary>>}
      if admitted, do: send(peer, {:inject, wire(0x65, 0x21, <<0>>)})

      assert {:ok, %Result{outcome: :unconfirmed, issue: :timeout, response: nil} = result} =
               Task.await(call)

      assert result.admission != nil == admitted
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
      assert_receive {:binding_serial_close, ^peer}
      refute_receive {:binding_serial_close, ^peer}, 10
      refute_receive {:serial_write, _}, 10
    end
  end

  test "a valid callback queued beyond source custody cannot report success" do
    {handle, peer, routes} = interviewed_peer(lifetime: 200)
    monitor = Process.monitor(handle.owner)
    call = Task.async(fn -> Zigbee.change_binding(handle, routes, request(), 1_000) end)
    assert_receive {:serial_write, <<0xFE, _, 0x25, 0x21, _::binary>>}
    send(peer, {:inject, wire(0x65, 0x21, <<0>>)})
    wait_state(handle.owner, &(&1.binding.flow.admission != nil))
    :ok = :sys.suspend(handle.owner)
    send(peer, {:inject, callback(:bind, 0)})
    wait_message(handle.owner, fn message -> match?({:zigbee_serial, _, _}, message) end)
    Process.sleep(max(0, routes.entries[@ieee].expires_at_ms - now() + 5))
    :ok = :sys.resume(handle.owner)
    assert {:ok, %Result{outcome: :unconfirmed, issue: :timeout} = result} = Task.await(call)
    assert result.admission.status == 0
    assert result.response.status == 0
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    assert_receive {:binding_serial_close, ^peer}
  end

  test "loss of a pending binding caller before or after SRSP ends its owner" do
    for admitted <- [false, true] do
      {handle, peer, routes} = interviewed_peer()
      monitor = Process.monitor(handle.owner)
      caller = spawn(fn -> Zigbee.change_binding(handle, routes, request(), 1_000) end)
      assert_receive {:serial_write, <<0xFE, _, 0x25, 0x21, _::binary>>}

      if admitted do
        send(peer, {:inject, wire(0x65, 0x21, <<0>>)})
        wait_state(handle.owner, &(&1.binding.flow.admission != nil))
      end

      Process.exit(caller, :kill)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
      assert_receive {:binding_serial_close, ^peer}
      refute_receive {:binding_serial_close, ^peer}, 10
    end
  end

  test "serial loss and explicit close retain available admission without claiming peer success" do
    for ending <- [:disconnect, :adapter_loss, :close] do
      {handle, peer, routes} = interviewed_peer()
      call = Task.async(fn -> Zigbee.change_binding(handle, routes, request(), 1_000) end)
      assert_receive {:serial_write, <<0xFE, _, 0x25, 0x21, _::binary>>}
      send(peer, {:inject, wire(0x65, 0x21, <<0>>)})
      wait_state(handle.owner, &(&1.binding.flow.admission != nil))

      case ending do
        :disconnect -> send(peer, {:disconnect, "credential-canary"})
        :adapter_loss -> Process.exit(peer, :kill)
        :close -> assert :ok = Zigbee.close(handle)
      end

      assert {:ok, %Result{outcome: :unconfirmed, issue: :coordinator_lost} = result} =
               Task.await(call)

      assert result.admission.status == 0
      assert result.response == nil
      refute inspect(result) =~ "credential-canary"
      assert_receive {:binding_serial_close, ^peer}
      refute_receive {:binding_serial_close, ^peer}, 10
    end
  end

  test "malformed or mismatched SRSP ends the epoch and retains an early callback" do
    for response <- [wire(0x65, 0x21, <<>>), wire(0x65, 0x21, <<0, 0>>), wire(0x65, 0x22, <<0>>)] do
      {handle, peer, routes} = interviewed_peer()
      monitor = Process.monitor(handle.owner)
      call = Task.async(fn -> Zigbee.change_binding(handle, routes, request(), 1_000) end)
      assert_receive {:serial_write, <<0xFE, _, 0x25, 0x21, _::binary>>}
      send(peer, {:inject, callback(:bind, 0) <> response})

      assert {:ok, %Result{outcome: :unconfirmed, issue: :invalid_frame, admission: nil} = result} =
               Task.await(call)

      assert result.response.status == 0
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
      assert_receive {:binding_serial_close, ^peer}
    end
  end

  test "binding write faults and a blocking callback become bounded redacted results" do
    for behavior <- [:raise, :throw, :exit, :malformed, :error, {:delay, 50}] do
      {handle, peer, routes} = interviewed_peer(binding_write: behavior)
      monitor = Process.monitor(handle.owner)
      timeout = if is_tuple(behavior), do: 20, else: 1_000

      assert {:ok, %Result{outcome: :unconfirmed, admission: nil, response: nil} = result} =
               Zigbee.change_binding(handle, routes, request(), timeout)

      assert result.issue == if(is_tuple(behavior), do: :timeout, else: :serial)
      refute inspect(result) =~ "credential-canary"
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
      assert_receive {:binding_serial_close, ^peer}
      refute_receive {:binding_serial_close, ^peer}, 10

      if is_tuple(behavior) do
        assert_receive {:serial_write, <<0xFE, _, 0x25, 0x21, _::binary>>}
      else
        refute_receive {:serial_write, _}, 10
      end
    end
  end

  test "the retirement table stops at 256 observed pairs while the event queue reports overflow" do
    {handle, peer, routes} = interviewed_peer()
    bytes = Enum.map_join(0..259, &callback(:bind, 0, &1))
    send(peer, {:inject, bytes})
    wait_state(handle.owner, &(&1.observation_sequence == 263))
    state = :sys.get_state(handle.owner)
    assert MapSet.size(state.used_bindings) == 256
    assert state.event_count == 128
    assert state.dropped == 132

    assert {:error, %Error{kind: :overload}} =
             Zigbee.change_binding(handle, routes, request(), 1_000)

    assert {:ok, _} = Zigbee.handle(handle.owner)
    assert {:ok, %{events: events, dropped: 132}} = Zigbee.drain_events(handle, 128)
    assert length(events) == 128
    refute_receive {:serial_write, _}, 10
  end

  defp interviewed_peer(options \\ []) do
    {:ok, config} =
      Config.new(
        serial: TestBindingSerial,
        device_id: "simulated-coordinator",
        expected_version: {2, 0, 3, 2, 0},
        timeout_ms: 1_000,
        serial_options: [
          test_pid: self(),
          drop_reply: true,
          binding_write: Keyword.get(options, :binding_write, :ok)
        ]
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

    node = <<@route::little-16, 0, @route::little-16, 0::104>>
    send(peer, {:inject, wire(0x65, 2, <<0>>) <> wire(0x45, 0x82, node)})

    assert_receive {:serial_write, <<0xFE, 4, 0x25, 5, _::binary>>}

    endpoints = <<@route::little-16, 0, @route::little-16, 0>>
    send(peer, {:inject, wire(0x65, 5, <<0>>) <> wire(0x45, 0x85, endpoints)})

    assert {:ok, %{outcome: :complete} = result} = Task.await(call)
    {:ok, routes} = Routes.new(result.owner_epoch)
    {:ok, routes} = Routes.adopt(routes, result, now(), Keyword.get(options, :lifetime, 20_000))
    {handle, peer, routes}
  end

  defp request(overrides \\ []) do
    {:ok, request} =
      Binding.new(
        Keyword.merge(
          [
            operation: :bind,
            peer_ieee: @ieee,
            route_address: @route,
            source_endpoint: 1,
            cluster: 6,
            target: {:ieee, @destination, 2},
            correlation_id: "binding"
          ],
          overrides
        )
      )

    request
  end

  defp group_payload,
    do: <<@route::little-16, @ieee::binary, 1, 6::little-16, 1, 0x2345::little-16, 0::56>>

  defp callback(operation, status, source \\ @route),
    do: wire(0x45, if(operation == :bind, do: 0xA1, else: 0xA2), <<source::little-16, status>>)

  defp wire(command, id, payload) do
    body = <<byte_size(payload), command, id, payload::binary>>
    checksum = Enum.reduce(:binary.bin_to_list(body), 0, &Bitwise.bxor/2)
    <<0xFE, body::binary, checksum>>
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp wait_state(owner, predicate, attempts \\ 200)

  defp wait_state(owner, predicate, attempts) when attempts > 0 do
    if predicate.(:sys.get_state(owner)) do
      :ok
    else
      Process.sleep(1)
      wait_state(owner, predicate, attempts - 1)
    end
  end

  defp wait_state(_, _, 0), do: flunk("binding state did not arrive")

  defp wait_message(owner, predicate, attempts \\ 200)

  defp wait_message(owner, predicate, attempts) when attempts > 0 do
    {:messages, messages} = Process.info(owner, :messages)

    if Enum.any?(messages, predicate) do
      :ok
    else
      Process.sleep(1)
      wait_message(owner, predicate, attempts - 1)
    end
  end

  defp wait_message(_, _, 0), do: flunk("binding message was not queued")
end
