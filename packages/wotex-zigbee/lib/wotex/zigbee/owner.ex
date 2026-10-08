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
  """

  use GenServer

  alias Wotex.Zigbee.{Command, Config, Error, Event, Frame, Handle, Interview, Reply, Routes}
  alias Wotex.Zigbee.Interview.Flow

  @max_query_routes 128

  @doc "Starts a coordinator owner under a consumer supervisor."
  @spec start_link(Config.t()) :: GenServer.on_start()
  def start_link(%Config{} = config), do: GenServer.start_link(__MODULE__, config)

  @doc "Starts an owner without linking while serial/version admission runs."
  @spec start(Config.t()) :: GenServer.on_start()
  def start(%Config{} = config), do: GenServer.start(__MODULE__, config)

  @doc "Waits for exact SYS_VERSION negotiation and obtains this owner epoch."
  @spec ready(pid(), pos_integer()) :: {:ok, Handle.t()} | {:error, Error.t()}
  def ready(owner, timeout), do: safe_call(owner, :ready, timeout + 100)

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

  def call(%Handle{owner: owner, epoch: epoch, timeout_ms: limit}, :routed, [
        routes,
        request,
        timeout
      ])
      when is_pid(owner) and is_reference(epoch) and is_integer(limit) and limit > 0 do
    valid_timeout = is_integer(timeout) and timeout > 0
    wait = if valid_timeout, do: min(timeout, limit) + 100, else: limit + 100
    deadline = if valid_timeout, do: System.monotonic_time(:millisecond) + min(timeout, limit)
    safe_call(owner, {:routed, epoch, [routes, request, timeout, deadline]}, wait)
  end

  def call(_, operation, _) when operation in [:command, :interview, :routed, :close, :drain],
    do: {:error, %Error{kind: :stale_handle, operation: operation}}

  def call(_, _, _), do: {:error, error(:invalid_command, :owner)}

  @impl GenServer
  def init(%Config{} = config) do
    with true <- Config.valid?(config),
         true <- Code.ensure_loaded?(config.serial),
         true <- function_exported?(config.serial, :open, 3),
         true <- function_exported?(config.serial, :write, 2),
         true <- function_exported?(config.serial, :close, 1),
         {:ok, port} <- config.serial.open(config.device_id, serial_options(config), self()) do
      {:ok, bytes} = Frame.encode(Command.version())

      case config.serial.write(port, bytes) do
        :ok ->
          timer = Process.send_after(self(), :version_timeout, config.timeout_ms)

          {:ok,
           %{
             config: config,
             port: port,
             epoch: make_ref(),
             mode: :negotiating,
             version_timer: timer,
             ready_waiter: nil,
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
           }}

        {:error, _} ->
          config.serial.close(port)
          {:stop, %Error{kind: :serial, operation: :open}}
      end
    else
      false -> {:stop, %Error{kind: :invalid_config, operation: :open}}
      {:error, _} -> {:stop, %Error{kind: :serial, operation: :open}}
    end
  end

  @impl GenServer
  def handle_call(:ready, from, %{mode: :negotiating, ready_waiter: nil} = state),
    do: {:noreply, %{state | ready_waiter: from}}

  def handle_call(:ready, _, %{mode: :negotiating} = state),
    do: {:reply, {:error, error(:overload, :ready)}, state}

  def handle_call(:ready, _, %{mode: :ready} = state), do: {:reply, {:ok, handle_for(state)}, state}

  def handle_call(:ready, _, %{mode: {:failed, kind}} = state),
    do: {:stop, :normal, {:error, error(kind, :ready)}, state}

  def handle_call(:handle, _, %{mode: :ready} = state),
    do: {:reply, {:ok, handle_for(state)}, state}

  def handle_call(:handle, _, state),
    do: {:reply, {:error, error(:coordinator_lost, :handle)}, state}

  def handle_call({:close, epoch, []}, _, state) do
    if epoch == state.epoch do
      fail_waiters(state, :coordinator_lost)
      {:stop, :normal, :ok, state}
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
    fail_waiters(state, :timeout)

    if state.ready_waiter do
      {:stop, :normal, state}
    else
      Process.send_after(self(), :failed_stop, 1_000)
      {:noreply, %{state | mode: {:failed, :timeout}}}
    end
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
  def terminate(_, state), do: state.config.serial.close(state.port)

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
    Process.cancel_timer(state.version_timer)

    if payload == version_bytes(state.config.expected_version) do
      if state.ready_waiter, do: GenServer.reply(state.ready_waiter, {:ok, handle_for(state)})
      %{state | mode: :ready, ready_waiter: nil}
    else
      fail_waiters(state, :version_mismatch)
      Process.send_after(self(), :failed_stop, 1_000)
      %{state | mode: {:failed, :version_mismatch}, ready_waiter: nil}
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

  defp serial_write(state, bytes) do
    case state.config.serial.write(state.port, bytes) do
      :ok -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
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
