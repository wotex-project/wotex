defmodule Wotex.CoAP.Datagram.UDP do
  @moduledoc """
  Owns one explicit UDP socket and normalizes its messages for a CoAP owner.

  No socket opens on dependency load. The numeric destination and generation
  are fixed during startup; owner death closes the socket. The adapter does not
  interpret CoAP messages, allocate identities, retry or select another backend.
  """

  @behaviour Wotex.CoAP.Datagram
  use GenServer
  import Kernel, except: [send: 2]
  alias Wotex.CoAP.{Datagram, Error, Lifetime}

  @impl Datagram
  @spec open(Datagram.config(), pid(), pos_integer()) ::
          {:ok, Datagram.handle()} | {:error, Error.t()}
  def open(%{host: host, port: port, generation: generation, options: []} = config, owner, timeout)
      when map_size(config) == 4 and is_tuple(host) and is_integer(port) and port in 1..65_535 and
             is_reference(generation) and
             is_integer(timeout) and
             timeout in 1..60_000 do
    if valid_ip?(host) and valid_owner?(owner) do
      case GenServer.start(__MODULE__, {config, owner}, timeout: timeout) do
        {:ok, pid} -> {:ok, %{pid: pid, generation: generation}}
        {:error, %Error{}} = error -> error
        {:error, _} -> {:error, Error.new(:socket_failed)}
      end
    else
      {:error, Error.new(:invalid_datagram_config)}
    end
  end

  def open(_, _, _), do: {:error, Error.new(:invalid_datagram_config)}

  @impl Datagram
  @spec send(Datagram.handle(), binary()) :: :ok | {:error, Error.t()}
  def send(handle, bytes) when is_binary(bytes) and byte_size(bytes) <= 1152,
    do: call(handle, {:send, bytes})

  def send(_, _), do: {:error, Error.new(:invalid_datagram)}

  @impl Datagram
  @spec set_active_once(Datagram.handle()) :: :ok | {:error, Error.t()}
  def set_active_once(handle), do: call(handle, :arm)

  @impl Datagram
  @spec close(Datagram.handle()) :: :ok | {:error, Error.t()}
  def close(handle) do
    case identity(handle) do
      :closed -> :ok
      :owned -> stop(handle)
      :invalid -> {:error, Error.new(:invalid_datagram_handle)}
    end
  end

  defp stop(handle) do
    GenServer.stop(handle.pid, :normal, 100)
  catch
    :exit, {reason, _} when reason in [:noproc, :normal] ->
      :ok

    :exit, {{:normal, {:sys, :terminate, _}}, _} ->
      :ok

    :exit, _ ->
      if identity(handle) == :owned do
        monitor = Process.monitor(handle.pid)
        Process.exit(handle.pid, :kill)

        receive do
          {:DOWN, ^monitor, :process, _, _} -> :ok
        after
          100 -> Process.demonitor(monitor, [:flush])
        end
      end

      {:error, Error.new(:cleanup_timeout)}
  end

  @impl GenServer
  def init({config, owner}) do
    Process.put(:wotex_coap_datagram, {__MODULE__, config.generation})
    monitor = Process.monitor(owner)
    lifetime = Lifetime.start([owner], 0)
    family = if tuple_size(config.host) == 8, do: :inet6, else: :inet

    case :gen_udp.open(0, [family, :binary, active: false]) do
      {:ok, socket} ->
        {:ok, %{config: config, owner: owner, monitor: monitor, socket: socket, lifetime: lifetime}}

      {:error, reason} ->
        {:stop, Error.new(:socket_failed, nil, %{reason: reason})}
    end
  end

  @impl GenServer
  def handle_call({generation, operation}, _, %{config: %{generation: generation}} = state) do
    result =
      case operation do
        {:send, bytes} -> :gen_udp.send(state.socket, state.config.host, state.config.port, bytes)
        :arm -> :inet.setopts(state.socket, active: :once)
      end

    {:reply, normalize(result), state}
  end

  def handle_call(_, _, state), do: {:reply, {:error, Error.new(:invalid_datagram_handle)}, state}

  @impl GenServer
  def handle_info({:udp, socket, host, port, bytes}, %{socket: socket} = state) do
    deliver(state, {:data, host, port, bytes})
    {:noreply, state}
  end

  def handle_info({:udp_error, socket, _}, %{socket: socket} = state) do
    deliver(state, {:error, :transport_error})
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, monitor, :process, _, _}, %{monitor: monitor} = state),
    do: {:stop, :normal, state}

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def format_status(status) do
    Map.new(status, fn
      {:log, _} -> {:log, []}
      {key, _} -> {key, :redacted}
    end)
  end

  @impl GenServer
  def terminate(_, state) do
    :gen_udp.close(state.socket)
    deliver(state, :closed)
  end

  defp call(handle, operation) do
    case identity(handle) do
      :owned -> GenServer.call(handle.pid, {handle.generation, operation}, 1000)
      :closed -> {:error, Error.new(:connection_closed)}
      :invalid -> {:error, Error.new(:invalid_datagram_handle)}
    end
  catch
    :exit, _ -> {:error, Error.new(:connection_closed)}
  end

  defp identity(%{pid: pid, generation: generation} = handle)
       when map_size(handle) == 2 and is_pid(pid) and node(pid) == node() and pid != self() and
              is_reference(generation) do
    case :erlang.process_info(pid, {:dictionary, :wotex_coap_datagram}) do
      :undefined -> :closed
      {{:dictionary, :wotex_coap_datagram}, {__MODULE__, ^generation}} -> :owned
      _ -> :invalid
    end
  end

  defp identity(_), do: :invalid

  defp valid_owner?(owner), do: is_pid(owner) and node(owner) == node()

  defp valid_ip?(host) do
    maximum = if tuple_size(host) == 4, do: 255, else: 65_535

    tuple_size(host) in [4, 8] and
      Enum.all?(Tuple.to_list(host), &(is_integer(&1) and &1 in 0..maximum))
  end

  defp deliver(state, event),
    do: Kernel.send(state.owner, {:wotex_datagram, state.config.generation, event})

  defp normalize(:ok), do: :ok
  defp normalize({:error, _}), do: {:error, Error.new(:transport_error)}
end
