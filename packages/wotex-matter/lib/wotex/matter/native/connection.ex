defmodule Wotex.Matter.Native.Connection do
  @moduledoc """
  Owns the Port and request correlation state for one native controller.

  `Wotex.Matter.Native` starts this process explicitly and monitors the caller
  that created it. The process validates the fixed startup identity, assigns
  increasing native request IDs, accepts one response for the expected ID, and
  closes the Port when the caller or connection terminates. A missed response
  deadline expires the generation so a delayed frame cannot be correlated with
  later work. Admitted calls retain one caller monitor and deadline timer until
  completion. The bounded FIFO queue removes dead or expired callers without
  transmission. Native response waits also service queued call admission,
  cancellation, report consumption and receiver death. Losing the active caller
  closes its generation and fails queued requests before transmission.
  One owned 50 ms maintenance timer reclaims dead or expired reservations whose
  callers never submitted a message. It consumes an already queued message before
  releasing that slot and rejects a late submission after its deadline. The same
  timer terminates an abandoned close; no global reaper process is started.
  Writes to native stdin never suspend this owner. A busy or failed pipe closes
  the generation; a rejected report ACK cannot restore native credit or leave
  the subscription waiting indefinitely.
  Missing or malformed replies after a submitted write, invoke, commissioning
  operation or commissioning-window request retain unknown effect without retry.
  A validated native failure keeps the SDK's own submission classification.
  Ordinary request IDs end at uint64 maximum. Consuming that final ID schedules
  generation cleanup after its response, using the reserved `close` identity;
  neither ordinary dispatch nor internal cancellation can wrap the counter.
  Ordinary subscriptions own a separately linked report validator. Reports retain
  credit until that owner validates admission; this connection alone forwards
  public deliveries and terminal messages, preserving their order. Losing a
  receiver or stream owner during unconfirmed registration closes the generation;
  a late successful reply cannot reopen it or return a live handle. Retiring the
  subscription kills and reaps its validator, including a suspended validator.
  Cleanup waits for native exit, the Port monitor and removal from Port.info.
  Exit notification can precede asynchronous release of the Port's driver state.
  It is an implementation module; consumers use
  `Wotex.Matter.Native` and its opaque `Wotex.Matter.Native.Handle`.
  """

  use GenServer

  alias Wotex.Matter.{Error, Subscription}
  alias Wotex.Matter.Native.{Admission, ReportLedger, Request, StreamOwner, Wire}

  @sdk_revision "250a9e6c50ee2068107f3c4808b680f5f2925415"
  @maximum_line_bytes 131_071
  @cleanup_timeout 1_000
  @response_grace 50
  @maximum_request_id 0xFFFFFFFFFFFFFFFF
  @mutating_operations [:write, :invoke, :commission_on_network, :open_window]
  @mutating_wire_operations Enum.map(@mutating_operations, &Atom.to_string/1)

  @spec start(pid(), map()) ::
          {:ok, pid(), String.t(), :ets.tid()} | {:error, Error.t()}
  def start(owner, options) do
    deadline = System.monotonic_time(:millisecond) + options.timeout

    case GenServer.start(__MODULE__, {owner, options, deadline}) do
      {:ok, pid} ->
        try do
          case GenServer.call(pid, :identity) do
            {:ok, generation, admission} -> {:ok, pid, generation, admission}
            {:error, _} = error -> error
          end
        catch
          :exit, _ -> {:error, Error.new(:controller_start_failed)}
        end

      {:error, %Error{}} = error ->
        error

      {:error, {:shutdown, %Error{} = error}} ->
        {:error, error}

      {:error, _} ->
        {:error, Error.new(:controller_start_failed)}
    end
  end

  @spec request(pid(), String.t(), :ets.tid(), map(), pos_integer(), integer()) ::
          {:ok, term()} | {:error, Error.t()}
  def request(pid, generation, admission, message, timeout, deadline),
    do:
      call(pid, generation, admission, {:request, generation, message, timeout}, timeout, deadline)

  @spec subscribe(pid(), String.t(), :ets.tid(), map(), pid(), pos_integer(), boolean()) ::
          {:ok, Subscription.t()} | {:error, Error.t()}
  def subscribe(pid, generation, admission, request, receiver, timeout, acknowledged) do
    call(
      pid,
      generation,
      admission,
      {:subscribe, generation, request, receiver, timeout, acknowledged},
      timeout
    )
  end

  @spec unsubscribe(pid(), String.t(), :ets.tid(), Subscription.t(), pos_integer()) ::
          :ok | {:error, Error.t()}
  def unsubscribe(pid, generation, admission, subscription, timeout) do
    if Process.alive?(pid) do
      case call(
             pid,
             generation,
             admission,
             {:unsubscribe, generation, subscription, timeout},
             timeout
           ) do
        {:ok, nil} -> :ok
        {:error, _} = error -> error
      end
    else
      if valid_subscription_handle?(subscription, pid),
        do: :ok,
        else: {:error, Error.new(:invalid_handle)}
    end
  end

  @spec health(pid(), String.t(), :ets.tid(), pos_integer()) ::
          {:ok, map()} | {:error, Error.t()}
  def health(pid, generation, admission, timeout),
    do: call(pid, generation, admission, {:health, generation, timeout}, timeout)

  @doc false
  @spec invalidate(pid(), String.t(), :ets.tid()) :: {:ok, nil} | {:error, Error.t()}
  def invalidate(pid, generation, admission),
    do: control_call(pid, generation, admission, :invalidate, @cleanup_timeout)

  @spec disconnect(pid(), String.t(), :ets.tid(), pos_integer()) :: :ok | {:error, Error.t()}
  def disconnect(pid, generation, admission, timeout \\ @cleanup_timeout) do
    if Process.alive?(pid) do
      case control_call(pid, generation, admission, :disconnect, timeout) do
        {:ok, nil} -> :ok
        {:error, %Error{code: :transport_closed}} -> :ok
        {:error, _} = error -> error
      end
    else
      :ok
    end
  end

  @impl GenServer
  def init({owner, options, deadline}) do
    Process.flag(:trap_exit, true)
    owner_monitor = Process.monitor(owner)
    generation = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

    case open_port(options.executable) do
      {:ok, port} ->
        case handshake(port, owner_monitor, generation, options, deadline) do
          :ok ->
            {:ok,
             %{
               port: port,
               owner_monitor: owner_monitor,
               generation: generation,
               admission: Admission.new(generation),
               admission_timer: schedule_admission_reap(),
               calls: %{},
               call_order: :queue.new(),
               caller_monitors: %{},
               active_call: nil,
               close_call: nil,
               drain_scheduled: false,
               fabric_id: options.fabric_id,
               next_id: 2,
               subscriptions: %{},
               subscription_ids: %{},
               subscription_monitors: %{},
               closed_references: MapSet.new(),
               report_ledger: ReportLedger.new(),
               internal_requests: %{}
             }}

          {:error, %Error{} = error} ->
            close_port(port)
            {:stop, {:shutdown, error}}
        end

      {:error, %Error{} = error} ->
        {:stop, {:shutdown, error}}
    end
  end

  @impl GenServer
  def handle_call({:bounded, message, deadline, lease}, from, state),
    do: {:noreply, enqueue_call(state, message, deadline, lease, from)}

  def handle_call({:close_control, generation, kind, deadline, token}, _from, state) do
    cond do
      generation != state.generation or not Admission.close_owned?(state.admission, token) ->
        {:reply, {:error, Error.new(:invalid_handle)}, state}

      kind == :invalidate ->
        {:stop, :normal, {:ok, nil}, state}

      deadline <= System.monotonic_time(:millisecond) ->
        {:stop, :normal, {:error, Error.new(:timeout)}, state}

      true ->
        {:disconnect, generation}
        |> handle_call(nil, Map.put(state, :call_deadline, deadline))
        |> clear_call_deadline()
    end
  end

  def handle_call(:identity, _, state),
    do: {:reply, {:ok, state.generation, state.admission}, state}

  def handle_call({:invalidate, generation}, _, state) do
    if generation == state.generation,
      do: {:stop, :normal, {:ok, nil}, state},
      else: {:reply, {:error, Error.new(:invalid_handle)}, state}
  end

  def handle_call({:request, generation, message, timeout}, _, state) do
    cond do
      generation != state.generation ->
        {:reply, {:error, Error.new(:invalid_handle)}, state}

      not is_map(message) or map_size(message) > 1024 or
        not Map.has_key?(message, :type) or not is_atom(message.type) or
        not Enum.all?(Map.keys(message), &is_atom/1) or Request.validate(message) != :ok ->
        {:reply, {:error, Error.new(:invalid_request)}, state}

      true ->
        parameters =
          message
          |> Map.delete(:type)
          |> stringify_keys()

        operation =
          message
          |> Map.fetch!(:type)
          |> Atom.to_string()

        state
        |> execute(operation, parameters, timeout)
        |> decode_operation_reply(message.type)
    end
  end

  def handle_call({:health, generation, timeout}, _, state) do
    if generation == state.generation do
      execute(state, "health", %{}, timeout)
    else
      {:reply, {:error, Error.new(:invalid_handle)}, state}
    end
  end

  def handle_call({:subscribe, generation, request, receiver, timeout, acknowledged}, _, state) do
    cond do
      generation != state.generation ->
        {:reply, {:error, Error.new(:invalid_handle)}, state}

      map_size(state.subscriptions) >= 64 or MapSet.size(state.closed_references) >= 1_024 ->
        {:reply, {:error, Error.new(:busy)}, state}

      not Process.alive?(receiver) ->
        {:reply, {:error, Error.new(:receiver_closed)}, state}

      true ->
        reference = make_ref()
        native_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
        monitor = Process.monitor(receiver)

        {stream_owner, stream_monitor} =
          if acknowledged do
            {nil, nil}
          else
            {:ok, owner} = StreamOwner.start_link(self(), generation, reference, receiver, request)
            {owner, Process.monitor(owner)}
          end

        subscription = %{
          reference: reference,
          native_id: native_id,
          generation: 1,
          handle_generation: 1,
          receiver: receiver,
          acknowledged: acknowledged,
          stream_owner: stream_owner,
          stream_monitor: stream_monitor,
          monitor: monitor,
          queue_limit: request.queue_limit,
          resubscribe: request.resubscribe,
          kind: request.kind,
          paths: request.paths,
          status: :establishing,
          close_result: :cancelled,
          native_terminal_received: false,
          retiring_generation: nil,
          retiring_last_report_sequence: nil,
          recovery_attempt: 0,
          buffered: [],
          last_report_sequence: 0
        }

        parameters =
          request
          |> Map.put(:subscription_id, native_id)
          |> stringify_keys()

        prepared = put_subscription(state, subscription)

        case request_frame(prepared, "subscribe", parameters, timeout) do
          {:ok, result, next_state} ->
            case establish_subscription(result, subscription, next_state) do
              {:ok, handle, established} ->
                send(self(), {:flush_subscription, reference})
                {:reply, {:ok, handle}, established}

              {:error, error, failed} ->
                {:stop, :normal, {:error, error},
                 notify_session_failure(error, drop_subscription(failed, reference))}
            end

          {:error, error, next_state} ->
            error_reply(error, drop_subscription(next_state, reference))
        end
    end
  end

  def handle_call({:unsubscribe, generation, subscription, timeout}, _, state) do
    with true <- generation == state.generation,
         :ok <- validate_owned_subscription(subscription, state) do
      if MapSet.member?(state.closed_references, subscription.reference) do
        {:reply, {:ok, nil}, state}
      else
        current = Map.fetch!(state.subscriptions, subscription.reference)

        closing =
          state
          |> put_in([:subscriptions, subscription.reference, :status], :closing)
          |> put_in([:subscriptions, subscription.reference, :close_result], :cancelled)

        parameters = %{
          "subscription_id" => current.native_id,
          "generation" => current.generation
        }

        case request_frame(closing, "unsubscribe", parameters, timeout) do
          {:ok, nil, next_state} ->
            if Map.has_key?(next_state.subscriptions, subscription.reference) do
              error = Error.new(:invalid_frame)
              {:stop, :normal, {:error, error}, notify_session_failure(error, next_state)}
            else
              {:reply, {:ok, nil}, next_state}
            end

          {:ok, _, next_state} ->
            error = Error.new(:invalid_frame)
            {:stop, :normal, {:error, error}, notify_session_failure(error, next_state)}

          {:error, error, next_state} ->
            error_reply(error, next_state)
        end
      end
    else
      _ -> {:reply, {:error, Error.new(:invalid_handle)}, state}
    end
  end

  def handle_call({:disconnect, generation}, _, state) do
    if generation == state.generation do
      case request_frame(state, "close", %{}, @cleanup_timeout) do
        {:ok, nil, next_state} ->
          case await_close_exit(next_state) do
            :ok -> {:stop, :normal, {:ok, nil}, %{next_state | port: nil}}
            {:error, error} -> {:stop, :normal, {:error, error}, next_state}
          end

        {:ok, _, next_state} ->
          {:stop, :normal, {:error, Error.new(:invalid_frame)}, next_state}

        {:error, error, next_state} ->
          {:stop, :normal, {:error, error}, next_state}
      end
    else
      {:reply, {:error, Error.new(:invalid_handle)}, state}
    end
  end

  @impl GenServer
  def handle_info(
        {:request_ids_exhausted, generation},
        %{generation: generation, next_id: :exhausted} = state
      ) do
    closing =
      state
      |> Map.put(:call_deadline, System.monotonic_time(:millisecond) + @cleanup_timeout)
      |> then(&handle_call({:disconnect, generation}, nil, &1))

    {:stop, reason, _, next_state} = closing
    {:stop, reason, notify_session_failure(Error.new(:transport_closed), next_state)}
  end

  def handle_info({:reap_admission, token}, state) do
    case reap_admission(state, token) do
      {:ok, next_state} -> {:noreply, next_state}
      {:error, error, next_state} -> {:stop, :normal, notify_session_failure(error, next_state)}
    end
  end

  def handle_info(:drain_calls, state) do
    case :queue.out(state.call_order) do
      {:empty, _} ->
        {:noreply, %{state | drain_scheduled: false}}

      {{:value, lease}, order} ->
        call = Map.fetch!(state.calls, lease)
        active = %{state | call_order: order, active_call: lease, drain_scheduled: false}
        remaining = call.deadline - System.monotonic_time(:millisecond)

        result =
          cond do
            Admission.closing?(state.admission) ->
              {:reply, {:error, Error.new(:transport_closed)}, active}

            not Process.alive?(elem(call.from, 0)) ->
              {:reply, {:error, Error.new(:owner_closed)}, active}

            remaining <= 0 ->
              {:reply, {:error, Error.new(:timeout)}, active}

            true ->
              call.message
              |> remaining_budget(remaining)
              |> handle_call(call.from, Map.put(active, :call_deadline, call.deadline))
              |> clear_call_deadline()
          end

        case result do
          {:reply, reply, next_state} ->
            {:noreply, next_state |> finish_call(lease, reply) |> schedule_drain()}

          {:stop, reason, reply, next_state} ->
            {:stop, reason, finish_call(next_state, lease, reply)}
        end
    end
  end

  def handle_info({:expire_call, lease}, state) do
    if lease == state.active_call,
      do: {:noreply, state},
      else: {:noreply, finish_call(state, lease, {:error, Error.new(:timeout)})}
  end

  def handle_info(
        {:native_report_admitted, owner, generation, reference, sequence, token, admission},
        state
      ) do
    with true <- generation == state.generation,
         {:ok, %{stream_owner: ^owner, acknowledged: false, status: :active} = subscription} <-
           Map.fetch(state.subscriptions, reference),
         {:ok, %{stream: {^reference, _}, token: ^token, bytes: bytes, consumed: false}} <-
           Map.fetch(state.report_ledger.pending, sequence) do
      case admission do
        {:ok, delivery} ->
          case Process.info(subscription.receiver, :message_queue_len) do
            {:message_queue_len, length} when length < subscription.queue_limit ->
              send(subscription.receiver, {:wotex_matter, reference, delivery})
              emit_subscription(:deliver, subscription.kind, :ok)
              {:noreply, acknowledge_report(state, sequence, bytes)}

            _ ->
              {:noreply, overflow_subscription(state, reference, sequence, bytes)}
          end

        {:error, :receiver_overflow} ->
          {:noreply, overflow_subscription(state, reference, sequence, bytes)}

        _ ->
          {:noreply, notify_session_failure(Error.new(:invalid_frame), fail_native_input(state))}
      end
    else
      _ -> {:noreply, state}
    end
  end

  def handle_info({:native_report_consumed, generation, reference, sequence, token}, state) do
    with true <- generation == state.generation,
         {:ok, %{acknowledged: true} = subscription} <- Map.fetch(state.subscriptions, reference),
         {:ok, %{stream: {^reference, _}, token: ^token, bytes: bytes, consumed: false}} <-
           Map.fetch(state.report_ledger.pending, sequence) do
      emit_subscription(:deliver, subscription.kind, :ok)
      {:noreply, acknowledge_report(state, sequence, bytes)}
    else
      _ -> {:noreply, state}
    end
  end

  def handle_info(
        {:native_input_failed, generation},
        %{generation: generation, channel_failed: true} = state
      ),
      do: {:stop, :normal, notify_session_failure(Error.new(:transport_closed), state)}

  def handle_info({:DOWN, monitor, :process, _, _}, %{owner_monitor: monitor} = state),
    do: {:stop, :normal, notify_session_failure(Error.new(:owner_closed), state)}

  def handle_info({:DOWN, monitor, :process, _, _}, state) do
    case Map.fetch(state.caller_monitors, monitor) do
      {:ok, lease} ->
        {:noreply, finish_call(state, lease, {:error, Error.new(:owner_closed)})}

      :error ->
        case Map.fetch(state.subscription_monitors, monitor) do
          {:ok, reference} ->
            subscription = Map.fetch!(state.subscriptions, reference)

            if monitor == subscription.stream_monitor and subscription.status != :closing do
              send(
                subscription.receiver,
                {:wotex_matter, reference, {:error, Error.new(:owner_closed)}}
              )

              {:noreply, cancel_subscription(state, reference, :owner_closed)}
            else
              {:noreply, cancel_subscription(state, reference, :receiver_closed)}
            end

          :error ->
            {:noreply, state}
        end
    end
  end

  def handle_info({:flush_subscription, reference}, state),
    do: {:noreply, flush_subscription(state, reference)}

  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state)
      when byte_size(line) <= @maximum_line_bytes do
    case decode_async_line(line, state) do
      {:ok, next_state} -> {:noreply, next_state}
      {:error, error} -> {:stop, :normal, notify_session_failure(error, state)}
    end
  end

  def handle_info({port, {:data, {:noeol, _}}}, %{port: port} = state),
    do: {:stop, :normal, notify_session_failure(Error.new(:response_limit), state)}

  def handle_info({port, {:exit_status, _}}, %{port: port} = state),
    do: {:stop, :normal, notify_session_failure(Error.new(:transport_closed), state)}

  def handle_info({:EXIT, port, _}, %{port: port} = state),
    do: {:stop, :normal, notify_session_failure(Error.new(:transport_closed), state)}

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) when is_map(state) do
    if timer = Map.get(state, :admission_timer), do: Process.cancel_timer(elem(timer, 0))

    Enum.each(Map.get(state, :calls, %{}), fn {lease, _} ->
      finish_call(state, lease, {:error, Error.new(:transport_closed)})
    end)

    cleanup_deadline = System.monotonic_time(:millisecond) + @cleanup_timeout
    owners = stop_stream_owners(Map.values(Map.get(state, :subscriptions, %{})))

    Enum.each(Map.get(state, :subscriptions, %{}), fn {_reference, subscription} ->
      result =
        if subscription.status == :closing,
          do: subscription.close_result,
          else: :session_closed

      emit_subscription(:close, subscription.kind, result)
    end)

    close_port(Map.get(state, :port))
    await_stream_owners(owners, cleanup_deadline)
    if Map.get(state, :close_call), do: GenServer.reply(state.close_call, {:ok, nil})
    :ok
  end

  def terminate(_, _), do: :ok

  defp schedule_admission_reap do
    token = make_ref()
    {Process.send_after(self(), {:reap_admission, token}, 50), token}
  end

  defp reap_admission(%{admission_timer: {_, token}} = state, token) do
    now = System.monotonic_time(:millisecond)

    for {lease, caller, deadline} <- Admission.reservations(state.admission),
        not Map.has_key?(state.calls, lease),
        deadline <= now or not Process.alive?(caller) do
      # Consume an already submitted call before releasing its reservation.
      # A caller lost before submission has no corresponding mailbox message.
      receive do
        {:"$gen_call", from, {:bounded, _, ^deadline, ^lease}} ->
          GenServer.reply(from, {:error, Error.new(:timeout)})
      after
        0 -> :ok
      end

      Admission.release(state.admission, lease)
    end

    case Admission.close_failure(state.admission, now) do
      nil -> {:ok, %{state | admission_timer: schedule_admission_reap()}}
      code -> {:error, Error.new(code), state}
    end
  end

  defp reap_admission(state, _), do: {:ok, state}

  defp enqueue_call(state, message, deadline, lease, {caller, _} = from) do
    cond do
      deadline <= System.monotonic_time(:millisecond) and
          not Admission.owned?(state.admission, lease, caller, deadline) ->
        GenServer.reply(from, {:error, Error.new(:timeout)})
        state

      not Admission.owned?(state.admission, lease, caller, deadline) or
          Map.has_key?(state.calls, lease) ->
        GenServer.reply(from, {:error, Error.new(:invalid_handle)})
        state

      Admission.closing?(state.admission) ->
        Admission.release(state.admission, lease)
        GenServer.reply(from, {:error, Error.new(:transport_closed)})
        state

      not Process.alive?(caller) or deadline <= System.monotonic_time(:millisecond) ->
        Admission.release(state.admission, lease)
        GenServer.reply(from, {:error, Error.new(:timeout)})
        state

      true ->
        monitor = Process.monitor(caller)
        remaining = max(deadline - System.monotonic_time(:millisecond), 0)
        timer = Process.send_after(self(), {:expire_call, lease}, remaining)
        call = %{message: message, deadline: deadline, from: from, monitor: monitor, timer: timer}

        %{
          state
          | calls: Map.put(state.calls, lease, call),
            call_order: :queue.in(lease, state.call_order),
            caller_monitors: Map.put(state.caller_monitors, monitor, lease)
        }
        |> schedule_drain()
    end
  end

  defp schedule_drain(%{active_call: nil, drain_scheduled: false} = state) do
    if :queue.is_empty(state.call_order) do
      state
    else
      send(self(), :drain_calls)
      %{state | drain_scheduled: true}
    end
  end

  defp schedule_drain(state), do: state

  defp finish_call(state, lease, reply) do
    case Map.pop(state.calls, lease) do
      {nil, _} ->
        state

      {call, calls} ->
        Process.cancel_timer(call.timer)
        Process.demonitor(call.monitor, [:flush])
        Admission.release(state.admission, lease)
        GenServer.reply(call.from, reply)

        %{
          state
          | calls: calls,
            call_order: :queue.filter(&(&1 != lease), state.call_order),
            caller_monitors: Map.delete(state.caller_monitors, call.monitor),
            active_call: if(state.active_call == lease, do: nil, else: state.active_call)
        }
    end
  end

  defp execute(state, operation, parameters, timeout) do
    case request_frame(state, operation, parameters, timeout) do
      {:ok, result, next_state} ->
        {:reply, {:ok, result}, next_state}

      {:error, error, next_state} ->
        error_reply(error, next_state)
    end
  end

  defp error_reply(error, state) do
    if error.code == :timeout or Map.get(state, :channel_failed, false),
      do: {:stop, :normal, {:error, error}, notify_session_failure(error, state)},
      else: {:reply, {:error, error}, state}
  end

  defp notify_session_failure(error, state) do
    subscriptions =
      Map.new(state.subscriptions, fn {reference, subscription} ->
        if subscription.status == :closing do
          {reference, subscription}
        else
          send(subscription.receiver, {:wotex_matter, reference, {:error, error}})
          {reference, %{subscription | status: :closing, close_result: error.code}}
        end
      end)

    %{state | subscriptions: subscriptions}
  end

  defp decode_operation_reply({:reply, {:ok, result}, state}, type) do
    case Wire.decode(type, result) do
      {:ok, decoded} ->
        if System.monotonic_time(:millisecond) <= state.call_deadline do
          {:reply, {:ok, decoded}, state}
        else
          effect = if type in @mutating_operations, do: :unknown, else: :none
          error = Error.new(:timeout) |> Error.with_effect(effect)
          {:stop, :normal, {:error, error}, notify_session_failure(error, state)}
        end

      {:error, error} ->
        effect = if type in @mutating_operations, do: :unknown, else: :none
        error = Error.with_effect(error, effect)
        {:stop, :normal, {:error, error}, notify_session_failure(error, state)}
    end
  end

  defp decode_operation_reply(reply, _), do: reply

  defp remaining_budget({:request, generation, message, timeout}, remaining),
    do: {:request, generation, message, min(timeout, remaining)}

  defp remaining_budget({:health, generation, timeout}, remaining),
    do: {:health, generation, min(timeout, remaining)}

  defp remaining_budget(
         {:subscribe, generation, request, receiver, timeout, acknowledged},
         remaining
       ),
       do: {:subscribe, generation, request, receiver, min(timeout, remaining), acknowledged}

  defp remaining_budget({:unsubscribe, generation, subscription, timeout}, remaining),
    do: {:unsubscribe, generation, subscription, min(timeout, remaining)}

  defp remaining_budget(message, _), do: message

  defp clear_call_deadline({:reply, reply, state}),
    do: {:reply, reply, Map.delete(state, :call_deadline)}

  defp clear_call_deadline({:stop, reason, reply, state}),
    do: {:stop, reason, reply, Map.delete(state, :call_deadline)}

  defp request_frame(state, operation, parameters, timeout) do
    case take_request_id(state, operation) do
      {:ok, id, next_state} ->
        dispatch_request_frame(next_state, id, operation, parameters, timeout)

      :exhausted ->
        {:error, Error.new(:transport_closed), Map.put(state, :channel_failed, true)}
    end
  end

  defp take_request_id(%{next_id: :exhausted} = state, "close"),
    do: {:ok, "close", state}

  defp take_request_id(%{next_id: :exhausted}, _), do: :exhausted

  defp take_request_id(state, _) do
    id = Integer.to_string(state.next_id)

    next =
      if state.next_id == @maximum_request_id do
        send(self(), {:request_ids_exhausted, state.generation})
        :exhausted
      else
        state.next_id + 1
      end

    {:ok, id, %{state | next_id: next}}
  end

  defp dispatch_request_frame(state, id, operation, parameters, timeout) do
    frame = %{
      "version" => 1,
      "id" => id,
      "operation" => operation,
      "parameters" => parameters,
      "timeout_ms" => timeout
    }

    deadline = Map.get(state, :call_deadline, System.monotonic_time(:millisecond) + timeout)

    case send_request_frame(state.port, frame, deadline, state.active_call) do
      :ok ->
        case await_response_until(state, id, deadline) do
          {:ok, result, response_state} ->
            {:ok, result, response_state}

          {:error, error, response_state} ->
            {:error, error, response_state}

          {:channel_error, error, response_state} ->
            effect = if operation in @mutating_wire_operations, do: :unknown, else: :none

            {:error, Error.with_effect(error, effect),
             Map.put(response_state, :channel_failed, true)}
        end

      {:error, :transport_closed} ->
        {:error, Error.new(:transport_closed), Map.put(state, :channel_failed, true)}

      {:error, code} ->
        {:error, Error.new(code), state}
    end
  end

  defp control_call(pid, generation, admission, kind, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    case Admission.begin_close(admission, pid, generation, deadline) do
      {:first, token} ->
        GenServer.call(pid, {:close_control, generation, kind, deadline, token}, timeout + 100)

      :waiting ->
        await_connection_close(pid, deadline)

      {:error, code} ->
        {:error, Error.new(code)}
    end
  catch
    :exit, {:timeout, _} -> {:error, Error.new(:timeout)}
    :exit, _ -> {:error, Error.new(:transport_closed)}
  end

  defp await_connection_close(pid, deadline) do
    monitor = Process.monitor(pid)

    try do
      receive do
        {:DOWN, ^monitor, :process, ^pid, _} -> {:ok, nil}
      after
        max(deadline - System.monotonic_time(:millisecond), 0) -> {:error, Error.new(:timeout)}
      end
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  defp call(pid, generation, admission, message, timeout, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + timeout

    if deadline <= System.monotonic_time(:millisecond) do
      {:error, Error.new(:timeout)}
    else
      admitted_call(pid, generation, admission, message, deadline)
    end
  end

  defp admitted_call(pid, generation, admission, message, deadline) do
    case Admission.acquire(admission, pid, generation, deadline) do
      {:ok, lease} -> await_call(pid, admission, message, deadline, lease)
      {:error, code} -> {:error, Error.new(code)}
    end
  end

  defp await_call(pid, admission, message, deadline, lease) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      GenServer.call(pid, {:bounded, message, deadline, lease}, remaining + 100)
    else
      Admission.release(admission, lease)
      {:error, Error.new(:timeout)}
    end
  catch
    :exit, {:timeout, _} -> {:error, call_error(:timeout, message, lease)}
    :exit, _ -> {:error, call_error(:transport_closed, message, lease)}
  end

  defp call_error(code, message, lease) do
    submitted = Admission.cancel_unsubmitted(lease) == :submitted

    mutation =
      case message do
        {:request, _, %{type: type}, _} -> type in @mutating_operations
        _ -> false
      end

    effect = if submitted and mutation, do: :unknown, else: :none
    Error.new(code) |> Error.with_effect(effect)
  end

  defp open_port(executable) do
    {:ok, %{type: :regular, mode: mode}} = File.stat("/bin/kill")
    true = Bitwise.band(mode, 0o111) != 0

    port =
      Port.open(
        {:spawn_executable, String.to_charlist(executable)},
        [:binary, :exit_status, :use_stdio, {:line, @maximum_line_bytes}]
      )

    {:ok, port}
  rescue
    _ -> {:error, Error.new(:controller_start_failed)}
  end

  defp handshake(port, owner_monitor, generation, options, deadline) do
    with :ok <- await_ready(port, owner_monitor, deadline),
         true <- send_frame(port, flow_frame(generation)),
         :ok <- send_request_frame(port, open_frame(options), deadline),
         {:ok, identity} <- handshake_response(port, owner_monitor, "1", deadline),
         :ok <- controller_identity(identity, options) do
      :ok
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, code} when is_atom(code) -> {:error, Error.new(code)}
      _ -> {:error, Error.new(:controller_start_failed)}
    end
  end

  defp controller_identity(identity, options) do
    expected = %{
      "lifecycle" => "persistent",
      "fabric_id" => options.fabric_id,
      "controller_node_id" => options.controller_node_id,
      "vendor_id" => options.vendor_id
    }

    if identity == expected,
      do: :ok,
      else: {:error, Error.new(:invalid_controller_identity)}
  end

  defp handshake_response(port, owner_monitor, id, deadline) do
    with {:ok, line} <- await_line_until(port, owner_monitor, deadline),
         {:ok, frame} <- Wire.frame(line) do
      case decode_response(frame, id) do
        {:ok, _} = result -> result
        {:error, %Error{}} = error -> error
        _ -> {:error, Error.new(:invalid_frame)}
      end
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp await_ready(port, owner_monitor, deadline) do
    case await_line_until(port, owner_monitor, deadline) do
      {:ok, line} ->
        with {:ok, frame} <- Wire.frame(line),
             true <-
               frame == %{
                 "version" => 1,
                 "event" => "ready",
                 "backend" => "matter-native",
                 "revision" => @sdk_revision
               } do
          :ok
        else
          _ -> {:error, Error.new(:invalid_ready)}
        end

      {:error, _} = error ->
        error
    end
  end

  defp await_response_until(state, id, deadline) do
    case await_owner_line(state, deadline + @response_grace) do
      {:ok, line, received_state} ->
        case Wire.frame(line) do
          {:ok, frame} -> decode_received_response(frame, line, received_state, id, deadline)
          _ -> {:channel_error, Error.new(:invalid_frame), received_state}
        end

      {:error, error, received_state} ->
        {:channel_error, error, received_state}
    end
  end

  defp decode_received_response(frame, line, state, id, deadline) do
    case decode_response(frame, id) do
      {:ok, result} ->
        if System.monotonic_time(:millisecond) <= deadline,
          do: {:ok, result, state},
          else: {:channel_error, Error.new(:timeout), state}

      {:error, %Error{} = error} ->
        {:error, error, state}

      :not_response ->
        case decode_async_frame(frame, byte_size(line) + 1, state) do
          {:ok, next_state} -> await_response_until(next_state, id, deadline)
          {:error, error} -> {:channel_error, error, state}
        end
    end
  end

  defp await_owner_line(state, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    port = state.port
    owner_monitor = state.owner_monitor

    if remaining <= 0 do
      {:error, Error.new(:timeout), state}
    else
      receive do
        {^port, {:data, {:eol, line}}} when byte_size(line) <= @maximum_line_bytes ->
          if System.monotonic_time(:millisecond) < deadline,
            do: {:ok, line, state},
            else: {:error, Error.new(:timeout), state}

        {^port, {:data, {:noeol, _}}} ->
          {:error, Error.new(:response_limit), state}

        {^port, {:exit_status, _}} ->
          {:error, Error.new(:transport_closed), state}

        {:EXIT, ^port, _} ->
          {:error, Error.new(:transport_closed), state}

        {:DOWN, ^owner_monitor, :process, _, _} ->
          {:error, Error.new(:owner_closed), state}

        {:DOWN, monitor, :process, _, _} = message ->
          if Map.get(state.caller_monitors, monitor, :unknown) == state.active_call do
            {:error, Error.new(:owner_closed), state}
          else
            {:noreply, next_state} = handle_info(message, state)
            await_owner_line(next_state, deadline)
          end

        {:"$gen_call", from, {:close_control, generation, _kind, _call_deadline, token}} ->
          if generation == state.generation and Admission.close_owned?(state.admission, token) do
            {:error, Error.new(:transport_closed), %{state | close_call: from}}
          else
            GenServer.reply(from, {:error, Error.new(:invalid_handle)})
            await_owner_line(state, deadline)
          end

        {:"$gen_call", from, {:bounded, message, call_deadline, lease}} ->
          state
          |> enqueue_call(message, call_deadline, lease, from)
          |> await_owner_line(deadline)

        {:reap_admission, token} ->
          case reap_admission(state, token) do
            {:ok, next_state} -> await_owner_line(next_state, deadline)
            {:error, error, next_state} -> {:error, error, next_state}
          end

        {:expire_call, _} = message ->
          {:noreply, next_state} = handle_info(message, state)
          await_owner_line(next_state, deadline)

        {:native_report_admitted, _, _, _, _, _, _} = message ->
          {:noreply, next_state} = handle_info(message, state)
          await_owner_line(next_state, deadline)

        {:native_report_consumed, _, _, _, _} = message ->
          {:noreply, next_state} = handle_info(message, state)
          await_owner_line(next_state, deadline)

        {:native_input_failed, generation} when generation == state.generation ->
          {:error, Error.new(:transport_closed), state}

        {:flush_subscription, _} = message ->
          {:noreply, next_state} = handle_info(message, state)
          await_owner_line(next_state, deadline)
      after
        remaining -> {:error, Error.new(:timeout), state}
      end
    end
  end

  defp await_line_until(port, owner_monitor, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, Error.new(:timeout)}
    else
      result =
        receive do
          {^port, {:data, {:eol, line}}} when byte_size(line) <= @maximum_line_bytes ->
            {:ok, line}

          {^port, {:data, {:noeol, _}}} ->
            {:error, Error.new(:response_limit)}

          {^port, {:exit_status, _}} ->
            {:error, Error.new(:transport_closed)}

          {:EXIT, ^port, _} ->
            {:error, Error.new(:transport_closed)}

          {:DOWN, ^owner_monitor, :process, _, _} ->
            {:error, Error.new(:owner_closed)}
        after
          remaining -> {:error, Error.new(:timeout)}
        end

      if System.monotonic_time(:millisecond) < deadline,
        do: result,
        else: {:error, Error.new(:timeout)}
    end
  end

  defp decode_response(
         %{"version" => 1, "id" => id, "ok" => true, "result" => result} = frame,
         id
       )
       when map_size(frame) == 4,
       do: {:ok, result}

  defp decode_response(
         %{"version" => 1, "id" => id, "ok" => false, "error" => error} = frame,
         id
       )
       when map_size(frame) == 4 do
    case Wire.error(error) do
      {:ok, error} -> {:error, error}
      :error -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp decode_response(_, _), do: :not_response

  defp decode_async_line(line, state) do
    with {:ok, frame} <- Wire.frame(line) do
      decode_async_frame(frame, byte_size(line) + 1, state)
    else
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp decode_async_frame(
         %{
           "version" => 1,
           "event" => "subscription_status",
           "session_generation" => session_generation,
           "subscription_id" => native_id,
           "generation" => generation,
           "status" => "resubscribing",
           "continuity" => "lost",
           "attempt" => attempt
         } = frame,
         _encoded_bytes,
         state
       )
       when map_size(frame) == 8 and is_binary(native_id) and is_integer(generation) and
              generation > 1 and is_integer(attempt) and attempt in 1..5 do
    with true <- session_generation == state.generation,
         {:ok, reference} <- subscription_reference(state, native_id),
         {:ok, next_state} <- begin_recovery(state, reference, generation, attempt) do
      {:ok, next_state}
    else
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp decode_async_frame(
         %{
           "version" => 1,
           "event" => "subscription_status",
           "session_generation" => session_generation,
           "subscription_id" => native_id,
           "generation" => generation,
           "status" => "resubscribed",
           "continuity" => "unknown",
           "attempt" => attempt,
           "min_interval_s" => minimum,
           "max_interval_s" => maximum,
           "sdk_subscription_id" => sdk_id
         } = frame,
         _encoded_bytes,
         state
       )
       when map_size(frame) == 11 and is_binary(native_id) and is_integer(generation) and
              generation > 1 and is_integer(attempt) and attempt in 1..5 and
              is_integer(minimum) and minimum in 0..65_535 and is_integer(maximum) and
              maximum in 1..65_535 and minimum <= maximum and is_integer(sdk_id) and
              sdk_id in 0..0xFFFFFFFF do
    with true <- session_generation == state.generation,
         {:ok, reference} <- Map.fetch(state.subscription_ids, {native_id, generation}),
         {:ok, next_state} <-
           finish_recovery(state, reference, generation, attempt, minimum, maximum, sdk_id) do
      {:ok, next_state}
    else
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp decode_async_frame(
         %{
           "version" => 1,
           "event" => "subscription_report",
           "session_generation" => session_generation,
           "subscription_id" => native_id,
           "generation" => generation,
           "report_sequence" => sequence,
           "kind" => kind,
           "value" => value,
           "metadata" => metadata
         } = frame,
         encoded_bytes,
         state
       )
       when map_size(frame) == 9 and is_binary(native_id) and is_integer(generation) and
              generation > 0 and is_integer(sequence) and sequence > 0 and
              kind in ["attribute", "event"] and is_map(metadata) do
    key = {native_id, generation}

    with true <- session_generation == state.generation,
         {:ok, reference} <- Map.fetch(state.subscription_ids, key),
         {:ok, delivery} <- Wire.subscription(kind, value, metadata),
         true <- delivery_path_matches?(delivery, Map.fetch!(state.subscriptions, reference)),
         {:ok, registered} <- register_report(state, reference, sequence, encoded_bytes),
         {:ok, next_state} <-
           admit_report(registered, reference, delivery, sequence, encoded_bytes) do
      {:ok, next_state}
    else
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp decode_async_frame(
         %{
           "version" => 1,
           "event" => "stream_retired",
           "session_generation" => session_generation,
           "subscription_id" => native_id,
           "generation" => generation,
           "last_report_sequence" => last_sequence
         } = frame,
         _encoded_bytes,
         state
       )
       when map_size(frame) == 6 and is_binary(native_id) and is_integer(generation) and
              generation > 0 and is_integer(last_sequence) and last_sequence >= 0 do
    key = {native_id, generation}

    with true <- session_generation == state.generation,
         {:ok, reference} <- Map.fetch(state.subscription_ids, key) do
      retire_stream_generation(state, reference, generation, last_sequence)
    else
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp decode_async_frame(
         %{"version" => 1, "id" => id, "ok" => true, "result" => nil} = frame,
         _bytes,
         state
       )
       when map_size(frame) == 4 and is_binary(id) do
    case Map.pop(state.internal_requests, id) do
      {nil, _} -> {:error, Error.new(:invalid_frame)}
      {_reference, requests} -> {:ok, %{state | internal_requests: requests}}
    end
  end

  defp decode_async_frame(
         %{
           "version" => 1,
           "event" => "subscription_error",
           "session_generation" => session_generation,
           "subscription_id" => native_id,
           "generation" => generation,
           "error" => raw_error
         } = frame,
         _encoded_bytes,
         state
       )
       when map_size(frame) == 6 and is_binary(native_id) and is_integer(generation) and
              generation > 0 do
    key = {native_id, generation}

    with true <- session_generation == state.generation,
         {:ok, reference} <- Map.fetch(state.subscription_ids, key),
         {:ok, error} <- Wire.error(raw_error),
         %{status: status} = subscription <- Map.fetch!(state.subscriptions, reference),
         true <- status in [:active, :establishing, :recovering, :closing],
         false <- subscription.native_terminal_received do
      if status != :closing do
        send(subscription.receiver, {:wotex_matter, reference, {:error, error}})
      end

      closing =
        state
        |> put_in([:subscriptions, reference, :status], :closing)
        |> put_in([:subscriptions, reference, :native_terminal_received], true)
        |> put_in(
          [:subscriptions, reference, :close_result],
          if(status == :closing, do: subscription.close_result, else: error.code)
        )

      {:ok, closing}
    else
      _ -> {:error, Error.new(:invalid_frame)}
    end
  end

  defp decode_async_frame(_, _, _), do: {:error, Error.new(:invalid_frame)}

  defp send_frame(port, frame) do
    case Request.encode(frame) do
      {:ok, encoded} when byte_size(encoded) + 1 <= @maximum_line_bytes + 1 ->
        Port.command(port, [encoded, ?\n], [:nosuspend])

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp send_request_frame(port, frame, deadline, lease \\ nil) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))
    frame = Map.put(frame, "timeout_ms", min(frame["timeout_ms"], remaining))

    case Request.encode(frame) do
      {:ok, encoded} when byte_size(encoded) + 1 <= @maximum_line_bytes + 1 ->
        if System.monotonic_time(:millisecond) >= deadline,
          do: {:error, :timeout},
          else: submit_request(port, encoded, lease)

      _ ->
        {:error, :invalid_request}
    end
  rescue
    _ -> {:error, :transport_closed}
  end

  defp submit_request(port, encoded, lease) do
    case Admission.mark_submission(lease) do
      :ok ->
        if Port.command(port, [encoded, ?\n], [:nosuspend]) do
          :ok
        else
          Admission.clear_submission(lease)
          {:error, :transport_closed}
        end

      :cancelled ->
        {:error, :timeout}
    end
  rescue
    ArgumentError ->
      Admission.clear_submission(lease)
      {:error, :transport_closed}
  end

  defp flow_frame(generation),
    do: %{"version" => 1, "event" => "flow_open", "session_generation" => generation}

  defp open_frame(options) do
    %{
      "version" => 1,
      "id" => "1",
      "operation" => "open",
      "parameters" => %{
        "lifecycle" => options.lifecycle,
        "storage_path" => options.storage_path,
        "storage_mode" => options.storage_mode,
        "authority" => options.authority,
        "vendor_id" => options.vendor_id,
        "fabric_id" => options.fabric_id,
        "controller_node_id" => options.controller_node_id,
        "paa_trust_store" => options.paa_trust_store
      },
      "timeout_ms" => options.timeout
    }
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      key = if is_atom(key), do: Atom.to_string(key), else: key
      {key, stringify_keys(value)}
    end)
  end

  defp stringify_keys(values) when is_list(values), do: Enum.map(values, &stringify_keys/1)
  defp stringify_keys({:context, id}) when is_integer(id), do: ["context", id]
  defp stringify_keys(value), do: value

  defp establish_subscription(result, subscription, state) do
    current = Map.get(state.subscriptions, subscription.reference)
    receiver_alive = Process.alive?(subscription.receiver)
    owner_alive = is_nil(subscription.stream_owner) or Process.alive?(subscription.stream_owner)

    if match?(%{status: :establishing}, current) and receiver_alive and owner_alive do
      decode_subscription_result(result, subscription, state)
    else
      error = Error.new(if receiver_alive, do: :owner_closed, else: :receiver_closed)
      {:error, error, drop_subscription(state, subscription.reference)}
    end
  end

  defp decode_subscription_result(
         %{
           "subscription_id" => native_id,
           "generation" => generation,
           "min_interval_s" => minimum,
           "max_interval_s" => maximum,
           "sdk_subscription_id" => sdk_id
         } = result,
         subscription,
         state
       )
       when map_size(result) == 5 and native_id == subscription.native_id and
              generation == subscription.generation and is_integer(minimum) and
              minimum in 0..65_535 and is_integer(maximum) and maximum in 1..65_535 and
              minimum <= maximum and is_integer(sdk_id) and sdk_id in 0..0xFFFFFFFF do
    active =
      state
      |> put_in([:subscriptions, subscription.reference, :status], :active)
      |> put_in([:subscriptions, subscription.reference, :min_interval_s], minimum)
      |> put_in([:subscriptions, subscription.reference, :max_interval_s], maximum)
      |> put_in([:subscriptions, subscription.reference, :sdk_subscription_id], sdk_id)

    emit_subscription(:open, subscription.kind, :ok)

    handle = %Subscription{
      pid: self(),
      reference: subscription.reference,
      generation: subscription.handle_generation
    }

    {:ok, handle, active}
  end

  defp decode_subscription_result(_, subscription, state),
    do: {:error, Error.new(:invalid_frame), drop_subscription(state, subscription.reference)}

  defp put_subscription(state, subscription) do
    key = {subscription.native_id, subscription.generation}

    {:ok, ledger} =
      ReportLedger.open(state.report_ledger, {subscription.reference, subscription.generation})

    %{
      state
      | report_ledger: ledger,
        subscriptions: Map.put(state.subscriptions, subscription.reference, subscription),
        subscription_ids: Map.put(state.subscription_ids, key, subscription.reference),
        subscription_monitors:
          state.subscription_monitors
          |> Map.put(subscription.monitor, subscription.reference)
          |> put_stream_monitor(subscription)
    }
  end

  defp subscription_reference(state, native_id) do
    references =
      for {reference, %{native_id: ^native_id}} <- state.subscriptions,
          do: reference

    case references do
      [reference] -> {:ok, reference}
      _ -> :error
    end
  end

  defp begin_recovery(state, reference, generation, attempt) do
    subscription = Map.fetch!(state.subscriptions, reference)

    cond do
      subscription.resubscribe and subscription.status == :active and
        generation == subscription.generation + 1 and
        attempt == 1 and is_nil(subscription.retiring_generation) ->
        recovering = %{
          subscription
          | status: :recovering,
            retiring_generation: subscription.generation,
            retiring_last_report_sequence: subscription.last_report_sequence,
            generation: generation,
            recovery_attempt: attempt,
            last_report_sequence: 0
        }

        transitioned =
          state
          |> put_in([:subscriptions, reference], recovering)
          |> put_in([:subscription_ids, {subscription.native_id, generation}], reference)

        {:ok, ledger} = ReportLedger.open(transitioned.report_ledger, {reference, generation})
        transitioned = %{transitioned | report_ledger: ledger}

        deliver_subscription_status(transitioned, reference, :resubscribing, %{
          continuity: :lost,
          generation: generation,
          attempt: attempt
        })

      subscription.status == :recovering and generation == subscription.generation and
          attempt == subscription.recovery_attempt + 1 ->
        recovering = put_in(state.subscriptions[reference].recovery_attempt, attempt)

        deliver_subscription_status(recovering, reference, :resubscribing, %{
          continuity: :lost,
          generation: generation,
          attempt: attempt
        })

      true ->
        :error
    end
  end

  defp finish_recovery(state, reference, generation, attempt, minimum, maximum, sdk_id) do
    subscription = Map.fetch!(state.subscriptions, reference)

    if subscription.status == :recovering and generation == subscription.generation and
         attempt == subscription.recovery_attempt and is_nil(subscription.retiring_generation) do
      case deliver_subscription_status(state, reference, :resubscribed, %{
             continuity: :unknown,
             generation: generation,
             attempt: attempt,
             min_interval_s: minimum,
             max_interval_s: maximum,
             sdk_subscription_id: sdk_id
           }) do
        {:ok, delivered} ->
          active =
            delivered
            |> put_in([:subscriptions, reference, :status], :active)
            |> put_in([:subscriptions, reference, :min_interval_s], minimum)
            |> put_in([:subscriptions, reference, :max_interval_s], maximum)
            |> put_in([:subscriptions, reference, :sdk_subscription_id], sdk_id)

          {:ok, active}

        {:overflow, closing} ->
          {:ok, closing}
      end
    else
      :error
    end
  end

  defp deliver_subscription_status(state, reference, status, metadata) do
    subscription = Map.fetch!(state.subscriptions, reference)

    case Process.info(subscription.receiver, :message_queue_len) do
      {:message_queue_len, length} when length < subscription.queue_limit ->
        send(subscription.receiver, {:wotex_matter, reference, {:status, status, metadata}})
        emit_subscription(:deliver, subscription.kind, status)
        {:ok, state}

      _ ->
        error = Error.new(:receiver_overflow)
        send(subscription.receiver, {:wotex_matter, reference, {:error, error}})
        {:overflow, cancel_subscription(state, reference, :receiver_overflow)}
    end
  end

  defp retire_stream_generation(state, reference, generation, last_sequence) do
    subscription = Map.fetch!(state.subscriptions, reference)

    cond do
      subscription.retiring_generation == generation and
        subscription.retiring_last_report_sequence == last_sequence and
          subscription.status in [:recovering, :closing] ->
        transitioned =
          state
          |> consume_retired_reports(reference, generation, last_sequence)
          |> update_in([:subscription_ids], &Map.delete(&1, {subscription.native_id, generation}))
          |> put_in([:subscriptions, reference, :retiring_generation], nil)
          |> put_in([:subscriptions, reference, :retiring_last_report_sequence], nil)

        {:ok, transitioned}

      subscription.status == :closing and subscription.generation == generation and
        subscription.last_report_sequence == last_sequence and
          is_nil(subscription.retiring_generation) ->
        retired =
          state
          |> consume_retired_reports(reference, generation, last_sequence)
          |> retire_subscription(reference)

        {:ok, retired}

      true ->
        {:error, Error.new(:invalid_frame)}
    end
  end

  defp drop_subscription(state, reference) do
    case Map.pop(state.subscriptions, reference) do
      {nil, _} ->
        state

      {subscription, subscriptions} ->
        Process.demonitor(subscription.monitor, [:flush])
        if subscription.stream_monitor, do: Process.demonitor(subscription.stream_monitor, [:flush])
        owners = stop_stream_owners([subscription])
        await_stream_owners(owners, System.monotonic_time(:millisecond) + @cleanup_timeout)

        ledger =
          Enum.reduce(state.report_ledger.streams, state.report_ledger, fn
            {{^reference, _} = stream, last}, current ->
              {:ok, retired} = ReportLedger.retire(current, stream, last)
              retired

            _, current ->
              current
          end)

        subscription_ids =
          state.subscription_ids
          |> Enum.reject(fn {_key, owner} -> owner == reference end)
          |> Map.new()

        %{
          state
          | report_ledger: ledger,
            subscriptions: subscriptions,
            subscription_ids: subscription_ids,
            subscription_monitors:
              state.subscription_monitors
              |> Map.delete(subscription.monitor)
              |> Map.delete(subscription.stream_monitor)
        }
    end
  end

  defp put_stream_monitor(monitors, %{stream_monitor: nil}), do: monitors

  defp put_stream_monitor(monitors, subscription),
    do: Map.put(monitors, subscription.stream_monitor, subscription.reference)

  defp stop_stream_owners(subscriptions) do
    for %{stream_owner: owner} <- subscriptions, is_pid(owner) do
      monitor = Process.monitor(owner)
      Process.exit(owner, :kill)
      {owner, monitor}
    end
  end

  defp await_stream_owners(owners, deadline) do
    Enum.each(owners, fn {owner, monitor} ->
      receive do
        {:DOWN, ^monitor, :process, ^owner, _} -> :ok
      after
        max(0, deadline - System.monotonic_time(:millisecond)) ->
          Process.demonitor(monitor, [:flush])
      end
    end)
  end

  defp retire_subscription(state, reference) do
    subscription = Map.get(state.subscriptions, reference)
    closed = MapSet.put(state.closed_references, reference)

    if subscription do
      emit_subscription(:close, subscription.kind, subscription.close_result)
    end

    state
    |> drop_subscription(reference)
    |> Map.put(:closed_references, closed)
  end

  defp validate_owned_subscription(%Subscription{} = subscription, state) do
    cond do
      not valid_subscription_handle?(subscription, self()) ->
        :error

      MapSet.member?(state.closed_references, subscription.reference) ->
        :ok

      true ->
        case Map.fetch(state.subscriptions, subscription.reference) do
          {:ok, current} when current.handle_generation == subscription.generation -> :ok
          _ -> :error
        end
    end
  end

  defp valid_subscription_handle?(%Subscription{} = subscription, pid),
    do:
      subscription.pid == pid and is_reference(subscription.reference) and
        is_integer(subscription.generation) and subscription.generation > 0

  defp valid_subscription_handle?(_, _), do: false

  defp admit_report(state, reference, delivery, sequence, encoded_bytes) do
    subscription = Map.fetch!(state.subscriptions, reference)

    cond do
      subscription.status == :establishing ->
        if length(subscription.buffered) < subscription.queue_limit do
          buffered = subscription.buffered ++ [{delivery, sequence, encoded_bytes}]
          {:ok, put_in(state.subscriptions[reference].buffered, buffered)}
        else
          {:ok, overflow_subscription(state, reference, sequence, encoded_bytes)}
        end

      subscription.status == :active ->
        {:ok, deliver_report(state, reference, delivery, sequence, encoded_bytes)}

      subscription.status == :closing ->
        {:ok, acknowledge_report(state, sequence, encoded_bytes)}

      true ->
        {:error, Error.new(:invalid_frame)}
    end
  end

  defp flush_subscription(state, reference) do
    case Map.fetch(state.subscriptions, reference) do
      {:ok, %{status: :active, buffered: buffered}} ->
        state = put_in(state.subscriptions[reference].buffered, [])

        Enum.reduce(buffered, state, fn {delivery, sequence, bytes}, acc ->
          if Map.has_key?(acc.subscriptions, reference),
            do: deliver_report(acc, reference, delivery, sequence, bytes),
            else: acknowledge_report(acc, sequence, bytes)
        end)

      _ ->
        state
    end
  end

  defp deliver_report(state, reference, delivery, sequence, encoded_bytes) do
    subscription = Map.fetch!(state.subscriptions, reference)
    receiver = subscription.stream_owner || subscription.receiver
    limit = if subscription.stream_owner, do: 64, else: subscription.queue_limit

    case Process.info(receiver, :message_queue_len) do
      {:message_queue_len, length} when length < limit ->
        pending = Map.fetch!(state.report_ledger.pending, sequence)

        envelope = %Wotex.Matter.Native.Delivery{
          connection: self(),
          generation: state.generation,
          reference: reference,
          sequence: sequence,
          token: pending.token,
          value: delivery
        }

        send(receiver, {:wotex_matter, reference, envelope})
        state

      _ ->
        overflow_subscription(state, reference, sequence, encoded_bytes)
    end
  end

  defp overflow_subscription(state, reference, sequence, encoded_bytes) do
    subscription = Map.fetch!(state.subscriptions, reference)
    error = Error.new(:receiver_overflow)
    send(subscription.receiver, {:wotex_matter, reference, {:error, error}})

    state
    |> acknowledge_report(sequence, encoded_bytes)
    |> cancel_subscription(reference, :receiver_overflow)
  end

  defp acknowledge_report(state, sequence, encoded_bytes) do
    case Map.fetch(state.report_ledger.pending, sequence) do
      {:ok, %{bytes: ^encoded_bytes, stream: stream, token: token}} ->
        case ReportLedger.consume(state.report_ledger, stream, sequence, token) do
          {:ok, ledger} -> advance_acknowledgement(%{state | report_ledger: ledger})
          :ignore -> state
        end

      _ ->
        state
    end
  end

  defp register_report(state, reference, sequence, encoded_bytes) do
    stream = {reference, Map.fetch!(state.subscriptions, reference).generation}

    with {:ok, ledger} <-
           ReportLedger.register(state.report_ledger, stream, sequence, encoded_bytes, make_ref()) do
      {:ok,
       state
       |> Map.put(:report_ledger, ledger)
       |> put_in([:subscriptions, reference, :last_report_sequence], sequence)}
    end
  end

  defp consume_retired_reports(state, reference, generation, last_sequence) do
    {:ok, ledger} = ReportLedger.retire(state.report_ledger, {reference, generation}, last_sequence)
    advance_acknowledgement(%{state | report_ledger: ledger})
  end

  defp advance_acknowledgement(state) do
    case ReportLedger.advance(state.report_ledger) do
      {nil, _} ->
        state

      {ack, ledger} ->
        frame = %{
          "version" => 1,
          "event" => "report_ack",
          "session_generation" => state.generation,
          "report_sequence" => ack.report_sequence,
          "acknowledged_bytes" => ack.acknowledged_bytes
        }

        if send_frame(state.port, frame),
          do: %{state | report_ledger: ledger},
          else: fail_native_input(state)
    end
  end

  defp delivery_path_matches?({:ok, _, %{kind: kind, path: path}}, subscription) do
    kind == subscription.kind and
      Enum.any?(subscription.paths, fn expected ->
        expected.fabric_id == path.fabric_id and expected.node_id == path.node_id and
          expected.endpoint == path.endpoint and expected.cluster == path.cluster and
          expected.member == path.member
      end)
  end

  defp cancel_subscription(state, reference, result) do
    case Map.fetch(state.subscriptions, reference) do
      {:ok, %{status: status} = subscription}
      when status in [:active, :establishing, :recovering] ->
        state =
          state
          |> put_in([:subscriptions, reference, :status], :closing)
          |> put_in([:subscriptions, reference, :close_result], result)

        owners = stop_stream_owners([subscription])
        await_stream_owners(owners, System.monotonic_time(:millisecond) + @cleanup_timeout)

        if status == :establishing do
          # Registration has no confirmed native handle, and its SDK wait may
          # block control input. Termination bounds cleanup without assuming
          # that registration succeeded.
          fail_native_input(state)
        else
          case take_request_id(state, "unsubscribe") do
            {:ok, id, next_state} ->
              submit_cancellation(next_state, subscription, reference, result, id)

            :exhausted ->
              fail_native_input(state)
          end
        end

      _ ->
        state
    end
  end

  defp submit_cancellation(state, subscription, reference, result, id) do
    frame = %{
      "version" => 1,
      "id" => id,
      "operation" => "unsubscribe",
      "parameters" => %{
        "subscription_id" => subscription.native_id,
        "generation" => subscription.generation
      },
      "timeout_ms" => @cleanup_timeout
    }

    if send_frame(state.port, frame) do
      state
      |> put_in([:subscriptions, reference, :status], :closing)
      |> put_in([:subscriptions, reference, :close_result], result)
      |> Map.put(:internal_requests, Map.put(state.internal_requests, id, reference))
    else
      fail_native_input(state)
    end
  end

  defp fail_native_input(state) do
    if Map.get(state, :channel_failed, false) do
      state
    else
      send(self(), {:native_input_failed, state.generation})
      Map.put(state, :channel_failed, true)
    end
  end

  defp close_port(port) when is_port(port) do
    deadline = System.monotonic_time(:millisecond) + @cleanup_timeout

    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        # Reap the exact owned child before dropping its Port identity. A failed
        # native operation may leave the child unable to observe closed stdin.
        System.cmd("/bin/kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)
        if Port.info(port), do: Port.close(port)
        await_port_closed(port, deadline)

      nil ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp close_port(_), do: :ok

  defp await_close_exit(%{port: port, owner_monitor: monitor, call_deadline: deadline}) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, Error.new(:timeout)}
    else
      receive do
        {^port, {:exit_status, 0}} ->
          if System.monotonic_time(:millisecond) <= deadline,
            do: await_port_closed(port, deadline),
            else: {:error, Error.new(:timeout)}

        {^port, {:exit_status, status}} ->
          {:error, Error.new(:invalid_transport_return, nil, %{exit_status: status})}

        {^port, {:data, _}} ->
          {:error, Error.new(:invalid_frame)}

        {:DOWN, ^monitor, :process, _, _} ->
          {:error, Error.new(:owner_closed)}
      after
        remaining -> {:error, Error.new(:timeout)}
      end
    end
  end

  defp await_port_closed(port, deadline) do
    monitor = :erlang.monitor(:port, port)

    try do
      receive do
        {:DOWN, ^monitor, :port, ^port, _} -> await_port_release(port, deadline)
      after
        max(0, deadline - System.monotonic_time(:millisecond)) ->
          {:error, Error.new(:timeout)}
      end
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  defp await_port_release(port, deadline) do
    cond do
      Port.info(port) == nil ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, Error.new(:timeout)}

      true ->
        receive do
        after
          1 -> await_port_release(port, deadline)
        end
    end
  end

  defp emit_subscription(event, kind, result) do
    :telemetry.execute(
      [:wotex, :matter, :subscription, event],
      %{count: 1},
      %{kind: kind, result: result}
    )
  end
end
