defmodule Wotex.CoAP.RuntimeRelay do
  @moduledoc false

  use GenServer
  alias Wotex.CoAP.{Connection, Error, Lifetime, RuntimeFrame, RuntimeHandle, RuntimeNative}

  @doc false
  @spec open(map()) :: {:ok, RuntimeHandle.t()} | {:error, Error.t()}
  def open(options) do
    generation = make_ref()

    case GenServer.start(__MODULE__, Map.merge(options, %{generation: generation, caller: self()})) do
      {:ok, pid} -> GenServer.call(pid, {:open, generation}, remaining(options.deadline) + 1100)
      _ -> {:error, Error.new(:connection_closed)}
    end
  catch
    :exit, _ -> {:error, Error.new(:connection_closed)}
  end

  @doc false
  @spec close(term(), 0..1000) :: :ok | {:error, Error.t()}
  def close(handle, budget \\ 1000)

  def close(handle, budget) when is_integer(budget) and budget in 0..1000 do
    case RuntimeHandle.identity(handle) do
      :invalid -> {:error, Error.new(:invalid_subscription)}
      :closed -> :ok
      :owned -> close_live(handle, budget)
    end
  end

  def close(_, _), do: {:error, Error.new(:invalid_options)}

  defp close_live(handle, budget) do
    monitor = Process.monitor(handle.pid)
    deadline = now() + 1000

    try do
      result =
        GenServer.call(handle.pid, {:close, handle.generation, now() + budget, deadline}, 900)

      case result do
        {:error, %Error{code: code}} when code in [:invalid_subscription, :busy] -> result
        _ -> await_closed(monitor, result, deadline)
      end
    catch
      :exit, _ ->
        abort_handle(handle)
        {:error, Error.new(:cleanup_timeout)}
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  defp await_closed(monitor, result, deadline) do
    receive do
      {:DOWN, ^monitor, :process, _, _} -> result
    after
      remaining(deadline) -> {:error, Error.new(:deadline_exceeded)}
    end
  end

  defp abort_handle(handle) do
    if RuntimeHandle.identity(handle) == :owned do
      case :erlang.process_info(handle.pid, {:dictionary, :wotex_coap_runtime_native}) do
        {{:dictionary, :wotex_coap_runtime_native}, {generation, pid}}
        when generation == handle.generation ->
          Connection.abort(pid)

        _ ->
          :ok
      end

      if RuntimeHandle.identity(handle) == :owned, do: Process.exit(handle.pid, :kill)
    end
  end

  @impl GenServer
  def init(options) do
    Process.flag(:trap_exit, true)
    Process.put(:wotex_coap_runtime_relay, {__MODULE__, options.generation})

    {:ok,
     Map.merge(options, %{
       phase: :new,
       from: nil,
       caller_monitor: Process.monitor(options.caller),
       owner_monitor: Process.monitor(options.owner),
       lifetime: Lifetime.start([options.owner], 0),
       worker: nil,
       worker_monitor: nil,
       session: nil,
       subscription: nil,
       subscription_monitor: nil,
       buffered: [],
       opening_timer: nil,
       close_timer: nil,
       close_deadline: nil,
       close_from: nil,
       close_worker: nil,
       close_monitor: nil,
       outcome: :ok
     })}
  end

  @impl GenServer
  def handle_call({:open, generation}, from, %{generation: generation, phase: :new} = state) do
    next = %{state | from: from, phase: :opening}

    if Process.alive?(state.owner) and remaining(state.deadline) > 0 do
      {worker, monitor} = RuntimeNative.start(self(), generation, state)
      timer = Process.send_after(self(), {:opening_deadline, generation}, remaining(state.deadline))
      {:noreply, %{next | worker: worker, worker_monitor: monitor, opening_timer: timer}}
    else
      begin_close(next, {:error, Error.new(:deadline_exceeded)})
    end
  end

  def handle_call(
        {:close, generation, operation_deadline, deadline},
        from,
        %{generation: generation} = state
      ) do
    if state.close_from do
      {:reply, {:error, Error.new(:busy)}, state}
    else
      begin_close(%{state | close_from: from}, :ok, {operation_deadline, deadline})
    end
  end

  def handle_call(_, _, state), do: {:reply, {:error, Error.new(:invalid_subscription)}, state}

  @impl GenServer
  def handle_info(
        {:runtime_session, token, worker, session},
        %{generation: token, worker: worker, session: nil} = state
      ) do
    if RuntimeNative.valid_session?(session, worker, self(), state.connection_options) do
      Process.put(:wotex_coap_runtime_native, {token, session.pid})
      next = %{state | session: session}

      if state.phase == :opening do
        send(worker, {:subscribe, token})
        {:noreply, next}
      else
        start_close_worker(next)
      end
    else
      begin_close(state, {:error, Error.new(:invalid_session)})
    end
  end

  def handle_info(
        {:runtime_subscribed, token, worker, {:ok, subscription}},
        %{generation: token, worker: worker, phase: :opening} = state
      ) do
    if RuntimeNative.valid_subscription?(state.session, subscription) and
         remaining(state.deadline) > 0 do
      cancel_timer(state.opening_timer)
      Process.demonitor(state.caller_monitor, [:flush])
      handle = %RuntimeHandle{pid: self(), generation: token}
      GenServer.reply(state.from, {:ok, handle})

      next = %{
        state
        | phase: :bound,
          from: nil,
          caller_monitor: nil,
          opening_timer: nil,
          subscription: subscription,
          subscription_monitor: Process.monitor(subscription.pid),
          buffered: []
      }

      flush_buffer(next, Enum.reverse(state.buffered))
    else
      code = if remaining(state.deadline) == 0, do: :deadline_exceeded, else: :invalid_subscription
      begin_close(state, {:error, Error.new(code)})
    end
  end

  def handle_info(
        {:runtime_subscribed, token, worker, {:error, %Error{}} = error},
        %{generation: token, worker: worker, phase: :opening} = state
      ),
      do: begin_close(state, error)

  def handle_info(
        {:runtime_subscribed, token, worker, _},
        %{generation: token, worker: worker, phase: :opening} = state
      ),
      do: begin_close(state, {:error, Error.new(:invalid_transport_return)})

  def handle_info({:wotex_coap, reference, event}, %{phase: :opening} = state)
      when is_reference(reference) do
    if length(state.buffered) < 64,
      do: {:noreply, %{state | buffered: [{reference, event} | state.buffered]}},
      else: begin_close(state, {:error, Error.new(:receiver_overflow)})
  end

  def handle_info(
        {:wotex_coap, reference, event},
        %{phase: :bound, subscription: %{reference: reference}} = state
      ),
      do: forward(state, event)

  def handle_info(
        {:opening_deadline, generation},
        %{generation: generation, phase: :opening} = state
      ),
      do: begin_close(state, {:error, Error.new(:deadline_exceeded)})

  def handle_info(
        {:close_deadline, generation},
        %{generation: generation, phase: :closing} = state
      ),
      do: abort(state)

  def handle_info(
        {:runtime_closed, generation, worker, result},
        %{generation: generation, close_worker: worker, phase: :closing} = state
      ),
      do: finish(state, result)

  def handle_info({:DOWN, ref, :process, _, _}, %{owner_monitor: ref} = state),
    do: begin_close(state, {:error, Error.new(:connection_closed)})

  def handle_info({:DOWN, ref, :process, _, _}, %{caller_monitor: ref} = state),
    do: begin_close(state, {:error, Error.new(:connection_closed)})

  def handle_info(
        {:DOWN, ref, :process, _, _},
        %{subscription_monitor: ref, phase: :bound} = state
      ),
      do: forward(state, {:error, Error.new(:connection_closed)})

  def handle_info({:DOWN, ref, :process, _, _}, %{worker_monitor: ref, phase: :closing} = state) do
    if state.session, do: {:noreply, state}, else: finish(state, :ok)
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{worker_monitor: ref, phase: :bound} = state),
    do: forward(state, {:error, Error.new(:connection_closed)})

  def handle_info({:DOWN, ref, :process, _, _}, %{worker_monitor: ref} = state),
    do: begin_close(state, {:error, Error.new(:connection_closed)})

  def handle_info({:DOWN, ref, :process, _, _}, %{close_monitor: ref, phase: :closing} = state),
    do: finish(state, {:error, Error.new(:connection_closed)})

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
    cancel_timer(state.opening_timer)
    cancel_timer(state.close_timer)
    for pid <- [state.worker, state.close_worker], is_pid(pid), do: Process.exit(pid, :kill)
    :ok
  end

  defp forward(state, {:ok, value, metadata}) when is_map(metadata) do
    with :ok <-
           RuntimeFrame.validate(value, metadata),
         {:message_queue_len, length} when length < state.max_queue_length <-
           Process.info(state.owner, :message_queue_len) do
      send(state.owner, {:wotex_transport_frame, {:value, value, metadata}})
      {:noreply, state}
    else
      {:error, %Error{}} = error -> forward(state, error)
      _ -> forward(state, {:error, Error.new(:receiver_overflow)})
    end
  end

  defp forward(state, {:error, %Error{} = error}) do
    error = RuntimeFrame.error(error)
    send(state.owner, {:wotex_transport_frame, {:error, error}})
    send(state.owner, {:wotex_transport_status, :transport_down})
    begin_close(state, {:error, error})
  end

  defp forward(state, _), do: forward(state, {:error, Error.new(:invalid_transport_return)})

  defp flush_buffer(state, []), do: {:noreply, state}

  defp flush_buffer(state, [{reference, event} | rest]) do
    if reference == state.subscription.reference do
      case forward(state, event) do
        {:noreply, %{phase: :bound} = next} -> flush_buffer(next, rest)
        result -> result
      end
    else
      flush_buffer(state, rest)
    end
  end

  defp begin_close(state, outcome, deadline \\ nil)
  defp begin_close(%{phase: :closing} = state, _, _), do: {:noreply, state}

  defp begin_close(state, outcome, deadline) do
    cancel_timer(state.opening_timer)
    {operation_deadline, cleanup_deadline} = close_deadlines(deadline)

    next = %{
      state
      | phase: :closing,
        outcome: outcome,
        buffered: [],
        opening_timer: nil,
        close_deadline: operation_deadline,
        close_timer:
          Process.send_after(
            self(),
            {:close_deadline, state.generation},
            remaining(cleanup_deadline)
          )
    }

    cond do
      state.session ->
        start_close_worker(next)

      is_pid(state.worker) ->
        Process.exit(state.worker, :kill)
        {:noreply, next}

      true ->
        finish(next, :ok)
    end
  end

  defp close_deadlines(nil), do: {now() + 900, now() + 900}

  defp close_deadlines({operation, cleanup}) do
    cleanup = min(cleanup - 100, now() + 900)
    {min(operation, cleanup), cleanup}
  end

  defp start_close_worker(state) do
    parent = self()

    {worker, monitor} =
      :erlang.spawn_opt(
        fn ->
          result = RuntimeNative.close(state.session, state.subscription, state.close_deadline)
          send(parent, {:runtime_closed, state.generation, self(), result})
        end,
        [:link, :monitor]
      )

    {:noreply, %{state | close_worker: worker, close_monitor: monitor}}
  end

  defp abort(state) do
    RuntimeNative.abort(state.session)
    finish(state, {:error, Error.new(:deadline_exceeded)})
  end

  defp finish(state, close_result) do
    if state.from, do: GenServer.reply(state.from, state.outcome)
    if state.close_from, do: GenServer.reply(state.close_from, close_result)
    {:stop, :normal, state}
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)
  defp remaining(deadline), do: max(deadline - now(), 0)
  defp now, do: System.monotonic_time(:millisecond)
end
