defmodule Wotex.BACnet.COVOwner do
  @moduledoc """
  Owns one native COV subscription from registration through cancellation.

  The process monitors the session, client, receiver, listener, and establishing
  caller. It uses cancellable workers for control exchanges so renewal and
  cleanup remain responsive to owner loss. Establishment succeeds only after a
  validated control ACK; an early report is buffered until that point.

  A finite local lease starts with the control exchange and may renew halfway
  through its configured lifetime. Server time remaining is retained as report
  metadata and cannot silently extend the lease. Confirmed duplicate reports
  are acknowledged by the listener while repeated delivery is suppressed.

  Queue overflow, expiry, protocol failure, and owner death end delivery and
  begin bounded cancellation. Cleanup stops owned workers and timers and settles
  their wrapper registrations without terminating a borrowed client. Consumers
  interact through `Wotex.BACnet.Subscription`, not process messages.
  """

  use GenServer
  alias Wotex.BACnet.{COVCache, COVListener, COVWire, Error, Subscription}

  @doc false
  @spec start_link(map()) :: GenServer.on_start()
  def start_link(options) do
    case GenServer.start(__MODULE__, options) do
      {:ok, pid} ->
        Process.link(pid)
        {:ok, pid}

      error ->
        error
    end
  end

  @impl GenServer
  def init(options) do
    Process.flag(:trap_exit, true)

    handle = %Subscription{
      pid: self(),
      reference: make_ref(),
      generation: make_ref(),
      session_generation: options.config.generation
    }

    state =
      Map.merge(options, %{
        handle: handle,
        phase: :opening,
        listener: nil,
        listener_monitor: nil,
        identifier: nil,
        receiver_monitor: Process.monitor(options.request.receiver),
        caller_monitor: Process.monitor(elem(options.from, 0)),
        session_monitor: Process.monitor(options.session),
        client_monitor: Process.monitor(options.config.client),
        control: nil,
        control_worker: nil,
        pending_lease: nil,
        renew_deadline: nil,
        renew_timer: nil,
        expiry_timer: nil,
        expiry: nil,
        lifetime_token: nil,
        cache: [],
        buffered: nil,
        established: false,
        close_from: nil,
        close_result: :ok,
        cleanup_timer: nil,
        cleanup_deadline: nil,
        cancellation: :ok,
        opening_timer:
          Process.send_after(
            self(),
            {:opening_deadline, handle.generation},
            max(options.deadline - now(), 0)
          )
      })

    {:ok, state, {:continue, :open}}
  end

  @impl GenServer
  def handle_continue(:open, state) do
    cond do
      not Process.alive?(state.request.receiver) ->
        close(state, Error.new(:receiver_closed))

      not Process.alive?(elem(state.from, 0)) ->
        close(state, Error.new(:connection_closed))

      now() >= state.deadline ->
        close(state, Error.new(:deadline_exceeded))

      true ->
        case COVListener.start_link(%{
               owner: self(),
               client: state.config.client,
               destination: state.config.destination,
               request: state.request,
               deadline: state.deadline
             }) do
          {:ok, listener} ->
            {:noreply, %{state | listener: listener, listener_monitor: Process.monitor(listener)}}

          _ ->
            close(state, Error.new(:startup_failed))
        end
    end
  end

  @impl GenServer
  def handle_call({:cancel, handle, deadline}, from, state) do
    cond do
      handle != state.handle -> {:reply, {:error, Error.new(:invalid_subscription)}, state}
      state.phase == :closing -> {:reply, {:error, Error.new(:busy)}, state}
      true -> close(%{state | close_from: from}, nil, deadline)
    end
  end

  def handle_call(_, _, state), do: {:reply, {:error, Error.new(:invalid_subscription)}, state}

  @impl GenServer
  def handle_info({:cancel_from, from, handle, deadline}, state) do
    case handle_call({:cancel, handle, deadline}, from, state) do
      {:reply, reply, next} ->
        GenServer.reply(from, reply)
        {:noreply, next}

      result ->
        result
    end
  end

  def handle_info(
        {:cov_listener, listener, identifier},
        %{listener: listener, phase: :opening, identifier: nil} = state
      ) do
    cancel_timer(state.opening_timer)
    start_control(%{state | identifier: identifier, opening_timer: nil}, :opening, state.deadline)
  end

  def handle_info(
        {:cov_report, listener, report, value},
        %{listener: listener, phase: phase} = state
      )
      when phase in [:opening, :active, :renewing] do
    {duplicate, cache} = duplicate(state, report)
    next = %{state | cache: cache}
    if duplicate, do: {:noreply, next}, else: accept_report(next, {report, value})
  end

  def handle_info({:cov_listener_error, listener, %Error{} = error}, %{listener: listener} = state),
    do: close(state, error)

  def handle_info({:cov_result, token, result}, %{control: %{token: token} = control} = state) do
    stop_control(control)
    state = %{state | control: nil}
    result = if now() >= control.deadline, do: {:error, Error.new(:deadline_exceeded)}, else: result
    control_result(state, control, result)
  end

  def handle_info({:control_deadline, token}, %{control: %{token: token} = control} = state) do
    stop_control(control)
    control_result(%{state | control: nil}, control, {:error, Error.new(:deadline_exceeded)})
  end

  def handle_info(
        {:opening_deadline, generation},
        %{handle: %{generation: generation}, phase: :opening} = state
      ),
      do: close(state, Error.new(:deadline_exceeded))

  def handle_info({:renew, token}, %{lifetime_token: token, phase: :active} = state) do
    deadline = min(now() + state.timeout, state.expiry)

    pending =
      :gen_server.send_request(
        state.session,
        {:cov_lease, self(), state.handle.session_generation}
      )

    {:noreply, %{state | pending_lease: pending, renew_deadline: deadline, renew_timer: nil}}
  end

  def handle_info({:expire, token}, %{lifetime_token: token, phase: phase} = state)
      when phase in [:active, :renewing] do
    close(state, Error.new(:subscription_expired))
  end

  def handle_info({:session_closing, session, deadline}, %{session: session} = state),
    do: close(state, Error.new(:connection_closed), deadline)

  def handle_info(
        {:cleanup_deadline, generation},
        %{handle: %{generation: generation}, phase: :closing} = state
      ),
      do: finish(state, {:error, Error.new(:deadline_exceeded)})

  def handle_info({:DOWN, reference, :process, _, _}, %{receiver_monitor: reference} = state),
    do: close(state, Error.new(:receiver_closed))

  def handle_info({:DOWN, reference, :process, _, _}, %{session_monitor: reference} = state),
    do: close(state, Error.new(:connection_closed))

  def handle_info({:DOWN, reference, :process, _, _}, %{client_monitor: reference} = state),
    do: close(state, Error.new(:connection_closed))

  def handle_info({:DOWN, reference, :process, _, _}, %{caller_monitor: reference} = state),
    do: close(state, Error.new(:connection_closed))

  def handle_info({:DOWN, reference, :process, _, _}, %{listener_monitor: reference} = state),
    do: close(state, Error.new(:connection_closed))

  def handle_info(
        {:DOWN, reference, :process, _, _},
        %{control: %{monitor: reference} = control} = state
      ) do
    stop_control(control)
    control_result(%{state | control: nil}, control, {:error, Error.new(:connection_closed)})
  end

  def handle_info({:EXIT, session, _}, %{session: session} = state),
    do: close(state, Error.new(:connection_closed))

  def handle_info(message, %{pending_lease: pending} = state) when pending != nil do
    case :gen_server.check_response(message, pending) do
      {:reply, {:ok, lease}} when is_reference(lease) ->
        start_control(%{state | pending_lease: nil, lease: lease}, :renewing, state.renew_deadline)

      {:reply, {:error, %Error{} = error}} ->
        close(%{state | pending_lease: nil}, error)

      {:reply, _} ->
        close(%{state | pending_lease: nil}, Error.new(:invalid_transport_return))

      {:error, _} ->
        close(%{state | pending_lease: nil}, Error.new(:connection_closed))

      :no_reply ->
        {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    stop_control(state.control)
    children = Enum.filter([state.listener, state.control_worker], &is_pid/1)
    deadline = state.cleanup_deadline || now() + 1000

    monitors =
      Enum.map(children, fn pid ->
        ref = Process.monitor(pid)
        Process.exit(pid, :kill)
        ref
      end)

    Enum.each(monitors, fn ref ->
      receive do
        {:DOWN, ^ref, :process, _, _} -> :ok
      after
        max(deadline - now(), 0) -> Process.demonitor(ref, [:flush])
      end
    end)

    settled = settle(state.config.client, children, deadline)

    Enum.each(
      [state.opening_timer, state.expiry_timer, state.renew_timer, state.cleanup_timer],
      &cancel_timer/1
    )

    if state.pending_lease, do: :gen_server.receive_response(state.pending_lease, 0)
    release_lease(state)
    telemetry(:close, state.close_result)

    if state.close_from do
      result = if state.cancellation == :ok, do: settled, else: state.cancellation
      send(state.session, {:cov_cancelled, self(), result})
    end

    :ok
  end

  defp settle(client, children, deadline) do
    GenServer.call(client, {:wotex_client, :settle, children}, max(deadline - now(), 1))
  catch
    :exit, _ -> {:error, Error.new(:deadline_exceeded)}
  end

  defp start_control(state, kind, deadline) do
    if now() >= deadline do
      close(state, Error.new(:deadline_exceeded))
    else
      token = make_ref()
      parent = self()
      started = now()

      {worker, monitor} =
        :erlang.spawn_opt(
          fn ->
            result =
              COVWire.exchange(
                state.config,
                state.request,
                state.identifier,
                deadline,
                kind == :closing
              )

            send(parent, {:cov_result, token, result})
          end,
          [:link, :monitor]
        )

      control = %{
        worker: worker,
        monitor: monitor,
        token: token,
        kind: kind,
        deadline: deadline,
        started: started,
        timer: Process.send_after(self(), {:control_deadline, token}, max(deadline - now(), 0))
      }

      {:noreply, %{state | control: control, control_worker: worker, phase: kind}}
    end
  end

  defp control_result(%{phase: :closing} = state, _, result),
    do: finish(state, cancel_result(result))

  defp control_result(state, _, {:error, %Error{} = error}), do: close(state, error)

  defp control_result(state, control, {:ok, :subscribed}) do
    if state.established, do: release_lease(state)
    cancel_timer(state.expiry_timer)
    cancel_timer(state.renew_timer)
    expiry = control.started + state.request.lifetime * 1000
    token = make_ref()

    state = %{
      state
      | lease: nil,
        phase: :active,
        expiry: expiry,
        lifetime_token: token,
        expiry_timer: Process.send_after(self(), {:expire, token}, max(expiry - now(), 0)),
        renew_timer:
          if(state.request.renew,
            do:
              Process.send_after(
                self(),
                {:renew, token},
                max(control.started + state.request.lifetime * 500 - now(), 0)
              ),
            else: nil
          )
    }

    if now() >= expiry do
      close(state, Error.new(:subscription_expired))
    else
      established(state)
    end
  end

  defp control_result(state, _, _), do: close(state, Error.new(:invalid_transport_return))

  defp established(%{established: true} = state), do: {:noreply, state}

  defp established(state) do
    telemetry(:open, :ok)
    send(state.session, {:cov_established, self(), state.handle})
    Process.demonitor(state.caller_monitor, [:flush])
    next = %{state | established: true, from: nil, caller_monitor: nil, buffered: nil}
    if state.buffered, do: emit(next, state.buffered), else: {:noreply, next}
  end

  defp accept_report(%{phase: :opening, buffered: nil} = state, report),
    do: {:noreply, %{state | buffered: report}}

  defp accept_report(%{phase: :opening} = state, _), do: close(state, Error.new(:receiver_overflow))
  defp accept_report(state, report), do: emit(state, report)

  defp emit(state, {report, value}) do
    case Process.info(state.request.receiver, :message_queue_len) do
      {:message_queue_len, length} when length < state.request.max_queue_length ->
        metadata = %{
          source: state.config.destination,
          device_instance: report.device_instance,
          process_identifier: report.process_identifier,
          object_type: report.object_type,
          instance: report.instance,
          property: state.request.property,
          array_index: state.request.array_index,
          time_remaining: report.time_remaining,
          report_values: report.values
        }

        send(
          state.request.receiver,
          {:wotex_bacnet, state.handle.reference, {:ok, value, metadata}}
        )

        telemetry(:deliver, :ok)
        {:noreply, state}

      _ ->
        close(state, Error.new(:receiver_overflow))
    end
  end

  defp duplicate(state, %{confirmed: false}), do: {false, state.cache}

  defp duplicate(state, report) do
    key =
      {state.config.destination, report.invoke_id,
       :crypto.hash(:sha256, :erlang.term_to_binary(report))}

    COVCache.touch(state.cache, key, now(), state.request.duplicate_window_ms)
  end

  defp close(state, error, deadline \\ nil)
  defp close(%{phase: :closing} = state, _, _), do: {:noreply, state}

  defp close(state, error, deadline) do
    close_result = if error, do: {:error, error}, else: :ok
    if state.from, do: GenServer.reply(state.from, close_result)

    if state.established and error,
      do: send(state.request.receiver, {:wotex_bacnet, state.handle.reference, {:error, error}})

    stop_control(state.control)
    Enum.each([state.opening_timer, state.renew_timer, state.expiry_timer], &cancel_timer/1)
    if state.pending_lease, do: :gen_server.receive_response(state.pending_lease, 0)
    if state.listener, do: GenServer.cast(state.listener, :close)
    deadline = min(deadline || now() + 1000, now() + 1000)

    state = %{
      state
      | phase: :closing,
        from: nil,
        pending_lease: nil,
        control: nil,
        opening_timer: nil,
        renew_timer: nil,
        expiry_timer: nil,
        buffered: nil,
        cache: [],
        close_result: close_result,
        cleanup_deadline: deadline,
        cleanup_timer:
          Process.send_after(
            self(),
            {:cleanup_deadline, state.handle.generation},
            max(deadline - now(), 0)
          )
    }

    if state.identifier && Process.alive?(state.config.client) && now() < deadline,
      do: start_control(state, :closing, deadline),
      else: finish(state, :ok)
  end

  defp finish(state, cancellation), do: {:stop, :normal, %{state | cancellation: cancellation}}

  defp cancel_result({:ok, :subscribed}), do: :ok
  defp cancel_result({:error, %Error{}} = result), do: result
  defp cancel_result(_), do: {:error, Error.new(:invalid_transport_return)}

  defp stop_control(nil), do: :ok

  defp stop_control(control) do
    Process.exit(control.worker, :kill)
    Process.demonitor(control.monitor, [:flush])
    cancel_timer(control.timer)
  end

  defp release_lease(%{lease: nil}), do: :ok
  defp release_lease(state), do: send(state.session, {:cov_control_release, self(), state.lease})
  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp telemetry(event, result) do
    :telemetry.execute(
      [:wotex, :bacnet, :subscription, event],
      %{count: 1},
      %{result: if(result == :ok, do: :ok, else: :error)}
    )
  end

  defp now, do: System.monotonic_time(:millisecond)
end
