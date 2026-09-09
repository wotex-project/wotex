defmodule Wotex.BLE.RuntimeRelay do
  @moduledoc """
  Owns a persistent BLE session for one Wotex Runtime subscription.

  This implementation process monitors the public Runtime owner and the
  establishing caller while a worker opens the first-party BlueZ session.
  It returns an opaque handle only after native subscription establishment,
  bounds early frames to 64, and validates each frame against the original
  mapping before forwarding it to Runtime. Equal values remain distinct
  updates; metadata changes cannot silently retarget the stream.

  Owner loss, establishment expiry, native failure or bounded receiver-queue
  overflow closes the original session. Cancellation has a one-second local
  cleanup grace and at most 64 concurrent waiters. The relay owns no reconnect
  policy, credentials or final observation timestamp. Runtime owns public
  stream identity and result projection; the relay uses only its transport
  callback and owner-message contracts.
  """

  use GenServer
  alias Wotex.BLE
  alias Wotex.BLE.BlueZ.{Connection, Stream}
  alias Wotex.BLE.{Error, RuntimeFrame, Session, Subscription}

  @derive {Inspect, only: []}
  @enforce_keys [:pid, :reference, :generation]
  defstruct @enforce_keys
  @type t :: %__MODULE__{pid: pid(), reference: reference(), generation: 1}

  @doc false
  @spec open(map(), pid(), pos_integer()) :: {:ok, t()} | {:error, Error.t()}
  def open(prepared, owner, limit) do
    token = make_ref()

    case GenServer.start(__MODULE__, {prepared, owner, limit, {self(), token}}) do
      {:ok, pid} -> await(pid, token, prepared.deadline)
      _ -> {:error, Error.new(:transport_error)}
    end
  end

  @doc false
  @spec close(term()) :: :ok | {:error, Error.t()}
  def close(handle) do
    if handle?(handle) do
      if Process.alive?(handle.pid), do: cancel(handle), else: :ok
    else
      {:error, Error.new(:invalid_subscription)}
    end
  end

  @impl GenServer
  def init({prepared, owner, limit, waiter}) do
    parent = self()
    token = make_ref()
    worker = spawn_monitor(fn -> establish(parent, token, prepared, limit) end)

    {:ok,
     %{
       status: :opening,
       owner: owner,
       owner_monitor: Process.monitor(owner),
       caller_monitor: Process.monitor(elem(waiter, 0)),
       waiter: waiter,
       handle: %__MODULE__{pid: self(), reference: make_ref(), generation: 1},
       mapping: prepared.mapping,
       deadline: prepared.deadline,
       limit: limit,
       worker: worker,
       worker_token: token,
       cleanup: nil,
       cleanup_token: nil,
       session: nil,
       connection_monitor: nil,
       subscription: nil,
       subscription_monitor: nil,
       buffer: :queue.new(),
       buffered: 0,
       metadata: nil,
       cancelers: [],
       timer: Process.send_after(self(), {:open_deadline, token}, max(prepared.deadline - now(), 0))
     }}
  end

  @impl GenServer
  def handle_call({:close, handle}, from, %{handle: handle} = state) do
    if length(state.cancelers) < 64 do
      {:noreply, begin_close(%{state | cancelers: [from | state.cancelers]}, nil)}
    else
      {:reply, {:error, Error.new(:busy)}, state}
    end
  end

  def handle_call(_, _, state), do: {:reply, {:error, Error.new(:invalid_subscription)}, state}

  @impl GenServer
  def handle_info(
        {:relay_session, token, session},
        %{worker_token: token, status: :opening} = state
      ) do
    {:noreply, %{state | session: session, connection_monitor: Process.monitor(session.handle.pid)}}
  end

  def handle_info(
        {:relay_established, token, result},
        %{worker_token: token, status: :opening} = state
      ) do
    state = stop_worker(state)

    case result do
      {:ok, %Subscription{} = subscription} -> bind(state, subscription)
      {:error, %Error{} = error} -> {:noreply, begin_close(state, error)}
      _ -> {:noreply, begin_close(state, Error.new(:invalid_response))}
    end
  end

  def handle_info({:wotex_ble, reference, event}, %{status: :opening} = state)
      when is_reference(reference) do
    if state.buffered < 64 do
      {:noreply,
       %{state | buffer: :queue.in({reference, event}, state.buffer), buffered: state.buffered + 1}}
    else
      {:noreply, begin_close(state, Error.new(:receiver_overflow))}
    end
  end

  def handle_info(
        {:wotex_ble, reference, event},
        %{status: :bound, subscription: %{reference: reference}} = state
      ),
      do: {:noreply, deliver(state, event)}

  def handle_info({:open_deadline, token}, %{worker_token: token, status: :opening} = state),
    do: {:noreply, begin_close(state, Error.new(:deadline_exceeded))}

  def handle_info({:cancel_open, token}, %{waiter: {_, token}} = state),
    do: {:noreply, begin_close(state, Error.new(:deadline_exceeded))}

  def handle_info(
        {:relay_cleanup, token, result},
        %{cleanup_token: token, status: :closing} = state
      ),
      do: finish(state, result)

  def handle_info({:close_deadline, token}, %{cleanup_token: token, status: :closing} = state),
    do: finish(state, {:error, Error.new(:cleanup_timeout)})

  def handle_info({:DOWN, ref, :process, _, _}, state) do
    cond do
      ref in [state.owner_monitor, state.caller_monitor] ->
        {:noreply, begin_close(state, Error.new(:disconnected))}

      state.status == :closing ->
        {:noreply, state}

      ref == state.connection_monitor ->
        {:noreply, begin_close(state, Error.new(:disconnected))}

      ref == state.subscription_monitor ->
        {:noreply, begin_close(state, Error.new(:subscription_lost))}

      state.worker != nil and elem(state.worker, 1) == ref ->
        {:noreply, begin_close(%{state | worker: nil}, Error.new(:transport_error))}

      true ->
        {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def format_status(status) do
    Map.new(status, fn
      {:state, state} -> {:state, %{status: state.status, buffered: state.buffered}}
      {:message, _} -> {:message, :redacted}
      {:reason, _} -> {:reason, :redacted}
      {:log, _} -> {:log, []}
      entry -> entry
    end)
  end

  defp bind(state, subscription) do
    valid =
      Stream.handle?(subscription) and match?(%Session{handle: %Connection{}}, state.session) and
        subscription.session_reference == state.session.handle.reference and
        Process.alive?(subscription.pid)

    if valid and now() < state.deadline do
      Process.cancel_timer(state.timer)
      Process.demonitor(state.caller_monitor, [:flush])
      GenServer.reply(state.waiter, {:ok, state.handle})
      buffer = :queue.to_list(state.buffer)

      state = %{
        state
        | status: :bound,
          subscription: subscription,
          subscription_monitor: Process.monitor(subscription.pid),
          waiter: nil,
          caller_monitor: nil,
          timer: nil,
          buffer: :queue.new(),
          buffered: 0
      }

      {:noreply,
       Enum.reduce(buffer, state, fn
         {reference, event}, %{status: :bound} = acc when reference == subscription.reference ->
           deliver(acc, event)

         _, acc ->
           acc
       end)}
    else
      code = if now() >= state.deadline, do: :deadline_exceeded, else: :invalid_subscription
      {:noreply, begin_close(state, Error.new(code))}
    end
  end

  defp deliver(state, {:ok, bytes, metadata}) do
    case RuntimeFrame.validate(bytes, metadata, state.mapping) do
      {:ok, bytes, metadata} ->
        if state.metadata == nil or state.metadata == metadata do
          forward(%{state | metadata: metadata}, {:value, bytes, metadata})
        else
          state
        end

      {:error, error} ->
        begin_close(state, error)

      :ignore ->
        state
    end
  end

  defp deliver(state, {:error, %Error{} = error}), do: begin_close(state, error)
  defp deliver(state, _), do: begin_close(state, Error.new(:invalid_response))

  defp forward(state, frame) do
    case Process.info(state.owner, :message_queue_len) do
      {:message_queue_len, length} when length < state.limit ->
        send(state.owner, {:wotex_transport_frame, frame})
        state

      nil ->
        begin_close(state, Error.new(:disconnected))

      _ ->
        begin_close(state, Error.new(:receiver_overflow))
    end
  end

  defp begin_close(%{status: :closing} = state, _), do: state

  defp begin_close(state, error) do
    if state.timer, do: Process.cancel_timer(state.timer)
    state = stop_worker(state)

    if state.waiter do
      GenServer.reply(state.waiter, {:error, error || Error.new(:disconnected)})
    else
      if error do
        send(state.owner, {:wotex_transport_frame, {:error, error}})
        send(state.owner, {:wotex_transport_status, :session_lost})
      end
    end

    parent = self()
    token = make_ref()
    session = state.session

    worker =
      spawn_monitor(fn ->
        result = if session, do: BLE.disconnect(session), else: :ok
        send(parent, {:relay_cleanup, token, result})
      end)

    %{
      state
      | status: :closing,
        waiter: nil,
        buffer: :queue.new(),
        buffered: 0,
        cleanup: worker,
        cleanup_token: token,
        timer: Process.send_after(self(), {:close_deadline, token}, 1000)
    }
  end

  defp finish(state, result) do
    Process.cancel_timer(state.timer)

    if state.cleanup do
      {pid, monitor} = state.cleanup
      Process.demonitor(monitor, [:flush])
      Process.exit(pid, :kill)
    end

    Enum.each(state.cancelers, &GenServer.reply(&1, result))
    {:stop, :normal, %{state | status: :closed}}
  end

  defp stop_worker(%{worker: nil} = state), do: state

  defp stop_worker(state) do
    {pid, monitor} = state.worker
    Process.demonitor(monitor, [:flush])
    Process.exit(pid, :kill)
    %{state | worker: nil}
  end

  defp establish(parent, token, prepared, limit) do
    result =
      with {:ok, remaining} <- remaining(prepared.deadline),
           options = Keyword.merge(prepared.options, owner: parent, timeout: remaining),
           {:ok, session} <- BLE.connect(options) do
        send(parent, {:relay_session, token, session})

        with {:ok, remaining} <- remaining(prepared.deadline) do
          BLE.subscribe(session, %{
            address: prepared.mapping.address,
            receiver: parent,
            mode: prepared.mapping.mode,
            max_queue_length: limit,
            value_type: :bytes,
            timeout: remaining
          })
        end
      end

    send(parent, {:relay_established, token, result})
  end

  defp remaining(deadline) do
    left = deadline - now()
    if left > 0, do: {:ok, left}, else: {:error, Error.new(:deadline_exceeded)}
  end

  defp await(pid, token, deadline) do
    monitor = Process.monitor(pid)

    receive do
      {^token, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^pid, _} ->
        {:error, Error.new(:disconnected)}
    after
      max(deadline - now(), 0) + 1100 ->
        Process.demonitor(monitor, [:flush])
        send(pid, {:cancel_open, token})
        {:error, Error.new(:deadline_exceeded)}
    end
  end

  defp handle?(%__MODULE__{pid: pid, reference: reference, generation: 1} = handle),
    do: map_size(handle) == 4 and is_pid(pid) and is_reference(reference)

  defp handle?(_), do: false

  defp cancel(handle) do
    GenServer.call(handle.pid, {:close, handle}, 1100)
  catch
    :exit, {:timeout, _} ->
      {:error, Error.new(:cleanup_timeout)}

    :exit, _ ->
      if Process.alive?(handle.pid), do: {:error, Error.new(:invalid_subscription)}, else: :ok
  end

  defp now, do: System.monotonic_time(:millisecond)
end
