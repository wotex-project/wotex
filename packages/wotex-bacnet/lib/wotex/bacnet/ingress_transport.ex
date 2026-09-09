defmodule Wotex.BACnet.IngressTransport do
  @moduledoc """
  Owns BACnet/IP UDP sockets whose receive credits follow client consumption.

  The transport implements BACstack's public transport behaviour. It opens
  passive sockets only through `open/2`; the owning stack attaches its client
  before receive activity starts. Each active-once socket reserves capacity,
  and at most eight decoded datagrams can await consumption anywhere between
  this process, StackOwner and StackClient. No packet creates a worker process.

  A full window that remains unconsumed for 100 milliseconds closes this owned
  stack with `:slow_consumer`. Session watchers receive the terminal reason
  before shutdown, and system messages permit cleanup of a suspended stack
  owner. Borrowers can verify the attached live client but cannot attach a
  replacement or stop the owner's stack through this handshake.

  Counters describe local admissions and rejections, not guaranteed delivery.
  The requested OS receive buffer is 262144 bytes; `stats/1` reports each actual
  socket value. The selected inet API has no portable kernel-drop counter, so
  that measurement is explicitly `:unavailable`.
  """

  @behaviour BACnet.Stack.TransportBehaviour
  use GenServer
  alias BACnet.Stack.Transport.IPv4Transport
  alias Wotex.BACnet.{Error, IngressWindow, IPv4Interface, IPv4Packet, StackOwner}

  @type portal :: {port(), :inet.ip4_address()}

  @impl BACnet.Stack.TransportBehaviour
  def open(owner, opts) when is_pid(owner), do: GenServer.start_link(__MODULE__, {owner, opts})

  @impl BACnet.Stack.TransportBehaviour
  def close(pid), do: GenServer.stop(pid, :normal, 1000)

  @impl BACnet.Stack.TransportBehaviour
  def bacnet_protocol, do: :bacnet_ipv4

  @impl BACnet.Stack.TransportBehaviour
  def max_apdu_length, do: 1476

  @impl BACnet.Stack.TransportBehaviour
  def max_npdu_length, do: 1462

  @impl BACnet.Stack.TransportBehaviour
  def get_broadcast_address(pid), do: GenServer.call(pid, :broadcast)

  @impl BACnet.Stack.TransportBehaviour
  def get_local_address(pid), do: GenServer.call(pid, :local)

  @impl BACnet.Stack.TransportBehaviour
  def get_portal(pid), do: GenServer.call(pid, :portal)

  @impl BACnet.Stack.TransportBehaviour
  def is_destination_routed(pid, destination), do: GenServer.call(pid, {:routed, destination})

  @impl BACnet.Stack.TransportBehaviour
  def is_valid_destination(destination), do: IPv4Transport.is_valid_destination(destination)

  @impl BACnet.Stack.TransportBehaviour
  def send({socket, broadcast}, {ip, _} = destination, data, opts \\ []) do
    IPv4Transport.send(
      socket,
      destination,
      data,
      Keyword.put_new(opts, :is_broadcast, ip == broadcast)
    )
  end

  @doc false
  @spec attach(pid(), pid()) :: {:ok, reference()} | {:error, Error.t()}
  def attach(transport, client), do: GenServer.call(transport, {:attach, client}, 100)

  @doc false
  @spec generation(pid()) :: reference()
  def generation(transport), do: GenServer.call(transport, :generation, 100)

  @doc false
  @spec verify(pid(), pid(), reference(), pos_integer()) :: :ok | {:error, Error.t()}
  def verify(transport, client, generation, timeout) do
    if :proc_lib.translate_initial_call(transport) == {__MODULE__, :init, 1},
      do: GenServer.call(transport, {:verify, client, generation}, timeout),
      else: {:error, Error.new(:unbounded_receive_policy)}
  catch
    :exit, _ -> {:error, Error.new(:unbounded_receive_policy)}
  end

  @doc false
  @spec watch(pid(), pid(), reference()) :: :ok | {:error, Error.t()}
  def watch(transport, client, generation),
    do: GenServer.call(transport, {:watch, client, generation}, 100)

  @doc "Returns bounded local ingress counters and actual socket receive-buffer sizes."
  @spec stats(pid()) :: map()
  def stats(transport), do: GenServer.call(transport, :stats, 100)

  @impl GenServer
  def init({owner, opts}) do
    with {:ok, interface} <- IPv4Interface.resolve(Keyword.fetch!(opts, :local_ip)),
         {:ok, sockets} <- open_sockets(interface, Keyword.fetch!(opts, :bacnet_port)) do
      [socket | _] = sockets
      {:ok, {_, port}} = :inet.sockname(socket)

      {:ok,
       %{
         owner: owner,
         owner_monitor: Process.monitor(owner),
         client: nil,
         watchers: %{},
         sockets: sockets,
         socket_monitors: Map.new(sockets, &{&1, :erlang.monitor(:port, &1)}),
         port: port,
         interface: interface,
         portal: {socket, interface.broadcast},
         armed: MapSet.new(),
         window: IngressWindow.new(make_ref()),
         timer: nil,
         receive_buffers: Enum.map(sockets, &receive_buffer/1)
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call(:broadcast, _, state),
    do: {:reply, {state.interface.broadcast, state.port}, state}

  def handle_call(:local, _, state), do: {:reply, {state.interface.ip, state.port}, state}
  def handle_call(:portal, _, state), do: {:reply, state.portal, state}
  def handle_call(:stats, _, state), do: {:reply, snapshot(state), state}
  def handle_call(:generation, _, state), do: {:reply, state.window.generation, state}

  def handle_call({:routed, destination}, _, state),
    do: {:reply, IPv4Interface.routed?(state.interface, destination), state}

  def handle_call({:attach, client}, {owner, _}, %{owner: owner, client: nil} = state)
      when is_pid(client) do
    if Process.alive?(client) do
      next = arm(%{state | client: client})
      {:reply, {:ok, next.window.generation}, next}
    else
      {:reply, {:error, Error.new(:invalid_stack_client)}, state}
    end
  end

  def handle_call({:attach, _}, _, state),
    do: {:reply, {:error, Error.new(:invalid_stack_client)}, state}

  def handle_call({:verify, client, generation}, _, state),
    do: {:reply, proof(state, client, generation), state}

  def handle_call({:watch, client, generation}, {watcher, _}, state) do
    cond do
      proof(state, client, generation) != :ok ->
        {:reply, {:error, Error.new(:unbounded_receive_policy)}, state}

      Map.has_key?(state.watchers, watcher) ->
        {:reply, :ok, state}

      map_size(state.watchers) >= 64 ->
        {:reply, {:error, Error.new(:busy)}, state}

      true ->
        {:reply, :ok,
         %{state | watchers: Map.put(state.watchers, watcher, Process.monitor(watcher))}}
    end
  end

  @impl GenServer
  def handle_info({:udp, socket, address, port, data}, state) do
    if MapSet.member?(state.armed, socket) do
      state = %{state | armed: MapSet.delete(state.armed, socket)}
      receive_datagram(state, {address, port}, data)
    else
      {:noreply, state}
    end
  end

  def handle_info({:wotex_bacnet_consumed, generation, receipt}, state) do
    if IngressWindow.expired?(state.window, now()) do
      fail(state, :slow_consumer)
    else
      next = %{state | window: IngressWindow.consume(state.window, generation, receipt)}
      {:noreply, arm(timer(next))}
    end
  end

  def handle_info({:starved, generation, started}, %{window: window} = state)
      when window.generation == generation and window.starved_at == started do
    if IngressWindow.expired?(window, now()),
      do: fail(state, :slow_consumer),
      else: {:noreply, state}
  end

  def handle_info({:udp_error, socket, _}, state) do
    if socket in state.sockets,
      do:
        fail(%{state | window: IngressWindow.count(state.window, :socket_error)}, :transport_exit),
      else: {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{owner_monitor: ref} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, ref, :port, socket, _}, state) do
    if state.socket_monitors[socket] == ref,
      do:
        fail(%{state | window: IngressWindow.count(state.window, :socket_error)}, :transport_exit),
      else: {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _}, state) do
    if state.watchers[pid] == ref,
      do: {:noreply, %{state | watchers: Map.delete(state.watchers, pid)}},
      else: {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    Enum.each(state.sockets, &:gen_udp.close/1)
  end

  defp receive_datagram(state, {address, port}, _)
       when address == state.interface.ip and port == state.port,
       do: {:noreply, arm(%{state | window: IngressWindow.count(state.window, :self_packet)})}

  defp receive_datagram(state, source, bytes) do
    case IPv4Packet.decode(bytes) do
      {:ok, frame} ->
        receipt = make_ref()
        {:ok, window} = IngressWindow.admit(state.window, receipt, now())

        window =
          case frame do
            {:apdu, _, _, bytes} when byte_size(bytes) <= 1476 -> window
            _ -> IngressWindow.count(window, :rejected)
          end

        message = {:bacnet_transport, {:bacnet_ipv4, __MODULE__}, source, frame, state.portal}
        Kernel.send(state.owner, {:wotex_bacnet_datagram, window.generation, receipt, message})
        {:noreply, arm(timer(%{state | window: window}))}

      {:error, reason} ->
        {:noreply, arm(%{state | window: IngressWindow.count(state.window, reason)})}
    end
  end

  defp arm(state) do
    Enum.reduce(state.sockets, state, fn socket, acc ->
      if not MapSet.member?(acc.armed, socket) and
           MapSet.size(acc.armed) < IngressWindow.available(acc.window) do
        case :inet.setopts(socket, active: :once) do
          :ok ->
            %{acc | armed: MapSet.put(acc.armed, socket)}

          {:error, reason} ->
            Kernel.send(self(), {:udp_error, socket, reason})
            acc
        end
      else
        acc
      end
    end)
  end

  defp timer(%{window: %{starved_at: nil}, timer: ref} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %{state | timer: nil}
  end

  defp timer(%{window: %{starved_at: started}, timer: nil} = state) when is_integer(started),
    do: %{
      state
      | timer:
          Process.send_after(
            self(),
            {:starved, state.window.generation, started},
            max(started + 100 - now(), 0)
          )
    }

  defp timer(state), do: state

  defp proof(state, client, generation) do
    if state.client == client and state.window.generation == generation and Process.alive?(client),
      do: :ok,
      else: {:error, Error.new(:unbounded_receive_policy)}
  end

  defp fail(state, reason) do
    deadline = now() + 1000

    Enum.each(state.watchers, fn {pid, _} ->
      Kernel.send(
        pid,
        {:wotex_bacnet_transport_closed, self(), state.window.generation, reason, deadline}
      )
    end)

    # One terminal cleanup worker avoids a stop-call cycle if the owner is
    # already closing this transport. It never exists on the packet path.
    {:ok, cleanup_worker} = Task.start(fn -> StackOwner.shutdown_group(state.owner, deadline) end)

    :telemetry.execute([:wotex, :bacnet, :ingress, :stop], snapshot(state), %{
      reason: reason,
      cleanup_worker: cleanup_worker
    })

    {:stop, :normal, state}
  end

  defp snapshot(state),
    do: %{
      outstanding: MapSet.size(state.window.outstanding),
      peak: state.window.peak,
      armed: MapSet.size(state.armed),
      counters: state.window.counters,
      receive_buffers: state.receive_buffers,
      kernel_drops: :unavailable
    }

  defp open_sockets(interface, port) do
    addresses =
      if interface.mask && not match?({:win32, _}, :os.type()),
        do: [interface.ip, interface.broadcast],
        else: [interface.ip]

    result =
      Enum.reduce_while(addresses, {:ok, []}, fn address, {:ok, sockets} ->
        case :gen_udp.open(port, [
               :binary,
               :inet,
               active: false,
               ip: address,
               broadcast: true,
               recbuf: 262_144
             ]) do
          {:ok, socket} ->
            {:cont, {:ok, [socket | sockets]}}

          {:error, reason} ->
            Enum.each(sockets, &:gen_udp.close/1)
            {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, sockets} -> {:ok, Enum.reverse(sockets)}
      error -> error
    end
  end

  defp receive_buffer(socket) do
    {:ok, [recbuf: bytes]} = :inet.getopts(socket, [:recbuf])
    bytes
  end

  defp now, do: System.monotonic_time(:millisecond)
end
