defmodule Wotex.BACnet.OperationOwner do
  @moduledoc false

  use GenServer

  alias Wotex.BACnet.{BACstack, Batch, COVOwner, Error, StackOwner, Subscription}

  @doc false
  @spec start_link(map()) :: GenServer.on_start()
  def start_link(config) do
    case GenServer.start(__MODULE__, {config, self()}) do
      {:ok, pid} ->
        Process.link(pid)
        {:ok, pid}

      error ->
        error
    end
  end

  @doc false
  @spec request(pid(), reference(), map(), integer()) :: {:ok, term()} | {:error, Error.t()}
  def request(pid, generation, message, deadline) do
    GenServer.call(pid, {:request, generation, message, deadline}, remaining(deadline) + 1100)
  catch
    :exit, _ -> failure(:connection_closed, message)
  end

  @doc false
  @spec subscribe(pid(), reference(), term(), integer(), pos_integer()) :: term()
  def subscribe(pid, generation, request, deadline, timeout) do
    GenServer.call(
      pid,
      {:subscribe_cov, generation, request, deadline, timeout},
      remaining(deadline) + 1100
    )
  catch
    :exit, _ -> {:error, Error.new(:connection_closed)}
  end

  @doc false
  @spec unsubscribe(pid(), reference(), Subscription.t(), integer()) :: :ok | {:error, Error.t()}
  def unsubscribe(pid, generation, subscription, deadline) do
    cond do
      not Subscription.valid?(subscription) or subscription.session_generation != generation ->
        {:error, Error.new(:invalid_subscription)}

      not Process.alive?(subscription.pid) ->
        :ok

      true ->
        GenServer.call(
          pid,
          {:unsubscribe_cov, generation, subscription, deadline},
          remaining(deadline) + 1100
        )
    end
  catch
    :exit, _ -> {:error, Error.new(:connection_closed)}
  end

  @doc false
  @spec close(pid()) :: :ok
  def close(pid), do: close(pid, System.monotonic_time(:millisecond) + 1000)

  @doc false
  @spec close(pid(), integer()) :: :ok
  def close(pid, deadline) do
    monitor = Process.monitor(pid)

    try do
      GenServer.call(pid, {:close, deadline}, remaining(deadline) + 100)

      receive do
        {:DOWN, ^monitor, :process, ^pid, _} -> :ok
      after
        remaining(deadline + 100) -> force_close(pid)
      end
    catch
      :exit, _ -> force_close(pid)
    after
      Process.demonitor(monitor, [:flush])
    end

    :ok
  end

  @impl GenServer
  def init({config, owner}) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       config: config,
       owner: Process.monitor(owner),
       owner_pid: owner,
       client: Process.monitor(config.client),
       pending: %{},
       subscriptions: %{},
       controls: %{},
       cleanup_deadline: nil
     }}
  end

  @impl GenServer
  def handle_call({:close, deadline}, _, state),
    do: {:stop, :normal, :ok, %{state | cleanup_deadline: deadline}}

  def handle_call({:request, generation, message, deadline}, from, state) do
    remaining = deadline - System.monotonic_time(:millisecond)

    cond do
      generation != state.config.generation ->
        {:reply, admission_failure(:connection_closed, message), state}

      remaining <= 0 ->
        {:reply, admission_failure(:deadline_exceeded, message), state}

      pending_count(state) >= 64 ->
        {:reply, admission_failure(:busy, message), state}

      true ->
        {:noreply, admit(state, from, message, deadline, remaining)}
    end
  end

  def handle_call({:subscribe_cov, generation, request, deadline, timeout}, from, state) do
    cond do
      generation != state.config.generation ->
        {:reply, {:error, Error.new(:connection_closed)}, state}

      state.config.stack_client_kind != :wotex ->
        {:reply, {:error, Error.new(:not_supported)}, state}

      remaining(deadline) == 0 ->
        {:reply, {:error, Error.new(:deadline_exceeded)}, state}

      map_size(state.subscriptions) >= 64 or pending_count(state) >= 64 ->
        {:reply, {:error, Error.new(:busy)}, state}

      true ->
        start_subscription(state, from, request, deadline, timeout)
    end
  end

  def handle_call({:cov_lease, pid, generation}, {pid, _}, state) do
    cond do
      generation != state.config.generation or not Map.has_key?(state.subscriptions, pid) ->
        {:reply, {:error, Error.new(:connection_closed)}, state}

      Map.has_key?(state.controls, pid) or pending_count(state) >= 64 ->
        {:reply, {:error, Error.new(:busy)}, state}

      true ->
        token = make_ref()
        {:reply, {:ok, token}, %{state | controls: Map.put(state.controls, pid, token)}}
    end
  end

  def handle_call({:unsubscribe_cov, generation, handle, deadline}, from, state) do
    cond do
      generation != state.config.generation or handle.session_generation != generation ->
        {:reply, {:error, Error.new(:invalid_subscription)}, state}

      not Process.alive?(handle.pid) ->
        {:reply, :ok, state}

      not Map.has_key?(state.subscriptions, handle.pid) ->
        {:reply, {:error, Error.new(:invalid_subscription)}, state}

      state.subscriptions[handle.pid].handle != handle ->
        {:reply, {:error, Error.new(:invalid_subscription)}, state}

      state.subscriptions[handle.pid].cancel_from != nil ->
        {:reply, {:error, Error.new(:busy)}, state}

      true ->
        send(handle.pid, {:cancel_from, from, handle, deadline})
        subs = Map.update!(state.subscriptions, handle.pid, &%{&1 | cancel_from: from})
        {:noreply, %{state | subscriptions: subs}}
    end
  end

  @impl GenServer
  def handle_info({:result, reference, result}, state) do
    case Map.pop(state.pending, reference) do
      {nil, _} ->
        {:noreply, state}

      {operation, pending} ->
        operation_result(state, operation, reference, pending, result)
    end
  end

  def handle_info({:cov_cancelled, pid, result}, state) do
    case state.subscriptions[pid] do
      %{cancel_from: from} = subscription when is_tuple(from) ->
        next = %{subscription | cancel_result: result}
        {:noreply, %{state | subscriptions: Map.put(state.subscriptions, pid, next)}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:cov_control_release, pid, token}, state) do
    controls =
      if state.controls[pid] == token, do: Map.delete(state.controls, pid), else: state.controls

    {:noreply, %{state | controls: controls}}
  end

  def handle_info({:cov_established, pid, handle}, state) do
    case state.subscriptions[pid] do
      %{from: from} = subscription when is_tuple(from) ->
        result =
          if remaining(subscription.deadline) > 0,
            do: {:ok, handle},
            else: {:error, Error.new(:deadline_exceeded)}

        GenServer.reply(from, result)

        if match?({:error, _}, result),
          do: send(pid, {:session_closing, self(), System.monotonic_time(:millisecond) + 1000})

        next = %{subscription | from: nil, handle: handle}

        {:noreply,
         %{
           state
           | subscriptions: Map.put(state.subscriptions, pid, next),
             controls: Map.delete(state.controls, pid)
         }}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:timeout, reference}, state) do
    case Map.pop(state.pending, reference) do
      {nil, _} ->
        {:noreply, state}

      {operation, pending} ->
        stop_worker(operation)
        GenServer.reply(operation.from, operation_failure(:deadline_exceeded, operation))
        next = %{state | pending: pending}
        if state.config.owned_stack, do: {:stop, :normal, next}, else: {:noreply, next}
    end
  end

  def handle_info({:DOWN, reference, :process, _, _}, %{owner: reference} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, reference, :process, _, _}, %{client: reference} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, reference, :process, pid, reason} = message, state) do
    case state.subscriptions[pid] do
      %{monitor: ^reference} = subscription ->
        if reason != :normal and subscription.handle,
          do:
            send(subscription.receiver, {
              :wotex_bacnet,
              subscription.handle.reference,
              {:error, Error.new(:connection_closed)}
            })

        if subscription.from,
          do: GenServer.reply(subscription.from, {:error, Error.new(:connection_closed)})

        if subscription.cancel_from,
          do: GenServer.reply(subscription.cancel_from, subscription.cancel_result)

        {:noreply,
         %{
           state
           | subscriptions: Map.delete(state.subscriptions, pid),
             controls: Map.delete(state.controls, pid)
         }}

      _ ->
        worker_down(message, state)
    end
  end

  def handle_info({:EXIT, owner, _}, %{owner_pid: owner} = state), do: {:stop, :normal, state}
  def handle_info(_, state), do: {:noreply, state}

  defp worker_down({:DOWN, reference, :process, _, _}, state) do
    case Enum.find(state.pending, fn {_, op} -> reference in [op.caller, op.worker_monitor] end) do
      nil ->
        {:noreply, state}

      {key, operation} ->
        stop_worker(operation)

        if reference == operation.worker_monitor,
          do: GenServer.reply(operation.from, operation_failure(:connection_closed, operation))

        next = %{state | pending: Map.delete(state.pending, key)}
        if state.config.owned_stack, do: {:stop, :normal, next}, else: {:noreply, next}
    end
  end

  @impl GenServer
  def terminate(_, state) do
    Enum.each(state.pending, fn {_, operation} ->
      stop_worker(operation)
      GenServer.reply(operation.from, operation_failure(:connection_closed, operation))
    end)

    deadline =
      min(
        state.cleanup_deadline || System.monotonic_time(:millisecond) + 1000,
        System.monotonic_time(:millisecond) + 1000
      )

    close_subscriptions(state, deadline)
    if state.config.owned_stack, do: StackOwner.close(state.config.owned_stack, deadline)
    :ok
  end

  defp admit(state, from, message, deadline, remaining) do
    receiver = self()
    reference = make_ref()
    caller = Process.monitor(elem(from, 0))

    {message, batch} =
      case message do
        %{type: :read_properties, requests: [first | _] = requests} ->
          {first, Batch.start(requests, deadline)}

        _ ->
          {message, nil}
      end

    {worker, monitor} = start_worker(receiver, reference, state.config, message, deadline)

    operation = %{
      from: from,
      caller: caller,
      worker: worker,
      worker_monitor: monitor,
      message: message,
      batch: batch,
      deadline: deadline,
      timer: Process.send_after(self(), {:timeout, reference}, remaining)
    }

    %{state | pending: Map.put(state.pending, reference, operation)}
  end

  defp start_worker(receiver, reference, config, message, deadline) do
    :erlang.spawn_opt(
      fn ->
        result = BACstack.exchange(config, message, deadline)
        send(receiver, {:result, reference, result})
      end,
      [:link, :monitor]
    )
  end

  defp operation_result(state, %{batch: nil} = operation, _, pending, result),
    do: finish_operation(state, operation, pending, result)

  defp operation_result(state, operation, reference, pending, result) do
    case Batch.accept(operation.batch, result, System.monotonic_time(:millisecond)) do
      {:continue, batch} ->
        Process.exit(operation.worker, :kill)
        Process.demonitor(operation.worker_monitor, [:flush])
        [message | _] = batch.remaining

        {worker, monitor} =
          start_worker(self(), reference, state.config, message, operation.deadline)

        next = %{
          operation
          | batch: batch,
            message: message,
            worker: worker,
            worker_monitor: monitor
        }

        {:noreply, %{state | pending: Map.put(pending, reference, next)}}

      {:done, values} ->
        finish_operation(state, operation, pending, {:ok, values})

      {:error, _} = error ->
        finish_operation(state, operation, pending, error)
    end
  end

  defp finish_operation(state, operation, pending, result) do
    release(operation)
    expired = System.monotonic_time(:millisecond) >= operation.deadline
    reply = if expired, do: operation_failure(:deadline_exceeded, operation), else: result
    GenServer.reply(operation.from, reply)
    next = %{state | pending: pending}
    if expired and state.config.owned_stack, do: {:stop, :normal, next}, else: {:noreply, next}
  end

  defp operation_failure(code, %{batch: %{index: index}, message: %{property: property}}),
    do: {:error, Batch.failure(Error.new(code), index, property)}

  defp operation_failure(code, operation), do: failure(code, operation.message)

  defp start_subscription(state, from, request, deadline, timeout) do
    lease = make_ref()

    case COVOwner.start_link(%{
           config: state.config,
           session: self(),
           request: request,
           from: from,
           deadline: deadline,
           timeout: timeout,
           lease: lease
         }) do
      {:ok, pid} ->
        subscription = %{
          monitor: Process.monitor(pid),
          from: from,
          handle: nil,
          receiver: request.receiver,
          deadline: deadline,
          cancel_from: nil,
          cancel_result: {:error, Error.new(:connection_closed)}
        }

        {:noreply,
         %{
           state
           | subscriptions: Map.put(state.subscriptions, pid, subscription),
             controls: Map.put(state.controls, pid, lease)
         }}

      _ ->
        {:reply, {:error, Error.new(:startup_failed)}, state}
    end
  end

  defp close_subscriptions(state, deadline) do
    Enum.each(state.subscriptions, fn {pid, _} ->
      send(pid, {:session_closing, self(), deadline})
    end)

    Enum.each(state.subscriptions, fn {pid, subscription} ->
      receive do
        {:DOWN, ref, :process, ^pid, _} when ref == subscription.monitor -> :ok
      after
        remaining(deadline + 100) -> force_close(pid)
      end

      if subscription.from,
        do: GenServer.reply(subscription.from, {:error, Error.new(:connection_closed)})

      if subscription.cancel_from,
        do: GenServer.reply(subscription.cancel_from, subscription.cancel_result)
    end)
  end

  defp force_close(pid) do
    Process.unlink(pid)
    Process.exit(pid, :kill)
  end

  defp pending_count(state), do: map_size(state.pending) + map_size(state.controls)
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp admission_failure(code, %{type: :read_properties} = message), do: failure(code, message)
  defp admission_failure(code, _), do: {:error, Error.new(code)}

  defp failure(code, %{type: :read_properties, requests: [%{property: property} | _]}),
    do: {:error, Batch.failure(Error.new(code), 0, property)}

  defp failure(code, %{type: :write_property}),
    do: {:error, %{Error.new(code) | effect: :unknown}}

  defp failure(code, _), do: {:error, Error.new(code)}

  defp stop_worker(operation) do
    Process.exit(operation.worker, :kill)
    release(operation)
  end

  defp release(operation) do
    Process.cancel_timer(operation.timer)
    Process.demonitor(operation.caller, [:flush])
    Process.demonitor(operation.worker_monitor, [:flush])
  end
end
