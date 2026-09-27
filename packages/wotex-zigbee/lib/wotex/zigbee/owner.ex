defmodule Wotex.Zigbee.Owner do
  @moduledoc """
  One explicit TI ZNP serial owner with a negotiated firmware epoch.

  The owner accepts fragmented serial chunks, permits one outstanding SREQ,
  keeps AREQs in a finite queue and reports its overflow count. A command
  timeout ends the owner instead of matching a late SRSP to a later request.
  Neither startup nor timeout forms or resets a Zigbee network. The serial
  adapter and supervision policy belong to the consumer.
  """

  use GenServer

  alias Wotex.Zigbee.{Command, Config, Error, Event, Frame, Handle, Reply}

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
  def call(%Handle{owner: owner, epoch: epoch, timeout_ms: limit}, :command, [frame, timeout])
      when is_pid(owner) and is_reference(epoch) and is_integer(limit) and limit > 0 do
    valid_timeout = is_integer(timeout) and timeout > 0
    wait = if valid_timeout, do: min(timeout, limit) + 100, else: limit + 100
    deadline = if valid_timeout, do: System.monotonic_time(:millisecond) + min(timeout, limit)
    safe_call(owner, {:command, epoch, [frame, timeout, deadline]}, wait)
  end

  def call(%Handle{owner: owner, epoch: epoch, timeout_ms: limit}, operation, args)
      when is_pid(owner) and is_reference(epoch) and is_integer(limit) and limit > 0 and
             operation != :command and is_list(args) do
    safe_call(owner, {operation, epoch, args}, limit + 100)
  end

  def call(_, operation, _), do: {:error, %Error{kind: :stale_handle, operation: operation}}

  @impl GenServer
  def init(%Config{} = config) do
    with true <- Config.valid?(config),
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
    remaining =
      if is_integer(deadline), do: deadline - System.monotonic_time(:millisecond), else: -1

    cond do
      epoch != state.epoch ->
        {:reply, {:error, error(:stale_handle, :command)}, state}

      state.mode != :ready ->
        {:reply, {:error, error(:coordinator_lost, :command)}, state}

      state.pending != nil ->
        {:reply, {:error, error(:overload, :command)}, state}

      not is_integer(timeout) or timeout < 1 or timeout > state.config.timeout_ms ->
        {:reply, {:error, error(:invalid_value, :command)}, state}

      remaining <= 0 ->
        {:reply, {:error, error(:timeout, :command)}, state}

      true ->
        send_command(state, frame, remaining, from)
    end
  end

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
    {:stop, :normal, %{state | pending: nil}}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state), do: state.config.serial.close(state.port)

  defp send_command(state, %Frame{type: :sreq} = frame, timeout, from) do
    case Frame.encode(frame) do
      {:ok, bytes} ->
        case state.config.serial.write(state.port, bytes) do
          :ok ->
            reference = make_ref()
            timer = Process.send_after(self(), {:command_timeout, reference}, timeout)

            pending = %{
              from: from,
              subsystem: frame.subsystem,
              id: frame.id,
              reference: reference,
              timer: timer
            }

            {:noreply, %{state | pending: pending}}

          {:error, _} ->
            {:stop, :normal, {:error, error(:serial, :command)}, state}
        end

      error ->
        {:reply, error, state}
    end
  end

  defp send_command(state, _, _, _),
    do: {:reply, {:error, error(:invalid_command, :command)}, state}

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
    Process.cancel_timer(pending.timer)

    if frame.subsystem == pending.subsystem and frame.id == pending.id and
         byte_size(frame.payload) > 0 do
      <<status, _::binary>> = frame.payload

      reply = %Reply{
        subsystem: frame.subsystem,
        id: frame.id,
        status: status,
        payload: frame.payload
      }

      GenServer.reply(pending.from, {:ok, reply})
      %{state | pending: nil}
    else
      GenServer.reply(pending.from, {:error, error(:invalid_frame, :command)})
      %{state | pending: nil, mode: :failed}
    end
  end

  defp accept_frame(%Frame{type: :areq} = frame, state) do
    if state.event_count >= state.config.max_events do
      %{state | dropped: state.dropped + 1}
    else
      %{
        state
        | events: :queue.in(Event.from_frame(frame), state.events),
          event_count: state.event_count + 1
      }
    end
  end

  defp accept_frame(_, state), do: state

  defp take_events(queue, 0, collected), do: {Enum.reverse(collected), queue}

  defp take_events(queue, count, collected) do
    case :queue.out(queue) do
      {{:value, event}, rest} -> take_events(rest, count - 1, [event | collected])
      {:empty, _} -> {Enum.reverse(collected), queue}
    end
  end

  defp fail_waiters(state, kind) do
    if state.ready_waiter, do: GenServer.reply(state.ready_waiter, {:error, error(kind, :ready)})
    if state.pending, do: GenServer.reply(state.pending.from, {:error, error(kind, :command)})
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
