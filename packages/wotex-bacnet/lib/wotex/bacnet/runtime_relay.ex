defmodule Wotex.BACnet.RuntimeRelay do
  @moduledoc false

  use GenServer
  alias Wotex.BACnet.{Error, RuntimeFrame, RuntimeHandle, RuntimeNative, Session}

  @doc false
  @spec open(map()) :: {:ok, RuntimeHandle.t()} | {:error, Error.t()}
  def open(options) do
    generation = make_ref()

    with {:ok, pid} <- GenServer.start(__MODULE__, Map.put(options, :generation, generation)) do
      Process.link(pid)
      GenServer.call(pid, {:open, generation}, remaining(options.deadline) + 1100)
    end
  catch
    :exit, _ -> {:error, Error.new(:connection_closed)}
  end

  @doc false
  @spec close(term()) :: :ok | {:error, Error.t()}
  def close(handle) do
    cond do
      not RuntimeHandle.valid?(handle) -> {:error, Error.new(:invalid_subscription)}
      not Process.alive?(handle.pid) -> :ok
      true -> close_live(handle)
    end
  end

  defp close_live(handle) do
    monitor = Process.monitor(handle.pid)
    deadline = now() + 1000

    try do
      result = GenServer.call(handle.pid, {:close, handle.generation, deadline}, 1100)

      case result do
        {:error, %Error{code: code}} when code in [:invalid_subscription, :busy] -> result
        _ -> await_closed(monitor, result, deadline)
      end
    catch
      :exit, _ -> {:error, Error.new(:connection_closed)}
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  defp await_closed(monitor, result, deadline) do
    receive do
      {:DOWN, ^monitor, :process, _, _} -> result
    after
      remaining(deadline) + 100 -> {:error, Error.new(:deadline_exceeded)}
    end
  end

  @impl GenServer
  def init(options) do
    Process.flag(:trap_exit, true)

    {:ok,
     Map.merge(options, %{
       phase: :new,
       from: nil,
       caller_monitor: nil,
       owner_monitor: Process.monitor(options.owner),
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
    next = %{state | from: from, caller_monitor: Process.monitor(elem(from, 0)), phase: :opening}

    if Process.alive?(state.owner) and remaining(state.deadline) > 0 do
      {worker, monitor} = RuntimeNative.start(self(), generation, state)
      timer = Process.send_after(self(), {:opening_deadline, generation}, remaining(state.deadline))
      {:noreply, %{next | worker: worker, worker_monitor: monitor, opening_timer: timer}}
    else
      begin_close(next, {:error, Error.new(:deadline_exceeded)})
    end
  end

  def handle_call({:close, generation, deadline}, from, %{generation: generation} = state) do
    if state.close_from do
      {:reply, {:error, Error.new(:busy)}, state}
    else
      begin_close(%{state | close_from: from}, :ok, deadline)
    end
  end

  def handle_call(_, _, state), do: {:reply, {:error, Error.new(:invalid_subscription)}, state}

  @impl GenServer
  def handle_info(
        {:runtime_session, token, worker, %Session{} = session},
        %{generation: token, worker: worker, session: nil} = state
      ) do
    next = %{state | session: session}

    if state.phase == :opening do
      send(worker, {:subscribe, token, self()})
      {:noreply, next}
    else
      start_close_worker(next)
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

  def handle_info({:wotex_bacnet, reference, event}, %{phase: :opening} = state)
      when is_reference(reference) do
    if length(state.buffered) < 64,
      do: {:noreply, %{state | buffered: [{reference, event} | state.buffered]}},
      else: begin_close(state, {:error, Error.new(:receiver_overflow)})
  end

  def handle_info(
        {:wotex_bacnet, reference, event},
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

  def handle_info({:EXIT, owner, _}, %{owner: owner} = state),
    do: begin_close(state, {:error, Error.new(:connection_closed)})

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    cancel_timer(state.opening_timer)
    cancel_timer(state.close_timer)
    for pid <- [state.worker, state.close_worker], is_pid(pid), do: Process.exit(pid, :kill)
    :ok
  end

  defp forward(state, {:ok, value, metadata}) when is_map(metadata) do
    with :ok <-
           RuntimeFrame.validate(
             value,
             metadata,
             state.request,
             Keyword.get(state.client_options, :destination)
           ),
         {:message_queue_len, length} when length < 1000 <-
           Process.info(state.owner, :message_queue_len) do
      send(state.owner, {:wotex_transport_frame, {:value, value, metadata}})
      {:noreply, state}
    else
      {:error, %Error{}} = error -> forward(state, error)
      _ -> forward(state, {:error, Error.new(:receiver_overflow)})
    end
  end

  defp forward(state, {:error, %Error{} = error}) do
    send(state.owner, {:wotex_transport_frame, {:error, error}})
    send(state.owner, {:wotex_transport_status, :session_lost})
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
    deadline = min(deadline || now() + 1000, now() + 1000)

    next = %{
      state
      | phase: :closing,
        outcome: outcome,
        buffered: [],
        opening_timer: nil,
        close_deadline: deadline,
        close_timer:
          Process.send_after(self(), {:close_deadline, state.generation}, remaining(deadline))
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

  defp start_close_worker(%{close_worker: worker} = state) when is_pid(worker),
    do: {:noreply, state}

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
    RuntimeNative.abort(state.session, state.subscription, state.close_deadline)
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
