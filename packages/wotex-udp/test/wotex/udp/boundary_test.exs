defmodule Wotex.UDP.BoundaryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Wotex.UDP
  alias Wotex.UDP.{Admission, Backend, Config, Endpoint, Error}

  test "invalid values and unknown address families never open a socket" do
    {:ok, local} = Endpoint.bind({127, 0, 0, 1}, 0)
    {:ok, config} = Config.new(local: local)

    capture_log(fn ->
      assert {:error, %Error{kind: :invalid_config}} = UDP.open(%Config{config | max_timeout_ms: 0})
    end)

    assert {:error, %Error{kind: :invalid_config}} = Backend.open(nil)
    assert {:error, %Error{kind: :invalid_config}} = Config.new(:invalid)
    assert {:error, %Error{kind: :invalid_config}} = Config.new(local: local, unicast_hops: 0)
    assert {:error, %Error{kind: :invalid_config}} = Config.new(local: local, multicast_hops: 256)
    assert {:error, %Error{kind: :invalid_endpoint}} = Endpoint.bind({1, 2, 3}, 0)
    assert {:error, %Error{kind: :invalid_endpoint}} = Endpoint.bind({-1, 2, 3, 4}, 0)
    assert {:error, %Error{kind: :invalid_endpoint}} = Endpoint.bind({1, 2, 3, 4}, 65_536)
    assert {:error, %Error{kind: :invalid_endpoint}} = Endpoint.unicast({1, 2, 3, 4}, 0)
    assert {:error, %Error{kind: :invalid_endpoint}} = Endpoint.unicast({0, 0, 0, 0}, 9)
    assert {:error, %Error{kind: :invalid_endpoint}} = Endpoint.unicast({0, 0, 0, 0, 0, 0, 0, 0}, 9)
    assert {:error, %Error{kind: :invalid_endpoint}} = Endpoint.from_sockaddr(%{})
    refute Endpoint.valid?(%Endpoint{local | family: :inet6})
    refute Endpoint.valid?(%Endpoint{local | kind: :unsupported})

    assert {:error, %Error{kind: :invalid_endpoint}} =
             Endpoint.unicast({0xFE80, 0, 0, 0, 0, 0, 0, 1}, 123)

    assert {:ok, %Endpoint{scope_id: 2} = scoped} =
             Endpoint.unicast({0xFE80, 0, 0, 0, 0, 0, 0, 1}, 123, scope_id: 2)

    assert Endpoint.sockaddr(scoped).scope_id == 2

    assert {:error, %Error{kind: :invalid_endpoint}} =
             Endpoint.unicast({127, 0, 0, 1}, 123, scope_id: 2)

    assert {:error, %Error{kind: :invalid_endpoint}} =
             Endpoint.unicast({127, 0, 0, 1}, 123, scope_id: 1, scope_id: 2)
  end

  test "a failed bind closes its newly opened socket and preserves the first owner" do
    {:ok, local} = Endpoint.bind({127, 0, 0, 1}, 0)
    {:ok, config} = Config.new(local: local)
    {:ok, first} = UDP.open(config)
    on_exit(fn -> UDP.close(first) end)
    {:ok, bound} = UDP.local(first)
    {:ok, occupied} = Endpoint.bind(bound.address, bound.port)
    {:ok, occupied_config} = Config.new(local: occupied)

    capture_log(fn ->
      assert {:error, %Error{kind: :socket, reason: :eaddrinuse}} = UDP.open(occupied_config)
    end)

    assert {:ok, ^bound} = UDP.local(first)
  end

  test "direct socket failures remain typed at the owner backend" do
    {:ok, local} = Endpoint.bind({127, 0, 0, 1}, 0)
    {:ok, config} = Config.new(local: local, broadcast: true)
    {:ok, backend} = Backend.open(config)
    {:ok, destination} = Backend.local(backend)
    {:ok, other_family} = Endpoint.unicast({0, 0, 0, 0, 0, 0, 0, 1}, 1234)

    assert {:error, %Error{kind: :invalid_endpoint}} = Backend.send(backend, destination, [1], 10)

    assert {:error, %Error{kind: :datagram_too_large}} =
             Backend.send(backend, destination, :binary.copy(<<1>>, 1_473), 10)

    assert {:error, %Error{kind: :address_family}} = Backend.send(backend, other_family, <<1>>, 10)
    assert {:error, %Error{kind: :invalid_deadline}} = Backend.recv_batch(backend, 1, -1)

    assert {:error, %Error{kind: :invalid_endpoint}} =
             Backend.join(backend, destination, {127, 0, 0, 1})

    assert {:error, %Error{kind: :invalid_endpoint}} = Backend.join(backend, nil, {127, 0, 0, 1})

    assert :ok = Backend.close(backend)
    assert {:error, %Error{kind: :closed}} = Backend.local(backend)
    assert {:error, %Error{kind: :closed}} = Backend.send(backend, destination, <<1>>, 10)
  end

  test "multicast values and malformed interface selections remain distinct" do
    assert {:ok, %Endpoint{family: :inet6}} =
             Endpoint.multicast({0xFF02, 0, 0, 0, 0, 0, 0, 1}, 4_000, scope_id: 1)

    assert {:error, %Error{kind: :invalid_endpoint}} =
             Endpoint.multicast({0xFF02, 0, 0, 0, 0, 0, 0, 1}, 4_000)

    assert {:error, %Error{kind: :invalid_endpoint}} =
             Endpoint.broadcast({0xFF02, 0, 0, 0, 0, 0, 0, 1}, 4_000)

    {:ok, local} = Endpoint.bind({0, 0, 0, 0, 0, 0, 0, 1}, 0)
    {:ok, config} = Config.new(local: local, multicast: true, multicast_interface: 1)

    case Backend.open(config) do
      {:ok, backend} ->
        on_exit(fn -> Backend.close(backend) end)
        {:ok, group} = Endpoint.multicast({0xFF02, 0, 0, 0, 0, 0, 0, 1}, 4_000, scope_id: 1)
        assert {:error, %Error{kind: :invalid_endpoint}} = Backend.join(backend, group, -1)
        result = Backend.join(backend, group, 1)
        assert result == :ok or match?({:error, %Error{}}, result)

      {:error, %Error{kind: :socket}} ->
        :ok
    end
  end

  test "source and error values are explicit even for unusual OS inputs" do
    assert {:ok, %Endpoint{kind: :bind}} =
             Endpoint.from_sockaddr(%{addr: {0, 0, 0, 0}, port: 0})

    assert %Error{kind: :permission} = Error.from_socket(:send, :eperm)
    assert %Error{kind: :closed} = Error.from_socket(:recv, :closed)
    assert %Error{kind: :unsupported_feature} = Error.from_socket(:open, :enoprotoopt)
    assert %Error{kind: :unsupported_feature} = Error.from_socket(:open, :eopnotsupp)
    assert %Error{kind: :unsupported_feature} = Error.from_socket(:open, :enotsup)

    assert %Error{kind: :unsupported_feature, reason: nil} =
             Error.from_socket(:join, {:invalid, {:socket_option, {:ipv6, :add_membership}}})

    assert %Error{kind: :overload} = Error.from_socket(:send, :enobufs)
    assert %Error{kind: :datagram_too_large} = Error.from_socket(:send, :emsgsize)
    assert Exception.message(Error.from_socket(:recv, :timeout)) == "UDP recv failed: timeout"
  end

  test "backend batch boundaries preserve complete datagrams and discard malformed batches" do
    {:ok, local} = Endpoint.bind({127, 0, 0, 1}, 0)
    {:ok, config} = Config.new(local: local, max_datagram_bytes: 4, max_batch_datagrams: 2)
    {:ok, backend} = Backend.open(config)
    on_exit(fn -> Backend.close(backend) end)
    {:ok, destination} = Backend.local(backend)
    {:ok, peer} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    on_exit(fn -> :gen_udp.close(peer) end)
    send_packet = fn data -> :gen_udp.send(peer, destination.address, destination.port, data) end

    assert {:error, %Error{kind: :invalid_batch_size}} = Backend.recv_batch(backend, 3, 20)
    assert {:error, %Error{kind: :invalid_deadline}} = Backend.recv(backend, -1)
    assert :ok = send_packet.(<<1>>)
    assert :ok = send_packet.(<<2>>)
    assert {:ok, [%{data: <<1>>}, %{data: <<2>>}]} = Backend.recv_batch(backend, 2, 100)
    assert :ok = send_packet.(<<3>>)
    assert {:ok, [%{data: <<3>>}]} = Backend.recv_batch(backend, 2, 20)
    assert {:error, %Error{kind: :timeout}} = Backend.recv_batch(backend, 2, 0)
    assert :ok = send_packet.(<<4>>)
    assert :ok = send_packet.(<<0::40>>)
    assert {:error, %Error{kind: :datagram_too_large}} = Backend.recv_batch(backend, 2, 100)
    assert {:error, %Error{kind: :timeout}} = Backend.recv(backend, 0)
    {:ok, multicast} = Endpoint.multicast({239, 1, 2, 3}, 5000)

    assert {:error, %Error{kind: :multicast_disabled}} =
             Backend.join(backend, multicast, {127, 0, 0, 1})
  end

  test "malformed publication values fail without retaining caller input" do
    notification = :erlang.alias([:explicit_unalias])
    table = Admission.new(2, 4, notification)

    request = %{
      id: make_ref(),
      from: {self(), notification},
      operation: :local,
      args: [],
      deadline: 0,
      epoch: make_ref()
    }

    assert {:error, %Error{kind: :invalid_handle}} = Admission.enqueue(make_ref(), request)
    assert {:error, %Error{kind: :invalid_handle}} = Admission.enqueue(table, nil)

    assert {:error, %Error{kind: :invalid_handle}} =
             Admission.enqueue(table, Map.put(request, :secret, "publication-canary"))

    assert {:error, %Error{kind: :invalid_handle}} =
             Admission.enqueue(table, %{request | args: nil})

    assert Admission.usage(table) == 0
    :erlang.unalias(notification)
  end

  test "duplicate request identities cannot change reservations and repeated release is inert" do
    notification = :erlang.alias([:explicit_unalias])
    table = Admission.new(3, 8, notification)
    {:ok, destination} = Endpoint.unicast({127, 0, 0, 1}, 1234)

    request = %{
      id: make_ref(),
      from: {self(), notification},
      operation: :send,
      args: [destination, <<1, 2>>, 100],
      deadline: System.monotonic_time(:millisecond) + 100,
      epoch: make_ref()
    }

    assert {:ok, ^notification} = Admission.enqueue(table, request)

    assert {:error, %Error{kind: :invalid_handle}} =
             Admission.enqueue(table, %{request | args: [destination, <<3, 4, 5>>, 100]})

    second = %{request | id: make_ref(), args: [destination, <<6, 7, 8>>, 100]}
    assert {:ok, nil} = Admission.enqueue(table, second)
    assert Admission.usage(table) == 2 * 9 + 5
    assert :ok = Admission.release(table, request.id)
    assert Admission.usage(table) == 9 + 3
    assert :ok = Admission.release(table, request.id)
    assert :ok = Admission.release(table, make_ref())
    assert Admission.usage(table) == 9 + 3
    assert :ok = Admission.release(table, second.id)
    assert Admission.usage(table) == 0
    :ets.delete(table)
    assert Admission.usage(table) == 0
    :erlang.unalias(notification)
  end

  test "foreign local socket metadata fails as a payload-free endpoint error" do
    {:ok, local} = Endpoint.bind({127, 0, 0, 1}, 0)
    {:ok, config} = Config.new(local: local)
    {:ok, unix} = :socket.open(:local, :dgram, :default)

    path =
      Path.join(System.tmp_dir!(), "wotex-udp-source-canary-#{System.unique_integer([:positive])}")

    on_exit(fn ->
      :socket.close(unix)
      File.rm(path)
    end)

    assert :ok = :socket.bind(unix, %{family: :local, path: path})
    backend = %Backend{handle: unix, config: config}
    assert {:error, %Error{kind: :invalid_endpoint} = error} = Backend.local(backend)
    refute inspect(error) =~ "source-canary"
  end

  test "direct multicast membership rejects a malformed numeric interface" do
    {:ok, local} = Endpoint.bind({127, 0, 0, 1}, 0)

    {:ok, config} =
      Config.new(local: local, multicast: true, multicast_interface: {127, 0, 0, 1})

    {:ok, backend} = Backend.open(config)
    on_exit(fn -> Backend.close(backend) end)
    {:ok, group} = Endpoint.multicast({239, 1, 2, 3}, 5000)
    assert {:error, %Error{kind: :invalid_endpoint}} = Backend.join(backend, group, {256, 0, 0, 1})
    assert {:ok, _} = Backend.local(backend)
  end

  test "multicast configuration requires a concrete interface of the matching family" do
    {:ok, ipv4} = Endpoint.bind({127, 0, 0, 1}, 0)
    {:ok, ipv6} = Endpoint.bind({0, 0, 0, 0, 0, 0, 0, 1}, 0)

    for interface <- [nil, 0, 1, {0, 0, 0, 0}, {239, 1, 2, 3}, {255, 255, 255, 255}, "lo0"] do
      assert {:error, %Error{kind: :invalid_config}} =
               Config.new(local: ipv4, multicast: true, multicast_interface: interface)
    end

    for interface <- [nil, 0, -1, 2_147_483_648, {127, 0, 0, 1}, "lo0"] do
      assert {:error, %Error{kind: :invalid_config}} =
               Config.new(local: ipv6, multicast: true, multicast_interface: interface)
    end

    assert {:error, %Error{kind: :invalid_config}} =
             Config.new(local: ipv4, multicast_interface: {127, 0, 0, 1})

    assert {:ok, config} =
             Config.new(local: ipv4, multicast: true, multicast_interface: {127, 0, 0, 1})

    refute Config.valid?(%Config{config | multicast_interface: nil})
    assert {:ok, _} = Config.new(local: ipv6, multicast: true, multicast_interface: 2_147_483_647)
  end

  test "IPv4 multicast selects the explicit egress address and refuses wildcard memberships" do
    {:ok, local} = Endpoint.bind({127, 0, 0, 1}, 0)

    {:ok, config} =
      Config.new(local: local, multicast: true, multicast_interface: {127, 0, 0, 1})

    {:ok, backend} = Backend.open(config)
    on_exit(fn -> Backend.close(backend) end)
    assert {:ok, {127, 0, 0, 1}} = :socket.getopt(backend.handle, :ip, :multicast_if)
    {:ok, group} = Endpoint.multicast({239, 1, 2, 3}, 4_000)

    for interface <- [{0, 0, 0, 0}, {239, 1, 2, 4}, {255, 255, 255, 255}, 0] do
      assert {:error, %Error{kind: :invalid_endpoint}} = Backend.join(backend, group, interface)
      assert {:error, %Error{kind: :invalid_endpoint}} = Backend.leave(backend, group, interface)
    end

    assert {:ok, {127, 0, 0, 1}} = :socket.getopt(backend.handle, :ip, :multicast_if)
  end

  test "IPv6 scoped sends and memberships cannot substitute another interface" do
    {:ok, local} = Endpoint.bind({0, 0, 0, 0, 0, 0, 0, 1}, 0)
    {:ok, config} = Config.new(local: local, multicast: true, multicast_interface: 1)

    case Backend.open(config) do
      {:ok, backend} ->
        on_exit(fn -> Backend.close(backend) end)
        assert {:ok, 1} = :socket.getopt(backend.handle, :ipv6, :multicast_if)
        {:ok, group} = Endpoint.multicast({0xFF02, 0, 0, 0, 0, 0, 0, 1}, 4_000, scope_id: 2)
        assert {:error, %Error{kind: :invalid_endpoint}} = Backend.send(backend, group, <<1>>, 0)

        assert {:error, %Error{kind: :invalid_endpoint}} =
                 Backend.send_nowait(backend, group, <<1>>)

        assert {:error, %Error{kind: :invalid_endpoint}} = Backend.join(backend, group, 1)
        assert {:error, %Error{kind: :invalid_endpoint}} = Backend.join(backend, group, 0)
        assert {:error, %Error{kind: :invalid_endpoint}} = Backend.leave(backend, group, 1)
        assert {:ok, 1} = :socket.getopt(backend.handle, :ipv6, :multicast_if)
        assert {:ok, _} = Backend.local(backend)
        {:ok, matching} = Endpoint.multicast(group.address, group.port, scope_id: 1)
        {:ok, global} = Endpoint.multicast({0xFF0E, 0, 0, 0, 0, 0, 0, 1}, 4_000)
        assert :ok = Backend.close(backend)
        assert {:error, %Error{kind: :closed}} = Backend.send(backend, matching, <<1>>, 0)
        assert {:error, %Error{kind: :closed}} = Backend.send_nowait(backend, matching, <<1>>)

        membership_error =
          if :socket.is_supported(:options, {:ipv6, :add_membership}),
            do: :closed,
            else: :unsupported_feature

        assert {:error, %Error{kind: ^membership_error}} = Backend.join(backend, global, 1)

      {:error, %Error{kind: kind}} when kind in [:socket, :unsupported_feature] ->
        :ok
    end
  end

  test "an unavailable multicast interface fails open without selecting an OS default" do
    {:ok, local} = Endpoint.bind({127, 0, 0, 1}, 0)

    {:ok, config} =
      Config.new(local: local, multicast: true, multicast_interface: {203, 0, 113, 250})

    assert {:error, %Error{kind: :socket, operation: :open}} = Backend.open(config)
    {:ok, ordinary} = Config.new(local: local)
    assert {:ok, backend} = Backend.open(ordinary)
    assert :ok = Backend.close(backend)
  end
end
