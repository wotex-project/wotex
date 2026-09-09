defmodule Wotex.BLE.BlueZ.SubscriptionOwner do
  @moduledoc """
  Owns one native subscription's delivery and bounded cancellation lifecycle.

  This implementation process monitors the connection, establishing caller and
  selected receiver. It returns a generation-bound `Wotex.BLE.Subscription`
  only after native establishment succeeds. Active reports are decoded with
  the configured codec and delivered under that handle's reference; malformed
  values, receiver overflow and connection loss end delivery with at most one
  terminal error.

  Receiver death or explicit cancellation asks the connection's control lane
  to release the original subscription. Cleanup has a one-second grace and at
  most 64 simultaneous cancellation waiters. Closed owner processes retain no
  lifetime tombstone. Session membership is checked by the connection before
  this helper treats an already-dead handle as idempotently closed. Status
  inspection omits peer data, credentials and queued values.
  """

  use GenServer
  alias Wotex.BLE.{Error, Subscription, Value}

  @doc false
  @spec start(map(), map(), GenServer.from(), reference(), integer()) :: GenServer.on_start()
  def start(connection, config, from, token, deadline),
    do: GenServer.start(__MODULE__, {connection, config, from, token, deadline})

  @doc false
  @spec cancel(Subscription.t()) :: :ok | {:error, Error.t()}
  def cancel(handle) do
    case call(handle.pid, {:cancel, handle}, 1100) do
      {:error, %Error{code: :disconnected}} -> :ok
      result -> result
    end
  end

  @impl GenServer
  def init({connection, config, from, token, deadline}) do
    {:ok,
     %{
       connection: connection,
       config: config,
       caller: Process.monitor(elem(from, 0)),
       receiver: Process.monitor(config.receiver),
       parent: Process.monitor(connection.pid),
       handle: %Subscription{
         pid: self(),
         reference: make_ref(),
         generation: 1,
         session_reference: connection.reference
       },
       status: :starting,
       waiter: from,
       cancelers: [],
       token: token,
       native_id: nil,
       timer: Process.send_after(self(), {:owner_deadline, token}, max(deadline - now(), 0) + 1000),
       terminal: false,
       result: :ok
     }}
  end

  @impl GenServer
  def handle_call({:cancel, handle}, from, %{handle: handle} = state) do
    if length(state.cancelers) < 64,
      do: {:noreply, stop(%{state | cancelers: [from | state.cancelers]})},
      else: {:reply, {:error, Error.new(:busy)}, state}
  end

  def handle_call(_, _from, state), do: {:reply, {:error, Error.new(:invalid_subscription)}, state}

  @impl GenServer
  def handle_info({token, {:ok, binding}}, %{token: token, status: :starting} = state) do
    Process.demonitor(state.caller, [:flush])
    Process.cancel_timer(state.timer)
    telemetry(:open, :ok)
    GenServer.reply(state.waiter, {:ok, state.handle})

    {:noreply,
     %{
       state
       | status: :active,
         native_id: binding.subscription_id,
         waiter: nil,
         token: nil,
         caller: nil
     }}
  end

  def handle_info({token, {:error, error}}, %{token: token, status: :starting} = state) do
    finish(%{state | result: {:error, error}})
  end

  def handle_info({token, result}, %{token: token, status: :closing} = state) do
    case result do
      :ok -> finish(state)
      {:ok, nil} -> finish(state)
      {:error, error} -> {:noreply, %{state | result: {:error, error}}}
    end
  end

  def handle_info({:ble_stream, id, event}, %{native_id: id, status: :active} = state) do
    {:noreply, deliver(state, event)}
  end

  def handle_info({:owner_deadline, token}, %{token: token} = state) do
    finish(%{state | result: {:error, Error.new(:cleanup_timeout)}})
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{parent: ref} = state) do
    error = Error.new(:disconnected)
    state = if state.status == :active, do: terminal(state, error), else: state
    finish(state)
  end

  def handle_info({:DOWN, ref, :process, _, _}, state) do
    if ref in [state.receiver, state.caller],
      do: {:noreply, stop(state)},
      else: {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def format_status(status) do
    Map.new(status, fn
      {:state, state} -> {:state, %{status: state.status}}
      {:message, _} -> {:message, :redacted}
      {:reason, _} -> {:reason, :redacted}
      {:log, _} -> {:log, []}
      entry -> entry
    end)
  end

  defp deliver(state, {:ok, bytes, metadata}) do
    case Process.info(state.config.receiver, :message_queue_len) do
      {:message_queue_len, length} when length < state.config.max_queue_length ->
        case Value.decode(bytes, state.config.type, state.config.codec) do
          {:ok, value} ->
            send(
              state.config.receiver,
              {:wotex_ble, state.handle.reference, {:ok, value, metadata}}
            )

            telemetry(:deliver, :ok)
            state

          {:error, error} ->
            stop(terminal(state, error))
        end

      nil ->
        stop(state)

      _ ->
        stop(terminal(state, Error.new(:receiver_overflow)))
    end
  end

  defp deliver(state, {:error, error}), do: stop(terminal(state, error))

  defp terminal(%{terminal: true} = state, _), do: state

  defp terminal(state, error) do
    send(state.config.receiver, {:wotex_ble, state.handle.reference, {:error, error}})
    %{state | terminal: true, result: {:error, error}}
  end

  defp stop(%{status: :closing} = state), do: state

  defp stop(state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    token = make_ref()
    timer = Process.send_after(self(), {:owner_deadline, token}, 1000)

    GenServer.cast(
      state.connection.pid,
      {state.connection.reference, :unsubscribe, self(), {self(), token}}
    )

    %{state | status: :closing, token: token, timer: timer}
  end

  defp finish(state) do
    if state.timer, do: Process.cancel_timer(state.timer)

    code =
      case state.result do
        :ok -> :ok
        {:error, error} -> error.code
      end

    telemetry(:close, code)

    if state.waiter,
      do:
        GenServer.reply(
          state.waiter,
          if(state.result == :ok, do: {:error, Error.new(:disconnected)}, else: state.result)
        )

    Enum.each(state.cancelers, &GenServer.reply(&1, state.result))
    {:stop, :normal, state}
  end

  defp call(pid, request, timeout) do
    GenServer.call(pid, request, timeout)
  catch
    :exit, {:timeout, _} ->
      {:error, Error.new(:cleanup_timeout)}

    :exit, _ ->
      {:error, Error.new(if(Process.alive?(pid), do: :invalid_subscription, else: :disconnected))}
  end

  defp telemetry(event, code),
    do: :telemetry.execute([:wotex, :ble, :subscription, event], %{count: 1}, %{code: code})

  defp now, do: System.monotonic_time(:millisecond)
end
