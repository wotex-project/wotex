defmodule Wotex.Lab.Otlp.Exporter do
  @moduledoc """
  An explicitly started, bounded OTLP exporter for Lab telemetry spans.

  A host starts the exporter with an `:id`, a `:sink` function and optional
  budgets; loading the Lab starts nothing. While alive it attaches one
  telemetry handler to the closing events of `Wotex.Lab.Otlp.Events.events/0`
  and detaches it when it stops. The handler runs in the emitting process: it
  copies only the event, the native duration, the closed projection inputs and
  the current time to the exporter, or counts a drop when the exporter's
  mailbox already holds `:max_buffer` messages. It never blocks the emitter.

  The exporter projects events through `Wotex.Lab.Otlp.Events`, with random
  trace and span identifiers, into two buffers of at most `:max_buffer`
  records each (512 by default, ceiling 4,096); records beyond that are counted
  as dropped. Every `:interval_ms` (5,000) and on `flush/2` it encodes at most
  `:max_batch` records (256, ceiling 1,024) of one signal with
  `Wotex.Lab.Otlp.Encoder` and calls `sink.(signal, %{body: body, headers:
  headers})` in one monitored process; only one export is in flight. The sink
  returns `{:ok, %{status: status, body: body}}` or `{:error, error}`. A 2xx
  status with a well-formed `partial_success` counts accepted and rejected
  records; another status, a malformed response, a sink error, a crash or the
  `:deadline_ms` (5,000) marks the batch failed. Failed batches are not retried
  and nothing is persisted, so export is lossy and makes no exactly-once
  claim. `stats/1` reports buffered, exported, rejected, failed and dropped
  counts by signal and the last error code without server text.

  `:signals` selects `:traces`, `:logs` or both. `:service_instance` becomes
  the `service.instance.id` resource attribute beside `service.name` =
  `wotex_lab`; it must be a Lab identifier.
  """

  use GenServer

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Otlp.{Encoder, Events}

  @options ~w(id sink signals service_instance interval_ms max_buffer max_batch deadline_ms name)a
  @defaults %{interval_ms: 5_000, max_buffer: 512, max_batch: 256, deadline_ms: 5_000}
  @bounds %{
    interval_ms: 100..60_000,
    max_buffer: 1..4_096,
    max_batch: 1..1_024,
    deadline_ms: 100..60_000
  }
  @signals [:traces, :logs]
  @content_type {"content-type", "application/x-protobuf"}

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.get(opts, :id, :default)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      type: :worker
    }
  end

  @doc "Starts an exporter with `:id`, `:sink` and optional signals, identity and budgets."
  @spec start_link(keyword()) :: GenServer.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <- validate(opts) do
      case Keyword.get(opts, :name) do
        nil -> GenServer.start_link(__MODULE__, opts)
        name -> GenServer.start_link(__MODULE__, opts, name: name)
      end
    end
  end

  @doc """
  Exports every buffered record now and returns the stats afterwards.

  Records emitted by other processes before the call are included once their
  handler messages reached the exporter; the call waits at most `timeout`.
  """
  @spec flush(GenServer.server(), timeout()) :: map()
  def flush(exporter, timeout \\ 30_000), do: GenServer.call(exporter, :flush, timeout)

  @doc "Buffered, exported, rejected, failed and dropped counts and the last error code."
  @spec stats(GenServer.server()) :: map()
  def stats(exporter), do: GenServer.call(exporter, :stats)

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)
    config = Map.merge(@defaults, Map.new(Keyword.take(opts, Map.keys(@defaults))))
    signals = Keyword.get(opts, :signals, @signals)
    drops = :counters.new(1, [:write_concurrency])
    handler = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach_many(
        handler,
        Events.events(),
        &__MODULE__.handle_event/4,
        %{exporter: self(), drops: drops, max_queue: config.max_buffer}
      )

    state = %{
      sink: Keyword.fetch!(opts, :sink),
      signals: signals,
      resource: [
        {"service.name", "wotex_lab"},
        {"service.instance.id", Keyword.get(opts, :service_instance, "wotex-lab")}
      ],
      config: config,
      handler: handler,
      drops: drops,
      buffers: %{traces: :queue.new(), logs: :queue.new()},
      depth: %{traces: 0, logs: 0},
      counts: Map.new(@signals, &{&1, %{exported: 0, rejected: 0, failed: 0, dropped: 0}}),
      in_flight: nil,
      waiting: [],
      last_error: nil
    }

    Process.send_after(self(), :tick, config.interval_ms)
    {:ok, state}
  end

  @doc false
  @spec handle_event([atom()], map(), map(), map()) :: :ok
  def handle_event(event, measurements, metadata, %{
        exporter: exporter,
        drops: drops,
        max_queue: max_queue
      }) do
    case Process.info(exporter, :message_queue_len) do
      {:message_queue_len, length} when length < max_queue ->
        duration = Map.get(measurements, :duration)
        projected = Map.take(metadata, [:outcome, :profile, :kind])
        send(exporter, {:otlp_event, event, duration, projected, System.os_time(:nanosecond)})

      _ ->
        :counters.add(drops, 1, 1)
    end

    :ok
  end

  @impl GenServer
  def handle_call(:flush, from, state) do
    state = %{state | waiting: [from | state.waiting]}
    {:noreply, reply_waiting(export(state))}
  end

  def handle_call(:stats, _, state), do: {:reply, stats_view(state), state}

  @impl GenServer
  def handle_info({:otlp_event, event, duration, metadata, end_ns}, state) do
    context = %{
      end_ns: end_ns,
      trace_id: :crypto.strong_rand_bytes(16),
      span_id: :crypto.strong_rand_bytes(8)
    }

    case Events.project(event, %{duration: duration}, metadata, context) do
      {:ok, span, log} ->
        state = if :traces in state.signals, do: buffer(state, :traces, span), else: state
        state = if log && :logs in state.signals, do: buffer(state, :logs, log), else: state
        {:noreply, state}

      :ignore ->
        {:noreply, state}
    end
  end

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, state.config.interval_ms)
    {:noreply, export(state)}
  end

  def handle_info({:otlp_result, pid, result}, %{in_flight: %{pid: pid} = flight} = state) do
    Process.demonitor(flight.monitor, [:flush])
    Process.cancel_timer(flight.timer)
    {:noreply, reply_waiting(export(settle(state, flight, result)))}
  end

  def handle_info({:otlp_deadline, monitor}, %{in_flight: %{monitor: monitor} = flight} = state) do
    Process.demonitor(monitor, [:flush])
    Process.exit(flight.pid, :kill)
    error = Error.new(:export_deadline, :export, "OTLP export exceeded its deadline")
    {:noreply, reply_waiting(export(settle(state, flight, {:error, error})))}
  end

  def handle_info(
        {:DOWN, monitor, :process, _, _},
        %{in_flight: %{monitor: monitor} = flight} = state
      ) do
    Process.cancel_timer(flight.timer)
    error = Error.new(:export_crashed, :export, "OTLP export process exited")
    {:noreply, reply_waiting(export(settle(state, flight, {:error, error})))}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, state) do
    :telemetry.detach(state.handler)
    if state.in_flight, do: Process.exit(state.in_flight.pid, :kill)
    :ok
  end

  defp buffer(state, signal, record) do
    if state.depth[signal] >= state.config.max_buffer do
      update_count(state, signal, :dropped, 1)
    else
      %{
        state
        | buffers: Map.update!(state.buffers, signal, &:queue.in(record, &1)),
          depth: Map.update!(state.depth, signal, &(&1 + 1))
      }
    end
  end

  defp export(%{in_flight: nil} = state) do
    signal = Enum.max_by(state.signals, &state.depth[&1])
    if state.depth[signal] > 0, do: start_export(state, signal), else: state
  end

  defp export(state), do: state

  defp start_export(state, signal) do
    {records, rest, count} = take(state.buffers[signal], state.config.max_batch, [], 0)

    state = %{
      state
      | buffers: Map.put(state.buffers, signal, rest),
        depth: Map.update!(state.depth, signal, &(&1 - count))
    }

    encoded =
      case signal do
        :traces -> Encoder.encode_traces(state.resource, records)
        :logs -> Encoder.encode_logs(state.resource, records)
      end

    case encoded do
      {:ok, body} ->
        owner = self()
        sink = state.sink
        request = %{body: body, headers: [@content_type]}

        {pid, monitor} =
          spawn_monitor(fn -> send(owner, {:otlp_result, self(), sink.(signal, request)}) end)

        timer = Process.send_after(self(), {:otlp_deadline, monitor}, state.config.deadline_ms)
        flight = %{pid: pid, monitor: monitor, timer: timer, signal: signal, count: count}
        %{state | in_flight: flight}

      {:error, error} ->
        state
        |> update_count(signal, :failed, count)
        |> Map.put(:last_error, error.code)
    end
  end

  defp take(queue, 0, acc, count), do: {Enum.reverse(acc), queue, count}

  defp take(queue, remaining, acc, count) do
    case :queue.out(queue) do
      {{:value, record}, rest} -> take(rest, remaining - 1, [record | acc], count + 1)
      {:empty, rest} -> {Enum.reverse(acc), rest, count}
    end
  end

  defp settle(state, flight, result) do
    state = %{state | in_flight: nil}

    case result do
      {:ok, %{status: status, body: body}}
      when is_integer(status) and status in 200..299 and is_binary(body) ->
        case Encoder.partial_success(flight.signal, body) do
          {:ok, %{rejected: rejected}} ->
            rejected = min(rejected, flight.count)

            state
            |> update_count(flight.signal, :exported, flight.count - rejected)
            |> update_count(flight.signal, :rejected, rejected)
            |> then(&if(rejected > 0, do: %{&1 | last_error: :partial_success}, else: &1))

          {:error, error} ->
            state
            |> update_count(flight.signal, :failed, flight.count)
            |> Map.put(:last_error, error.code)
        end

      {:ok, %{status: status}} when is_integer(status) ->
        state
        |> update_count(flight.signal, :failed, flight.count)
        |> Map.put(:last_error, :rejected_status)

      {:error, %Error{code: code}} ->
        state
        |> update_count(flight.signal, :failed, flight.count)
        |> Map.put(:last_error, code)

      _ ->
        state
        |> update_count(flight.signal, :failed, flight.count)
        |> Map.put(:last_error, :invalid_sink_result)
    end
  end

  defp reply_waiting(%{in_flight: nil, waiting: [_ | _]} = state) do
    if Enum.all?(state.signals, &(state.depth[&1] == 0)) do
      view = stats_view(state)
      Enum.each(state.waiting, &GenServer.reply(&1, view))
      %{state | waiting: []}
    else
      state
    end
  end

  defp reply_waiting(state), do: state

  defp update_count(state, signal, key, amount),
    do: update_in(state, [:counts, signal, key], &(&1 + amount))

  defp stats_view(state) do
    %{
      buffered: state.depth,
      traces: state.counts.traces,
      logs: state.counts.logs,
      handler_dropped: :counters.get(state.drops, 1),
      in_flight: state.in_flight != nil,
      last_error: state.last_error
    }
  end

  defp validate(opts) do
    with :ok <- Options.validate(opts, @options),
         true <- Options.identifier?(to_string(Keyword.get(opts, :id, ""))),
         true <- is_function(Keyword.get(opts, :sink), 2),
         true <- signals?(Keyword.get(opts, :signals, @signals)),
         true <- Options.identifier?(Keyword.get(opts, :service_instance, "wotex-lab")),
         true <-
           Enum.all?(@bounds, fn {key, range} -> Keyword.get(opts, key, @defaults[key]) in range end) do
      :ok
    else
      _ ->
        {:error,
         Error.new(:invalid_otlp_exporter, :construction, "OTLP exporter options are invalid")}
    end
  end

  defp signals?(signals),
    do:
      is_list(signals) and signals != [] and Enum.uniq(signals) == signals and
        Enum.all?(signals, &(&1 in @signals))
end
