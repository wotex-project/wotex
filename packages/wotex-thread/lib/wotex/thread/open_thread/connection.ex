defmodule Wotex.Thread.OpenThread.Connection do
  @moduledoc false

  use GenServer
  alias Wotex.Thread.{Error, Session}
  alias Wotex.Thread.OpenThread.{Config, Frame, Request}

  @owner_key {__MODULE__, :owner}

  @derive {Inspect, only: [:pid, :generation]}
  @enforce_keys [:pid, :reference, :generation]
  defstruct @enforce_keys
  @opaque t :: %__MODULE__{pid: pid(), reference: reference(), generation: 1}

  @doc false
  @spec start(term(), :link | :unlinked) :: {:ok, pid()} | {:error, Error.t()}
  def start(options, link) do
    entered = now()

    with {:ok, config} <- Config.new(options) do
      args = {config, entered + config.timeout, self()}

      result =
        case link do
          :link -> GenServer.start_link(__MODULE__, args)
          :unlinked -> GenServer.start(__MODULE__, args)
        end

      case result do
        {:ok, pid} -> {:ok, pid}
        {:error, %Error{}} = error -> error
        _ -> {:error, Error.new(:transport_unavailable)}
      end
    end
  end

  @doc false
  @spec session(term()) :: {:ok, Session.t()} | {:error, Error.t()}
  def session(pid) when is_pid(pid) and node(pid) == node(), do: call(pid, :session, 61_000)
  def session(_), do: {:error, Error.new(:invalid_handle)}

  @doc false
  @spec request(term(), term(), term()) :: {:ok, term()} | {:error, Error.t()}
  def request(handle, message, timeout) do
    entered = now()

    with :ok <- validate(handle),
         true <- is_integer(timeout) and timeout in 1..60_000,
         {:ok, _} <- Request.encode(message) do
      call(handle.pid, {handle.reference, :request, message, entered + timeout}, timeout + 1000)
    else
      false -> {:error, Error.new(:invalid_options)}
      {:error, _} = error -> error
    end
  end

  @doc false
  @spec disconnect(term()) :: :ok | {:error, Error.t()}
  def disconnect(handle) do
    with :ok <- validate(handle) do
      case call(handle.pid, {handle.reference, :close}, 1100) do
        {:error, %Error{code: :connection_closed}} -> :ok
        result -> result
      end
    end
  end

  @impl GenServer
  def init({config, deadline, starter}) do
    Process.flag(:trap_exit, true)

    cond do
      now() >= deadline ->
        {:stop, Error.new(:timeout)}

      not Process.alive?(config.owner) or not Process.alive?(starter) ->
        {:stop, Error.new(:owner_down)}

      true ->
        init_owner(config, deadline, starter)
    end
  end

  defp init_owner(config, deadline, starter) do
    reference = make_ref()
    Process.put(@owner_key, reference)

    state = %{
      config: config,
      deadline: deadline,
      owner_ref: Process.monitor(config.owner),
      starter_ref: Process.monitor(starter),
      handle: %__MODULE__{pid: self(), reference: reference, generation: 1},
      status: :starting,
      port: nil,
      buffer: <<>>,
      waiters: %{},
      pending: %{},
      queue: :queue.new(),
      active: nil,
      counter: 0,
      close_waiters: [],
      close_ack: false,
      failure: nil,
      start_timer: Process.send_after(self(), :startup_timeout, max(deadline - now(), 0))
    }

    case open_port(config.executable) do
      {:ok, port} -> {:ok, %{state | port: port}}
      :error -> {:stop, Error.new(:transport_unavailable)}
    end
  end

  @impl GenServer
  def handle_call(:session, _from, %{status: :ready} = state) do
    {:reply, {:ok, session_value(state)}, state}
  end

  def handle_call(:session, from, %{status: status} = state) when status in [:starting, :opening] do
    if map_size(state.waiters) < 64 do
      reference = Process.monitor(elem(from, 0))
      {:noreply, %{state | waiters: Map.put(state.waiters, reference, from)}}
    else
      {:reply, {:error, Error.new(:busy)}, state}
    end
  end

  def handle_call({reference, :close}, from, %{handle: %{reference: reference}} = state) do
    if length(state.close_waiters) < 64 do
      state = %{state | close_waiters: [from | state.close_waiters]}
      {:noreply, close(state, nil)}
    else
      {:reply, {:error, Error.new(:busy)}, state}
    end
  end

  def handle_call(
        {reference, :request, message, deadline},
        from,
        %{handle: %{reference: reference}, status: :ready} = state
      ) do
    case Request.encode(message) do
      {:ok, {operation, parameters}} ->
        cond do
          not is_integer(deadline) or deadline <= now() ->
            {:reply, {:error, Error.new(:timeout)}, state}

          map_size(state.pending) >= 64 ->
            {:reply, {:error, Error.new(:busy)}, state}

          true ->
            {:noreply, admit(state, from, operation, parameters, deadline)}
        end

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call(_, _from, %{status: :closing} = state),
    do: {:reply, {:error, Error.new(:connection_closed)}, state}

  def handle_call(_, _from, state), do: {:reply, {:error, Error.new(:invalid_handle)}, state}

  @impl GenServer
  def handle_info({port, {:data, {:eol, bytes}}}, %{port: port} = state) do
    if byte_size(state.buffer) + byte_size(bytes) < 131_072 do
      case Frame.decode(state.buffer <> bytes) do
        {:ok, frame} -> {:noreply, frame(frame, %{state | buffer: <<>>})}
        :error -> {:noreply, close(state, Error.new(:invalid_response))}
      end
    else
      {:noreply, close(state, Error.new(:response_limit))}
    end
  end

  def handle_info({port, {:data, {:noeol, bytes}}}, %{port: port} = state) do
    if byte_size(state.buffer) + byte_size(bytes) < 131_072,
      do: {:noreply, %{state | buffer: state.buffer <> bytes}},
      else: {:noreply, close(state, Error.new(:response_limit))}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    failure =
      cond do
        state.failure ->
          state.failure

        state.buffer != <<>> ->
          Error.new(:invalid_response)

        state.status != :closing or not state.close_ack or code != 0 ->
          Error.new(:connection_closed)

        true ->
          nil
      end

    {:stop, :normal, reply_all(%{state | failure: failure, port: nil})}
  end

  def handle_info(:startup_timeout, %{status: status} = state) when status in [:starting, :opening],
    do: {:noreply, close(state, Error.new(:timeout))}

  def handle_info({:deadline, id}, state) do
    cond do
      state.active == id ->
        {:noreply, close(state, Error.new(:timeout))}

      Map.has_key?(state.pending, id) ->
        {:noreply, complete(state, id, {:error, Error.new(:timeout)})}

      true ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, reference, :process, _, _}, state) do
    cond do
      reference in [state.owner_ref, state.starter_ref] ->
        {:noreply, close(state, Error.new(:owner_down))}

      Map.has_key?(state.waiters, reference) ->
        {:noreply, %{state | waiters: Map.delete(state.waiters, reference)}}

      true ->
        {:noreply, caller_down(state, reference)}
    end
  end

  def handle_info(:terminate_bridge, %{status: :closing} = state) do
    signal_port(state.port, "-TERM")
    {:noreply, state}
  end

  def handle_info(:kill_bridge, %{status: :closing} = state) do
    signal_port(state.port, "-KILL")
    Process.send_after(self(), :cleanup_deadline, 100)
    {:noreply, %{state | failure: Error.new(:cleanup_timeout)}}
  end

  def handle_info(:cleanup_deadline, %{status: :closing} = state),
    do: {:stop, :normal, reply_all(%{state | failure: Error.new(:cleanup_timeout)})}

  def handle_info({:EXIT, port, :normal}, %{port: port} = state), do: {:noreply, state}

  def handle_info({:EXIT, port, _}, %{port: port} = state),
    do: {:noreply, close(state, Error.new(:connection_closed))}

  def handle_info({:EXIT, pid, _}, state) when is_pid(pid),
    do: {:noreply, close(state, Error.new(:owner_down))}

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    if state.port && Port.info(state.port), do: Port.close(state.port)
    :ok
  end

  @impl GenServer
  def format_status(status) do
    Map.new(status, fn
      {:state, state} -> {:state, %{status: state.status, pending: map_size(state.pending)}}
      {:message, _} -> {:message, :redacted}
      {:reason, _} -> {:reason, :redacted}
      {:log, _} -> {:log, []}
      entry -> entry
    end)
  end

  defp validate(%__MODULE__{pid: pid, reference: reference, generation: 1} = handle)
       when map_size(handle) == 4 and is_pid(pid) and node(pid) == node() and
              is_reference(reference),
       do: :ok

  defp validate(_), do: {:error, Error.new(:invalid_handle)}

  defp frame(message, %{status: :starting} = state) do
    if Frame.ready?(message) and now() < state.deadline do
      parameters = %{
        radio_url: state.config.radio_url,
        interface: state.config.interface,
        storage_path: state.config.storage_path,
        storage_mode: Atom.to_string(state.config.storage_mode),
        allow_network_creation: state.config.allow_network_creation
      }

      if send_frame(state.port, "open", "open", parameters, state.deadline),
        do: %{state | status: :opening},
        else: close(state, Error.new(:connection_closed))
    else
      close(state, Error.new(:invalid_response))
    end
  end

  defp frame(message, %{status: :opening} = state) do
    case timed_response(message, "open", "open", state.deadline) do
      {:ok, _} ->
        Process.cancel_timer(state.start_timer)
        Process.demonitor(state.starter_ref, [:flush])

        Enum.each(state.waiters, fn {monitor, from} ->
          Process.demonitor(monitor, [:flush])
          GenServer.reply(from, {:ok, session_value(state)})
        end)

        %{state | status: :ready, waiters: %{}, starter_ref: nil}

      {:error, error} ->
        close(state, error)

      :invalid ->
        close(state, Error.new(:invalid_response))
    end
  end

  defp frame(message, %{status: :ready, active: id} = state) when is_binary(id) do
    pending = state.pending[id]

    case timed_response(message, id, pending.operation, pending.deadline) do
      :invalid ->
        close(state, Error.new(:invalid_response))

      {:error, %Error{code: code} = error}
      when code in [:timeout, :connection_closed, :invalid_response] ->
        close(state, error)

      result ->
        advance(complete(state, id, result))
    end
  end

  defp frame(message, %{status: :closing, close_ack: false} = state) do
    case Frame.response(message, "close", "close") do
      {:ok, nil} -> %{state | close_ack: true}
      _ -> %{state | failure: state.failure || Error.new(:invalid_response)}
    end
  end

  defp frame(_, state), do: close(state, Error.new(:invalid_response))

  defp timed_response(message, id, operation, deadline) do
    if now() < deadline,
      do: Frame.response(message, id, operation),
      else: {:error, Error.new(:timeout)}
  end

  defp admit(state, from, operation, parameters, deadline) do
    id = Integer.to_string(state.counter + 1)

    pending = %{
      from: from,
      operation: operation,
      parameters: parameters,
      deadline: deadline,
      monitor: Process.monitor(elem(from, 0)),
      timer: Process.send_after(self(), {:deadline, id}, max(deadline - now(), 0))
    }

    advance(%{
      state
      | counter: state.counter + 1,
        pending: Map.put(state.pending, id, pending),
        queue: :queue.in(id, state.queue)
    })
  end

  defp advance(%{active: nil, status: :ready} = state) do
    case :queue.out(state.queue) do
      {{:value, id}, queue} ->
        state = %{state | queue: queue}
        pending = state.pending[id]

        cond do
          pending == nil ->
            advance(state)

          not Process.alive?(elem(pending.from, 0)) ->
            advance(complete(state, id, {:error, Error.new(:owner_down)}))

          pending.deadline <= now() ->
            advance(complete(state, id, {:error, Error.new(:timeout)}))

          send_frame(state.port, id, pending.operation, pending.parameters, pending.deadline) ->
            %{state | active: id}

          true ->
            close(state, Error.new(:connection_closed))
        end

      {:empty, _} ->
        state
    end
  end

  defp advance(state), do: state

  defp complete(state, id, result) do
    {pending, rest} = Map.pop(state.pending, id)
    Process.cancel_timer(pending.timer)
    Process.demonitor(pending.monitor, [:flush])
    GenServer.reply(pending.from, result)

    %{
      state
      | pending: rest,
        queue: :queue.filter(&(&1 != id), state.queue),
        active: if(state.active == id, do: nil, else: state.active)
    }
  end

  defp caller_down(state, monitor) do
    case Enum.find(state.pending, fn {_, request} -> request.monitor == monitor end) do
      {id, _} when id == state.active -> close(state, Error.new(:owner_down))
      {id, _} -> complete(state, id, {:error, Error.new(:owner_down)})
      nil -> state
    end
  end

  defp close(%{status: :closing} = state, error), do: %{state | failure: state.failure || error}

  defp close(state, error) do
    Process.cancel_timer(state.start_timer)
    send_frame(state.port, "close", "close", %{}, now() + 900)
    Process.send_after(self(), :terminate_bridge, 40)
    Process.send_after(self(), :kill_bridge, 900)
    %{state | status: :closing, failure: error}
  end

  defp reply_all(state) do
    error = state.failure || Error.new(:connection_closed)

    Enum.each(state.waiters, fn {monitor, from} ->
      Process.demonitor(monitor, [:flush])
      GenServer.reply(from, {:error, error})
    end)

    Enum.each(
      state.close_waiters,
      &GenServer.reply(&1, if(state.failure, do: {:error, state.failure}, else: :ok))
    )

    Enum.reduce(
      Map.keys(state.pending),
      %{state | waiters: %{}, close_waiters: []},
      &complete(&2, &1, {:error, error})
    )
  end

  defp session_value(state),
    do: %Session{
      client: Wotex.Thread.OpenThread,
      handle: state.handle,
      timeout: state.config.timeout
    }

  defp open_port(executable) do
    {:ok,
     Port.open({:spawn_executable, executable}, [
       :binary,
       :exit_status,
       {:line, 131_071},
       args: [],
       env: Enum.map(System.get_env(), fn {key, _} -> {String.to_charlist(key), false} end)
     ])}
  rescue
    _ -> :error
  end

  defp send_frame(port, id, operation, parameters, deadline) do
    timeout = deadline - now()

    timeout > 0 and
      Port.command(
        port,
        Jason.encode!(%{
          version: 1,
          id: id,
          operation: operation,
          parameters: parameters,
          timeout_ms: min(timeout, 60_000)
        }) <> "\n",
        [:nosuspend]
      )
  rescue
    _ -> false
  end

  defp signal_port(port, signal) do
    case port && Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        System.cmd("/bin/kill", [signal, Integer.to_string(pid)],
          stderr_to_stdout: true,
          env: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
        )

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp call(pid, message, timeout) do
    case owner_status(pid, message) do
      :owned -> GenServer.call(pid, message, timeout)
      :closed -> {:error, Error.new(:connection_closed)}
      :invalid -> {:error, Error.new(:invalid_handle)}
    end
  catch
    :exit, {:timeout, _} -> {:error, Error.new(:cleanup_timeout)}
    :exit, _ -> {:error, Error.new(:connection_closed)}
  end

  defp owner_status(pid, message) when pid != self() do
    case :erlang.process_info(pid, {:dictionary, @owner_key}) do
      {{:dictionary, @owner_key}, reference} when is_reference(reference) ->
        if message == :session or elem(message, 0) == reference, do: :owned, else: :invalid

      :undefined ->
        :closed

      _ ->
        :invalid
    end
  end

  defp owner_status(_, _), do: :invalid

  defp now, do: System.monotonic_time(:millisecond)
end
