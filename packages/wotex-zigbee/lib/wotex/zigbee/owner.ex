defmodule Wotex.Zigbee.Owner do
  @moduledoc """
  One explicit TI ZNP serial owner with a negotiated firmware epoch.

  The owner accepts fragmented serial chunks, permits one outstanding SREQ,
  keeps AREQs in a finite queue and reports its overflow count. A command
  timeout ends the owner instead of matching a late SRSP to a later request.
  An interview, binding, network inspection or channel migration holds that slot
  across its observations while preserving unrelated indications. Caller
  death also ends a pending epoch.
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
    Binding,
    ChannelMigration,
    Command,
    Config,
    Credentials,
    Downlinks,
    Error,
    Event,
    Frame,
    Handle,
    Interview,
    KeyRotation,
    PermitJoin,
    Reply,
    Routes
  }

  alias Wotex.Zigbee.Binding.Flow, as: BindingFlow
  alias Wotex.Zigbee.ChannelMigration.Flow, as: MigrationFlow
  alias Wotex.Zigbee.Credentials.{KeyCall, PortCall}
  alias Wotex.Zigbee.Interview.Flow
  alias Wotex.Zigbee.KeyRotation.Flow, as: RotationFlow
  alias Wotex.Zigbee.KeyRotation.Wire, as: RotationWire
  alias Wotex.Zigbee.Network.Flow, as: NetworkFlow
  alias Wotex.Zigbee.PeerProbe.Flow, as: ProbeFlow
  alias Wotex.Zigbee.PermitJoin.Result, as: PermitResult

  @max_query_routes 128
  @max_binding_pairs 256
  @operations [
    :command,
    :interview,
    :routed,
    :queued,
    :binding,
    :network,
    :permit_join,
    :channel_migration,
    :key_rotation,
    :close,
    :drain
  ]

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

  def call(%Handle{owner: owner, epoch: epoch, timeout_ms: limit}, :network, [timeout])
      when is_pid(owner) and is_reference(epoch) and is_integer(limit) and limit > 0 do
    valid_timeout = is_integer(timeout) and timeout > 0
    wait = if valid_timeout, do: min(timeout, limit) + 100, else: limit + 100
    deadline = if valid_timeout, do: System.monotonic_time(:millisecond) + min(timeout, limit)
    safe_call(owner, {:network, epoch, [timeout, deadline]}, wait)
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
             operation in [:routed, :queued, :binding, :permit_join] do
    valid_timeout = is_integer(timeout) and timeout > 0
    wait = if valid_timeout, do: min(timeout, limit) + 100, else: limit + 100
    deadline = if valid_timeout, do: System.monotonic_time(:millisecond) + min(timeout, limit)
    safe_call(owner, {operation, epoch, [routes, request, timeout, deadline]}, wait)
  end

  def call(%Handle{owner: owner, epoch: epoch, timeout_ms: limit}, operation, [
        credentials,
        routes,
        request,
        timeout
      ])
      when is_pid(owner) and is_reference(epoch) and is_integer(limit) and limit > 0 and
             operation in [:channel_migration, :key_rotation] do
    valid_timeout = is_integer(timeout) and timeout > 0
    wait = if valid_timeout, do: min(timeout, limit) + 100, else: limit + 100
    deadline = if valid_timeout, do: System.monotonic_time(:millisecond) + min(timeout, limit)

    safe_call(
      owner,
      {operation, epoch, [credentials, routes, request, timeout, deadline]},
      wait
    )
  end

  def call(_, operation, _)
      when operation in @operations,
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

      busy?(state) ->
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

  def handle_call({:binding, epoch, [routes, request, timeout, deadline]}, from, state) do
    deadline = bounded_deadline(deadline, timeout, state.config.timeout_ms)

    with :ok <- binding_admission(state, epoch, request, timeout, deadline, from),
         {:ok, expiry} <-
           Routes.check_peer(
             routes,
             request.peer_ieee,
             request.route_address,
             state.epoch,
             System.monotonic_time(:millisecond)
           ) do
      send_binding(state, request, min(deadline, expiry), from)
    else
      {:error, _} = failure -> {:reply, failure, state}
    end
  end

  def handle_call({:network, epoch, [timeout, deadline]}, from, state) do
    deadline = bounded_deadline(deadline, timeout, state.config.timeout_ms)

    case network_admission(state, epoch, timeout, deadline, from) do
      :ok -> send_network(state, deadline, from)
      kind -> {:reply, {:error, error(kind, :network)}, state}
    end
  end

  def handle_call({:permit_join, epoch, [credentials, request, timeout, deadline]}, from, state) do
    deadline = bounded_deadline(deadline, timeout, state.config.timeout_ms)

    with :ok <- network_admission(state, epoch, timeout, deadline, from),
         true <- Credentials.valid?(credentials) and PermitJoin.valid?(request) do
      send_network(state, deadline, from, %{credentials: credentials, request: request})
    else
      false -> {:reply, {:error, error(:invalid_value, :permit_join)}, state}
      kind -> {:reply, {:error, error(kind, :permit_join)}, state}
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

  def handle_call(
        {:channel_migration, epoch, [credentials, routes, request, timeout, deadline]},
        from,
        state
      ) do
    with :ok <- network_admission(state, epoch, timeout, deadline, from),
         true <- Credentials.valid?(credentials) and ChannelMigration.valid?(request),
         {:ok, bounded} <- migration_custody(routes, request, state.epoch, deadline),
         {:ok, tokens} <- migration_tokens(state, request) do
      send_migration(state, credentials, routes, request, bounded, tokens, from)
    else
      false -> {:reply, {:error, error(:invalid_value, :channel_migration)}, state}
      {:error, %Error{} = error} -> {:reply, {:error, error}, state}
      kind -> {:reply, {:error, error(kind, :channel_migration)}, state}
    end
  end

  def handle_call(
        {:key_rotation, epoch, [credentials, routes, request, timeout, deadline]},
        from,
        state
      ) do
    with :ok <- network_admission(state, epoch, timeout, deadline, from),
         true <- Credentials.valid?(credentials) and KeyRotation.valid?(request),
         {:ok, bounded} <- migration_custody(routes, request, state.epoch, deadline),
         {:ok, tokens} <- migration_tokens(state, request) do
      send_migration(state, credentials, routes, request, bounded, tokens, from)
    else
      false -> {:reply, {:error, error(:invalid_value, :key_rotation)}, state}
      {:error, %Error{} = error} -> {:reply, {:error, error}, state}
      kind -> {:reply, {:error, error(kind, :key_rotation)}, state}
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

  def handle_info({:binding_timeout, reference}, %{binding: %{reference: reference}} = state),
    do: {:stop, :normal, end_binding(state, :timeout, true)}

  def handle_info({:network_timeout, reference}, %{network: %{reference: reference}} = state),
    do: {:stop, :normal, end_network(state, :timeout)}

  def handle_info({:migration_timeout, reference}, %{migration: %{reference: reference}} = state),
    do: {:stop, :normal, end_migration(state, :timeout, true)}

  def handle_info(
        {:migration_settled, reference},
        %{migration: %{reference: reference, phase: :settle}} = state
      ),
      do: migration_info(start_migration_readings(state))

  def handle_info(
        {:migration_settled, reference},
        %{migration: %{reference: reference, phase: :distribute}} = state
      ),
      do: migration_info(start_switch_readings(state))

  def handle_info(
        {:migration_peer_timeout, reference},
        %{migration: %{peer_reference: reference, phase: :peer}} = state
      ),
      do: migration_info(expire_migration_peer(state))

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

  def handle_info({:DOWN, monitor, :process, _, _}, %{binding: %{monitor: monitor}} = state),
    do: {:stop, :normal, end_binding(state, :coordinator_lost, true)}

  def handle_info({:DOWN, monitor, :process, _, _}, %{network: %{monitor: monitor}} = state),
    do: {:stop, :normal, end_network(state, :coordinator_lost)}

  def handle_info({:DOWN, monitor, :process, _, _}, %{migration: %{monitor: monitor}} = state),
    do: {:stop, :normal, end_migration(state, :coordinator_lost, true)}

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

  defp accept_frame(%Frame{type: :srsp} = frame, %{migration: migration, pending: pending} = state)
       when is_map(migration) and is_map(pending) do
    cond do
      expired?(migration.deadline) or expired?(pending.deadline) ->
        end_migration(state, :timeout, true)

      frame.subsystem != pending.subsystem or frame.id != pending.id ->
        end_migration(state, :invalid_frame, true)

      true ->
        accept_migration_reply(state, frame)
    end
  end

  defp accept_frame(%Frame{type: :srsp} = frame, %{network: network, pending: pending} = state)
       when is_map(network) and is_map(pending) do
    cond do
      expired?(network.deadline) ->
        end_network(state, :timeout)

      frame.subsystem != pending.subsystem or frame.id != pending.id ->
        end_network(state, :invalid_frame)

      true ->
        accept_network_reply(state, frame)
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

        accept_admission(state, pending, reply)
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

    state = remember_binding_callback(state, event)
    accept_event(state, event)
  end

  defp accept_frame(_, state), do: state

  defp accept_admission(%{interview: interview} = state, _, reply) when is_map(interview) do
    flow = Flow.admit(interview.flow, reply)
    progress_interview(%{state | pending: nil, interview: %{interview | flow: flow}})
  end

  defp accept_admission(%{binding: binding} = state, _, reply) when is_map(binding) do
    flow = BindingFlow.admit(binding.flow, reply)
    progress_binding(%{state | pending: nil, binding: %{binding | flow: flow}})
  end

  defp accept_admission(state, pending, reply) do
    GenServer.reply(pending.from, {:ok, reply})
    clear_pending(state)
  end

  defp accept_event(%{migration: %{phase: :peer}} = state, event) do
    if migration_source?(state, event) do
      case ProbeFlow.offer(state.migration.flow.probes, event) do
        {:matched, probes} ->
          flow = %{state.migration.flow | probes: probes}
          progress_migration_peer(%{state | migration: %{state.migration | flow: flow}})

        :unmatched ->
          enqueue_event(state, event)
      end
    else
      enqueue_event(state, event)
    end
  end

  defp accept_event(%{binding: binding} = state, event) when is_map(binding) do
    case BindingFlow.offer(binding.flow, event) do
      {:matched, flow} -> progress_binding(%{state | binding: %{binding | flow: flow}})
      :unmatched -> enqueue_event(state, event)
    end
  end

  defp accept_event(state, event) do
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
      busy?(state) -> :overload
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
    cond do
      expired?(state.interview.deadline) ->
        end_interview(state, :timeout, true)

      not Process.alive?(elem(state.interview.from, 0)) ->
        end_interview(state, :caller_lost, true)

      true ->
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

  defp fail_response(%{binding: binding} = state, kind) when is_map(binding),
    do: end_binding(state, kind, true)

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
      binding: nil,
      network: nil,
      migration: nil,
      used_bindings: MapSet.new(),
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

  defp busy?(state),
    do:
      Enum.any?(
        [state.pending, state.interview, state.binding, state.network, state.migration],
        &(&1 != nil)
      )

  defp binding_admission(state, epoch, request, timeout, deadline, from) do
    kind =
      cond do
        epoch != state.epoch ->
          :stale_handle

        state.mode != :ready ->
          :coordinator_lost

        busy?(state) ->
          :overload

        not Binding.valid?(request) ->
          :invalid_value

        not valid_timeout?(timeout, state.config.timeout_ms) ->
          :invalid_value

        expired?(deadline) ->
          :timeout

        MapSet.member?(state.used_bindings, {request.operation, request.route_address}) ->
          :correlation_exhausted

        MapSet.size(state.used_bindings) >= @max_binding_pairs ->
          :overload

        not Process.alive?(elem(from, 0)) ->
          :coordinator_lost

        true ->
          nil
      end

    if kind, do: {:error, error(kind, :binding)}, else: :ok
  end

  defp send_binding(state, request, deadline, from) do
    reference = make_ref()

    binding = %{
      flow: BindingFlow.new(request, state.epoch),
      from: from,
      reference: reference,
      monitor: Process.monitor(elem(from, 0)),
      timer: deadline_timer({:binding_timeout, reference}, deadline),
      deadline: deadline
    }

    {:ok, frame} = Binding.frame(request)
    pairs = MapSet.put(state.used_bindings, {request.operation, request.route_address})
    updated = %{state | binding: binding, used_bindings: pairs}

    case write_budgeted_frame(updated, frame, deadline) do
      :ok ->
        {:noreply, %{updated | pending: %{subsystem: 5, id: frame.id, deadline: deadline}}}

      {:refused, kind} ->
        clear_binding(updated)
        {:reply, {:error, error(kind, :binding)}, state}

      {:failed, kind} ->
        {:stop, :normal, end_binding(updated, kind, true)}
    end
  end

  defp write_budgeted_frame(state, frame, deadline) do
    {:ok, bytes} = Frame.encode(frame)

    if expired?(deadline) do
      {:refused, :timeout}
    else
      case serial_write(state, bytes) do
        :ok -> if expired?(deadline), do: {:failed, :timeout}, else: :ok
        :error -> {:failed, :serial}
      end
    end
  end

  defp progress_binding(state) do
    cond do
      expired?(state.binding.deadline) ->
        end_binding(state, :timeout, true)

      not Process.alive?(elem(state.binding.from, 0)) ->
        end_binding(state, :coordinator_lost, true)

      true ->
        case BindingFlow.advance(state.binding.flow) do
          :waiting -> state
          {:done, result} -> reply_binding(state, result)
        end
    end
  end

  defp end_binding(state, kind, failed) do
    updated = reply_binding(state, BindingFlow.finish(state.binding.flow, kind))
    if failed, do: %{updated | mode: :failed}, else: updated
  end

  defp reply_binding(state, result) do
    GenServer.reply(state.binding.from, {:ok, result})
    clear_binding(state)
  end

  defp clear_binding(state) do
    Process.cancel_timer(state.binding.timer)
    Process.demonitor(state.binding.monitor, [:flush])
    %{state | binding: nil, pending: nil}
  end

  defp remember_binding_callback(state, %Event{kind: kind, source_address: route})
       when kind in [:zdo_bind, :zdo_unbind] do
    operation = if kind == :zdo_bind, do: :bind, else: :unbind

    if MapSet.size(state.used_bindings) < @max_binding_pairs,
      do: %{state | used_bindings: MapSet.put(state.used_bindings, {operation, route})},
      else: state
  end

  defp remember_binding_callback(state, _), do: state

  defp network_admission(state, epoch, timeout, deadline, from) do
    cond do
      epoch != state.epoch -> :stale_handle
      state.mode != :ready -> :coordinator_lost
      busy?(state) -> :overload
      not valid_timeout?(timeout, state.config.timeout_ms) -> :invalid_value
      expired?(deadline) -> :timeout
      not Process.alive?(elem(from, 0)) -> :coordinator_lost
      true -> :ok
    end
  end

  defp send_network(state, deadline, from, purpose \\ nil) do
    reference = make_ref()

    network = %{
      flow: NetworkFlow.new(state.epoch),
      phase: :metadata,
      purpose: purpose,
      snapshot: nil,
      admission: nil,
      from: from,
      reference: reference,
      monitor: Process.monitor(elem(from, 0)),
      timer: deadline_timer({:network_timeout, reference}, deadline),
      deadline: deadline
    }

    updated = %{state | network: network}

    case issue_network(updated) do
      {:ok, next} ->
        {:noreply, next}

      {:refused, next} ->
        clear_network(next)
        operation = if purpose == nil, do: :network, else: :permit_join
        {:reply, {:error, error(:timeout, operation)}, state}

      {:failed, next} ->
        {:stop, :normal, next}
    end
  end

  defp issue_network(state) do
    if Process.alive?(elem(state.network.from, 0)),
      do: write_network(state),
      else: {:failed, end_network(state, :coordinator_lost)}
  end

  defp write_network(state) do
    {:ok, frame} = NetworkFlow.command(state.network.flow)

    case write_budgeted_frame(state, frame, state.network.deadline) do
      :ok ->
        {:ok,
         %{
           state
           | pending: %{subsystem: frame.subsystem, id: frame.id, deadline: state.network.deadline}
         }}

      {:refused, _} when state.network.flow.readings == [] ->
        {:refused, state}

      {_, kind} ->
        {:failed, end_network(state, kind)}
    end
  end

  defp progress_network(state) do
    cond do
      expired?(state.network.deadline) ->
        end_network(state, :timeout)

      not Process.alive?(elem(state.network.from, 0)) ->
        end_network(state, :coordinator_lost)

      true ->
        advance_network(state)
    end
  end

  defp end_network(state, kind),
    do: %{reply_network(state, finish_network(state, kind)) | mode: :failed}

  defp accept_network_reply(%{network: %{phase: :permit_join}} = state, frame) do
    case frame.payload do
      <<status>> ->
        reply = %Reply{subsystem: 5, id: 0x36, status: status, payload: frame.payload}
        network = %{state.network | admission: reply}
        progress_network(%{state | network: network, pending: nil})

      _ ->
        end_network(state, :invalid_frame)
    end
  end

  defp accept_network_reply(state, frame) do
    case NetworkFlow.admit(state.network.flow, frame.payload, System.monotonic_time(:millisecond)) do
      {:ok, flow} ->
        network = %{state.network | flow: flow}
        progress_network(%{state | network: network, pending: nil})

      {:error, _} ->
        end_network(state, :invalid_frame)
    end
  end

  defp advance_network(%{network: %{phase: :permit_join}} = state),
    do: reply_network(state, finish_network(state, nil))

  defp advance_network(state) do
    case NetworkFlow.advance(state.network.flow) do
      {:done, snapshot} -> complete_network(state, snapshot)
      {:next, _} -> advance_network_query(state)
    end
  end

  defp advance_network_query(state) do
    case issue_network(state) do
      {:ok, next} -> next
      {:failed, next} -> next
    end
  end

  defp complete_network(%{network: %{purpose: nil}} = state, snapshot),
    do: reply_network(state, snapshot)

  defp complete_network(state, snapshot) do
    state = %{state | network: %{state.network | snapshot: snapshot}}

    if PermitJoin.matches_snapshot?(state.network.purpose.request, snapshot),
      do: authorize_permit(state),
      else: reject_permit(state, snapshot.issue || :network_mismatch)
  end

  defp authorize_permit(state) do
    now = System.monotonic_time(:millisecond)

    cond do
      not Process.alive?(elem(state.network.from, 0)) -> end_network(state, :coordinator_lost)
      now >= state.network.deadline -> reject_permit(state, :timeout)
      true -> call_credential_port(state, now)
    end
  end

  defp call_credential_port(state, now) do
    context = %{
      operation: :permit_join,
      owner_epoch: state.epoch,
      request: state.network.purpose.request,
      network: state.network.snapshot,
      now_ms: now,
      deadline_ms: state.network.deadline
    }

    authorization =
      PortCall.authorize(state.network.purpose.credentials, context, context.deadline_ms - now)

    cond do
      not Process.alive?(elem(state.network.from, 0)) -> end_network(state, :coordinator_lost)
      expired?(state.network.deadline) -> reject_permit(state, :timeout)
      true -> finish_authorization(state, authorization)
    end
  end

  defp finish_authorization(state, {:error, kind}), do: reject_permit(state, kind)

  defp finish_authorization(state, {:ok, horizon}) do
    duration = state.network.purpose.request.duration_s * 1_000
    deadline = min(state.network.deadline, horizon - duration)

    if expired?(deadline),
      do: reject_permit(state, :timeout),
      else: dispatch_permit(state, deadline)
  end

  defp dispatch_permit(state, deadline) do
    {:ok, frame} = PermitJoin.frame(state.network.purpose.request)
    Process.cancel_timer(state.network.timer)

    network = %{
      state.network
      | phase: :permit_join,
        purpose: Map.delete(state.network.purpose, :credentials),
        deadline: deadline,
        timer: deadline_timer({:network_timeout, state.network.reference}, deadline)
    }

    state = %{state | network: network}

    case write_budgeted_frame(state, frame, deadline) do
      :ok -> %{state | pending: %{subsystem: 5, id: 0x36, deadline: deadline}}
      {:refused, kind} -> reject_permit(state, kind)
      {:failed, kind} -> end_network(state, kind)
    end
  end

  defp reject_permit(state, kind), do: reply_network(state, finish_network(state, kind))

  defp finish_network(%{network: %{purpose: nil}} = state, kind),
    do: NetworkFlow.finish(state.network.flow, kind)

  defp finish_network(state, kind) do
    network = state.network.snapshot || NetworkFlow.finish(state.network.flow, kind)
    {outcome, issue} = permit_outcome(state.network.admission, kind)

    %PermitResult{
      request: state.network.purpose.request,
      owner_epoch: state.epoch,
      network: network,
      admission: state.network.admission,
      outcome: outcome,
      issue: issue
    }
  end

  defp permit_outcome(_, kind) when kind != nil, do: {:unconfirmed, kind}
  defp permit_outcome(%Reply{status: 0}, nil), do: {:ncp_admitted, nil}
  defp permit_outcome(%Reply{}, nil), do: {:ncp_rejected, :status_failure}

  defp reply_network(state, snapshot) do
    GenServer.reply(state.network.from, {:ok, snapshot})
    clear_network(state)
  end

  defp clear_network(state) do
    Process.cancel_timer(state.network.timer)
    Process.demonitor(state.network.monitor, [:flush])
    %{state | network: nil, pending: nil}
  end

  defp migration_custody(routes, request, epoch, deadline) do
    now = System.monotonic_time(:millisecond)

    Enum.reduce_while(request.peers, {:ok, deadline}, fn peer, {:ok, bounded} ->
      case Routes.check_peer(routes, peer.peer_ieee, peer.route_address, epoch, now) do
        {:ok, expiry} -> {:cont, {:ok, min(bounded, expiry)}}
        error -> {:halt, error}
      end
    end)
  end

  defp migration_tokens(state, request) do
    tokens = Enum.reject(0..255, &MapSet.member?(state.used_tokens, &1))
    count = length(request.peers)

    if length(tokens) >= count,
      do: {:ok, Enum.take(tokens, count)},
      else: :correlation_exhausted
  end

  defp send_migration(state, credentials, routes, request, deadline, tokens, from) do
    reference = make_ref()
    kind = if match?(%KeyRotation{}, request), do: :key_rotation, else: :channel_migration

    flow =
      if kind == :key_rotation,
        do: RotationFlow.new(request, state.epoch, tokens),
        else: MigrationFlow.new(request, state.epoch, tokens)

    migration = %{
      flow: flow,
      kind: kind,
      network_flow: NetworkFlow.new(state.epoch),
      phase: :before,
      credentials: credentials,
      routes: routes,
      dispatched: false,
      from: from,
      reference: reference,
      monitor: Process.monitor(elem(from, 0)),
      timer: deadline_timer({:migration_timeout, reference}, deadline),
      settle_timer: nil,
      peer_timer: nil,
      peer_reference: nil,
      peer_deadline: nil,
      dispatch_deadline: nil,
      deadline: deadline
    }

    next = write_migration(%{state | migration: migration})
    if next.mode == :failed, do: {:stop, :normal, next}, else: {:noreply, next}
  end

  defp write_migration(state) do
    cond do
      not Process.alive?(elem(state.migration.from, 0)) ->
        end_migration(state, :coordinator_lost, true)

      expired?(state.migration.deadline) ->
        end_migration(state, :timeout, state.pending != nil)

      true ->
        issue_migration_frame(state)
    end
  end

  defp issue_migration_frame(state) do
    if state.migration.kind == :key_rotation and state.migration.phase == :move,
      do: issue_key_update(state),
      else: issue_public_migration_frame(state)
  end

  defp issue_public_migration_frame(state) do
    {:ok, frame} = migration_frame(state.migration)
    deadline = state.migration.peer_deadline || state.migration.deadline

    write_deadline =
      if state.migration.phase in [:move, :switch],
        do: state.migration.dispatch_deadline,
        else: deadline

    case write_budgeted_frame(state, frame, write_deadline) do
      :ok ->
        %{
          state
          | pending: %{subsystem: frame.subsystem, id: frame.id, deadline: deadline},
            migration: %{
              state.migration
              | dispatched: state.migration.dispatched or frame.id in [0x37, 0x4F]
            }
        }

      {:refused, kind} ->
        end_migration(state, kind, false)

      {:failed, kind} ->
        end_migration(state, kind, true)
    end
  end

  defp migration_frame(%{phase: phase, network_flow: flow})
       when phase in [:before, :before_switch, :after],
       do: NetworkFlow.command(flow)

  defp migration_frame(%{phase: :move, flow: flow}), do: ChannelMigration.frame(flow.request)
  defp migration_frame(%{phase: :switch, flow: flow}), do: {:ok, RotationWire.switch(flow.request)}
  defp migration_frame(%{phase: :peer, flow: flow}), do: ProbeFlow.command(flow.probes)

  defp accept_migration_reply(%{migration: %{phase: phase}} = state, frame)
       when phase in [:before, :before_switch, :after] do
    case NetworkFlow.admit(
           state.migration.network_flow,
           frame.payload,
           System.monotonic_time(:millisecond)
         ) do
      {:ok, flow} ->
        migration = %{state.migration | network_flow: flow}
        progress_migration_readings(%{state | migration: migration, pending: nil})

      {:error, _} ->
        end_migration(state, :invalid_frame, true)
    end
  end

  defp accept_migration_reply(state, %Frame{payload: <<status>>} = frame) do
    reply = %Reply{subsystem: frame.subsystem, id: frame.id, status: status, payload: frame.payload}
    state = %{state | pending: nil}

    case state.migration.phase do
      :move ->
        flow = %{state.migration.flow | admission: reply}
        progress_migration_move(%{state | migration: %{state.migration | flow: flow}})

      :peer ->
        flow = %{state.migration.flow | probes: ProbeFlow.admit(state.migration.flow.probes, reply)}
        progress_migration_peer(%{state | migration: %{state.migration | flow: flow}})

      :switch ->
        flow = %{state.migration.flow | switch: reply}
        progress_key_switch(%{state | migration: %{state.migration | flow: flow}})
    end
  end

  defp accept_migration_reply(state, _), do: end_migration(state, :invalid_frame, true)

  defp migration_lifetime(state) do
    cond do
      not Process.alive?(elem(state.migration.from, 0)) -> :coordinator_lost
      expired?(state.migration.deadline) -> :timeout
      true -> :ok
    end
  end

  defp progress_migration_readings(state) do
    case migration_lifetime(state) do
      :ok -> advance_migration_readings(state)
      kind -> end_migration(state, kind, true)
    end
  end

  defp advance_migration_readings(state) do
    case NetworkFlow.advance(state.migration.network_flow) do
      {:next, _} ->
        write_migration(state)

      {:done, snapshot} ->
        phase = state.migration.phase
        flow = Map.put(state.migration.flow, phase, snapshot)
        state = %{state | migration: %{state.migration | flow: flow}}

        if administration_matches?(state.migration.kind, flow.request, snapshot, phase),
          do: complete_migration_readings(state, phase),
          else: end_migration(state, snapshot.issue || :network_mismatch, false)
    end
  end

  defp complete_migration_readings(state, :before), do: authorize_migration(state)
  defp complete_migration_readings(state, :before_switch), do: authorize_migration(state)
  defp complete_migration_readings(state, :after), do: start_migration_peer(state)

  defp authorize_migration(state) do
    now = System.monotonic_time(:millisecond)

    cond do
      not Process.alive?(elem(state.migration.from, 0)) ->
        end_migration(state, :coordinator_lost, true)

      now >= state.migration.deadline ->
        end_migration(state, :timeout, false)

      true ->
        call_migration_authority(state, now)
    end
  end

  defp call_migration_authority(state, now) do
    context = administration_context(state, now)

    authorization =
      PortCall.authorize(state.migration.credentials, context, context.deadline_ms - now)

    case migration_lifetime(state) do
      :ok -> dispatch_administration(state, authorization)
      :timeout -> end_migration(state, :timeout, false)
      kind -> end_migration(state, kind, true)
    end
  end

  defp administration_context(state, now) do
    context = %{
      operation: state.migration.kind,
      request: state.migration.flow.request,
      network: Map.get(state.migration.flow, state.migration.phase, state.migration.flow.before),
      owner_epoch: state.epoch,
      now_ms: now,
      deadline_ms: state.migration.deadline
    }

    if state.migration.kind == :key_rotation,
      do:
        Map.merge(context, %{
          phase: if(state.migration.phase == :before_switch, do: :switch, else: :update),
          update: state.migration.flow.admission
        }),
      else: context
  end

  defp dispatch_administration(%{migration: %{kind: :key_rotation}} = state, result),
    do: dispatch_rotation(state, result)

  defp dispatch_administration(state, result), do: dispatch_migration(state, result)

  defp dispatch_migration(state, {:error, kind}), do: end_migration(state, kind, false)

  defp dispatch_migration(state, {:ok, horizon}) do
    request = state.migration.flow.request
    deadline = min(state.migration.deadline, horizon)

    case migration_custody(state.migration.routes, request, state.epoch, deadline) do
      {:ok, bounded} ->
        dispatch_deadline = min(bounded, horizon - request.settle_ms)

        if expired?(dispatch_deadline),
          do: end_migration(state, :timeout, false),
          else: write_migration_move(state, bounded, dispatch_deadline)

      {:error, error} ->
        end_migration(state, error.kind, false)
    end
  end

  defp write_migration_move(state, deadline, dispatch_deadline) do
    Process.cancel_timer(state.migration.timer)
    tokens = Enum.map(state.migration.flow.probes.peers, & &1.token)
    used = Enum.reduce(tokens, state.used_tokens, &MapSet.put(&2, &1))

    migration = %{
      state.migration
      | phase: :move,
        credentials: nil,
        dispatch_deadline: dispatch_deadline,
        deadline: deadline,
        timer: deadline_timer({:migration_timeout, state.migration.reference}, deadline)
    }

    write_migration(%{state | migration: migration, used_tokens: used})
  end

  defp progress_migration_move(state) do
    case migration_lifetime(state) do
      :ok ->
        if state.migration.flow.admission.status == 0,
          do: settle_administration(state),
          else: end_migration(state, :status_failure, false)

      kind ->
        end_migration(state, kind, true)
    end
  end

  defp settle_migration(state) do
    timer =
      Process.send_after(
        self(),
        {:migration_settled, state.migration.reference},
        state.migration.flow.request.settle_ms
      )

    %{state | migration: %{state.migration | phase: :settle, settle_timer: timer}}
  end

  defp start_migration_readings(state) do
    migration = %{state.migration | phase: :after, network_flow: NetworkFlow.new(state.epoch)}
    write_migration(%{state | migration: migration})
  end

  defp start_migration_peer(state) do
    reference = make_ref()

    deadline =
      min(
        state.migration.deadline,
        System.monotonic_time(:millisecond) + state.migration.flow.request.peer_timeout_ms
      )

    migration = %{
      state.migration
      | phase: :peer,
        peer_reference: reference,
        peer_deadline: deadline,
        peer_timer: deadline_timer({:migration_peer_timeout, reference}, deadline)
    }

    write_migration(%{state | migration: migration})
  end

  defp migration_source?(state, %Event{kind: :af_incoming} = event),
    do:
      match?(
        {:ok, _},
        Routes.resolve(state.migration.routes, event, System.monotonic_time(:millisecond))
      )

  defp migration_source?(_, _), do: true

  defp progress_migration_peer(state) do
    case migration_lifetime(state) do
      :ok ->
        if expired?(state.migration.peer_deadline),
          do: expire_migration_peer(state),
          else: advance_probe(state)

      kind ->
        end_migration(state, kind, true)
    end
  end

  defp expire_migration_peer(state) do
    if state.pending != nil or expired?(state.migration.deadline) do
      end_migration(state, :timeout, true)
    else
      {phase, probes} = ProbeFlow.finish_peer(state.migration.flow.probes, :timeout)
      advance_migration_peer(state, {phase, %{state.migration.flow | probes: probes}})
    end
  end

  defp advance_migration_peer(state, {:waiting, _}), do: state

  defp advance_migration_peer(state, {phase, flow}) do
    Process.cancel_timer(state.migration.peer_timer)
    state = %{state | migration: %{state.migration | flow: flow, peer_deadline: nil}}
    if phase == :done, do: end_migration(state, nil, false), else: start_migration_peer(state)
  end

  defp advance_probe(state) do
    {phase, probes} = ProbeFlow.advance(state.migration.flow.probes)
    advance_migration_peer(state, {phase, %{state.migration.flow | probes: probes}})
  end

  defp administration_matches?(:key_rotation, request, snapshot, _),
    do: KeyRotation.matches_snapshot?(request, snapshot)

  defp administration_matches?(:channel_migration, request, snapshot, phase),
    do: ChannelMigration.matches_snapshot?(request, snapshot, phase)

  defp issue_key_update(state) do
    now = System.monotonic_time(:millisecond)
    deadline = state.migration.dispatch_deadline

    if now >= deadline do
      end_migration(state, :timeout, false)
    else
      context = administration_context(state, now)

      writer = fn key ->
        frame = RotationWire.update(state.migration.flow.request, key)
        write_budgeted_frame(state, frame, deadline)
      end

      result =
        KeyCall.dispatch(
          state.migration.credentials,
          context,
          deadline - now,
          deadline,
          elem(state.migration.from, 0),
          writer
        )

      if Process.alive?(elem(state.migration.from, 0)),
        do: finish_key_dispatch(state, result),
        else: end_migration(state, :coordinator_lost, true)
    end
  end

  defp finish_key_dispatch(state, result) do
    case result do
      :ok ->
        state = %{
          state
          | migration: %{state.migration | dispatched: true},
            pending: %{subsystem: 5, id: 0x4E, deadline: state.migration.deadline}
        }

        case migration_lifetime(state) do
          :ok -> state
          kind -> end_migration(state, kind, true)
        end

      {:refused, kind} ->
        end_migration(state, kind, false)

      {:failed, kind} ->
        end_migration(state, kind, true)
    end
  end

  defp dispatch_rotation(state, {:error, kind}), do: end_migration(state, kind, false)

  defp dispatch_rotation(state, {:ok, horizon}) do
    request = state.migration.flow.request
    switching = state.migration.phase == :before_switch
    reserve = request.settle_ms + if(switching, do: 0, else: request.distribution_ms)
    deadline = min(state.migration.deadline, horizon)

    case migration_custody(state.migration.routes, request, state.epoch, deadline) do
      {:ok, bounded} ->
        dispatch = bounded - reserve

        if expired?(dispatch),
          do: end_migration(state, :timeout, false),
          else: write_rotation(state, bounded, dispatch, switching)

      {:error, error} ->
        end_migration(state, error.kind, false)
    end
  end

  defp write_rotation(state, deadline, dispatch, switching) do
    Process.cancel_timer(state.migration.timer)
    tokens = Enum.map(state.migration.flow.probes.peers, & &1.token)
    used = Enum.reduce(tokens, state.used_tokens, &MapSet.put(&2, &1))

    migration = %{
      state.migration
      | phase: if(switching, do: :switch, else: :move),
        deadline: deadline,
        dispatch_deadline: dispatch,
        timer: deadline_timer({:migration_timeout, state.migration.reference}, deadline)
    }

    write_migration(%{state | migration: migration, used_tokens: used})
  end

  defp settle_administration(%{migration: %{kind: :key_rotation}} = state) do
    timer =
      Process.send_after(
        self(),
        {:migration_settled, state.migration.reference},
        state.migration.flow.request.distribution_ms
      )

    %{state | migration: %{state.migration | phase: :distribute, settle_timer: timer}}
  end

  defp settle_administration(state), do: settle_migration(state)

  defp start_switch_readings(state) do
    migration = %{
      state.migration
      | phase: :before_switch,
        network_flow: NetworkFlow.new(state.epoch)
    }

    write_migration(%{state | migration: migration})
  end

  defp progress_key_switch(state) do
    case migration_lifetime(state) do
      :ok ->
        if state.migration.flow.switch.status == 0,
          do: settle_migration(%{state | migration: %{state.migration | credentials: nil}}),
          else: end_migration(state, :status_failure, false)

      kind ->
        end_migration(state, kind, true)
    end
  end

  defp migration_result(state, kind) do
    migration = state.migration

    flow =
      if migration.phase in [:before, :before_switch, :after] and
           Map.get(migration.flow, migration.phase) == nil do
        Map.put(migration.flow, migration.phase, NetworkFlow.finish(migration.network_flow, kind))
      else
        migration.flow
      end

    if migration.kind == :key_rotation,
      do: RotationFlow.finish(flow, kind),
      else: MigrationFlow.finish(flow, kind)
  end

  defp end_migration(state, kind, failed) do
    GenServer.reply(state.migration.from, {:ok, migration_result(state, kind)})
    Process.demonitor(state.migration.monitor, [:flush])

    for timer <- [state.migration.timer, state.migration.settle_timer, state.migration.peer_timer],
        is_reference(timer),
        do: Process.cancel_timer(timer)

    mode = if failed or state.migration.dispatched, do: :failed, else: state.mode
    %{state | migration: nil, pending: nil, mode: mode}
  end

  defp migration_info(%{mode: :failed} = state), do: {:stop, :normal, state}
  defp migration_info(state), do: {:noreply, state}

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

      state.binding ->
        GenServer.reply(state.binding.from, {:ok, BindingFlow.finish(state.binding.flow, kind)})

      state.network ->
        GenServer.reply(state.network.from, {:ok, finish_network(state, kind)})

      state.migration ->
        GenServer.reply(state.migration.from, {:ok, migration_result(state, kind)})

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
