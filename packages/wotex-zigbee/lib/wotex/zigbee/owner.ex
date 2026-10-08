defmodule Wotex.Zigbee.Owner do
  @moduledoc """
  One explicit TI ZNP serial owner with a negotiated firmware epoch.

  The owner accepts fragmented serial chunks, permits one outstanding SREQ,
  keeps AREQs in a finite queue and reports its overflow count. A command
  timeout ends the owner instead of matching a late SRSP to a later request.
  A bounded interview holds that admission slot across all of its steps while
  preserving unrelated indications. Caller death also ends a pending epoch.
  Neither startup nor timeout forms or resets a Zigbee network. The serial
  adapter and supervision policy belong to the consumer.

  Startup shares one deadline across serial open, version write and reply
  delivery. Negotiation monitors its original caller and any ready waiter.
  `open/1` retains monitoring through handle handoff and links the caller
  before replying. Caller-owned lifetime ends on normal or abnormal caller exit.
  Callback exceptions and malformed returns become redacted failures;
  explicit close reports failure instead of claiming successful cleanup.
  """

  use GenServer

  alias Wotex.Zigbee.{
    Command,
    Config,
    Downlinks,
    Error,
    Event,
    Frame,
    Handle,
    Interview,
    Reply,
    Routes
  }

  alias Wotex.Zigbee.Interview.Flow

  @max_query_routes 128

  @doc """
  Negotiates an owner and links it to this caller before delivering the handle.

  Original startup time and caller monitoring cover negotiation and handle
  handoff. The owner closes when this caller exits, including normal exit.
  Use `start_link/1` for consumer supervision instead of transferring this
  caller-owned lifetime by copying a handle.
  """
  @spec open(Config.t()) :: {:ok, Handle.t()} | {:error, Error.t()}
  def open(%Config{} = config) do
    case start_owner(config, :opening) do
      {:ok, owner} -> finish_open(owner, config.timeout_ms)
      {:error, %Error{}} = error -> error
      {:error, _} -> {:error, error(:serial, :open)}
    end
  end

  def open(_), do: {:error, error(:invalid_config, :open)}

  @doc "Starts a coordinator owner under a consumer supervisor."
  @spec start_link(Config.t()) :: GenServer.on_start()
  def start_link(config), do: start_owner(config, :linked)

  @doc "Starts an owner without linking while serial/version admission runs."
  @spec start(Config.t()) :: GenServer.on_start()
  def start(config), do: start_owner(config, :unlinked)

  @doc "Waits 1–60,000 ms for exact SYS_VERSION without extending the original startup budget."
  @spec ready(pid(), 1..60_000) :: {:ok, Handle.t()} | {:error, Error.t()}
  def ready(owner, timeout) when is_pid(owner) and is_integer(timeout) and timeout in 1..60_000 do
    deadline = System.monotonic_time(:millisecond) + timeout
    safe_call(owner, {:ready, deadline}, timeout + 100)
  end

  def ready(_, _), do: {:error, error(:invalid_value, :ready)}

  @doc "Gets a handle from an already negotiated supervised owner."
  @spec handle(pid()) :: {:ok, Handle.t()} | {:error, Error.t()}
  def handle(owner), do: safe_call(owner, :handle, 5_000)

  @doc "Executes one bounded owner call through its opaque epoch and caller deadline."
  @spec call(Handle.t(), atom(), [term()]) :: term()
  def call(%Handle{owner: owner, epoch: epoch, timeout_ms: limit}, operation, [value, timeout])
      when is_pid(owner) and is_reference(epoch) and is_integer(limit) and limit > 0 and
             operation in [:command, :interview] do
    valid_timeout = is_integer(timeout) and timeout > 0
    wait = if valid_timeout, do: min(timeout, limit) + 100, else: limit + 100
    deadline = if valid_timeout, do: System.monotonic_time(:millisecond) + min(timeout, limit)
    safe_call(owner, {operation, epoch, [value, timeout, deadline]}, wait)
  end

  def call(%Handle{owner: owner, epoch: epoch, timeout_ms: limit}, operation, args)
      when is_pid(owner) and is_reference(epoch) and is_integer(limit) and limit > 0 and
             operation in [:close, :drain] and is_list(args) do
    safe_call(owner, {operation, epoch, args}, limit + 100)
  end

  def call(%Handle{owner: owner, epoch: epoch, timeout_ms: limit}, operation, [
        routes,
        request,
        timeout
      ])
      when is_pid(owner) and is_reference(epoch) and is_integer(limit) and limit > 0 and
             operation in [:routed, :queued] do
    valid_timeout = is_integer(timeout) and timeout > 0
    wait = if valid_timeout, do: min(timeout, limit) + 100, else: limit + 100
    deadline = if valid_timeout, do: System.monotonic_time(:millisecond) + min(timeout, limit)
    safe_call(owner, {operation, epoch, [routes, request, timeout, deadline]}, wait)
  end

  def call(_, operation, _)
      when operation in [:command, :interview, :routed, :queued, :close, :drain],
      do: {:error, %Error{kind: :stale_handle, operation: operation}}

  def call(_, _, _), do: {:error, error(:invalid_command, :owner)}

  @impl GenServer
  def init({config, deadline, caller, mode}) do
    if mode == :opening, do: Process.flag(:trap_exit, true)

    with true <- Config.valid?(config),
         true <- Code.ensure_loaded?(config.serial),
         true <- function_exported?(config.serial, :open, 3),
         true <- function_exported?(config.serial, :write, 2),
         true <- function_exported?(config.serial, :close, 1),
         :ok <- startup_admission(deadline, caller),
         {:ok, port} <- serial_open(config) do
      state = initial_state(config, port, deadline, caller, mode)

      with :ok <- startup_admission(deadline, caller),
           :ok <- write_frame(state, Command.version(), deadline),
           :ok <- startup_admission(deadline, caller) do
        {:ok, %{state | version_timer: deadline_timer(:version_timeout, deadline)}}
      else
        kind ->
          serial_close(state)
          startup_stop(kind)
      end
    else
      false -> startup_stop(:invalid_config)
      {:error, _} -> startup_stop(:serial)
      kind -> startup_stop(kind)
    end
  end

  @impl GenServer
  def handle_call({:ready, _}, {caller, _}, %{handoff_pending: true} = state)
      when caller != state.startup_caller,
      do: {:reply, {:error, error(:invalid_value, :ready)}, state}

  def handle_call({:ready, deadline}, from, %{mode: :negotiating, ready_waiter: nil} = state)
      when is_integer(deadline) do
    deadline = min(deadline, state.version_deadline)

    if expired?(deadline) do
      {:stop, :normal, {:error, error(:timeout, :ready)}, state}
    else
      Process.cancel_timer(state.version_timer)

      {:noreply,
       %{
         state
         | ready_waiter: from,
           ready_monitor: Process.monitor(elem(from, 0)),
           version_deadline: deadline,
           version_timer: deadline_timer(:version_timeout, deadline)
       }}
    end
  end

  def handle_call({:ready, _}, _, %{mode: :negotiating} = state),
    do: {:reply, {:error, error(:overload, :ready)}, state}

  def handle_call({:ready, deadline}, _, %{mode: :awaiting_handoff} = state)
      when is_integer(deadline) do
    case startup_admission(min(deadline, state.version_deadline), state.startup_caller) do
      :ok -> {:reply, {:ok, handle_for(state)}, complete_startup(state)}
      kind -> {:stop, :normal, {:error, error(kind, :ready)}, state}
    end
  end

  def handle_call({:ready, deadline}, _, %{mode: :ready} = state) when is_integer(deadline) do
    result =
      if expired?(deadline), do: {:error, error(:timeout, :ready)}, else: {:ok, handle_for(state)}

    {:reply, result, state}
  end

  def handle_call({:ready, _}, _, %{mode: {:failed, kind}} = state),
    do: {:stop, :normal, {:error, error(kind, :ready)}, state}

  def handle_call(:handle, _, %{mode: :ready} = state),
    do: {:reply, {:ok, handle_for(state)}, state}

  def handle_call(:handle, _, state),
    do: {:reply, {:error, error(:coordinator_lost, :handle)}, state}

  def handle_call({:close, epoch, []}, _, state) do
    if epoch == state.epoch do
      fail_waiters(state, :coordinator_lost)
      result = if serial_close(state) == :ok, do: :ok, else: {:error, error(:serial, :close)}
      {:stop, :normal, result, %{state | close_attempted: true}}
    else
      {:reply, {:error, error(:stale_handle, :close)}, state}
    end
  end

  def handle_call({:drain, epoch, [count]}, _, state) do
    cond do
      epoch != state.epoch ->
        {:reply, {:error, error(:stale_handle, :drain)}, state}

      state.mode != :ready ->
        {:reply, {:error, error(:coordinator_lost, :drain)}, state}

      not is_integer(count) or count < 1 or count > state.config.max_events ->
        {:reply, {:error, error(:invalid_value, :drain)}, state}

      true ->
        {events, queue} = take_events(state.events, count, [])

        result =
          {:ok, %{events: events, dropped: state.dropped, framing_faults: state.framing_faults}}

        {:reply, result,
         %{
           state
           | events: queue,
             event_count: state.event_count - length(events),
             dropped: 0,
             framing_faults: 0
         }}
    end
  end

  def handle_call({:command, epoch, [frame, timeout, deadline]}, from, state) do
    deadline = bounded_deadline(deadline, timeout, state.config.timeout_ms)

    cond do
      epoch != state.epoch ->
        {:reply, {:error, error(:stale_handle, :command)}, state}

      state.mode != :ready ->
        {:reply, {:error, error(:coordinator_lost, :command)}, state}

      state.pending != nil or state.interview != nil ->
        {:reply, {:error, error(:overload, :command)}, state}

      not valid_timeout?(timeout, state.config.timeout_ms) ->
        {:reply, {:error, error(:invalid_value, :command)}, state}

      expired?(deadline) ->
        {:reply, {:error, error(:timeout, :command)}, state}

      not Command.admitted?(frame) ->
        {:reply, {:error, error(:invalid_command, :command)}, state}

      not route_capacity?(state, frame) ->
        {:reply, {:error, error(:overload, :command)}, state}

      not Process.alive?(elem(from, 0)) ->
        {:reply, {:error, error(:coordinator_lost, :command)}, state}

      true ->
        send_command(remember_command(state, frame), frame, deadline, from)
    end
  end

  def handle_call({:interview, epoch, [request, timeout, deadline]}, from, state) do
    deadline = bounded_deadline(deadline, timeout, state.config.timeout_ms)

    case interview_admission(state, epoch, request, timeout, deadline, from) do
      :ok ->
        reference = make_ref()
        monitor = Process.monitor(elem(from, 0))
        timer = deadline_timer({:interview_timeout, reference}, deadline)

        interview = %{
          flow: Flow.new(request, state.epoch),
          from: from,
          reference: reference,
          monitor: monitor,
          timer: timer,
          deadline: deadline
        }

        routes = MapSet.put(state.query_routes, request.route_address)
        updated = issue_interview(%{state | interview: interview, query_routes: routes})
        if updated.mode == :failed, do: {:stop, :normal, updated}, else: {:noreply, updated}

      kind ->
        {:reply, {:error, error(kind, :interview)}, state}
    end
  end

  def handle_call({:routed, epoch, [routes, request, timeout, deadline]}, from, state) do
    with {:ok, expiry} <-
           Routes.check_request(routes, request, state.epoch, System.monotonic_time(:millisecond)),
         {:ok, frame} <-
           Command.data_request(
             request.route_address,
             request.destination_endpoint,
             request.source_endpoint,
             request.cluster,
             request.transaction,
             request.data,
             radius: request.radius,
             aps_ack: request.aps_ack,
             aps_security: request.aps_security
           ) do
      bounded = if is_integer(deadline), do: min(deadline, expiry)
      handle_call({:command, epoch, [frame, timeout, bounded]}, from, state)
    else
      failure -> {:reply, failure, state}
    end
  end

  def handle_call({:queued, epoch, [routes, delivery, timeout, deadline]}, from, state) do
    cond do
      epoch != state.epoch ->
        {:reply, {:error, error(:stale_handle, :queued)}, state}

      not Downlinks.valid_delivery?(delivery) ->
        {:reply, {:error, error(:invalid_value, :queued)}, state}

      delivery.owner_epoch != state.epoch ->
        {:reply, {:error, error(:stale_epoch, :queued)}, state}

      delivery.entry.enqueued_at_ms > System.monotonic_time(:millisecond) ->
        {:reply, {:error, error(:invalid_value, :queued)}, state}

      true ->
        bounded = if is_integer(deadline), do: min(deadline, delivery.deadline_ms)

        handle_call(
          {:routed, epoch, [routes, delivery.entry.request, timeout, bounded]},
          from,
          state
        )
    end
  end

  def handle_call(_, _, state), do: {:reply, {:error, error(:invalid_command, :owner)}, state}

  @impl GenServer
  def handle_info({:zigbee_serial, port, chunk}, %{port: port} = state) do
    case Frame.feed(state.buffer, chunk, state.config.max_buffer_bytes) do
      {:ok, frames, buffer, faults} ->
        updated =
          Enum.reduce(
            frames,
            %{state | buffer: buffer, framing_faults: state.framing_faults + faults},
            &accept_frame/2
          )

        if updated.mode == :failed, do: {:stop, :normal, updated}, else: {:noreply, updated}

      {:error, _} ->
        fail_waiters(state, :overload)
        {:stop, :normal, state}
    end
  end

  def handle_info({:zigbee_serial_down, port, _}, %{port: port} = state) do
    fail_waiters(state, :coordinator_lost)
    {:stop, :normal, state}
  end

  def handle_info(:version_timeout, %{mode: :negotiating} = state) do
    updated = fail_negotiation(state, :timeout)
    if updated.mode == :failed, do: {:stop, :normal, updated}, else: {:noreply, updated}
  end

  def handle_info(:version_timeout, %{mode: :awaiting_handoff} = state),
    do: {:noreply, fail_negotiation(state, :timeout)}

  def handle_info({:DOWN, monitor, :process, _, _}, %{startup_monitor: monitor} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, monitor, :process, _, _}, %{ready_monitor: monitor} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, monitor, :process, _, _}, %{consumer_monitor: monitor} = state) do
    fail_waiters(state, :coordinator_lost)
    {:stop, :normal, state}
  end

  def handle_info({:EXIT, _, _}, %{close_attempted: true} = state), do: {:noreply, state}

  def handle_info({:EXIT, _, _}, %{consumer_caller: caller} = state) when is_pid(caller) do
    fail_waiters(state, :coordinator_lost)
    {:stop, :normal, state}
  end

  def handle_info(:failed_stop, %{mode: {:failed, _}} = state), do: {:stop, :normal, state}

  def handle_info(
        {:command_timeout, reference},
        %{pending: %{reference: reference} = pending} = state
      ) do
    GenServer.reply(pending.from, {:error, error(:timeout, :command)})
    {:stop, :normal, clear_pending(state)}
  end

  def handle_info(
        {:interview_timeout, reference},
        %{interview: %{reference: reference}} = state
      ),
      do: {:stop, :normal, end_interview(state, :timeout, true)}

  def handle_info(
        {:DOWN, monitor, :process, _, _},
        %{pending: %{monitor: monitor}} = state
      ),
      do: {:stop, :normal, clear_pending(state)}

  def handle_info(
        {:DOWN, monitor, :process, _, _},
        %{interview: %{monitor: monitor}} = state
      ),
      do: {:stop, :normal, end_interview(state, :caller_lost, true)}

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, %{close_attempted: true}), do: :ok
  def terminate(_, state), do: serial_close(state)

  defp send_command(state, frame, deadline, from) do
    reference = make_ref()

    pending = %{
      from: from,
      subsystem: frame.subsystem,
      id: frame.id,
      reference: reference,
      monitor: Process.monitor(elem(from, 0)),
      timer: deadline_timer({:command_timeout, reference}, deadline),
      deadline: deadline
    }

    case write_frame(state, frame, deadline) do
      :ok ->
        {:noreply, %{state | pending: pending}}

      kind ->
        cleaned = clear_pending(%{state | pending: pending})
        {:stop, :normal, {:error, error(kind, :command)}, cleaned}
    end
  end

  defp accept_frame(_, %{mode: :failed} = state), do: state

  defp accept_frame(
         %Frame{type: :srsp, subsystem: 1, id: 2, payload: payload},
         %{mode: :negotiating} = state
       ) do
    cond do
      expired?(state.version_deadline) ->
        fail_negotiation(state, :timeout)

      not Process.alive?(state.startup_caller) or not ready_caller_alive?(state) ->
        fail_negotiation(state, :coordinator_lost)

      payload != version_bytes(state.config.expected_version) ->
        fail_negotiation(state, :version_mismatch)

      true ->
        negotiate_handle(state)
    end
  end

  defp accept_frame(%Frame{type: :srsp} = frame, %{pending: pending} = state)
       when is_map(pending) do
    cond do
      expired?(pending.deadline) ->
        fail_response(state, :timeout)

      frame.subsystem != pending.subsystem or frame.id != pending.id or
          byte_size(frame.payload) != 1 ->
        fail_response(state, :invalid_frame)

      true ->
        <<status>> = frame.payload

        reply = %Reply{
          subsystem: frame.subsystem,
          id: frame.id,
          status: status,
          payload: frame.payload
        }

        if state.interview do
          flow = Flow.admit(state.interview.flow, reply)
          progress_interview(%{state | pending: nil, interview: %{state.interview | flow: flow}})
        else
          GenServer.reply(pending.from, {:ok, reply})
          clear_pending(state)
        end
    end
  end

  defp accept_frame(%Frame{type: :areq}, %{observation_sequence: 0xFFFFFFFFFFFFFFFF} = state) do
    fail_waiters(state, :correlation_exhausted)
    %{state | mode: :failed}
  end

  defp accept_frame(%Frame{type: :areq} = frame, state) do
    state = %{state | observation_sequence: state.observation_sequence + 1}

    event = %{
      Event.from_frame(frame)
      | owner_epoch: state.epoch,
        received_at_ms: System.monotonic_time(:millisecond),
        owner_sequence: state.observation_sequence
    }

    if state.interview do
      case Flow.offer(state.interview.flow, event) do
        {:matched, flow} ->
          progress_interview(%{state | interview: %{state.interview | flow: flow}})

        :unmatched ->
          enqueue_event(state, event)
      end
    else
      enqueue_event(state, event)
    end
  end

  defp accept_frame(_, state), do: state

  defp enqueue_event(state, event) do
    if state.event_count >= state.config.max_events do
      %{state | dropped: state.dropped + 1}
    else
      %{
        state
        | events: :queue.in(event, state.events),
          event_count: state.event_count + 1
      }
    end
  end

  defp interview_admission(state, epoch, request, timeout, deadline, from) do
    cond do
      epoch != state.epoch -> :stale_handle
      state.mode != :ready -> :coordinator_lost
      state.pending != nil or state.interview != nil -> :overload
      not Interview.valid?(request) -> :invalid_value
      not valid_timeout?(timeout, state.config.timeout_ms) -> :invalid_value
      expired?(deadline) -> :timeout
      MapSet.member?(state.query_routes, request.route_address) -> :correlation_exhausted
      MapSet.size(state.query_routes) >= @max_query_routes -> :overload
      not Process.alive?(elem(from, 0)) -> :coordinator_lost
      true -> :ok
    end
  end

  defp progress_interview(state) do
    if expired?(state.interview.deadline) do
      end_interview(state, :timeout, true)
    else
      case Flow.advance(state.interview.flow) do
        {:waiting, _} -> state
        {:next, flow} -> issue_interview(%{state | interview: %{state.interview | flow: flow}})
        {:done, result} -> reply_interview(state, result)
      end
    end
  end

  defp issue_interview(state) do
    case allocate_token(state) do
      {:ok, state} ->
        {:ok, frame} = Flow.command(state.interview.flow)
        deadline = state.interview.deadline

        if Process.alive?(elem(state.interview.from, 0)) do
          case write_frame(state, frame, deadline) do
            :ok ->
              %{state | pending: %{subsystem: frame.subsystem, id: frame.id, deadline: deadline}}

            kind ->
              end_interview(state, kind, true)
          end
        else
          end_interview(state, :caller_lost, true)
        end

      :exhausted ->
        end_interview(state, :correlation_exhausted, false)
    end
  end

  defp allocate_token(%{interview: %{flow: %{stage: {:basic, _}}}} = state) do
    case Enum.find(0..255, &(not MapSet.member?(state.used_tokens, &1))) do
      nil ->
        :exhausted

      token ->
        flow = %{state.interview.flow | token: token}

        {:ok,
         %{
           state
           | used_tokens: MapSet.put(state.used_tokens, token),
             interview: %{state.interview | flow: flow}
         }}
    end
  end

  defp allocate_token(state), do: {:ok, state}

  defp end_interview(state, kind, failed) do
    result = Flow.finish(state.interview.flow, kind)
    updated = reply_interview(state, result)
    if failed, do: %{updated | mode: :failed}, else: updated
  end

  defp reply_interview(state, result) do
    GenServer.reply(state.interview.from, {:ok, result})
    Process.cancel_timer(state.interview.timer)
    Process.demonitor(state.interview.monitor, [:flush])
    %{state | interview: nil, pending: nil}
  end

  defp fail_response(%{interview: interview} = state, kind) when is_map(interview),
    do: end_interview(state, kind, true)

  defp fail_response(state, kind) do
    GenServer.reply(state.pending.from, {:error, error(kind, :command)})
    %{clear_pending(state) | mode: :failed}
  end

  defp clear_pending(state) do
    Process.cancel_timer(state.pending.timer)
    Process.demonitor(state.pending.monitor, [:flush])
    %{state | pending: nil}
  end

  defp write_frame(state, frame, deadline) do
    if expired?(deadline) do
      :timeout
    else
      {:ok, bytes} = Frame.encode(frame)

      case serial_write(state, bytes) do
        :ok -> if expired?(deadline), do: :timeout, else: :ok
        :error -> :serial
      end
    end
  end

  defp serial_open(config) do
    case serial_callback(config.serial, :open, [config.device_id, serial_options(config), self()]) do
      {:ok, port} -> {:ok, port}
      _ -> {:error, :serial}
    end
  end

  defp serial_write(state, bytes) do
    case serial_callback(state.config.serial, :write, [state.port, bytes]) do
      :ok -> :ok
      _ -> :error
    end
  end

  defp serial_close(state) do
    case serial_callback(state.config.serial, :close, [state.port]) do
      :ok -> :ok
      _ -> :error
    end
  end

  defp serial_callback(module, function, args) do
    apply(module, function, args)
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp start_owner(%Config{} = config, mode) do
    if Config.valid?(config) do
      args = {config, System.monotonic_time(:millisecond) + config.timeout_ms, self(), mode}

      result =
        case mode do
          :linked -> GenServer.start_link(__MODULE__, args)
          :unlinked -> GenServer.start(__MODULE__, args)
          :opening -> GenServer.start(__MODULE__, args)
        end

      case result do
        {:error, {:shutdown, %Error{} = error}} -> {:error, error}
        result -> result
      end
    else
      {:error, error(:invalid_config, :open)}
    end
  end

  defp start_owner(_, _), do: {:error, error(:invalid_config, :open)}
  defp startup_stop(kind), do: {:stop, {:shutdown, error(kind, :open)}}

  defp initial_state(config, port, deadline, caller, mode) do
    %{
      config: config,
      port: port,
      close_attempted: false,
      epoch: make_ref(),
      mode: :negotiating,
      version_timer: nil,
      version_deadline: deadline,
      startup_caller: caller,
      startup_monitor: Process.monitor(caller),
      ready_waiter: nil,
      ready_monitor: nil,
      handoff_pending: mode == :opening,
      consumer_caller: if(mode == :opening, do: caller),
      consumer_monitor: nil,
      pending: nil,
      interview: nil,
      query_routes: MapSet.new(),
      used_tokens: MapSet.new(),
      observation_sequence: 0,
      buffer: <<>>,
      events: :queue.new(),
      event_count: 0,
      dropped: 0,
      framing_faults: 0
    }
  end

  defp startup_admission(deadline, caller) do
    cond do
      expired?(deadline) -> :timeout
      not Process.alive?(caller) -> :coordinator_lost
      true -> :ok
    end
  end

  defp ready_caller_alive?(%{ready_waiter: nil}), do: true
  defp ready_caller_alive?(state), do: Process.alive?(elem(state.ready_waiter, 0))

  defp negotiate_handle(%{handoff_pending: true, ready_waiter: nil} = state),
    do: %{state | mode: :awaiting_handoff}

  defp negotiate_handle(state) do
    updated = complete_startup(state)
    if state.ready_waiter, do: GenServer.reply(state.ready_waiter, {:ok, handle_for(updated)})
    updated
  end

  defp complete_startup(state) do
    Process.cancel_timer(state.version_timer)

    monitor =
      if state.handoff_pending do
        Process.link(state.startup_caller)
        Process.monitor(state.startup_caller)
      end

    %{clear_startup(state) | mode: :ready, handoff_pending: false, consumer_monitor: monitor}
  end

  defp finish_open(owner, timeout) do
    case ready(owner, timeout) do
      {:ok, _} = result -> result
      error -> stop_open_owner(owner, error)
    end
  end

  defp stop_open_owner(owner, error) do
    GenServer.stop(owner, :normal)
    error
  catch
    :exit, _ -> error
  end

  defp fail_negotiation(state, kind) do
    fail_waiters(state, kind)
    Process.cancel_timer(state.version_timer)
    serial_close(state)
    mode = if state.ready_waiter, do: :failed, else: {:failed, kind}
    if mode != :failed, do: Process.send_after(self(), :failed_stop, 1_000)
    %{clear_startup(state) | mode: mode, close_attempted: true, handoff_pending: false}
  end

  defp clear_startup(state) do
    Process.demonitor(state.startup_monitor, [:flush])
    if state.ready_monitor, do: Process.demonitor(state.ready_monitor, [:flush])
    %{state | startup_caller: nil, startup_monitor: nil, ready_waiter: nil, ready_monitor: nil}
  end

  defp bounded_deadline(deadline, timeout, limit)
       when is_integer(deadline) and is_integer(timeout) and timeout >= 1 and timeout <= limit,
       do: min(deadline, System.monotonic_time(:millisecond) + timeout)

  defp bounded_deadline(_, _, _), do: nil
  defp valid_timeout?(timeout, limit), do: is_integer(timeout) and timeout >= 1 and timeout <= limit
  defp expired?(nil), do: true
  defp expired?(deadline), do: deadline <= System.monotonic_time(:millisecond)

  defp deadline_timer(message, deadline),
    do: Process.send_after(self(), message, max(0, deadline - System.monotonic_time(:millisecond)))

  defp route_capacity?(state, %Frame{subsystem: 5, payload: <<route::little-16, _::binary>>}),
    do:
      MapSet.member?(state.query_routes, route) or
        MapSet.size(state.query_routes) < @max_query_routes

  defp route_capacity?(_, _), do: true

  defp remember_command(state, %Frame{subsystem: 5, payload: <<route::little-16, _::binary>>}),
    do: %{state | query_routes: MapSet.put(state.query_routes, route)}

  defp remember_command(state, %Frame{
         subsystem: 4,
         payload: <<_::48, token, _::16, length, data::binary-size(length)>>
       }) do
    tokens = MapSet.put(state.used_tokens, token)
    %{state | used_tokens: remember_sequence(tokens, data)}
  end

  defp remember_sequence(tokens, <<control, rest::binary>>) do
    case {Bitwise.band(control, 4), rest} do
      {0, <<sequence, _::binary>>} -> MapSet.put(tokens, sequence)
      {4, <<_::16, sequence, _::binary>>} -> MapSet.put(tokens, sequence)
      _ -> tokens
    end
  end

  defp remember_sequence(tokens, _), do: tokens

  defp take_events(queue, 0, collected), do: {Enum.reverse(collected), queue}

  defp take_events(queue, count, collected) do
    case :queue.out(queue) do
      {{:value, event}, rest} -> take_events(rest, count - 1, [event | collected])
      {:empty, _} -> {Enum.reverse(collected), queue}
    end
  end

  defp fail_waiters(state, kind) do
    if state.ready_waiter, do: GenServer.reply(state.ready_waiter, {:error, error(kind, :ready)})

    cond do
      state.interview ->
        GenServer.reply(state.interview.from, {:ok, Flow.finish(state.interview.flow, kind)})

      state.pending ->
        GenServer.reply(state.pending.from, {:error, error(kind, :command)})

      true ->
        :ok
    end
  end

  defp handle_for(state),
    do: %Handle{owner: self(), epoch: state.epoch, timeout_ms: state.config.timeout_ms}

  defp version_bytes({a, b, c, d, e}), do: <<a, b, c, d, e>>

  defp serial_options(config) do
    [
      baud_rate: 115_200,
      data_bits: 8,
      stop_bits: 1,
      parity: :none,
      flow_control: config.flow_control
    ] ++
      config.serial_options
  end

  defp safe_call(owner, message, timeout) do
    GenServer.call(owner, message, timeout)
  catch
    :exit, {:timeout, _} -> {:error, error(:timeout, :owner)}
    :exit, _ -> {:error, error(:coordinator_lost, :owner)}
  end

  defp error(kind, operation), do: %Error{kind: kind, operation: operation}
end
