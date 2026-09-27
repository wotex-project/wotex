defmodule Wotex.UDP.TransportTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.UDP
  alias Wotex.UDP.{Config, Endpoint, Error, Handle}

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
    {:ok, socket} = open_local(multicast: true)
    on_exit(fn -> UDP.close(socket) end)
    {:ok, group} = Endpoint.multicast({239, 1, 2, 3}, 5000)

    assert :ok = UDP.join(socket, group, {127, 0, 0, 1})
    assert :ok = UDP.leave(socket, group, {127, 0, 0, 1})
    assert {:error, %Error{kind: :invalid_endpoint}} = UDP.join(socket, group, 12)
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
    assert :atomics.get(admission, 1) == 0
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
    assert :atomics.get(socket.admission, 1) == radix + 1
    :ok = :sys.resume(owner)
    await_admission(socket.admission, 0)
    assert {:error, %Error{kind: :timeout}} = UDP.recv(socket, 0)
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
    assert :atomics.get(socket.admission, 1) <= 4 * (socket.max_queued_send_bytes + 1) + 32

    :ok = :sys.resume(owner)
    await_admission(socket.admission, 0)
    assert {:error, %Error{kind: :timeout}} = UDP.recv(socket, 0)
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

  defp open_local(options \\ []) do
    {:ok, local} = Endpoint.bind({127, 0, 0, 1}, 0)
    {:ok, config} = Config.new(Keyword.put(options, :local, local))
    UDP.open(config)
  end

  defp await_admission(admission, expected, attempts \\ 100)

  defp await_admission(admission, expected, attempts) when attempts > 0 do
    if :atomics.get(admission, 1) == expected do
      :ok
    else
      Process.sleep(1)
      await_admission(admission, expected, attempts - 1)
    end
  end

  defp await_admission(admission, expected, 0) do
    assert :atomics.get(admission, 1) == expected
  end
end
