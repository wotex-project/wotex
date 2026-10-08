defmodule Wotex.UDP.TransportTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.UDP
  alias Wotex.UDP.{Admission, Config, Endpoint, Error, Handle}

  test "construction is inert and addresses are validated" do
    assert {:ok, local} = Endpoint.bind({127, 0, 0, 1}, 0)
    assert {:ok, %Config{local: ^local}} = Config.new(local: local)
    assert {:error, %Error{kind: :invalid_endpoint}} = Endpoint.unicast({256, 0, 0, 1}, 123)
    assert {:error, %Error{kind: :invalid_endpoint}} = Endpoint.unicast({224, 0, 0, 1}, 123)
    assert {:error, %Error{kind: :invalid_endpoint}} = Endpoint.multicast({223, 0, 0, 1}, 123)

    assert {:error, %Error{kind: :invalid_endpoint}} =
             Endpoint.unicast({192, 0, 2, 255}, 123)

    assert {:error, %Error{kind: :invalid_config}} = Config.new(local: local, local: local)

    assert {:error, %Error{kind: :invalid_config}} =
             Config.new(local: local, max_datagram_bytes: 65_508)

    assert {:error, %Error{kind: :invalid_config}} = Config.new(local: local, unknown: true)
  end

  test "caller-owned IPv4 sockets preserve bytes and source address" do
    {:ok, receiver} = open_local()
    {:ok, sender} = open_local()

    on_exit(fn ->
      UDP.close(receiver)
      UDP.close(sender)
    end)

    {:ok, destination} = UDP.local(receiver)
    {:ok, source} = UDP.local(sender)

    assert :ok = UDP.send(sender, destination, <<0, 255, 1>>, 100)
    assert {:ok, %{data: <<0, 255, 1>>, source: ^source}} = UDP.recv(receiver, 100)
    assert :ok = UDP.send(sender, destination, <<>>, 100)
    assert {:ok, %{data: <<>>, source: ^source}} = UDP.recv(receiver, 100)
    assert {:error, %Error{kind: :timeout}} = UDP.recv(receiver, 0)
  end

  test "bounds reject oversize datagrams and excessive deadlines" do
    {:ok, receiver} = open_local(max_datagram_bytes: 4)
    {:ok, sender} = open_local()

    on_exit(fn ->
      UDP.close(receiver)
      UDP.close(sender)
    end)

    {:ok, destination} = UDP.local(receiver)

    assert {:error, %Error{kind: :datagram_too_large}} =
             UDP.send(receiver, destination, <<1, 2, 3, 4, 5>>, 100)

    assert {:error, %Error{kind: :invalid_datagram}} =
             UDP.send(receiver, destination, [1, 2], 100)

    assert :ok = UDP.send(sender, destination, <<1, 2, 3, 4, 5>>, 100)
    assert {:error, %Error{kind: :datagram_too_large}} = UDP.recv(receiver, 100)
    assert {:error, %Error{kind: :invalid_deadline}} = UDP.recv(receiver, 60_001)
  end

  test "broadcast and multicast require explicit admission" do
    {:ok, socket} = open_local()
    on_exit(fn -> UDP.close(socket) end)
    {:ok, broadcast} = Endpoint.broadcast({255, 255, 255, 255}, 5000)
    {:ok, multicast} = Endpoint.multicast({239, 1, 2, 3}, 5000)

    assert {:error, %Error{kind: :broadcast_disabled}} = UDP.send(socket, broadcast, <<1>>, 10)
    assert {:error, %Error{kind: :multicast_disabled}} = UDP.send(socket, multicast, <<1>>, 10)

    assert {:error, %Error{kind: :multicast_disabled}} =
             UDP.join(socket, multicast, {127, 0, 0, 1})
  end

  test "IPv4 multicast membership uses the selected interface" do
    {:ok, socket} = open_local(multicast: true, multicast_interface: {127, 0, 0, 1})
    on_exit(fn -> UDP.close(socket) end)
    {:ok, group} = Endpoint.multicast({239, 1, 2, 3}, 5000)

    assert :ok = UDP.join(socket, group, {127, 0, 0, 1})
    assert :ok = UDP.leave(socket, group, {127, 0, 0, 1})
    assert {:error, %Error{kind: :invalid_endpoint}} = UDP.join(socket, group, 12)
    assert {:error, %Error{kind: :invalid_endpoint}} = UDP.join(socket, group, {0, 0, 0, 0})
    assert {:error, %Error{kind: :invalid_endpoint}} = UDP.leave(socket, group, 0)
  end

  test "IPv6 loopback preserves the full source endpoint when the host supports it" do
    {:ok, local} = Endpoint.bind({0, 0, 0, 0, 0, 0, 0, 1}, 0)
    {:ok, config} = Config.new(local: local)

    case UDP.open(config) do
      {:ok, receiver} ->
        {:ok, sender} = UDP.open(config)

        on_exit(fn ->
          UDP.close(receiver)
          UDP.close(sender)
        end)

        {:ok, destination} = UDP.local(receiver)
        {:ok, source} = UDP.local(sender)

        assert :ok = UDP.send(sender, destination, <<42>>, 100)
        assert {:ok, %{data: <<42>>, source: ^source}} = UDP.recv(receiver, 100)

      {:error, %Error{kind: :socket}} ->
        :ok
    end
  end

  test "owner loss and socket errors are classified without payloads" do
    {:ok, socket} = open_local()
    assert :ok = UDP.close(socket)
    assert {:error, %Error{kind: :owner_lost} = error} = UDP.recv(socket, 0)
    assert error.reason == nil
    refute inspect(Error.from_socket(:send, {:eacces, "secret-payload"})) =~ "secret-payload"

    assert %Error{kind: :permission, reason: :eacces} =
             Error.from_socket(:send, :eacces)
  end

  test "malformed handles return typed errors at the public boundary" do
    assert {:error, %Error{kind: :invalid_handle}} = UDP.send(nil, nil, <<1>>, 10)
    assert {:error, %Error{kind: :invalid_handle}} = UDP.recv(nil, 10)
    assert {:error, %Error{kind: :invalid_handle}} = UDP.close(nil)

    invalid = %Handle{
      owner: self(),
      epoch: make_ref(),
      admission: make_ref(),
      max_timeout_ms: 0,
      max_datagram_bytes: 0,
      max_pending_calls: 0,
      max_queued_send_bytes: 0
    }

    assert {:error, %Error{kind: :invalid_handle}} = UDP.send(invalid, nil, <<1>>, 10)
    assert {:error, %Error{kind: :invalid_handle}} = UDP.local(invalid)

    {:ok, %Handle{} = valid} = open_local()
    on_exit(fn -> UDP.close(valid) end)
    forged = %Handle{valid | admission: make_ref()}
    assert {:error, %Error{kind: :invalid_handle}} = UDP.local(forged)
  end

  test "a stale epoch cannot operate on a live owner" do
    {:ok, %Handle{} = handle} = open_local()
    on_exit(fn -> UDP.close(handle) end)

    stale = %Handle{handle | epoch: make_ref()}
    assert {:error, %Error{kind: :stale_handle}} = UDP.local(stale)
    assert {:ok, %Endpoint{}} = UDP.local(handle)
  end

  test "an owner crash invalidates its handle" do
    {:ok, %Handle{owner: owner} = handle} = open_local()
    monitor = Process.monitor(owner)
    Process.unlink(owner)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}
    assert {:error, %Error{kind: :owner_lost}} = UDP.local(handle)
  end

  test "a supervised owner exposes a handle and loss is explicit" do
    {:ok, local} = Endpoint.bind({127, 0, 0, 1}, 0)
    {:ok, config} = Config.new(local: local)
    spec = UDP.child_spec(config, id: :udp_owner, restart: :temporary)
    {:ok, supervisor} = Supervisor.start_link([spec], strategy: :one_for_one)
    [{:udp_owner, owner, :worker, _}] = Supervisor.which_children(supervisor)
    {:ok, handle} = UDP.handle(owner)
    assert {:ok, %Endpoint{}} = UDP.local(handle)
    assert :ok = UDP.close(handle)
    assert {:error, %Error{kind: :owner_lost}} = UDP.local(handle)
    assert :ok = Supervisor.stop(supervisor)
  end

  test "batch receive has a finite count and total deadline" do
    {:ok, receiver} = open_local(max_batch_datagrams: 2)
    {:ok, sender} = open_local()

    on_exit(fn ->
      UDP.close(receiver)
      UDP.close(sender)
    end)

    {:ok, destination} = UDP.local(receiver)

    for data <- [<<1>>, <<2>>, <<3>>], do: :ok = UDP.send(sender, destination, data, 100)
    assert {:ok, [_, _]} = UDP.recv_batch(receiver, 2, 100)
    assert {:ok, [%{data: <<3>>}]} = UDP.recv_batch(receiver, 2, 10)
    assert {:error, %Error{kind: :invalid_batch_size}} = UDP.recv_batch(receiver, 3, 10)
  end

  test "pending calls and queued send bytes have finite admission" do
    {:ok, socket} =
      open_local(max_datagram_bytes: 4, max_pending_calls: 3, max_queued_send_bytes: 4)

    {:ok, destination} = UDP.local(socket)
    admission = socket.admission
    radix = socket.max_queued_send_bytes + 1
    owner = socket.owner
    :ok = :sys.suspend(owner)

    on_exit(fn ->
      if Process.alive?(owner) do
        :sys.resume(owner)
        UDP.close(socket)
      end
    end)

    first = Task.async(fn -> UDP.local(socket) end)
    await_admission(admission, radix)
    sender = Task.async(fn -> UDP.send(socket, destination, <<1, 2, 3, 4>>, 500) end)
    await_admission(admission, 2 * radix + 4)

    assert {:error, %Error{kind: :overload}} = UDP.send(socket, destination, <<5>>, 100)

    local = Task.async(fn -> UDP.local(socket) end)
    await_admission(admission, 3 * radix + 4)
    assert {:error, %Error{kind: :overload}} = UDP.local(socket)

    :ok = :sys.resume(owner)
    assert {:ok, ^destination} = Task.await(first, 1_000)
    assert :ok = Task.await(sender, 1_000)
    assert {:ok, ^destination} = Task.await(local, 1_000)
    assert Admission.usage(admission) == 0
    assert :ok = UDP.close(socket)
  end

  test "a timed-out queued send is discarded before it reaches the socket" do
    {:ok, socket} = open_local(max_pending_calls: 2)
    {:ok, destination} = UDP.local(socket)
    radix = socket.max_queued_send_bytes + 1
    owner = socket.owner
    :ok = :sys.suspend(owner)

    on_exit(fn ->
      if Process.alive?(owner) do
        :sys.resume(owner)
        UDP.close(socket)
      end
    end)

    sender = Task.async(fn -> UDP.send(socket, destination, <<9>>, 20) end)
    await_admission(socket.admission, radix + 1)

    assert {:error, %Error{kind: :timeout}} = Task.await(sender, 1_000)
    assert Admission.usage(socket.admission) == radix + 1
    :ok = :sys.resume(owner)
    await_admission(socket.admission, 0)
    assert {:error, %Error{kind: :timeout}} = UDP.recv(socket, 0)
    assert :ok = UDP.close(socket)
  end

  test "a burst of callers cannot exceed queued call and byte limits" do
    {:ok, socket} =
      open_local(max_datagram_bytes: 8, max_pending_calls: 8, max_queued_send_bytes: 32)

    {:ok, destination} = UDP.local(socket)
    owner = socket.owner
    :ok = :sys.suspend(owner)

    on_exit(fn ->
      if Process.alive?(owner) do
        :sys.resume(owner)
        UDP.close(socket)
      end
    end)

    results =
      1..100
      |> Task.async_stream(
        fn _ -> UDP.send(socket, destination, <<0::64>>, 50) end,
        max_concurrency: 100,
        timeout: 1_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, fn
             {:error, %Error{kind: kind}} -> kind in [:timeout, :overload]
             _ -> false
           end)

    assert Enum.count(results, &match?({:error, %Error{kind: :overload}}, &1)) >= 96
    assert Admission.usage(socket.admission) <= 4 * (socket.max_queued_send_bytes + 1) + 32

    :ok = :sys.resume(owner)
    await_admission(socket.admission, 0)
    assert {:error, %Error{kind: :timeout}} = UDP.recv(socket, 0)
    assert :ok = UDP.close(socket)
  end

  test "an independent gen_udp peer exchanges complete binary packets" do
    {:ok, socket} = open_local()
    on_exit(fn -> UDP.close(socket) end)
    {:ok, peer} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    on_exit(fn -> :gen_udp.close(peer) end)
    {:ok, {{127, 0, 0, 1}, peer_port}} = :inet.sockname(peer)
    {:ok, peer_endpoint} = Endpoint.unicast({127, 0, 0, 1}, peer_port)
    {:ok, local} = UDP.local(socket)
    local_port = local.port

    assert :ok = UDP.send(socket, peer_endpoint, <<0, 255, 3>>, 100)
    assert {:ok, {{127, 0, 0, 1}, ^local_port, <<0, 255, 3>>}} = :gen_udp.recv(peer, 0, 100)
    assert :ok = :gen_udp.send(peer, {127, 0, 0, 1}, local.port, <<4, 0, 5>>)
    assert {:ok, %{data: <<4, 0, 5>>, source: ^peer_endpoint}} = UDP.recv(socket, 100)
  end

  test "a new owner can reuse a port without reviving the old handle" do
    {:ok, first} = open_local()
    {:ok, bound} = UDP.local(first)
    assert :ok = UDP.close(first)

    {:ok, local} = Endpoint.bind(bound.address, bound.port)
    {:ok, config} = Config.new(local: local)
    {:ok, second} = UDP.open(config)
    on_exit(fn -> UDP.close(second) end)

    assert {:error, %Error{kind: :owner_lost}} = UDP.send(first, bound, <<1>>, 100)
    assert :ok = UDP.send(second, bound, <<2>>, 100)
    assert {:ok, %{data: <<2>>}} = UDP.recv(second, 100)
  end

  test "an independent multicast peer receives only the explicitly routed binary packet" do
    interface = {127, 0, 0, 1}
    group = {239, 1, 2, 3}

    {:ok, peer} =
      :gen_udp.open(0, [
        :binary,
        {:active, false},
        {:ip, {0, 0, 0, 0}},
        {:add_membership, {group, interface}}
      ])

    on_exit(fn -> :gen_udp.close(peer) end)
    {:ok, {_, port}} = :inet.sockname(peer)
    {:ok, destination} = Endpoint.multicast(group, port)
    {:ok, sender} = open_local(multicast: true, multicast_interface: interface)
    on_exit(fn -> UDP.close(sender) end)
    {:ok, source} = UDP.local(sender)
    source_port = source.port
    assert :ok = UDP.send(sender, destination, <<0, 255, 7>>, 100)
    assert {:ok, {^interface, ^source_port, <<0, 255, 7>>}} = :gen_udp.recv(peer, 0, 100)
    assert {:error, :timeout} = :gen_udp.recv(peer, 0, 0)
  end

  test "handle retrieval cannot queue behind a blocked or saturated owner" do
    {:ok, handle} = open_local(max_pending_calls: 1)
    owner = handle.owner
    :ok = :sys.suspend(owner)

    on_exit(fn ->
      if Process.alive?(owner) do
        :sys.resume(owner)
        UDP.close(handle)
      end
    end)

    request = Task.async(fn -> UDP.local(handle) end)
    await_admission(handle.admission, handle.max_queued_send_bytes + 1)
    {:message_queue_len, before} = Process.info(owner, :message_queue_len)

    results =
      1..100
      |> Task.async_stream(fn _ -> UDP.handle(owner) end, max_concurrency: 100, timeout: 1_000)
      |> Enum.to_list()

    assert Enum.all?(results, &(&1 == {:ok, {:ok, handle}}))
    assert elem(Process.info(owner, :message_queue_len), 1) <= before + 1
    assert {:error, %Error{kind: :overload}} = UDP.local(handle)
    :ok = :sys.resume(owner)
    assert {:ok, _} = Task.await(request, 1_000)
    await_admission(handle.admission, 0)
    assert :ok = UDP.close(handle)
  end

  test "handle retrieval rejects arbitrary processes and malformed selectors" do
    assert {:error, %Error{kind: :invalid_handle}} = UDP.handle(self())
    assert {:error, %Error{kind: :invalid_handle}} = UDP.handle(nil)
    assert {:error, %Error{kind: :invalid_handle}} = UDP.handle(:owner)
    {:ok, handle} = open_local()
    assert :ok = UDP.close(handle)
    assert {:error, %Error{kind: :owner_lost}} = UDP.handle(handle.owner)
  end

  test "forged limits and counters never change the live admission reservation" do
    {:ok, %Handle{} = handle} = open_local()
    on_exit(fn -> UDP.close(handle) end)

    for forged <- [
          %Handle{handle | max_queued_send_bytes: 1},
          %Handle{handle | max_pending_calls: 256},
          %Handle{handle | admission: :atomics.new(1, signed: false)},
          Map.put(handle, :extra, "payload-canary")
        ] do
      assert {:error, %Error{kind: :invalid_handle}} = UDP.local(forged)
      assert Admission.usage(handle.admission) == 0
    end

    assert {:ok, _} = UDP.local(handle)
  end

  test "caller death cancels a live receive without consuming the next datagram" do
    {:ok, receiver} = open_local(max_pending_calls: 1)
    {:ok, sender} = open_local()

    on_exit(fn ->
      UDP.close(receiver)
      UDP.close(sender)
    end)

    {:ok, destination} = UDP.local(receiver)

    for byte <- 1..100 do
      caller = spawn(fn -> UDP.recv(receiver, 60_000) end)
      await_receiving(receiver.owner)
      monitor = Process.monitor(caller)
      Process.exit(caller, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}
      await_admission(receiver.admission, 0)
      assert :ok = UDP.send(sender, destination, <<byte>>, 100)
      assert {:ok, %{data: <<^byte>>}} = UDP.recv(receiver, 100)
      await_admission(receiver.admission, 0)
    end
  end

  test "a dead queued sender is removed before dispatch and releases its byte budget" do
    {:ok, receiver} = open_local(max_pending_calls: 3, max_queued_send_bytes: 1_472)
    {:ok, destination} = UDP.local(receiver)
    active = spawn(fn -> UDP.recv(receiver, 60_000) end)
    await_receiving(receiver.owner)
    sender = spawn(fn -> UDP.send(receiver, destination, <<99>>, 60_000) end)
    radix = receiver.max_queued_send_bytes + 1
    await_admission(receiver.admission, 2 * radix + 1)
    Process.exit(sender, :kill)
    await_admission(receiver.admission, radix)
    Process.exit(active, :kill)
    await_admission(receiver.admission, 0)
    assert {:error, %Error{kind: :timeout}} = UDP.recv(receiver, 0)
    assert :ok = UDP.close(receiver)
  end

  test "queued deadlines expire while another receive is still active" do
    {:ok, receiver} = open_local(max_pending_calls: 2)
    {:ok, destination} = UDP.local(receiver)
    active = spawn(fn -> UDP.recv(receiver, 60_000) end)
    await_receiving(receiver.owner)
    radix = receiver.max_queued_send_bytes + 1
    assert {:error, %Error{kind: :timeout}} = UDP.send(receiver, destination, <<42>>, 20)
    await_admission(receiver.admission, radix)
    Process.exit(active, :kill)
    await_admission(receiver.admission, 0)
    assert {:error, %Error{kind: :timeout}} = UDP.recv(receiver, 0)
    assert :ok = UDP.close(receiver)
  end

  test "close cancels an active batch and queued calls before releasing the port" do
    {:ok, receiver} = open_local(max_pending_calls: 4)
    {:ok, destination} = UDP.local(receiver)
    active = Task.async(fn -> UDP.recv_batch(receiver, 2, 60_000) end)
    await_receiving(receiver.owner)
    queued = Task.async(fn -> UDP.send(receiver, destination, <<9>>, 60_000) end)
    await_admission(receiver.admission, 2 * (receiver.max_queued_send_bytes + 1) + 1)
    monitor = Process.monitor(receiver.owner)
    assert :ok = UDP.close(receiver)
    assert {:error, %Error{kind: :closed}} = Task.await(active, 1_000)
    assert {:error, %Error{kind: :closed}} = Task.await(queued, 1_000)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    await_admission(receiver.admission, 0)

    {:ok, local} = Endpoint.bind(destination.address, destination.port)
    {:ok, config} = Config.new(local: local)
    {:ok, replacement} = UDP.open(config)
    assert {:error, %Error{kind: :timeout}} = UDP.recv(replacement, 0)
    assert :ok = UDP.close(replacement)
  end

  test "canceled selects and stale socket notifications do not affect another owner" do
    {:ok, first} = open_local()
    {:ok, second} = open_local()

    on_exit(fn ->
      UDP.close(first)
      UDP.close(second)
    end)

    caller = spawn(fn -> UDP.recv(first, 60_000) end)
    state = await_receiving(first.owner)
    {:select_info, _, ref} = state.pending[state.active].select
    Process.exit(caller, :kill)
    await_admission(first.admission, 0)
    send(first.owner, {:"$socket", state.socket.handle, :select, ref})
    send(first.owner, {:"$socket", state.socket.handle, :abort, {ref, :closed}})
    send(second.owner, {:"$socket", state.socket.handle, :select, ref})
    assert :ok = UDP.close(first)
    {:ok, destination} = UDP.local(second)
    assert :ok = UDP.send(second, destination, <<7>>, 100)
    assert {:ok, %{data: <<7>>}} = UDP.recv(second, 100)
  end

  test "active owner death cancels its socket wait and frees its bound port" do
    {:ok, receiver} = open_local()
    {:ok, destination} = UDP.local(receiver)
    active = Task.async(fn -> UDP.recv(receiver, 60_000) end)
    await_receiving(receiver.owner)
    Process.unlink(receiver.owner)
    monitor = Process.monitor(receiver.owner)
    Process.exit(receiver.owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}
    assert {:error, %Error{kind: :owner_lost}} = Task.await(active, 1_000)
    {:ok, local} = Endpoint.bind(destination.address, destination.port)
    {:ok, config} = Config.new(local: local)
    {:ok, replacement} = UDP.open(config)
    assert :ok = UDP.close(replacement)
  end

  test "zero-timeout sends and batches poll complete queued datagrams" do
    {:ok, handle} = open_local(max_batch_datagrams: 2)
    on_exit(fn -> UDP.close(handle) end)
    {:ok, %Endpoint{} = destination} = UDP.local(handle)
    assert :ok = UDP.send(handle, destination, <<1>>, 0)
    assert :ok = UDP.send(handle, destination, <<2>>, 0)
    assert {:ok, [%{data: <<1>>}, %{data: <<2>>}]} = UDP.recv_batch(handle, 2, 0)
    assert {:error, %Error{kind: :timeout}} = UDP.recv_batch(handle, 2, 0)

    assert {:error, %Error{kind: :invalid_endpoint}} =
             UDP.send(handle, %Endpoint{destination | port: -1}, <<1>>, 10)

    assert {:error, %Error{kind: :invalid_endpoint}} = UDP.join(handle, nil, 0)

    assert {:error, %Error{kind: :invalid_endpoint}} =
             UDP.leave(handle, destination, "interface-canary")
  end

  test "real socket abort retires the active request and ignores stale control messages" do
    {:ok, handle} = open_local()
    active = Task.async(fn -> UDP.recv(handle, 60_000) end)
    state = await_receiving(handle.owner)
    assert :ok = :socket.close(state.socket.handle)
    assert {:error, %Error{kind: :closed}} = Task.await(active, 1_000)
    await_admission(handle.admission, 0)
    send(handle.owner, {:deadline, make_ref()})
    send(handle.owner, {:DOWN, make_ref(), :process, self(), :normal})
    send(handle.owner, :untrusted_notification)
    assert {:error, %Error{kind: :invalid_handle}} = GenServer.call(handle.owner, :unknown_control)
    assert {:error, %Error{kind: :closed}} = UDP.recv(handle, 100)
    assert {:error, %Error{kind: :closed}} = UDP.close(handle)
  end

  test "supervisor shutdown closes a live wait without affecting a second owner" do
    {:ok, local} = Endpoint.bind({127, 0, 0, 1}, 0)
    {:ok, config} = Config.new(local: local)
    {:ok, supervisor} = Supervisor.start_link([UDP.child_spec(config)], strategy: :one_for_one)
    [{_, owner, _, _}] = Supervisor.which_children(supervisor)
    {:ok, handle} = UDP.handle(owner)
    {:ok, destination} = UDP.local(handle)
    active = Task.async(fn -> UDP.recv(handle, 60_000) end)
    await_receiving(owner)
    {:ok, second} = open_local()
    on_exit(fn -> UDP.close(second) end)
    assert :ok = Supervisor.stop(supervisor)
    assert {:error, %Error{kind: :owner_lost}} = Task.await(active, 1_000)
    {:ok, bound} = Endpoint.bind(destination.address, destination.port)
    {:ok, reopened} = Config.new(local: bound)
    {:ok, replacement} = UDP.open(reopened)
    assert :ok = UDP.close(replacement)
    assert {:ok, _} = UDP.local(second)
  end

  test "a caller lost before owner dispatch never leaves work or consumes a datagram" do
    {:ok, handle} = open_local()
    :ok = :sys.suspend(handle.owner)
    caller = spawn(fn -> UDP.recv(handle, 60_000) end)
    await_admission(handle.admission, handle.max_queued_send_bytes + 1)
    monitor = Process.monitor(caller)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}
    :ok = :sys.resume(handle.owner)
    await_admission(handle.admission, 0)
    assert :sys.get_state(handle.owner).pending == %{}
    assert :ok = UDP.close(handle)
  end

  test "the receiving owner fences a stale admitted message and releases only its reservation" do
    {:ok, handle} = open_local()
    on_exit(fn -> UDP.close(handle) end)

    reply = :erlang.alias([:explicit_unalias])
    id = make_ref()

    request = %{
      id: id,
      from: {self(), reply},
      operation: :local,
      args: [],
      epoch: make_ref(),
      deadline: System.monotonic_time(:millisecond) + 100
    }

    assert {:ok, notification} = Admission.enqueue(handle.admission, request)
    if notification, do: send(notification, {:udp_work, notification})
    assert_receive {:udp_reply, ^id, {:error, %Error{kind: :stale_handle}}}
    assert Admission.usage(handle.admission) == 0
    assert {:ok, _} = UDP.local(handle)
  end

  test "an explicit process stop closes the owned socket during a receive" do
    {:ok, handle} = open_local()
    {:ok, destination} = UDP.local(handle)
    active = Task.async(fn -> UDP.recv(handle, 60_000) end)
    await_receiving(handle.owner)
    assert :ok = GenServer.stop(handle.owner, :normal, 1_000)
    assert {:error, %Error{kind: :owner_lost}} = Task.await(active, 1_000)
    {:ok, local} = Endpoint.bind(destination.address, destination.port)
    {:ok, config} = Config.new(local: local)
    {:ok, replacement} = UDP.open(config)
    assert :ok = UDP.close(replacement)
  end

  test "publication without notification is processed by the bounded owner sweep" do
    {:ok, sender} = open_local()
    {:ok, receiver} = open_local()

    on_exit(fn ->
      UDP.close(sender)
      UDP.close(receiver)
    end)

    {:ok, destination} = UDP.local(receiver)
    parent = self()

    publisher =
      spawn(fn ->
        reply = :erlang.alias([:explicit_unalias])
        id = make_ref()

        request = %{
          id: id,
          from: {self(), reply},
          epoch: sender.epoch,
          operation: :send,
          args: [destination, <<17>>, 1_000],
          deadline: System.monotonic_time(:millisecond) + 1_000
        }

        {:ok, notification} = Admission.enqueue(sender.admission, request)
        send(parent, {:published_without_notice, notification})

        receive do
          {:udp_reply, ^id, result} -> send(parent, {:sweep_result, result})
        end
      end)

    assert_receive {:published_without_notice, notification}
    assert_receive {:sweep_result, :ok}, 1_000
    assert {:ok, %{data: <<17>>}} = UDP.recv(receiver, 100)
    refute Process.alive?(publisher)
    await_admission(sender.admission, 0)
    :ok = :sys.suspend(sender.owner)
    for _ <- 1..100, do: send(notification, {:udp_work, notification})
    assert elem(Process.info(sender.owner, :message_queue_len), 1) <= 1
    :ok = :sys.resume(sender.owner)
    assert {:error, %Error{kind: :timeout}} = UDP.recv(receiver, 0)
    assert {:ok, _} = UDP.local(sender)
  end

  test "death after publication and before wake never strands a call or byte reservation" do
    {:ok, sender} =
      open_local(max_datagram_bytes: 8, max_pending_calls: 1, max_queued_send_bytes: 8)

    {:ok, receiver} = open_local()

    on_exit(fn ->
      UDP.close(sender)
      UDP.close(receiver)
    end)

    {:ok, destination} = UDP.local(receiver)
    parent = self()
    owner = sender.owner

    for byte <- 1..100 do
      :ok = :sys.suspend(owner)

      publisher =
        spawn(fn ->
          request = %{
            id: make_ref(),
            from: {self(), :erlang.alias([:explicit_unalias])},
            epoch: sender.epoch,
            operation: :send,
            args: [destination, <<99, 99, 99>>, 1_000],
            deadline: System.monotonic_time(:millisecond) + 1_000
          }

          result = Admission.enqueue(sender.admission, request)
          send(parent, {:unnotified, self(), result})

          receive do
            :never -> :ok
          end
        end)

      assert_receive {:unnotified, ^publisher, {:ok, _}}
      assert Admission.usage(sender.admission) == 12
      monitor = Process.monitor(publisher)
      Process.exit(publisher, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^publisher, :killed}
      :ok = :sys.resume(owner)
      await_admission(sender.admission, 0)
      assert :ok = UDP.send(sender, destination, <<byte>>, 100)
      assert {:ok, %{data: <<^byte>>}} = UDP.recv(receiver, 100)
      assert {:error, %Error{kind: :timeout}} = UDP.recv(receiver, 0)
    end

    assert Process.alive?(owner)
  end

  test "a publication flood is bounded before wake and canceled publishers release all capacity" do
    {:ok, sender} =
      open_local(max_datagram_bytes: 8, max_pending_calls: 8, max_queued_send_bytes: 32)

    {:ok, destination} = UDP.local(sender)
    owner = sender.owner
    :ok = :sys.suspend(owner)

    on_exit(fn ->
      if Process.alive?(owner) do
        :sys.resume(owner)
        UDP.close(sender)
      end
    end)

    results =
      1..100
      |> Task.async_stream(
        fn _ ->
          request = %{
            id: make_ref(),
            from: {self(), :erlang.alias([:explicit_unalias])},
            epoch: sender.epoch,
            operation: :send,
            args: [destination, <<0::64>>, 1_000],
            deadline: System.monotonic_time(:millisecond) + 1_000
          }

          Admission.enqueue(sender.admission, request)
        end,
        max_concurrency: 100,
        timeout: 1_000
      )
      |> Enum.to_list()

    assert Enum.count(results, &match?({:ok, {:ok, _}}, &1)) == 4
    assert Enum.count(results, &match?({:ok, {:error, %Error{kind: :overload}}}, &1)) == 96
    assert Admission.usage(sender.admission) == 4 * 33 + 32
    assert elem(Process.info(owner, :message_queue_len), 1) <= 1
    :ok = :sys.resume(owner)
    await_admission(sender.admission, 0)
    assert {:error, %Error{kind: :timeout}} = UDP.recv(sender, 0)
    assert :ok = UDP.close(sender)
  end

  test "owner death after publication deletes its queue and invalidates its handle" do
    {:ok, sender} = open_local()
    {:ok, destination} = UDP.local(sender)
    :ok = :sys.suspend(sender.owner)
    parent = self()

    publisher =
      spawn(fn ->
        monitor = Process.monitor(sender.owner)

        request = %{
          id: make_ref(),
          from: {self(), :erlang.alias([:explicit_unalias])},
          epoch: sender.epoch,
          operation: :send,
          args: [destination, <<1>>, 1_000],
          deadline: System.monotonic_time(:millisecond) + 1_000
        }

        result = Admission.enqueue(sender.admission, request)
        send(parent, {:before_owner_loss, result})

        receive do
          {:DOWN, ^monitor, :process, _, _} -> send(parent, :published_owner_lost)
        end
      end)

    assert_receive {:before_owner_loss, {:ok, _}}
    Process.unlink(sender.owner)
    monitor = Process.monitor(sender.owner)
    Process.exit(sender.owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}
    assert_receive :published_owner_lost
    refute Process.alive?(publisher)
    assert :ets.info(sender.admission) == :undefined
    assert {:error, %Error{kind: :owner_lost}} = UDP.local(sender)
    {:ok, local} = Endpoint.bind(destination.address, destination.port)
    {:ok, config} = Config.new(local: local)
    {:ok, replacement} = UDP.open(config)
    assert {:error, %Error{kind: :timeout}} = UDP.recv(replacement, 0)
    assert :ok = UDP.close(replacement)
  end

  test "an admitted close fences later producers before the owner receives its wake" do
    {:ok, handle} = open_local()
    {:ok, destination} = UDP.local(handle)
    :ok = :sys.suspend(handle.owner)
    closer = Task.async(fn -> UDP.close(handle) end)
    await_admission(handle.admission, handle.max_queued_send_bytes + 1)
    assert {:error, %Error{kind: :closed}} = UDP.send(handle, destination, <<1>>, 100)
    :ok = :sys.resume(handle.owner)
    assert :ok = Task.await(closer, 1_000)
    assert :ets.info(handle.admission) == :undefined
  end

  test "a canceled close published without notification does not close the live socket" do
    {:ok, handle} = open_local()
    on_exit(fn -> UDP.close(handle) end)
    :ok = :sys.suspend(handle.owner)
    parent = self()

    caller =
      spawn(fn ->
        request = %{
          id: make_ref(),
          from: {self(), :erlang.alias([:explicit_unalias])},
          epoch: handle.epoch,
          operation: :close,
          args: [],
          deadline: System.monotonic_time(:millisecond) + 1_000
        }

        send(parent, {:close_publication, Admission.enqueue(handle.admission, request)})

        receive do
          :never -> :ok
        end
      end)

    assert_receive {:close_publication, {:ok, _}}
    monitor = Process.monitor(caller)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}
    :ok = :sys.resume(handle.owner)
    await_admission(handle.admission, 0)
    assert {:ok, _} = UDP.local(handle)
  end

  test "zero-timeout calls refuse to queue behind an active receive" do
    {:ok, handle} = open_local(max_pending_calls: 4)
    on_exit(fn -> UDP.close(handle) end)
    {:ok, destination} = UDP.local(handle)
    receiver = Task.async(fn -> UDP.recv(handle, 1_000) end)
    await_receiving(handle.owner)
    reserved = Admission.usage(handle.admission)

    assert {:error, %Error{kind: :timeout}} = UDP.send(handle, destination, <<1>>, 0)
    assert {:error, %Error{kind: :timeout}} = UDP.recv(handle, 0)
    assert {:error, %Error{kind: :timeout}} = UDP.recv_batch(handle, 2, 0)
    assert Admission.usage(handle.admission) == reserved
    assert :ok = UDP.close(handle)
    assert {:error, %Error{kind: :closed}} = Task.await(receiver, 1_000)
  end

  test "an expired close reopens admission while the live caller receives its refusal" do
    {:ok, handle} = open_local(max_timeout_ms: 20)
    :ok = :sys.suspend(handle.owner)
    closer = Task.async(fn -> UDP.close(handle) end)
    await_admission(handle.admission, handle.max_queued_send_bytes + 1)
    Process.sleep(40)
    :ok = :sys.resume(handle.owner)
    assert {:error, %Error{kind: :timeout, operation: :close}} = Task.await(closer, 1_000)
    assert Process.alive?(handle.owner)
    assert {:ok, _} = UDP.local(handle)
    assert :ok = UDP.close(handle)
    refute Process.alive?(handle.owner)
    assert :ets.info(handle.admission) == :undefined
  end

  test "an expired idle poll retires its reply alias while its caller remains alive" do
    {:ok, sender} = open_local(max_timeout_ms: 20)
    {:ok, receiver} = open_local()
    {:ok, destination} = UDP.local(receiver)
    owner = sender.owner
    :ok = :sys.suspend(owner)

    on_exit(fn ->
      if Process.alive?(owner) do
        :sys.resume(owner)
        UDP.close(sender)
      end

      UDP.close(receiver)
    end)

    parent = self()

    caller =
      spawn_link(fn ->
        result = UDP.send(sender, destination, <<255>>, 0)
        send(parent, {:idle_poll_result, result})

        receive do
          :inspect_mailbox -> send(parent, {:idle_poll_mailbox, Process.info(self(), :messages)})
        end
      end)

    await_admission(sender.admission, sender.max_queued_send_bytes + 2)
    assert_receive {:idle_poll_result, {:error, %Error{kind: :timeout}}}, 500
    assert Process.alive?(caller)
    :ok = :sys.resume(owner)
    await_admission(sender.admission, 0)
    assert {:error, %Error{kind: :timeout}} = UDP.recv(receiver, 0)
    send(caller, :inspect_mailbox)
    assert_receive {:idle_poll_mailbox, {:messages, []}}
    assert {:ok, _} = UDP.local(sender)
    assert :ok = UDP.close(sender)
  end

  defp await_receiving(owner, attempts \\ 100)

  defp await_receiving(owner, attempts) when attempts > 0 do
    state = :sys.get_state(owner)

    if state.active && state.pending[state.active].select do
      state
    else
      Process.sleep(1)
      await_receiving(owner, attempts - 1)
    end
  end

  defp await_receiving(_, 0), do: flunk("owner did not enter a bounded socket wait")

  defp open_local(options \\ []) do
    {:ok, local} = Endpoint.bind({127, 0, 0, 1}, 0)
    {:ok, config} = Config.new(Keyword.put(options, :local, local))
    UDP.open(config)
  end

  defp await_admission(admission, expected, attempts \\ 100)

  defp await_admission(admission, expected, attempts) when attempts > 0 do
    if Admission.usage(admission) == expected do
      :ok
    else
      Process.sleep(1)
      await_admission(admission, expected, attempts - 1)
    end
  end

  defp await_admission(admission, expected, 0) do
    assert Admission.usage(admission) == expected
  end
end
