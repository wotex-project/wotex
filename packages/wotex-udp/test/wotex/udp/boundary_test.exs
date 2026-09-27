defmodule Wotex.UDP.BoundaryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Wotex.UDP
  alias Wotex.UDP.{Backend, Config, Endpoint, Error}

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
    {:ok, config} = Config.new(local: local, multicast: true)

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
    assert %Error{kind: :overload} = Error.from_socket(:send, :enobufs)
    assert %Error{kind: :datagram_too_large} = Error.from_socket(:send, :emsgsize)
    assert Exception.message(Error.from_socket(:recv, :timeout)) == "UDP recv failed: timeout"
  end
end
