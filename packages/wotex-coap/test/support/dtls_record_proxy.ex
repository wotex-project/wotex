defmodule Wotex.CoAP.Test.DTLSRecordProxy do
  @moduledoc false

  use GenServer
  import ExUnit.Assertions

  @spec start_link({:inet.port_number(), pid(), :hold | :hold_all | :trace | :forward}) ::
          GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @spec endpoint(pid()) :: :inet.port_number()
  def endpoint(pid), do: GenServer.call(pid, :endpoint)

  @spec deliver(pid(), binary()) :: :ok
  def deliver(pid, bytes), do: GenServer.call(pid, {:deliver, bytes})

  @spec close(pid()) :: map()
  def close(pid), do: GenServer.call(pid, :close)

  @impl GenServer
  def init({peer_port, receiver, mode}) do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: true, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)

    {:ok,
     %{
       socket: socket,
       port: port,
       peer_port: peer_port,
       receiver: receiver,
       mode: mode,
       client_port: nil,
       records: 0,
       plaintext: 0
     }}
  end

  @impl GenServer
  def handle_call(:endpoint, _, state), do: {:reply, state.port, state}

  def handle_call({:deliver, bytes}, _, state) do
    :ok = :gen_udp.send(state.socket, {127, 0, 0, 1}, state.client_port, bytes)
    {:reply, :ok, state}
  end

  def handle_call(:close, _, state) do
    :gen_udp.close(state.socket)
    {:stop, :normal, Map.take(state, [:port, :client_port, :records, :plaintext]), state}
  end

  @impl GenServer
  def handle_info({:udp, socket, _, port, bytes}, %{socket: socket, peer_port: port} = state) do
    case {state.mode, bytes} do
      {:hold, <<23, _::binary>>} ->
        send(state.receiver, {:dtls_record, self(), bytes})

      {:hold_all, _} ->
        send(state.receiver, {:held_datagram, self(), bytes})

      {mode, _} ->
        if mode == :trace, do: send(state.receiver, {:proxy_datagram, self(), :to_client, bytes})
        :ok = :gen_udp.send(socket, {127, 0, 0, 1}, state.client_port, bytes)
    end

    {:noreply, state}
  end

  def handle_info({:udp, socket, _, port, bytes}, %{socket: socket} = state) do
    assert state.records < 10_000
    assert state.client_port in [nil, port]
    if state.mode == :trace, do: send(state.receiver, {:proxy_datagram, self(), :to_server, bytes})
    :ok = :gen_udp.send(socket, {127, 0, 0, 1}, state.peer_port, bytes)
    plaintext = if dtls_record?(bytes), do: state.plaintext, else: state.plaintext + 1
    {:noreply, %{state | client_port: port, records: state.records + 1, plaintext: plaintext}}
  end

  @impl GenServer
  def terminate(_, state), do: :gen_udp.close(state.socket)

  defp dtls_record?(<<type, 254, _, _::binary>> = bytes),
    do: type in 20..23 and byte_size(bytes) >= 13

  defp dtls_record?(_), do: false
end
