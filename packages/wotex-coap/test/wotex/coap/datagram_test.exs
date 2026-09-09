defmodule Wotex.CoAP.DatagramTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.CoAP.{Connection, Error}
  alias Wotex.CoAP.Datagram.UDP

  test "WCO-C02 WCO-S01 malformed adapter values never touch an unrelated process" do
    config = config()

    for bad <- [
          nil,
          Map.put(config, :extra, true),
          %{config | host: {1}},
          %{config | host: {256, 0, 0, 1}},
          %{config | port: 0},
          %{config | generation: nil},
          %{config | options: [:unknown]}
        ] do
      assert {:error, %Error{code: :invalid_datagram_config}} = UDP.open(bad, self(), 100)
    end

    assert {:error, %Error{}} = UDP.open(config, :owner, 100)
    assert {:error, %Error{}} = UDP.open(config, self(), 0)
    {:ok, agent} = Agent.start_link(fn -> :untouched end)

    for bad <- [
          nil,
          %{},
          %{pid: self(), generation: make_ref()},
          %{pid: agent, generation: make_ref()}
        ] do
      assert {:error, %Error{code: :invalid_datagram_handle}} = UDP.send(bad, <<>>)
      assert {:error, %Error{code: :invalid_datagram_handle}} = UDP.set_active_once(bad)
      assert {:error, %Error{code: :invalid_datagram_handle}} = UDP.close(bad)
    end

    assert {:error, %Error{code: :invalid_datagram}} = UDP.send(nil, nil)
    assert {:error, %Error{code: :invalid_datagram}} = UDP.send(nil, :binary.copy(<<0>>, 1153))
    assert Agent.get(agent, & &1) == :untouched
    :ok = Agent.stop(agent)
    dead = %{pid: agent, generation: make_ref()}
    assert {:error, %Error{code: :connection_closed}} = UDP.send(dead, <<>>)
    assert :ok = UDP.close(dead)
    refute_received {:"$gen_call", _, _}
  end

  test "WCO-S01 WCO-V01 UDP normalizes active-once messages and retains generation identity" do
    {:ok, peer} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(peer)
    config = %{config() | port: port}
    {:ok, handle} = UDP.open(config, self(), 100)
    socket = :sys.get_state(handle.pid).socket
    generation = handle.generation
    assert :ok = UDP.send(handle, "request")
    assert {:ok, {ip, client_port, "request"}} = :gen_udp.recv(peer, 0, 1000)
    assert :ok = UDP.set_active_once(handle)
    :ok = :gen_udp.send(peer, ip, client_port, "response")
    assert_receive {:wotex_datagram, ^generation, {:data, {127, 0, 0, 1}, ^port, "response"}}
    assert {:error, %Error{}} = UDP.send(%{handle | generation: make_ref()}, "forged")
    assert {:error, %Error{}} = GenServer.call(handle.pid, {make_ref(), :arm})
    send(handle.pid, :unrelated)
    send(handle.pid, {:udp_error, socket, :injected})
    assert_receive {:wotex_datagram, ^generation, {:error, :transport_error}}
    assert_receive {:wotex_datagram, ^generation, :closed}
    assert :erlang.port_info(socket) == :undefined
    assert :ok = UDP.close(handle)
    :ok = :gen_udp.close(peer)
  end

  test "WCO-C03 WCO-V15 owner death and forced adapter close release actual sockets" do
    owner = spawn(fn -> receive do: (:done -> :ok) end)
    {:ok, handle} = UDP.open(config(), owner, 100)
    socket = :sys.get_state(handle.pid).socket
    monitor = Process.monitor(handle.pid)
    send(owner, :done)
    assert_receive {:DOWN, ^monitor, :process, _, reason}
    assert reason in [:normal, :killed]
    assert :erlang.port_info(socket) == :undefined

    {:ok, handle} = UDP.open(config(), self(), 100)
    socket = :sys.get_state(handle.pid).socket
    true = :erlang.suspend_process(handle.pid)
    assert {:error, %Error{code: :cleanup_timeout}} = UDP.close(handle)
    refute Process.alive?(handle.pid)
    assert :erlang.port_info(socket) == :undefined
    assert :ok = UDP.close(handle)
  end

  test "WCO-C04 WCO-V15 an unavailable socket returns bounded errors for send and arm" do
    {:ok, handle} = UDP.open(config(), self(), 100)
    :ok = :gen_udp.close(:sys.get_state(handle.pid).socket)
    assert {:error, %Error{code: :transport_error}} = UDP.send(handle, "request")
    assert {:error, %Error{code: :transport_error}} = UDP.set_active_once(handle)
    assert :ok = UDP.close(handle)
  end

  test "WCO-C03 WCO-I05 suspended UDP and connection owners still release the owned socket" do
    {:ok, connection} = Connection.start_link(host: "127.0.0.1")
    adapter = :sys.get_state(connection).handle.pid
    %{socket: socket, lifetime: lifetime} = :sys.get_state(adapter)
    adapter_monitor = Process.monitor(adapter)
    lifetime_monitor = Process.monitor(lifetime)
    true = :erlang.suspend_process(adapter)
    true = :erlang.suspend_process(connection)
    assert :ok = Connection.abort(connection)
    assert_receive {:DOWN, ^adapter_monitor, :process, ^adapter, :killed}, 100
    assert_receive {:DOWN, ^lifetime_monitor, :process, ^lifetime, :normal}, 100
    assert :erlang.port_info(socket) == :undefined
    assert :ok = Connection.abort(connection)

    {:ok, unrelated} = Agent.start_link(fn -> :untouched end)

    for pid <- [self(), unrelated, nil] do
      assert {:error, %Error{code: :invalid_session}} = Connection.abort(pid)
    end

    assert Agent.get(unrelated, & &1) == :untouched
    Agent.stop(unrelated)
    refute_received {:"$gen_call", _, _}
  end

  test "WCO-C03 a suspended adapter's lifetime monitor never stops its consumer owner" do
    owner = spawn(fn -> receive do: (:done -> :ok) end)
    {:ok, handle} = UDP.open(config(), owner, 100)
    %{socket: socket, lifetime: lifetime} = :sys.get_state(handle.pid)
    monitor = Process.monitor(lifetime)
    true = :erlang.suspend_process(handle.pid)
    Process.exit(handle.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^lifetime, _}, 100
    assert :erlang.port_info(socket) == :undefined
    assert Process.alive?(owner)
    send(owner, :done)
  end

  test "WCO-C03 WCO-I05 owner death escalates even while both owned processes are suspended" do
    owner = spawn(fn -> receive do: (:done -> :ok) end)
    {:ok, connection} = Connection.start_link(host: "127.0.0.1", owner: owner)
    Process.unlink(connection)
    %{handle: %{pid: adapter}, lifetime: connection_lifetime} = :sys.get_state(connection)
    %{socket: socket, lifetime: adapter_lifetime} = :sys.get_state(adapter)

    references =
      for pid <- [connection, adapter, connection_lifetime, adapter_lifetime],
          do: Process.monitor(pid)

    true = :erlang.suspend_process(adapter)
    true = :erlang.suspend_process(connection)
    started = System.monotonic_time(:millisecond)
    send(owner, :done)
    for reference <- references, do: assert_receive({:DOWN, ^reference, :process, _, _}, 1000)
    assert System.monotonic_time(:millisecond) - started < 1000
    assert :erlang.port_info(socket) == :undefined
  end

  defp config, do: %{host: {127, 0, 0, 1}, port: 5683, generation: make_ref(), options: []}
end
