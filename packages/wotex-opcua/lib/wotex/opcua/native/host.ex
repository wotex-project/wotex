defmodule Wotex.OPCUA.Native.Host do
  @moduledoc """
  Owns a verified native bootstrap process and its independent custody guardian.

  `start_link/1` accepts the explicit executable identities described by
  `Wotex.OPCUA.Native.HostOptions`. Its caller owns this temporary child. A native
  Session must start the host itself, so a short-lived establishment worker does
  not become the native process owner. Source hashing runs in one linked worker;
  hashing, spawn and readiness share the deadline captured at API entry.

  The successful return includes the decoded process readiness and the BEAM
  monotonic receive sample. This bootstrap does not send credentials or
  protocol requests at startup. Its internal `request/4` path admits at most 64
  outstanding service requests from monitored callers, correlates each native
  success or request-scoped failure by identity and replenishes credit for every
  validated output line. A caller timeout or caller death retires the request
  locally and sends a bounded native `cancel` control; a sent Write or Call keeps
  unknown effect. Browse pages map a native continuation to an owner-bound
  reference; only one is live per native Session.

  A terminal control, invalid or unsolicited output, a response for another
  generation, failed control cleanup or native exit ends the generation. Every
  unanswered request then receives one error whose effect is `:unknown` only for
  a sent Write or Call. When no request is waiting, the owner receives one
  `{:wotex_opcua_native, pid, {:error, error}}` message.

  Fallible initialization is unlinked; successful readiness requires a one-use
  claim from the original owner before its original deadline. That claim links
  the child to its owner. Owner death, an expired claim, failed initialization
  and OTP termination close the owned Port.
  The independently executing guardian then closes and reaps its SDK child under
  the separate 500 ms custody budget. Closing a Port alone is not an observed
  guardian exit status or evidence of remote Session deletion. The child
  specification is temporary: no automatic reconnect or replay occurs.
  """

  use GenServer

  alias Wotex.OPCUA.Browse.Continuation
  alias Wotex.OPCUA.{Error, Subscription}
  alias Wotex.OPCUA.Native.{Executable, Frame, HostOptions, Ready}

  @capacity 64
  @continuations 64
  @closed_handles 1024
  @control_ms 1000
  @maximum_line 131_072
  @mutations ~w(write call)
  @services ~w(read health write call)

  @typedoc "Process readiness and its separately captured BEAM monotonic receive time."
  @type sample :: %{ready: Ready.t(), received_at_ms: integer()}

  @doc "Starts a caller-owned bootstrap and returns its verified readiness before service admission."
  @spec start_link(term()) :: {:ok, pid(), sample()} | {:error, Error.t()}
  def start_link(options) do
    entered = System.monotonic_time(:millisecond)

    with {:ok, settings} <- HostOptions.new(options) do
      token = make_ref()
      deadline = entered + settings.timeout

      generation = owner_generation()

      case GenServer.start(__MODULE__, {settings, self(), token, deadline, generation},
             timeout: settings.timeout + 500
           ) do
        {:ok, pid} ->
          claim(pid, token, deadline)

        {:error, {:shutdown, %Error{} = error}} ->
          {:error, error}

        {:error, _} ->
          {:error, Error.new(:native_startup_failed)}
      end
    end
  catch
    :exit, _ -> {:error, Error.new(:native_startup_failed)}
  end

  @doc """
  Sends one bounded request to the native generation.

  `open` and `close` are owner-only. Read, health, Write and Call requests may
  come from any process; each caller is monitored while its request is open.
  """
  @spec request(pid(), String.t(), map(), pos_integer()) :: {:ok, term()} | {:error, Error.t()}
  def request(host, operation, parameters, timeout)
      when is_pid(host) and is_integer(timeout) and timeout in 1..60_000 do
    deadline = System.monotonic_time(:millisecond) + timeout

    GenServer.call(
      host,
      {__MODULE__, :request, operation, parameters, timeout, deadline},
      timeout + 100
    )
  catch
    :exit, reason -> {:error, exit_error(reason, operation)}
  end

  def request(_, _, _, _), do: {:error, Error.new(:invalid_native_frame, :request)}

  @doc """
  Establishes one native subscription and binds its reports to `receiver`.

  The handle is returned after the native owner accepted the server subscription
  and MonitoredItem. The receiver is monitored; its death, a full receiver queue
  (`max_queue` messages) or one terminal report ends that subscription.
  """
  @spec subscribe(pid(), map(), pid(), pos_integer(), pos_integer()) ::
          {:ok, Subscription.t()} | {:error, Error.t()}
  def subscribe(host, parameters, receiver, max_queue, timeout)
      when is_pid(host) and is_map(parameters) and is_pid(receiver) and is_integer(max_queue) and
             max_queue in 1..10_000 and is_integer(timeout) and timeout in 1..60_000 do
    deadline = System.monotonic_time(:millisecond) + timeout

    GenServer.call(
      host,
      {__MODULE__, :subscribe, parameters, receiver, max_queue, timeout, deadline},
      timeout + 100
    )
  catch
    :exit, reason -> {:error, exit_error(reason, "subscribe")}
  end

  def subscribe(_, _, _, _, _), do: {:error, Error.new(:invalid_value)}

  @doc """
  Cancels one subscription on this owner.

  A handle whose owner has already stopped, or one this owner recently closed,
  returns `:ok` without protocol I/O.
  """
  @spec unsubscribe(pid(), Subscription.t(), pos_integer()) :: :ok | {:error, Error.t()}
  def unsubscribe(host, %Subscription{pid: host} = subscription, timeout)
      when is_pid(host) and is_integer(timeout) and timeout in 1..60_000 do
    if Process.alive?(host) do
      deadline = System.monotonic_time(:millisecond) + timeout

      GenServer.call(
        host,
        {__MODULE__, :unsubscribe, subscription, timeout, deadline},
        timeout + @control_ms + 100
      )
    else
      :ok
    end
  catch
    :exit, {reason, _} when reason in [:noproc, :normal] -> :ok
    :exit, reason -> {:error, exit_error(reason, "unsubscribe")}
  end

  def unsubscribe(_, _, _), do: {:error, Error.new(:invalid_subscription)}

  @doc "Starts one bounded Browse page and binds any native token to this owner."
  @spec browse_page(pid(), map(), map(), pos_integer()) ::
          {:ok, map()} | {:error, Error.t()}
  def browse_page(host, parameters, limits, timeout)
      when is_pid(host) and is_map(parameters) and is_map(limits) and
             is_integer(timeout) and timeout in 1..60_000 do
    deadline = System.monotonic_time(:millisecond) + timeout

    GenServer.call(
      host,
      {__MODULE__, :browse_page, parameters, limits, timeout, deadline},
      timeout + @control_ms + 100
    )
  catch
    :exit, reason -> {:error, exit_error(reason, "browse")}
  end

  def browse_page(_, _, _, _), do: {:error, Error.new(:invalid_native_handle)}

  @doc "Consumes one owner-bound handle for the next native Browse page."
  @spec browse_next(pid(), Continuation.t(), pos_integer()) ::
          {:ok, map()} | {:error, Error.t()}
  def browse_next(host, handle, timeout), do: continue(host, handle, timeout, :next)

  @doc "Releases one owner-bound native server continuation."
  @spec browse_release(pid(), Continuation.t(), pos_integer()) :: :ok | {:error, Error.t()}
  def browse_release(host, handle, timeout) do
    case continue(host, handle, timeout, :release) do
      {:ok, nil} -> :ok
      error -> error
    end
  end

  defp continue(host, %Continuation{} = handle, timeout, operation)
       when is_pid(host) and is_integer(timeout) and timeout in 1..60_000 do
    call_timeout =
      if operation == :release,
        do: min(timeout, @control_ms) + 1100,
        else: timeout + @control_ms + 1100

    GenServer.call(host, {__MODULE__, :browse_continue, handle, timeout, operation}, call_timeout)
  catch
    :exit, reason -> {:error, exit_error(reason, "browse_next")}
  end

  defp continue(_, _, _, _), do: {:error, Error.new(:invalid_continuation)}

  @doc "Returns a temporary OTP child specification with a bounded local shutdown."
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: 1000,
      type: :worker
    }
  end

  @impl GenServer
  def init({settings, owner, token, deadline, generation}) do
    Process.flag(:trap_exit, true)
    monitor = Process.monitor(owner)

    with :ok <- verify(settings, owner, monitor, deadline),
         :ok <- budget(deadline),
         :ok <- owner_alive(owner),
         {:ok, port} <- spawn_native(settings) do
      case await_ready(port, owner, monitor, deadline, <<>>) do
        {:ok, sample} ->
          {:ok,
           %{
             port: port,
             owner: owner,
             monitor: monitor,
             token: token,
             sample: sample,
             deadline: deadline,
             generation: generation,
             pending: %{},
             monitors: %{},
             controls: %{},
             subscriptions: %{},
             tokens: %{},
             receivers: %{},
             discarding: MapSet.new(),
             closed: {:queue.new(), MapSet.new()},
             input: <<>>,
             next_id: 1,
             continuations: %{},
             expired: {:queue.new(), MapSet.new()},
             closing: false,
             credit_sequence: 0,
             claim_timer: :erlang.start_timer(remaining(deadline), self(), :claim_expired),
             claimed: false
           }}

        {:error, error} ->
          close_port(port)
          {:stop, {:shutdown, error}}
      end
    else
      {:error, error} -> {:stop, {:shutdown, error}}
    end
  end

  @impl GenServer
  def handle_call(
        {__MODULE__, :claim, token},
        {owner, _},
        %{token: token, owner: owner, claimed: false} = state
      ) do
    with :ok <- budget(state.deadline),
         :ok <- owner_alive(owner) do
      Process.link(owner)
      Process.cancel_timer(state.claim_timer)
      {:reply, {:ok, state.sample}, %{state | claimed: true}}
    else
      {:error, error} -> {:stop, :normal, {:error, error}, state}
    end
  end

  def handle_call(
        {__MODULE__, :request, operation, parameters, timeout, deadline},
        {caller, _} = from,
        %{claimed: true, closing: false} = state
      )
      when is_map(parameters) do
    cond do
      operation in ["open", "close"] and caller != state.owner ->
        {:reply, {:error, Error.new(:invalid_native_handle)}, state}

      operation in ["browse_next", "browse_release"] ->
        {:reply, {:error, Error.new(:invalid_continuation)}, state}

      operation == "close" ->
        start_close(state, from, timeout, deadline)

      operation not in ["open", "browse" | @services] ->
        {:reply, {:error, Error.new(:unsupported_protocol)}, state}

      true ->
        admit(state, from, operation, parameters, timeout, deadline, nil)
    end
  end

  def handle_call(
        {__MODULE__, :browse_page, parameters, limits, timeout, deadline},
        {owner, _} = from,
        %{owner: owner, claimed: true, closing: false} = state
      ) do
    if chains(state) < @continuations and outstanding(state) < @capacity and
         valid_browse_limits?(limits) do
      admit(
        state,
        from,
        "browse",
        Map.put(parameters, "allow_continuation", true),
        timeout,
        deadline,
        %{kind: :browse_page, pages: 0, references: 0, bytes: 0, limits: limits}
      )
    else
      {:reply, {:error, Error.new(:busy)}, state}
    end
  end

  def handle_call(
        {__MODULE__, :browse_continue, %Continuation{} = handle, timeout, operation},
        {owner, _} = from,
        %{owner: owner, claimed: true, closing: false} = state
      ) do
    owned = handle.pid == self() and handle.generation == state.generation

    case Map.fetch(state.continuations, handle.reference) do
      :error when owned ->
        {:reply, expired_continuation(state, handle, operation), state}

      {:ok, _} when map_size(state.pending) >= @capacity ->
        {:reply, {:error, %{Error.new(:busy) | details: %{phase: :admission}}}, state}

      {:ok, cursor} when owned ->
        cancel_timer(cursor.timer)
        state = %{state | continuations: Map.delete(state.continuations, handle.reference)}
        continue_cursor(state, from, cursor, timeout, operation)

      _ ->
        {:reply, {:error, Error.new(:invalid_continuation)}, state}
    end
  end

  def handle_call(
        {__MODULE__, :subscribe, parameters, receiver, max_queue, timeout, deadline},
        from,
        %{claimed: true, closing: false} = state
      ) do
    admit(state, from, "subscribe", parameters, timeout, deadline, %{
      kind: :subscribe,
      receiver: receiver,
      max_queue: max_queue
    })
  end

  def handle_call(
        {__MODULE__, :unsubscribe, %Subscription{} = subscription, timeout, deadline},
        from,
        %{claimed: true} = state
      ) do
    reference = subscription.reference
    {_, closed} = state.closed

    cond do
      subscription.generation != state.generation ->
        {:reply, {:error, Error.new(:invalid_subscription)}, state}

      MapSet.member?(closed, reference) ->
        {:reply, :ok, state}

      not Map.has_key?(state.subscriptions, reference) ->
        {:reply, {:error, Error.new(:invalid_subscription)}, state}

      state.subscriptions[reference].closing ->
        {:noreply, update_in(state.subscriptions[reference].waiters, &[from | &1])}

      true ->
        state = put_in(state.subscriptions[reference].closing, true)
        token = state.subscriptions[reference].token

        admit(state, from, "unsubscribe", %{"subscription" => token}, timeout, deadline, %{
          kind: :unsubscribe,
          reference: reference
        })
    end
  end

  def handle_call(_, _, state), do: {:reply, {:error, Error.new(:invalid_native_handle)}, state}

  defp valid_browse_limits?(%{max_pages: pages, max_references: references})
       when pages in 1..64 and references in 1..4096,
       do: true

  defp valid_browse_limits?(_), do: false

  defp admit(state, from, operation, parameters, timeout, deadline, cursor) do
    if outstanding(state) >= @capacity or owed(state) >= @capacity do
      {:reply, {:error, %{Error.new(:busy) | details: %{phase: :admission}}}, state}
    else
      case emit(state, operation, parameters, timeout, deadline) do
        {:ok, id, state} ->
          {caller, _} = from
          now = System.monotonic_time(:millisecond)

          entry = %{
            from: from,
            operation: operation,
            cursor: cursor,
            deadline: deadline,
            requested_timeout: parameters["session_timeout_ms"],
            monitor: monitor(caller),
            timer:
              :erlang.start_timer(max(min(deadline - now, timeout), 0), self(), {:request, id}),
            replied: false
          }

          {:noreply,
           %{
             state
             | pending: Map.put(state.pending, id, entry),
               monitors: Map.put(state.monitors, entry.monitor, id)
           }}

        {:error, %Error{} = error, state} ->
          fail(state, error, from)
      end
    end
  end

  defp monitor(caller), do: Process.monitor(caller)

  # Cancels a timer and removes a timeout message that already fired.
  defp cancel_timer(timer) do
    Process.cancel_timer(timer)

    receive do
      {:timeout, ^timer, _} -> :ok
    after
      0 -> :ok
    end
  end

  defp outstanding(state), do: Enum.count(state.pending, fn {_, entry} -> not entry.replied end)

  # Each pending request and control still owes exactly one native output line.
  # Keeping that total within the credit window plus the 64-envelope native queue
  # means a burst of timed-out requests cannot overflow the native output.
  defp owed(state), do: map_size(state.pending) + map_size(state.controls)

  # Writes one request line; the first request carries the initial credit.
  defp emit(state, operation, parameters, timeout, deadline) do
    now = System.monotonic_time(:millisecond)
    id = Integer.to_string(state.next_id)
    state = %{state | next_id: state.next_id + 1}

    with {:ok, admission} <-
           Frame.admission(state.sample.ready, state.sample.received_at_ms, deadline, now, timeout),
         {:ok, frame} <-
           Frame.request(
             state.generation,
             id,
             operation,
             parameters,
             admission.timeout_ms,
             admission.deadline_ms
           ),
         {:ok, credit} <- initial_credit(state),
         :ok <- send_optional(state.port, credit),
         :ok <- send_frame(state.port, frame) do
      {:ok, id, %{state | credit_sequence: max(state.credit_sequence, 1)}}
    else
      {:error, %Error{} = error} -> {:error, error, state}
    end
  end

  # Admission and encoding failures precede native I/O; only Port loss ends the owner.
  defp fail(state, %Error{code: :native_process_terminated} = error, from) do
    GenServer.reply(from, {:error, error})
    terminate_generation(state, error)
  end

  defp fail(state, error, _), do: {:reply, {:error, error}, state}

  defp start_close(state, from, timeout, deadline) do
    case emit(state, "close", %{}, timeout, deadline) do
      {:ok, id, state} ->
        now = System.monotonic_time(:millisecond)

        control = %{
          kind: :close,
          from: from,
          timer: :erlang.start_timer(max(min(deadline - now, timeout), 0), self(), {:control, id})
        }

        {:noreply, %{state | closing: true, controls: Map.put(state.controls, id, control)}}

      {:error, error, state} ->
        {:reply, {:error, error}, state}
    end
  end

  # A retired request remains correlated until its native final response arrives.
  defp retire(state, id, entry, reply) do
    if reply, do: GenServer.reply(entry.from, reply)
    Process.demonitor(entry.monitor, [:flush])
    cancel_timer(entry.timer)
    pending = Map.put(state.pending, id, %{entry | replied: true})
    state = %{state | pending: pending, monitors: Map.delete(state.monitors, entry.monitor)}

    if entry.operation == "open",
      do: {:open_lost, state},
      else: send_cancel(state, id)
  end

  # Without room for another owed line the native deadline ends the target instead.
  defp send_cancel(state, _) when map_size(state.pending) + map_size(state.controls) >= 80,
    do: {:ok, state}

  defp send_cancel(state, target) do
    deadline = System.monotonic_time(:millisecond) + @control_ms

    case emit(state, "cancel", %{"target_id" => target}, @control_ms, deadline) do
      {:ok, id, state} ->
        control = %{
          kind: :cancel,
          target: target,
          timer: :erlang.start_timer(@control_ms, self(), {:control, id})
        }

        {:ok, %{state | controls: Map.put(state.controls, id, control)}}

      {:error, _, state} ->
        {:cancel_failed, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, monitor, :process, owner, _}, %{monitor: monitor, owner: owner} = state),
    do: stop_generation(state, Error.new(:native_owner_lost), false)

  def handle_info({:DOWN, monitor, :process, _, _}, %{receivers: receivers} = state)
      when is_map_key(receivers, monitor) do
    reference = Map.fetch!(receivers, monitor)
    state = %{state | receivers: Map.delete(receivers, monitor)}

    case close_internally(state, reference, :receiver_down) do
      {:ok, state} -> {:noreply, state}
      {:stop, error, state} -> terminate_generation(state, error)
    end
  end

  def handle_info({:DOWN, monitor, :process, _, _}, %{monitors: monitors} = state)
      when is_map_key(monitors, monitor) do
    id = Map.fetch!(monitors, monitor)
    after_retire(retire(state, id, Map.fetch!(state.pending, id), nil))
  end

  def handle_info(
        {:timeout, timer, :claim_expired},
        %{claim_timer: timer, claimed: false} = state
      ),
      do: {:stop, :normal, state}

  # Timers are cancelled and flushed when a request is answered.
  def handle_info({:timeout, _, {:request, id}}, %{pending: pending} = state)
      when is_map_key(pending, id) do
    %{replied: false} = entry = Map.fetch!(pending, id)
    error = effect(Error.new(:deadline_exceeded, :request), entry)
    after_retire(retire(state, id, entry, {:error, error}))
  end

  def handle_info({:timeout, _, {:control, id}}, %{controls: controls} = state)
      when is_map_key(controls, id),
      do: terminate_generation(state, Error.new(:cleanup_failed))

  # The original browse deadline releases a continuation nobody consumed.
  def handle_info(
        {:timeout, timer, {:continuation, reference}},
        %{continuations: continuations} = state
      )
      when is_map_key(continuations, reference) do
    case Map.pop!(continuations, reference) do
      {%{timer: ^timer} = cursor, continuations} ->
        state = %{state | continuations: continuations, expired: expire(state.expired, reference)}
        deadline = System.monotonic_time(:millisecond) + @control_ms

        case emit(state, "browse_release", %{"continuation" => cursor.token}, @control_ms, deadline) do
          {:ok, id, state} ->
            control = %{
              kind: :browse_release,
              timer: :erlang.start_timer(@control_ms, self(), {:control, id})
            }

            {:noreply, %{state | controls: Map.put(state.controls, id, control)}}

          {:error, error, state} ->
            terminate_generation(state, error)
        end

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    terminate_generation(
      state,
      Error.new(:native_process_terminated, nil, %{exit_status: status})
    )
  end

  def handle_info({port, {:data, bytes}}, %{port: port} = state) do
    input = state.input <> bytes
    lines(%{state | input: input})
  end

  def handle_info({:EXIT, port, _}, %{port: port} = state),
    do: terminate_generation(state, Error.new(:native_process_terminated))

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    close_port(state.port)
    :ok
  end

  defp after_retire({:ok, state}), do: {:noreply, state}

  defp after_retire({:open_lost, state}),
    do: stop_generation(state, Error.new(:deadline_exceeded, :request), false)

  defp after_retire({:cancel_failed, state}),
    do: terminate_generation(state, Error.new(:native_process_terminated))

  # Splits arbitrary Port chunks into complete lines without exceeding one frame.
  defp lines(state) do
    case :binary.match(state.input, "\n") do
      {offset, 1} when offset < @maximum_line ->
        size = offset + 1
        <<line::binary-size(^size), rest::binary>> = state.input

        case handle_line(%{state | input: rest}, line) do
          {:noreply, state} -> lines(state)
          stop -> stop
        end

      :nomatch when byte_size(state.input) < @maximum_line ->
        {:noreply, state}

      _ ->
        terminate_generation(state, Error.new(:invalid_native_frame))
    end
  end

  defp handle_line(state, line) do
    case Frame.classify(line, state.generation) do
      {:terminal, error} ->
        terminate_generation(state, error)

      {:response, id} ->
        response(state, id, line)

      {:report, token} ->
        report(state, token, line)

      {:error, error} ->
        terminate_generation(state, error)
    end
  end

  # Routes one validated report; credit returns before any follow-up request.
  defp report(state, token, line) do
    if Map.has_key?(state.tokens, token) or MapSet.member?(state.discarding, token) do
      case Frame.report(line, state.generation, token) do
        {:error, error} ->
          terminate_generation(state, error)

        decoded ->
          reference = Map.get(state.tokens, token)
          after_native(state, line, fn state -> route(state, reference, decoded) end)
      end
    else
      terminate_generation(state, Error.new(:invalid_native_frame))
    end
  end

  defp route(state, nil, _), do: {:ok, state}

  defp route(state, reference, decoded) do
    subscription = Map.fetch!(state.subscriptions, reference)

    cond do
      subscription.closing ->
        {:ok, state}

      match?({:error_report, _}, decoded) ->
        {:error_report, error} = decoded
        send(subscription.receiver, {:wotex_opcua, reference, {:error, error}})
        delivered(:error)
        {:ok, remove_subscription(state, reference, :terminal)}

      true ->
        {:data, value, metadata} = decoded

        case Process.info(subscription.receiver, :message_queue_len) do
          nil ->
            close_internally(state, reference, :receiver_down)

          {:message_queue_len, length} when length >= subscription.max_queue ->
            error = Error.new(:receiver_overflow)
            send(subscription.receiver, {:wotex_opcua, reference, {:error, error}})
            delivered(:overflow)
            close_internally(state, reference, :receiver_overflow)

          _ ->
            send(subscription.receiver, {:wotex_opcua, reference, {:ok, value, metadata}})
            delivered(:ok)
            {:ok, state}
        end
    end
  end

  defp delivered(result),
    do:
      :telemetry.execute([:wotex, :opcua, :subscription, :deliver], %{count: 1}, %{result: result})

  # Sends native cancellation for a subscription that no caller is waiting on.
  defp close_internally(state, reference, reason) do
    subscription = Map.fetch!(state.subscriptions, reference)

    if subscription.closing do
      {:ok, state}
    else
      state = put_in(state.subscriptions[reference].closing, true)
      state = put_in(state.subscriptions[reference].reason, reason)
      unsubscribe_control(state, subscription.token, reference)
    end
  end

  defp unsubscribe_control(state, token, reference) do
    deadline = System.monotonic_time(:millisecond) + @control_ms

    case emit(state, "unsubscribe", %{"subscription" => token}, @control_ms, deadline) do
      {:ok, id, state} ->
        control = %{
          kind: :unsubscribe,
          token: token,
          reference: reference,
          timer: :erlang.start_timer(@control_ms, self(), {:control, id})
        }

        {:ok, %{state | controls: Map.put(state.controls, id, control)}}

      {:error, error, state} ->
        {:stop, error, state}
    end
  end

  defp remove_subscription(state, reference, reason) do
    case Map.pop(state.subscriptions, reference) do
      {nil, _} ->
        state

      {subscription, subscriptions} ->
        Process.demonitor(subscription.monitor, [:flush])
        for waiter <- subscription.waiters, do: GenServer.reply(waiter, :ok)
        {queue, members} = state.closed
        queue = :queue.in(reference, queue)
        members = MapSet.put(members, reference)

        {queue, members} =
          if :queue.len(queue) > @closed_handles do
            {{:value, oldest}, queue} = :queue.out(queue)
            {queue, MapSet.delete(members, oldest)}
          else
            {queue, members}
          end

        :telemetry.execute([:wotex, :opcua, :subscription, :close], %{count: 1}, %{
          result: Map.get(subscription, :reason) || reason
        })

        %{
          state
          | subscriptions: subscriptions,
            tokens: Map.delete(state.tokens, subscription.token),
            receivers: Map.delete(state.receivers, subscription.monitor),
            closed: {queue, members}
        }
    end
  end

  defp response(state, id, line) do
    cond do
      Map.has_key?(state.pending, id) -> pending_response(state, id, line)
      Map.has_key?(state.controls, id) -> control_response(state, id, line)
      true -> terminate_generation(state, Error.new(:invalid_native_frame))
    end
  end

  defp pending_response(state, id, line) do
    {entry, pending} = Map.pop!(state.pending, id)
    state = %{state | pending: pending}

    case Frame.response(line, state.generation, id, entry.operation, entry.requested_timeout) do
      {:error, error} ->
        terminate_generation(%{state | pending: Map.put(pending, id, entry)}, error)

      decoded ->
        if entry.replied do
          after_native(state, line, fn state ->
            orphaned(state, entry, decoded)
          end)
        else
          Process.demonitor(entry.monitor, [:flush])
          cancel_timer(entry.timer)
          state = %{state | monitors: Map.delete(state.monitors, entry.monitor)}
          after_native(state, line, fn state -> deliver(state, entry, decoded, line) end)
        end
    end
  end

  defp control_response(state, id, line) do
    {control, controls} = Map.pop!(state.controls, id)
    cancel_timer(control.timer)
    state = %{state | controls: controls}

    case {control.kind,
          Frame.response(line, state.generation, id, Atom.to_string(control.kind), nil)} do
      {:cancel, {:ok, %{"target_id" => target}}} when target == control.target ->
        after_native(state, line, fn state -> {:ok, state} end)

      {:browse_release, {:ok, nil}} ->
        after_native(state, line, fn state -> {:ok, state} end)

      {:close, {:ok, nil}} ->
        GenServer.reply(control.from, {:ok, nil})
        stop_generation(state, Error.new(:native_process_terminated), false)

      {:close, {:native_error, error}} ->
        GenServer.reply(control.from, {:error, error})
        stop_generation(state, Error.new(:native_process_terminated), false)

      {:unsubscribe, {:ok, nil}} ->
        after_native(state, line, fn state ->
          state = %{state | discarding: MapSet.delete(state.discarding, control.token)}

          {:ok,
           if(control.reference,
             do: remove_subscription(state, control.reference, :unsubscribed),
             else: state
           )}
        end)

      _ ->
        terminate_generation(state, Error.new(:invalid_native_frame))
    end
  end

  # Replenishes credit for one validated line before any follow-up request. A
  # native process that already exited cannot use the credit; its remaining
  # lines and exit status are still in the mailbox and are handled in order.
  defp after_native(state, line, continuation) do
    with {:ok, credit} <-
           Frame.credit(state.generation, state.credit_sequence + 1, 1, byte_size(line)),
         :ok <- replenish(state.port, credit) do
      case continuation.(%{state | credit_sequence: state.credit_sequence + 1}) do
        {:ok, state} -> {:noreply, state}
        {:stop, error, state} -> terminate_generation(state, error)
      end
    else
      {:error, error} -> terminate_generation(state, error)
    end
  end

  # A subscription created after its caller stopped waiting is cancelled at once.
  defp orphaned(state, %{cursor: %{kind: :subscribe}}, {:ok, %{"subscription" => token}}) do
    unsubscribe_control(%{state | discarding: MapSet.put(state.discarding, token)}, token, nil)
  end

  defp orphaned(state, %{cursor: %{kind: :unsubscribe, reference: reference}}, {:ok, nil}),
    do: {:ok, remove_subscription(state, reference, :unsubscribed)}

  defp orphaned(state, _, _), do: {:ok, state}

  defp deliver(state, %{cursor: %{kind: :subscribe} = cursor} = entry, {:ok, result}, _) do
    reference = make_ref()
    monitor = Process.monitor(cursor.receiver)

    subscription = %{
      token: result["subscription"],
      receiver: cursor.receiver,
      monitor: monitor,
      max_queue: cursor.max_queue,
      closing: false,
      reason: nil,
      waiters: []
    }

    handle = %Subscription{pid: self(), reference: reference, generation: state.generation}
    GenServer.reply(entry.from, {:ok, handle})

    {:ok,
     %{
       state
       | subscriptions: Map.put(state.subscriptions, reference, subscription),
         tokens: Map.put(state.tokens, subscription.token, reference),
         receivers: Map.put(state.receivers, monitor, reference)
     }}
  end

  defp deliver(state, %{cursor: %{kind: :unsubscribe, reference: reference}} = entry, {:ok, nil}, _) do
    GenServer.reply(entry.from, :ok)
    {:ok, remove_subscription(state, reference, :unsubscribed)}
  end

  defp deliver(state, entry, {:native_error, error}, _) do
    GenServer.reply(entry.from, {:error, error})
    {:ok, state}
  end

  defp deliver(state, %{cursor: nil} = entry, {:ok, %{"continuation" => token}}, _)
       when is_binary(token) do
    GenServer.reply(entry.from, {:error, Error.new(:response_limit)})
    {:stop, Error.new(:response_limit), state}
  end

  defp deliver(state, %{cursor: nil} = entry, {:ok, result}, _) do
    GenServer.reply(entry.from, {:ok, result})
    {:ok, state}
  end

  defp deliver(state, %{cursor: %{kind: :release_after} = cursor}, {:ok, nil}, _) do
    GenServer.reply(cursor.from, {:error, cursor.error})
    {:ok, state}
  end

  defp deliver(state, %{cursor: %{kind: :release}} = entry, {:ok, nil}, _) do
    GenServer.reply(entry.from, {:ok, nil})
    {:ok, state}
  end

  defp deliver(
         state,
         %{cursor: %{kind: kind} = old} = entry,
         {:ok, %{"references" => references, "continuation" => token} = result},
         line
       )
       when kind in [:browse_page, :next] do
    pages = old.pages + 1
    count = old.references + length(references)
    bytes = old.bytes + byte_size(line)

    cond do
      is_binary(token) and Enum.any?(state.continuations, fn {_, live} -> live.token == token end) ->
        GenServer.reply(entry.from, {:error, Error.new(:invalid_native_frame)})
        {:stop, Error.new(:invalid_native_frame), state}

      pages > old.limits.max_pages or count > old.limits.max_references or bytes > 1_048_576 or
          (is_binary(token) and pages == old.limits.max_pages) ->
        limited(state, entry, token)

      is_binary(token) ->
        reference = make_ref()
        handle = %Continuation{pid: self(), reference: reference, generation: state.generation}

        delay = max(entry.deadline - System.monotonic_time(:millisecond), 0)

        cursor = %{
          token: token,
          timer: :erlang.start_timer(delay, self(), {:continuation, reference}),
          deadline: entry.deadline,
          pages: pages,
          references: count,
          bytes: bytes,
          limits: old.limits
        }

        GenServer.reply(entry.from, {:ok, %{result | "continuation" => handle}})

        {:ok, %{state | continuations: Map.put(state.continuations, reference, cursor)}}

      true ->
        GenServer.reply(entry.from, {:ok, result})
        {:ok, state}
    end
  end

  # Excess results release the newest live server continuation on this Session.
  defp limited(state, entry, nil) do
    GenServer.reply(entry.from, {:error, Error.new(:response_limit)})
    {:ok, state}
  end

  defp limited(state, entry, token),
    do: emit_release(state, entry.from, token, Error.new(:response_limit))

  # A deadline-released handle reports its deadline; releasing it again is done.
  defp expired_continuation(%{expired: {_, expired}}, handle, operation) do
    cond do
      not MapSet.member?(expired, handle.reference) -> {:error, Error.new(:invalid_continuation)}
      operation == :next -> {:error, Error.new(:deadline_exceeded)}
      true -> {:ok, nil}
    end
  end

  defp continue_cursor(state, from, cursor, timeout, operation) do
    now = System.monotonic_time(:millisecond)

    if operation == :next and now >= cursor.deadline do
      # An expired browse still releases its live server continuation.
      release_after(state, from, cursor, Error.new(:deadline_exceeded))
    else
      {name, budget, deadline} =
        if operation == :release,
          do: {"browse_release", min(timeout, @control_ms), now + min(timeout, @control_ms)},
          else: {"browse_next", min(timeout, cursor.deadline - now), cursor.deadline}

      admit(
        state,
        from,
        name,
        %{"continuation" => cursor.token},
        budget,
        deadline,
        Map.put(cursor, :kind, operation)
      )
    end
  end

  defp expire({queue, members}, reference) do
    queue = :queue.in(reference, queue)
    members = MapSet.put(members, reference)

    if :queue.len(queue) > @continuations do
      {{:value, oldest}, queue} = :queue.out(queue)
      {queue, MapSet.delete(members, oldest)}
    else
      {queue, members}
    end
  end

  # Live continuations, deadline releases and unfinished Browse work.
  defp chains(state) do
    map_size(state.continuations) +
      Enum.count(state.pending, fn {_, entry} -> browse_cursor?(entry.cursor) end) +
      Enum.count(state.controls, fn {_, control} -> control.kind == :browse_release end)
  end

  defp browse_cursor?(%{kind: kind}) when kind in [:browse_page, :next, :release, :release_after],
    do: true

  defp browse_cursor?(_), do: false

  # Sends release for a cursor whose caller receives the original error after cleanup.
  defp release_after(state, from, cursor, error) do
    case emit_release(state, from, cursor.token, error) do
      {:ok, state} -> {:noreply, state}
      {:stop, error, state} -> terminate_generation(state, error)
    end
  end

  defp emit_release(state, from, token, error) do
    now = System.monotonic_time(:millisecond)
    deadline = now + @control_ms

    case emit(state, "browse_release", %{"continuation" => token}, @control_ms, deadline) do
      {:ok, id, state} ->
        {caller, _} = from

        entry = %{
          from: from,
          operation: "browse_release",
          cursor: %{kind: :release_after, from: from, error: error},
          deadline: deadline,
          requested_timeout: nil,
          monitor: monitor(caller),
          timer: :erlang.start_timer(@control_ms, self(), {:request, id}),
          replied: false
        }

        {:ok,
         %{
           state
           | pending: Map.put(state.pending, id, entry),
             monitors: Map.put(state.monitors, entry.monitor, id)
         }}

      {:error, _, state} ->
        GenServer.reply(from, {:error, error})
        {:stop, Error.new(:native_process_terminated), state}
    end
  end

  defp effect(error, %{operation: operation}) when operation in @mutations,
    do: %{error | effect: :unknown}

  defp effect(error, _), do: %{error | effect: :none}

  defp terminate_generation(state, error), do: stop_generation(state, error, true)

  # Fails every unanswered request once with its own effect and closes the owner.
  defp stop_generation(state, error, notify) do
    unanswered =
      state.pending
      |> Enum.reject(fn {_, entry} -> entry.replied end)
      |> Enum.map(fn {_, entry} -> entry end)

    for entry <- unanswered, do: GenServer.reply(entry.from, {:error, effect(error, entry)})

    for {_, %{kind: :close, from: from}} <- state.controls,
        do: GenServer.reply(from, {:error, error})

    for {reference, subscription} <- state.subscriptions do
      for waiter <- subscription.waiters, do: GenServer.reply(waiter, {:error, error})

      unless subscription.closing,
        do:
          send(subscription.receiver, {:wotex_opcua, reference, {:error, %{error | effect: :none}}})
    end

    if notify and unanswered == [] and state.subscriptions == %{} and
         not Enum.any?(state.controls, fn {_, control} -> control.kind == :close end) do
      send(state.owner, {:wotex_opcua_native, self(), {:error, error}})
    end

    {:stop, :normal, %{state | pending: %{}, controls: %{}, subscriptions: %{}}}
  end

  # The host answers every admitted request before a normal stop, so a normal
  # exit means the request was never emitted. A call timeout may follow emission.
  defp exit_error({reason, _}, _) when reason in [:normal, :noproc],
    do: Error.new(:native_process_terminated)

  defp exit_error(_, operation),
    do: effect(Error.new(:native_process_terminated), %{operation: operation})

  defp verify(settings, owner, owner_monitor, deadline) do
    host = self()
    token = make_ref()

    {worker, monitor} =
      :erlang.spawn_opt(
        fn ->
          result =
            with {:ok, _} <-
                   Executable.verify(settings.guardian, settings.guardian_digest, deadline),
                 {:ok, _} <-
                   Executable.verify(settings.executable, settings.executable_digest, deadline),
                 do: :ok

          send(host, {token, result})
        end,
        [:link, :monitor]
      )

    try do
      receive do
        {^token, result} -> result
        {:DOWN, ^owner_monitor, :process, ^owner, _} -> {:error, Error.new(:native_owner_lost)}
        {:EXIT, ^owner, _} -> {:error, Error.new(:native_owner_lost)}
        {:DOWN, ^monitor, :process, ^worker, _} -> {:error, Error.new(:invalid_native_executable)}
      after
        remaining(deadline) -> {:error, Error.new(:deadline_exceeded, :executable)}
      end
    after
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      Process.unlink(worker)
      Process.demonitor(monitor, [:flush])
    end
  end

  defp spawn_native(settings) do
    environment =
      System.get_env()
      |> Map.new(fn {key, _} -> {String.to_charlist(key), false} end)
      |> Map.put(~c"LC_ALL", ~c"C")
      |> Map.to_list()

    port =
      Port.open({:spawn_executable, settings.guardian}, [
        :binary,
        :exit_status,
        args: ["500", "131072", "65536", Path.dirname(settings.executable), settings.executable],
        env: environment
      ])

    {:ok, port}
  rescue
    _ in [ArgumentError, ErlangError] -> {:error, Error.new(:native_startup_failed)}
  end

  defp await_ready(port, owner, monitor, deadline, buffered) do
    receive do
      {^port, {:data, bytes}} when byte_size(buffered) + byte_size(bytes) <= 4096 ->
        received = System.monotonic_time(:millisecond)
        frame = buffered <> bytes

        if :binary.match(frame, "\n") == :nomatch do
          await_ready(port, owner, monitor, deadline, frame)
        else
          with :ok <- budget(deadline),
               {:ok, ready} <- Ready.decode(frame) do
            {:ok, %{ready: ready, received_at_ms: received}}
          end
        end

      {^port, {:data, _}} ->
        {:error, Error.new(:invalid_native_ready, :ready)}

      {^port, {:exit_status, status}} ->
        {:error, Error.new(:native_process_terminated, nil, %{exit_status: status})}

      {:EXIT, ^port, _} ->
        {:error, Error.new(:native_process_terminated)}

      {:DOWN, ^monitor, :process, ^owner, _} ->
        {:error, Error.new(:native_owner_lost)}

      {:EXIT, ^owner, _} ->
        {:error, Error.new(:native_owner_lost)}
    after
      remaining(deadline) -> {:error, Error.new(:deadline_exceeded, :ready)}
    end
  end

  defp replenish(port, frame) do
    case send_frame(port, frame) do
      {:error, _} = error -> if Port.info(port), do: error, else: :ok
      :ok -> :ok
    end
  end

  defp send_frame(port, frame) do
    if Port.command(port, frame), do: :ok, else: {:error, Error.new(:native_process_terminated)}
  rescue
    ArgumentError -> {:error, Error.new(:native_process_terminated)}
  end

  defp initial_credit(%{credit_sequence: 0, generation: generation}),
    do: Frame.credit(generation, 1, 16, 262_144)

  defp initial_credit(_), do: {:ok, nil}

  defp send_optional(_, nil), do: :ok
  defp send_optional(port, frame), do: send_frame(port, frame)

  defp owner_generation do
    case :binary.decode_unsigned(:crypto.strong_rand_bytes(8)) do
      0 -> owner_generation()
      generation -> generation
    end
  end

  defp claim(pid, token, deadline) do
    result =
      try do
        GenServer.call(pid, {__MODULE__, :claim, token}, remaining(deadline) + 100)
      catch
        :exit, _ -> {:error, Error.new(:native_startup_failed)}
      end

    case result do
      {:ok, sample} ->
        {:ok, pid, sample}

      {:error, _} = error ->
        stop_unclaimed(pid)
        error
    end
  end

  defp stop_unclaimed(pid) do
    GenServer.stop(pid, :normal, 500)
  catch
    :exit, _ -> :ok
  end

  defp close_port(port) do
    if Port.info(port), do: Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  defp owner_alive(owner) do
    if Process.alive?(owner), do: :ok, else: {:error, Error.new(:native_owner_lost)}
  end

  defp budget(deadline) do
    if remaining(deadline) > 0,
      do: :ok,
      else: {:error, Error.new(:deadline_exceeded, :ready)}
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
