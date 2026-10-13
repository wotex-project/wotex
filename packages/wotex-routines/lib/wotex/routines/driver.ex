defmodule Wotex.Routines.Driver do
  @moduledoc "Explicit consumer-supervised bounded wakeup driver. Scheduling timers supply no semantic clock or execution authority."

  use GenServer
  alias Wotex.Routines.{DriverHandle, Error}

  @fields [:id, :host, :context, :capacity, :poll_ms, :work_timeout_ms]
  @causes [:manual, :basis_changed, :poll]
  @maximum 9_223_372_036_854_775_807

  @doc "Validates explicit options and returns an OTP child map without starting anything."
  @spec specification(term()) :: {:ok, map()} | {:error, Error.t()}
  def specification(options) do
    with :ok <- options(options) do
      {:ok,
       %{
         id: options.id,
         start: {__MODULE__, :start_link, [options]},
         type: :worker,
         restart: :transient,
         shutdown: 5000
       }}
    end
  end

  @doc "Starts the configured driver only when explicitly invoked by its consumer."
  @spec start_link(term()) :: GenServer.on_start() | {:error, Error.t()}
  def start_link(options) do
    with :ok <- options(options), do: GenServer.start_link(__MODULE__, options)
  end

  @doc "Retrieves a local handle with an explicit bounded call timeout."
  @spec handle(term(), term()) :: {:ok, DriverHandle.t()} | {:error, Error.t()}
  def handle(pid, timeout) when is_pid(pid) and node(pid) == node(), do: call(pid, :handle, timeout)
  def handle(_, _), do: Error.refusal(:invalid_driver_handle)

  @doc "Atomically admits a bounded wakeup before sending; saturation never queues accepted work."
  @spec notify(term(), term()) :: :ok | {:error, Error.t()}
  def notify(handle, cause) do
    with :ok <- valid_handle(handle),
         true <- cause in @causes,
         :ok <- acquire(handle) do
      send(handle.pid, {handle.token, :notice, handle.counter, cause})
      :ok
    else
      false -> Error.refusal(:invalid_wakeup)
      error -> error
    end
  end

  @doc "Returns bounded operational counters, never private consumer context or semantic admission."
  @spec status(term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def status(handle, timeout) do
    with :ok <- valid_handle(handle), do: call(handle.pid, {handle.token, :status}, timeout)
  end

  @doc "Closes admission and waits for active worker retirement without compensation or replay."
  @spec retire(term(), term()) :: :ok | {:error, Error.t()}
  def retire(handle, timeout) do
    with :ok <- valid_handle(handle),
         :ok <- call_timeout(timeout) do
      :atomics.put(handle.counter, 2, 1)
      call(handle.pid, {handle.token, :retire}, timeout)
    end
  end

  defp options(options)
       when is_map(options) and not is_struct(options) and map_size(options) == 6 do
    valid =
      Enum.sort(Map.keys(options)) == Enum.sort(@fields) and
        identity_options?(options) and
        work_options?(options) and
        polling?(options[:poll_ms])

    if valid, do: :ok, else: Error.refusal(:invalid_driver_options)
  end

  defp options(_), do: Error.refusal(:invalid_driver_options)

  defp identity_options?(options) do
    is_binary(options[:id]) and byte_size(options[:id]) in 1..256 and String.valid?(options[:id]) and
      is_atom(options[:host]) and Code.ensure_loaded?(options[:host]) and
      function_exported?(options[:host], :wakeup, 3)
  end

  defp work_options?(options) do
    is_integer(options[:capacity]) and options[:capacity] in 1..64 and
      is_integer(options[:work_timeout_ms]) and options[:work_timeout_ms] in 1..60_000
  end

  defp polling?(nil), do: true
  defp polling?(value), do: is_integer(value) and value in 1..604_800_000

  defp valid_handle(%DriverHandle{} = handle) when map_size(handle) == 5 do
    valid =
      is_pid(handle.pid) and node(handle.pid) == node() and is_reference(handle.token) and
        is_reference(handle.counter) and
        is_integer(handle.capacity) and handle.capacity in 1..64 and
        :atomics.info(handle.counter).size == 2

    if valid, do: :ok, else: Error.refusal(:invalid_driver_handle)
  rescue
    _ -> Error.refusal(:invalid_driver_handle)
  end

  defp valid_handle(_), do: Error.refusal(:invalid_driver_handle)

  defp acquire(handle) do
    cond do
      not Process.alive?(handle.pid) or :atomics.get(handle.counter, 2) != 0 ->
        Error.refusal(:retired_driver)

      :atomics.add_get(handle.counter, 1, 1) <= handle.capacity ->
        :ok

      true ->
        :atomics.sub(handle.counter, 1, 1)
        Error.refusal(:wakeup_saturated)
    end
  end

  defp call(pid, request, timeout) when is_integer(timeout) and timeout in 1..60_000 do
    GenServer.call(pid, request, timeout)
  catch
    :exit, {:timeout, _} -> Error.refusal(:driver_call_timeout)
    :exit, _ -> Error.refusal(:retired_driver)
  end

  defp call(_, _, _), do: Error.refusal(:invalid_call_timeout)
  defp call_timeout(timeout) when is_integer(timeout) and timeout in 1..60_000, do: :ok
  defp call_timeout(_), do: Error.refusal(:invalid_call_timeout)

  @impl GenServer
  @doc false
  @spec init(map()) :: {:ok, map()}
  def init(options) do
    Process.flag(:trap_exit, true)
    counter = :atomics.new(2, signed: false)

    state = %{
      options: options,
      counter: counter,
      token: make_ref(),
      queue: :queue.new(),
      worker: nil,
      retiring: nil,
      poll: nil,
      stats: %{completed: 0, failed: 0, timed_out: 0, dropped: 0}
    }

    {:ok, poll(state)}
  end

  @impl GenServer
  @doc false
  @spec handle_call(term(), GenServer.from(), map()) :: tuple()
  def handle_call(:handle, _, state) do
    handle = %DriverHandle{
      pid: self(),
      token: state.token,
      counter: state.counter,
      capacity: state.options.capacity
    }

    {:reply, {:ok, handle}, state}
  end

  def handle_call({token, :status}, _, %{token: token} = state) do
    status =
      Map.merge(state.stats, %{
        active: state.worker != nil,
        pending: :queue.len(state.queue),
        closed: :atomics.get(state.counter, 2) != 0
      })

    {:reply, {:ok, status}, state}
  end

  def handle_call({token, :retire}, from, %{token: token, retiring: nil} = state) do
    :atomics.put(state.counter, 2, 1)
    cancel(state.poll)
    state = drop(%{state | retiring: from, poll: nil})

    case state.worker do
      nil ->
        {:stop, :normal, :ok, state}

      worker ->
        cancel(worker.timeout)
        Process.exit(worker.pid, :kill)
        {:noreply, %{state | worker: Map.put(worker, :phase, :retiring)}}
    end
  end

  def handle_call(_, _, state), do: {:reply, Error.refusal(:invalid_driver_request), state}

  @impl GenServer
  @doc false
  @spec handle_info(term(), map()) :: tuple()
  def handle_info({token, :notice, counter, cause}, %{token: token, counter: counter} = state)
      when cause in @causes do
    if :atomics.get(counter, 2) == 0 do
      state = %{state | queue: :queue.in(cause, state.queue)}
      {:noreply, next(state)}
    else
      :atomics.sub(counter, 1, 1)
      {:noreply, count(state, :dropped)}
    end
  end

  def handle_info({token, :poll}, %{token: token} = state) do
    state = %{state | poll: nil}

    idle =
      state.worker == nil and :queue.is_empty(state.queue) and :atomics.get(state.counter, 1) == 0

    handle = %{pid: self(), counter: state.counter, capacity: state.options.capacity}

    if idle and acquire(handle) == :ok do
      state = start(state, :poll)
      {:noreply, poll(state)}
    else
      {:noreply, poll(state)}
    end
  end

  def handle_info(
        {token, :result, work, result},
        %{token: token, worker: %{work: work, phase: :running} = worker} = state
      ) do
    cancel(worker.timeout)
    Process.demonitor(worker.monitor, [:flush])
    :atomics.sub(state.counter, 1, 1)
    state = %{state | worker: nil}
    state = if result == :ok, do: count(state, :completed), else: failed(state)
    {:noreply, next(state)}
  end

  def handle_info(
        {token, :timeout, work},
        %{token: token, worker: %{work: work, phase: :running} = worker} = state
      ) do
    :atomics.put(state.counter, 2, 1)
    Process.exit(worker.pid, :kill)
    state = %{state | worker: Map.put(worker, :phase, :timed_out)}
    state = count(state, :timed_out)
    {:noreply, drop(state)}
  end

  def handle_info(
        {:DOWN, monitor, :process, pid, _},
        %{worker: %{pid: pid, monitor: monitor}} = state
      ) do
    :atomics.sub(state.counter, 1, 1)
    state = %{state | worker: nil}

    if state.retiring != nil do
      GenServer.reply(state.retiring, :ok)
      {:stop, :normal, state}
    else
      :atomics.put(state.counter, 2, 0)
      state = failed(state)
      {:noreply, next(state)}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  @doc false
  @spec terminate(term(), map()) :: :ok
  def terminate(_, state) do
    :atomics.put(state.counter, 2, 1)
    cancel(state.poll)
    if state.worker != nil, do: Process.exit(state.worker.pid, :kill)
    :ok
  end

  @impl GenServer
  @doc false
  @spec format_status(map()) :: map()
  def format_status(status), do: Map.put(status, :state, :private_consumer_state)

  defp next(%{worker: nil, retiring: nil} = state) do
    if :atomics.get(state.counter, 2) == 0 do
      case :queue.out(state.queue) do
        {{:value, cause}, queue} -> start(%{state | queue: queue}, cause)
        {:empty, _} -> state
      end
    else
      state
    end
  end

  defp next(state), do: state

  defp failed(state) do
    state
    |> count(:failed)
    |> drop()
  end

  defp start(state, cause) do
    parent = self()
    token = state.token
    work = make_ref()
    options = state.options

    {pid, monitor} =
      :erlang.spawn_opt(
        fn ->
          result = invoke(options, cause)
          send(parent, {token, :result, work, result})
        end,
        [:link, :monitor]
      )

    timeout = Process.send_after(self(), {token, :timeout, work}, options.work_timeout_ms)
    %{state | worker: %{pid: pid, monitor: monitor, work: work, timeout: timeout, phase: :running}}
  end

  defp invoke(options, cause) do
    case options.host.wakeup(options.context, cause, %{work_timeout_ms: options.work_timeout_ms}) do
      :ok -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp poll(%{options: %{poll_ms: nil}} = state), do: state
  defp poll(%{retiring: from} = state) when from != nil, do: state

  defp poll(state),
    do: %{state | poll: Process.send_after(self(), {state.token, :poll}, state.options.poll_ms)}

  defp cancel(nil), do: :ok

  defp cancel(timer) do
    Process.cancel_timer(timer)
    :ok
  end

  defp drop(state) do
    size = :queue.len(state.queue)
    if size > 0, do: :atomics.sub(state.counter, 1, size)

    %{
      state
      | queue: :queue.new(),
        stats: Map.update!(state.stats, :dropped, &min(@maximum, &1 + size))
    }
  end

  defp count(state, key),
    do: %{state | stats: Map.update!(state.stats, key, &min(@maximum, &1 + 1))}
end
