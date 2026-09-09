defmodule Wotex.Modbus.Connection do
  @moduledoc """
  Owns one Modbus TCP socket and serializes deadline-bounded exchanges.

  `start_link/1` validates an explicit numeric IPv4 or IPv6 host, port, timeout,
  initial transaction identifier, Unit Identifier, owner, and security mode
  before opening the socket. `request/3` includes caller queue time in one
  finite deadline, sends a `Wotex.Modbus.Command`, reads one bounded response,
  and validates it with `Wotex.Modbus.Codec`.

  ## Lifecycle and effects

  The process monitors its explicit owner and closes the socket when that owner
  exits or `close/1` is called. It is not globally registered and never starts
  at dependency load. A failed read or unsent rejected request has no write
  effect. A transmitted write reports an unknown effect when its response does
  not establish the outcome; a correlated Modbus exception remains explicit.
  The connection never silently reconnects or retries a write.
  """

  use GenServer
  alias Wotex.Modbus.{Codec, Command, Error}

  @owner_key {__MODULE__, :owner}

  @doc "Starts a linked connection. The caller supplies host; no named process is registered."
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    with {:ok, config} <- config(opts) do
      config = Map.put(config, :creator, self())

      case GenServer.start(__MODULE__, config) do
        {:ok, pid} -> await_start(pid, config.timeout)
        {:error, _} = error -> error
      end
    end
  end

  @doc "Executes a validated command with a finite deadline including queue time."
  @spec request(pid(), Command.t(), pos_integer()) :: {:ok, term()} | {:error, Error.t()}
  def request(pid, %Command{} = command, timeout)
      when is_pid(pid) and is_integer(timeout) and timeout in 1..60_000 do
    deadline = System.monotonic_time(:millisecond) + timeout

    with :ok <- Command.validate(command) do
      case owner_status(pid) do
        :owned -> call(pid, command, deadline, timeout)
        :closed -> {:error, Error.new(:connection_closed)}
        :invalid -> {:error, Error.new(:invalid_session)}
      end
    end
  end

  def request(_, _, _), do: {:error, Error.new(:invalid_request)}

  @doc "Closes the connection idempotently."
  @spec close(pid()) :: :ok | {:error, Error.t()}
  def close(pid) do
    case owner_status(pid) do
      :owned -> stop_owned(pid)
      :closed -> :ok
      :invalid -> {:error, Error.new(:invalid_session)}
    end
  end

  defp owner_status(pid) when is_pid(pid) and node(pid) == node() and pid != self() do
    case :erlang.process_info(pid, {:dictionary, @owner_key}) do
      {{:dictionary, @owner_key}, reference} when is_reference(reference) -> :owned
      :undefined -> :closed
      _ -> :invalid
    end
  end

  defp owner_status(_), do: :invalid

  defp stop_owned(pid) do
    GenServer.stop(pid, :normal, 900)
  catch
    :exit, {:noproc, _} ->
      :ok

    :exit, {:normal, _} ->
      :ok

    :exit, {{:normal, {:sys, :terminate, _}}, {GenServer, :stop, _}} ->
      :ok

    :exit, _ ->
      force_close_owned(pid)
  end

  defp force_close_owned(pid) do
    case owner_status(pid) do
      :closed ->
        :ok

      :invalid ->
        {:error, Error.new(:invalid_session)}

      :owned ->
        Process.unlink(pid)
        monitor = Process.monitor(pid)
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor, :process, _, _} -> {:error, Error.new(:cleanup_timeout)}
        after
          100 ->
            Process.demonitor(monitor, [:flush])
            {:error, Error.new(:cleanup_timeout)}
        end
    end
  end

  @doc "Validates explicit connection options without opening a socket."
  @spec config(term()) :: {:ok, map()} | {:error, Error.t()}
  def config(opts) when is_list(opts) do
    if admitted_options?(opts),
      do: config_options(opts),
      else: {:error, Error.new(:invalid_options)}
  end

  def config(_), do: {:error, Error.new(:invalid_options)}

  @impl GenServer
  def init(config) do
    Process.put(@owner_key, make_ref())
    Process.flag(:trap_exit, true)
    server = self()
    token = make_ref()
    creator_monitor = Process.monitor(config.creator)
    owner_monitor = Process.monitor(config.owner)
    worker = spawn_link(fn -> send(server, {:connected, token, open_socket(config, server)}) end)
    timer = Process.send_after(self(), {:connect_timeout, token}, config.timeout)

    {:ok,
     %{
       phase: :connecting,
       socket: nil,
       transaction: config.transaction_id,
       owner_monitor: owner_monitor,
       creator_monitor: creator_monitor,
       creator: config.creator,
       worker: worker,
       connect_token: token,
       connect_timer: timer,
       ready_from: nil,
       active: nil,
       calls: %{},
       queue: :queue.new(),
       buffer: <<>>
     }}
  end

  @impl GenServer
  def handle_call(:ready, from, %{phase: :connecting} = state),
    do: {:noreply, %{state | ready_from: from}}

  def handle_call(:ready, _from, %{phase: :ready} = state) do
    Process.link(state.creator)
    {:reply, :ok, state}
  end

  def handle_call(:ready, _from, %{phase: {:failed, error}} = state),
    do: {:stop, :normal, {:error, error}, state}

  def handle_call({:request, command, deadline, admission}, from, %{phase: :ready} = state) do
    cond do
      remaining(deadline) == 0 -> {:reply, {:error, Error.new(:deadline_exceeded)}, state}
      map_size(state.calls) >= 64 -> {:reply, {:error, Error.new(:busy)}, state}
      true -> {:noreply, admit(state, command, deadline, from, admission)}
    end
  end

  def handle_call({:request, _, _, _}, _from, state),
    do: {:reply, {:error, Error.new(:connection_closed)}, state}

  @impl GenServer
  def handle_info({:connected, token, result}, %{connect_token: token, phase: :connecting} = state) do
    Process.cancel_timer(state.connect_timer)
    state = %{state | worker: nil}
    startup(result, state)
  end

  def handle_info({:connect_timeout, token}, %{connect_token: token, phase: :connecting} = state) do
    stop_worker(state.worker)
    startup({:error, :timeout}, %{state | worker: nil})
  end

  def handle_info({:sent, ref, result}, %{active: ref} = state) do
    state = %{state | worker: nil}

    case result do
      :ok -> {:noreply, state}
      {:error, reason} -> fail(state, Error.new(:transport_error, nil, %{reason: reason}))
    end
  end

  def handle_info({:tcp, socket, bytes}, %{socket: socket, active: ref} = state)
      when is_reference(ref) do
    receive_bytes(state, bytes)
  end

  def handle_info({:tcp, socket, _bytes}, %{socket: socket} = state),
    do: fail(state, Error.new(:response_mismatch))

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state),
    do: fail(state, Error.new(:transport_error, nil, %{reason: :closed}))

  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state),
    do: fail(state, Error.new(:transport_error, nil, %{reason: reason}))

  def handle_info({:deadline, ref}, %{active: ref} = state),
    do: fail(state, Error.new(:transport_error, nil, %{reason: :timeout}))

  def handle_info({:deadline, ref}, state) do
    {:noreply, finish(state, ref, {:error, Error.new(:deadline_exceeded)})}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    if monitor in [state.owner_monitor, state.creator_monitor],
      do: {:stop, :normal, state},
      else: caller_down(state, monitor)
  end

  def handle_info({:EXIT, creator, _reason}, %{creator: creator} = state),
    do: {:stop, :normal, state}

  def handle_info({:EXIT, worker, reason}, %{worker: worker} = state) when reason != :normal,
    do: worker_failed(state)

  def handle_info(_stale_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    stop_worker(state.worker)
    if state.socket, do: :gen_tcp.close(state.socket)
    Process.cancel_timer(state.connect_timer)

    Enum.each(state.calls, fn {ref, call} ->
      result =
        if ref == state.active,
          do: effect(Error.new(:connection_closed), call.command),
          else: {:error, Error.new(:connection_closed)}

      reply(call, result)
    end)
  end

  defp call(pid, command, deadline, timeout) do
    admission = make_ref()

    try do
      GenServer.call(pid, {:request, command, deadline, admission}, timeout + 1000)
    catch
      :exit, {:noproc, _call} ->
        {:error, Error.new(:connection_closed)}

      :exit, {:normal, _call} ->
        if admitted?(admission),
          do: effect(Error.new(:connection_closed), command),
          else: {:error, Error.new(:connection_closed)}

      :exit, _reason ->
        effect(Error.new(:connection_closed), command)
    after
      admitted?(admission)
    end
  end

  defp admitted?(admission) do
    receive do
      {:wotex_modbus_admitted, ^admission} -> true
    after
      0 -> false
    end
  end

  defp await_start(pid, timeout) do
    case GenServer.call(pid, :ready, timeout + 1000) do
      :ok -> {:ok, pid}
      {:error, _} = error -> error
    end
  catch
    :exit, _reason ->
      Process.unlink(pid)
      Process.exit(pid, :kill)
      {:error, Error.new(:connect_failed)}
  end

  defp open_socket(config, server) do
    options = [
      :binary,
      active: false,
      packet: :raw,
      nodelay: true,
      send_timeout: config.timeout,
      send_timeout_close: true
    ]

    options = if tuple_size(config.host) == 8, do: [:inet6 | options], else: options

    with {:ok, socket} <- :gen_tcp.connect(config.host, config.port, options, config.timeout) do
      case :gen_tcp.controlling_process(socket, server) do
        :ok ->
          {:ok, socket}

        {:error, reason} ->
          :gen_tcp.close(socket)
          {:error, reason}
      end
    end
  end

  defp startup({:ok, socket}, state) do
    case :inet.setopts(socket, active: :once) do
      :ok ->
        if state.ready_from do
          Process.link(state.creator)
          GenServer.reply(state.ready_from, :ok)
        end

        {:noreply, %{state | socket: socket, phase: :ready, ready_from: nil}}

      {:error, reason} ->
        :gen_tcp.close(socket)
        startup({:error, reason}, state)
    end
  end

  defp startup({:error, reason}, state) do
    error = Error.new(:connect_failed, nil, %{reason: reason})

    if state.ready_from do
      GenServer.reply(state.ready_from, {:error, error})
      {:stop, :normal, state}
    else
      {:noreply, %{state | phase: {:failed, error}}}
    end
  end

  defp worker_failed(%{phase: :connecting} = state),
    do: startup({:error, :worker_terminated}, %{state | worker: nil})

  defp worker_failed(state),
    do:
      fail(%{state | worker: nil}, Error.new(:transport_error, nil, %{reason: :worker_terminated}))

  defp admit(state, command, deadline, from, admission) do
    ref = make_ref()

    call = %{
      ref: ref,
      command: command,
      deadline: deadline,
      from: from,
      monitor: Process.monitor(elem(from, 0)),
      started: System.monotonic_time(),
      timer: Process.send_after(self(), {:deadline, ref}, remaining(deadline)),
      transaction: nil
    }

    send(elem(from, 0), {:wotex_modbus_admitted, admission})
    next(%{state | calls: Map.put(state.calls, ref, call), queue: :queue.in(ref, state.queue)})
  end

  defp next(%{active: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, ref}, rest} -> activate(%{state | queue: rest}, ref)
      {:empty, _} -> state
    end
  end

  defp next(state), do: state

  defp activate(state, ref) do
    call = Map.fetch!(state.calls, ref)

    if remaining(call.deadline) == 0 or not Process.alive?(elem(call.from, 0)) do
      state
      |> finish(ref, {:error, Error.new(:deadline_exceeded)})
      |> next()
    else
      {:ok, adu} = Codec.encode(call.command, state.transaction)
      call = %{call | transaction: state.transaction}
      server = self()
      worker = spawn_link(fn -> send(server, {:sent, ref, :gen_tcp.send(state.socket, adu)}) end)

      %{
        state
        | active: ref,
          transaction: rem(state.transaction + 1, 65_536),
          worker: worker,
          calls: Map.put(state.calls, ref, call)
      }
    end
  end

  defp receive_bytes(state, bytes) when byte_size(state.buffer) + byte_size(bytes) > 260,
    do: fail(state, Error.new(:invalid_mbap))

  defp receive_bytes(state, bytes) do
    data = state.buffer <> bytes

    case Codec.decode(data) do
      :more ->
        case :inet.setopts(state.socket, active: :once) do
          :ok -> {:noreply, %{state | buffer: data}}
          {:error, reason} -> fail(state, Error.new(:transport_error, nil, %{reason: reason}))
        end

      {:error, error} ->
        fail(state, error)

      {:ok, frame, tail} ->
        respond(state, frame, tail)
    end
  end

  defp respond(state, frame, tail) do
    call = Map.fetch!(state.calls, state.active)

    if remaining(call.deadline) == 0 do
      fail(state, Error.new(:transport_error, nil, %{reason: :timeout}))
    else
      case Codec.response(frame, call.command, call.transaction) do
        {:error, %Error{code: code} = error} when code != :remote_exception -> fail(state, error)
        result when tail == <<>> -> complete(state, result)
        _result -> fail(state, Error.new(:response_mismatch))
      end
    end
  end

  defp complete(state, result) do
    call = Map.fetch!(state.calls, state.active)

    result =
      case result do
        {:error, error} -> effect(error, call.command)
        success -> success
      end

    stop_worker(state.worker)
    state = finish(state, state.active, result)
    state = %{state | active: nil, worker: nil, buffer: <<>>}

    case :inet.setopts(state.socket, active: :once) do
      :ok -> {:noreply, next(state)}
      {:error, _reason} -> {:stop, :normal, state}
    end
  end

  defp fail(%{active: nil} = state, _error), do: {:stop, :normal, state}

  defp fail(state, error) do
    call = Map.fetch!(state.calls, state.active)
    {:stop, :normal, finish(state, state.active, effect(error, call.command))}
  end

  defp caller_down(state, monitor) do
    case Enum.find(state.calls, fn {_ref, call} -> call.monitor == monitor end) do
      {ref, _call} when ref == state.active -> {:stop, :normal, state}
      {ref, _call} -> {:noreply, finish(state, ref, {:error, Error.new(:connection_closed)})}
      nil -> {:noreply, state}
    end
  end

  defp finish(state, ref, result) do
    case Map.pop(state.calls, ref) do
      {nil, _} ->
        state

      {call, calls} ->
        reply(call, result)
        %{state | calls: calls, queue: :queue.filter(&(&1 != ref), state.queue)}
    end
  end

  defp reply(call, result) do
    Process.demonitor(call.monitor, [:flush])
    Process.cancel_timer(call.timer)

    :telemetry.execute(
      [:wotex, :modbus, :request, :stop],
      %{duration: System.monotonic_time() - call.started},
      %{
        function: call.command.function,
        result: if(match?({:ok, _}, result), do: :ok, else: :error)
      }
    )

    GenServer.reply(call.from, result)
  end

  defp stop_worker(nil), do: :ok
  defp stop_worker(pid), do: Process.exit(pid, :kill)

  defp effect(error, command),
    do: {:error, Error.with_effect(error, if(Command.write?(command), do: :unknown, else: :none))}

  defp remaining(deadline), do: max(0, deadline - System.monotonic_time(:millisecond))

  defp config_options(opts) do
    host = Keyword.get(opts, :host)
    port = Keyword.get(opts, :port, 502)
    timeout = Keyword.get(opts, :timeout, 5000)
    transaction = Keyword.get(opts, :transaction_id, 0)
    owner = Keyword.get(opts, :owner, self())
    unit = Keyword.get(opts, :unit_id, 1)

    with :ok <- security(Keyword.get(opts, :security, :none)),
         {:ok, host} <- address(host) do
      if is_integer(port) and port in 1..65_535 and is_integer(timeout) and timeout in 1..60_000 and
           is_integer(transaction) and transaction in 0..65_535 and is_pid(owner) and
           is_integer(unit) and (unit in 1..247 or unit == 255),
         do:
           {:ok,
            %{host: host, port: port, timeout: timeout, transaction_id: transaction, owner: owner}},
         else: {:error, Error.new(:invalid_options)}
    end
  end

  defp security(:none), do: :ok
  defp security(_), do: {:error, Error.new(:unsupported_security, :security)}

  defp address(host) when is_binary(host) and byte_size(host) <= 64 do
    with true <- String.valid?(host),
         {:ok, ip} <- :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip}
    else
      _ -> {:error, Error.new(:invalid_host, :host)}
    end
  end

  defp address(host) when is_tuple(host) do
    case :inet.ntoa(host) do
      {:error, _} -> {:error, Error.new(:invalid_host, :host)}
      _ -> {:ok, host}
    end
  rescue
    _ -> {:error, Error.new(:invalid_host, :host)}
  end

  defp address(_), do: {:error, Error.new(:invalid_host, :host)}

  defp admitted_options?(opts), do: admitted_options?(opts, %{})
  defp admitted_options?([], _), do: true

  defp admitted_options?([{key, _value} | rest], seen)
       when key in [:host, :port, :timeout, :transaction_id, :owner, :unit_id, :security] and
              not is_map_key(seen, key),
       do: admitted_options?(rest, Map.put(seen, key, true))

  defp admitted_options?(_, _), do: false
end
