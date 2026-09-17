defmodule Wotex.CoAP.Test.OSCORERelay do
  @moduledoc false

  # A loopback UDP relay between the native helper and an independent peer. It
  # forwards every datagram unchanged in `:forward` mode and counts both
  # directions. `{:duplicate, index}` relays the indexed peer datagram twice and
  # `{:corrupt, index}` flips one ciphertext byte of it, so protected replay and
  # tampering reach the client exactly as the peer would have sent them.

  use GenServer
  import ExUnit.Assertions

  @type mode :: :forward | {:duplicate, pos_integer()} | {:corrupt, pos_integer()}

  @spec start_link({:inet.port_number(), mode()}) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @spec endpoint(pid()) :: :inet.port_number()
  def endpoint(pid), do: GenServer.call(pid, :endpoint, 3000)

  @doc "Returns the datagrams received from each side and those delivered to the client."
  @spec counts(pid()) :: %{
          to_client: non_neg_integer(),
          to_peer: non_neg_integer(),
          delivered: non_neg_integer()
        }
  def counts(pid), do: GenServer.call(pid, :counts, 3000)

  @spec close(pid()) :: %{
          to_client: non_neg_integer(),
          to_peer: non_neg_integer(),
          delivered: non_neg_integer()
        }
  def close(pid), do: GenServer.call(pid, :close, 3000)

  @impl GenServer
  def init({peer_port, mode}) do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: true, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)

    {:ok,
     %{
       socket: socket,
       port: port,
       peer_port: peer_port,
       mode: mode,
       client_port: nil,
       to_client: 0,
       to_peer: 0,
       delivered: 0
     }}
  end

  @impl GenServer
  def handle_call(:endpoint, _, state), do: {:reply, state.port, state}

  def handle_call(:counts, _, state), do: {:reply, snapshot(state), state}

  def handle_call(:close, _, state) do
    :gen_udp.close(state.socket)
    {:stop, :normal, snapshot(state), %{state | socket: nil}}
  end

  @impl GenServer
  def handle_info({:udp, socket, _, port, bytes}, %{socket: socket, peer_port: port} = state) do
    state = %{state | to_client: state.to_client + 1}
    datagrams = transform(state.mode, state.to_client, bytes)
    for datagram <- datagrams, do: deliver(state, datagram)
    {:noreply, %{state | delivered: state.delivered + length(datagrams)}}
  end

  def handle_info({:udp, socket, _, port, bytes}, %{socket: socket} = state) do
    assert state.to_peer < 10_000
    assert state.client_port in [nil, port]
    :ok = :gen_udp.send(socket, {127, 0, 0, 1}, state.peer_port, bytes)
    {:noreply, %{state | client_port: port, to_peer: state.to_peer + 1}}
  end

  @impl GenServer
  def terminate(_, %{socket: nil}), do: :ok
  def terminate(_, state), do: :gen_udp.close(state.socket)

  defp snapshot(state), do: Map.take(state, [:delivered, :to_client, :to_peer])

  defp deliver(state, bytes),
    do: :ok = :gen_udp.send(state.socket, {127, 0, 0, 1}, state.client_port, bytes)

  defp transform({:duplicate, index}, index, bytes), do: [bytes, bytes]

  defp transform({:corrupt, index}, index, bytes) do
    last = byte_size(bytes) - 1
    head = binary_part(bytes, 0, last)
    [<<head::binary, Bitwise.bxor(:binary.last(bytes), 1)>>]
  end

  defp transform(_, _, bytes), do: [bytes]
end
