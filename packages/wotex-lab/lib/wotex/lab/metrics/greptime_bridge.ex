defmodule Wotex.Lab.Metrics.GreptimeBridge do
  @moduledoc """
  A supervised, instance-owned self-scraper and remote-write exporter.

  On every `:interval_ms` tick (or `scrape_now/1`) the bridge calls the
  explicit `:scrape` function, which returns exposition text or an admitted
  `Wotex.Lab.Metrics.Snapshot`; it never reads PromEx or collector internals.
  The snapshot is admitted through `Wotex.Lab.Metrics.Exposition`, extended
  with stale markers for series that vanished since the previous scrape,
  written to the optional `:history`, and queued for export. Export goes
  through the `:sink` function `(request, credential) -> result` with the
  encoded remote-write request (`Wotex.Lab.Metrics.ReqSink.write/3` is the
  Req-based port); the credential is resolved for each export from the
  host-supplied `%{reference: term, lookup: (term -> {:ok, credential})}` in
  the export process and never enters the bridge state, stats or errors.

  Supplied snapshots are revalidated. A new capture must have a wall timestamp
  strictly later than the last admitted capture, even after an export is dropped
  or fails. Equal milliseconds and clock rollback return `:unordered_snapshot`
  before history/queue admission; timestamps are never fabricated or shifted.
  This conservative whole-snapshot watermark is local to this bridge lifetime,
  not persisted receiver state. Retries reuse an already admitted snapshot.

  Budgets are explicit: one export in flight, `:queue_limit` queued snapshots
  (16, ceiling 256) with the oldest unsent snapshot dropped and counted on
  overload, and a `:deadline_ms` per export (5,000, ceiling 60,000) after
  which the export process is killed and the write reported as ambiguous.
  Only transport timeouts, connection failures, HTTP 5xx and a bounded number
  of 429 replies are retried, with capped exponential backoff and jitter and
  the same snapshot identity; any other 4xx is rejected once and never
  retried. Success means the server accepted the request; it is not an
  exactly-once or lossless claim, and a timeout after sending is reported as
  ambiguous rather than as loss or success. The export runs in a monitored
  process so a sink crash, a slow endpoint or a raising scrape function
  affects nothing but the bridge's own counters, which it emits as
  `[:wotex, :lab, :metrics, :export, ...]` telemetry for the collector.
  """

  use GenServer

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{Exposition, History, RemoteWrite, Snapshot}
  alias Wotex.Lab.Options
  alias Wotex.Lab.Telemetry

  @options ~w(id scrape sink credential history interval_ms queue_limit deadline_ms max_attempts
    backoff_ms max_backoff_ms labels instance_slot profile restart name)a
  @defaults %{
    queue_limit: 16,
    deadline_ms: 5_000,
    max_attempts: 5,
    backoff_ms: 200,
    max_backoff_ms: 5_000,
    instance_slot: 0,
    profile: :greptime
  }
  @ceilings %{queue_limit: 256, deadline_ms: 60_000, max_attempts: 20, max_backoff_ms: 300_000}
  @counters ~w(scraped admitted rejected exported retried dropped_overload
    dropped_exhausted rejected_permanent ambiguous failed history_failures bytes)a

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.get(opts, :id, :default)},
      start: {__MODULE__, :start_link, [opts]},
      restart: Keyword.get(opts, :restart, :transient),
      type: :worker
    }
  end

  @doc "Starts a bridge with `:scrape`, `:sink`, optional `:history`, `:credential` and budgets."
  @spec start_link(keyword()) :: GenServer.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <- validate(opts) do
      case Keyword.get(opts, :name) do
        nil -> GenServer.start_link(__MODULE__, opts)
        name -> GenServer.start_link(__MODULE__, opts, name: name)
      end
    end
  end

  @doc "Scrapes once now; returns the admission result and the queue depth."
  @spec scrape_now(GenServer.server()) :: {:ok, map()} | {:error, Error.t()}
  def scrape_now(bridge), do: GenServer.call(bridge, :scrape)

  @doc "Counters, queue depth, in-flight state and the last redacted error."
  @spec stats(GenServer.server()) :: map()
  def stats(bridge), do: GenServer.call(bridge, :stats)

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)
    config = Map.merge(@defaults, Map.new(Keyword.take(opts, Map.keys(@defaults))))

    state = %{
      scrape: Keyword.fetch!(opts, :scrape),
      sink: Keyword.fetch!(opts, :sink),
      credential: Keyword.get(opts, :credential),
      history: Keyword.get(opts, :history),
      labels: Keyword.get(opts, :labels, []),
      interval_ms: Keyword.get(opts, :interval_ms),
      config: config,
      queue: :queue.new(),
      depth: 0,
      in_flight: nil,
      retry_timer: nil,
      sequence: 0,
      previous: nil,
      counters: Map.new(@counters, &{&1, 0}),
      last_error: nil
    }

    {:ok, schedule(state)}
  end

  @impl GenServer
  def handle_call(:scrape, _from, state) do
    {result, state} = scrape(state)
    {:reply, result, state}
  end

  def handle_call(:stats, _from, state) do
    stats =
      Map.merge(state.counters, %{
        queue_depth: state.depth,
        in_flight: state.in_flight != nil,
        retry_pending: state.retry_timer != nil,
        sequence: state.sequence,
        last_error: state.last_error
      })

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    {_result, state} = scrape(state)
    {:noreply, schedule(state)}
  end

  def handle_info(:retry, state), do: {:noreply, export(%{state | retry_timer: nil})}

  def handle_info({:export_result, pid, result}, %{in_flight: %{pid: pid} = flight} = state) do
    Process.demonitor(flight.ref, [:flush])
    Process.cancel_timer(flight.timer)
    {:noreply, state |> Map.put(:in_flight, nil) |> settle(flight.item, result)}
  end

  def handle_info({:export_deadline, ref}, %{in_flight: %{ref: ref} = flight} = state) do
    Process.demonitor(ref, [:flush])
    Process.exit(flight.pid, :kill)
    error = Error.new(:export_deadline, :export, "export exceeded its deadline", class: :timeout)
    {:noreply, state |> Map.put(:in_flight, nil) |> settle(flight.item, {:error, error})}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{in_flight: %{ref: ref} = flight} = state) do
    Process.cancel_timer(flight.timer)
    error = Error.new(:export_crashed, :export, "export process exited", class: :unavailable)
    {:noreply, state |> Map.put(:in_flight, nil) |> settle(flight.item, {:error, error})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{in_flight: %{pid: pid}}), do: Process.exit(pid, :kill)
  def terminate(_reason, _state), do: :ok

  defp validate(opts) do
    with :ok <- Options.validate(opts, @options),
         true <- is_function(Keyword.get(opts, :scrape), 0),
         true <- is_function(Keyword.get(opts, :sink), 2),
         true <- credential?(Keyword.get(opts, :credential)),
         true <- interval?(Keyword.get(opts, :interval_ms)),
         true <- Enum.all?(@ceilings, fn {key, ceiling} -> budget?(opts, key, ceiling) end),
         true <- budget?(opts, :backoff_ms, 60_000),
         true <- is_list(Keyword.get(opts, :labels, [])) do
      :ok
    else
      {:error, error} ->
        {:error, error}

      false ->
        {:error, Error.new(:invalid_bridge, :construction, "bridge configuration is invalid")}
    end
  end

  defp credential?(nil), do: true
  defp credential?(%{reference: _reference, lookup: lookup}), do: is_function(lookup, 1)
  defp credential?(_credential), do: false

  defp interval?(nil), do: true
  defp interval?(interval), do: is_integer(interval) and interval >= 100

  defp budget?(opts, key, ceiling) do
    value = Keyword.get(opts, key, @defaults[key])
    is_integer(value) and value > 0 and value <= ceiling
  end

  defp schedule(%{interval_ms: nil} = state), do: state

  defp schedule(state) do
    Process.send_after(self(), :tick, state.interval_ms)
    state
  end

  defp scrape(state) do
    state = count(state, :scraped)
    sequence = state.sequence + 1
    state = %{state | sequence: sequence}

    case admit(state, sequence) do
      {:ok, snapshot} ->
        snapshot = with_stale_markers(state.previous, snapshot)
        state = %{state | previous: snapshot} |> count(:admitted)
        state = record(state, snapshot)
        state = enqueue(state, snapshot)
        {{:ok, %{sequence: sequence, queue_depth: state.depth}}, export(state)}

      {:error, error} ->
        state = state |> count(:rejected) |> Map.put(:last_error, redact(error))
        {{:error, error}, state}
    end
  end

  defp admit(state, sequence) do
    result =
      case safe_scrape(state.scrape) do
        {:ok, %Snapshot{} = snapshot} ->
          Snapshot.new(Map.from_struct(snapshot))

        {:ok, text} when is_binary(text) ->
          Exposition.parse(text, sequence: sequence, instance_slot: state.config.instance_slot)

        {:error, %Error{} = error} ->
          {:error, error}

        _other ->
          {:error, Error.new(:scrape_failed, :export, "scrape returned nothing admissible")}
      end

    with {:ok, snapshot} <- result,
         :ok <- ordered_capture(state.previous, snapshot) do
      {:ok, snapshot}
    end
  end

  defp ordered_capture(nil, _snapshot), do: :ok

  defp ordered_capture(previous, snapshot) when snapshot.wall_time_ms > previous.wall_time_ms,
    do: :ok

  defp ordered_capture(_previous, _snapshot),
    do: {:error, Error.new(:unordered_snapshot, :export, "capture time must strictly advance")}

  defp safe_scrape(scrape) do
    scrape.()
  catch
    _kind, _reason -> {:error, Error.new(:scrape_failed, :export, "scrape function failed")}
  end

  defp with_stale_markers(nil, snapshot), do: snapshot

  defp with_stale_markers(previous, snapshot) do
    case Snapshot.stale_markers(previous, snapshot) do
      [] ->
        snapshot

      markers ->
        case Snapshot.new(%{Map.from_struct(snapshot) | series: snapshot.series ++ markers}) do
          {:ok, marked} -> marked
          {:error, _error} -> snapshot
        end
    end
  end

  defp record(%{history: nil} = state, _snapshot), do: state

  defp record(state, snapshot) do
    case History.put(state.history, snapshot) do
      {:ok, _admission} -> state
      {:error, error} -> state |> count(:history_failures) |> Map.put(:last_error, redact(error))
    end
  catch
    :exit, _reason -> count(state, :history_failures)
  end

  defp enqueue(state, snapshot) do
    state =
      if state.depth >= state.config.queue_limit do
        {{:value, _oldest}, queue} = :queue.out(state.queue)
        Telemetry.event(:metrics, :export, %{dropped: 1}, %{profile: state.config.profile})
        %{state | queue: queue, depth: state.depth - 1} |> count(:dropped_overload)
      else
        state
      end

    item = %{snapshot: snapshot, attempts: 0}
    state = %{state | queue: :queue.in(item, state.queue), depth: state.depth + 1}
    backlog(state)
  end

  defp backlog(state) do
    Telemetry.event(:metrics, :export, %{backlog: state.depth}, %{profile: state.config.profile})
    state
  end

  defp export(%{in_flight: nil, retry_timer: nil, depth: depth} = state) when depth > 0 do
    {{:value, item}, queue} = :queue.out(state.queue)
    item = %{item | attempts: item.attempts + 1}
    owner = self()

    exporter = %{
      sink: state.sink,
      credential: state.credential,
      labels: state.labels,
      profile: state.config.profile
    }

    {pid, monitor} =
      spawn_monitor(fn ->
        send(owner, {:export_result, self(), run_export(exporter, item.snapshot)})
      end)

    timer = Process.send_after(self(), {:export_deadline, monitor}, state.config.deadline_ms)
    flight = %{pid: pid, ref: monitor, timer: timer, item: item}
    %{state | queue: queue, depth: depth - 1, in_flight: flight} |> backlog()
  end

  defp export(state), do: state

  defp run_export(exporter, snapshot) do
    Telemetry.span(:metrics, :export, %{profile: exporter.profile}, fn ->
      with {:ok, credential} <- resolve(exporter.credential),
           {:ok, request} <- RemoteWrite.encode(snapshot, labels: exporter.labels),
           {:ok, response} <- call_sink(exporter.sink, request, credential) do
        {:ok, Map.put(response, :bytes, request.bytes)}
      end
    end)
  end

  defp resolve(nil), do: {:ok, nil}

  defp resolve(%{reference: reference, lookup: lookup}) do
    case lookup.(reference) do
      {:ok, credential} -> {:ok, credential}
      _other -> {:error, Error.new(:unresolved_reference, :export, "export credential unresolved")}
    end
  end

  defp call_sink(sink, request, credential) do
    case sink.(request, credential) do
      {:ok, %{status: status} = response} when is_integer(status) -> {:ok, response}
      {:error, %Error{} = error} -> {:error, error}
      _other -> {:error, Error.new(:invalid_sink_result, :export, "sink returned an unknown shape")}
    end
  end

  defp settle(state, item, result) do
    case classify(result) do
      {:ok, bytes} ->
        Telemetry.event(:metrics, :export, %{bytes: bytes}, %{profile: state.config.profile})
        state |> count(:exported) |> count(:bytes, bytes) |> export()

      {:retry, error, retry_after} ->
        retry(state, item, error, retry_after)

      {:ambiguous, error} ->
        retry(count(state, :ambiguous), item, error, nil)

      {:reject, error} ->
        state |> count(:rejected_permanent) |> Map.put(:last_error, redact(error)) |> export()

      {:fail, error} ->
        state |> count(:failed) |> Map.put(:last_error, redact(error)) |> export()
    end
  end

  defp classify({:ok, %{status: status, bytes: bytes}}) when status in 200..299, do: {:ok, bytes}

  defp classify({:ok, %{status: 429} = response}) do
    error = Error.new(:rate_limited, :export, "sink replied 429", class: :rate_limited)
    {:retry, error, retry_after(Map.get(response, :headers, []))}
  end

  defp classify({:ok, %{status: status}}) when status in 500..599 do
    {:retry, Error.new(:server_error, :export, "sink replied #{status}", class: :unavailable), nil}
  end

  defp classify({:ok, %{status: status}}) do
    {:reject, Error.new(:rejected, :export, "sink replied #{status}", class: :permanent)}
  end

  defp classify({:error, %Error{class: :timeout} = error}), do: {:ambiguous, error}
  defp classify({:error, %Error{class: :unavailable} = error}), do: {:retry, error, nil}
  defp classify({:error, %Error{} = error}), do: {:fail, error}

  defp retry(state, item, error, retry_after) do
    state = Map.put(state, :last_error, redact(error))

    if item.attempts >= state.config.max_attempts do
      Telemetry.event(:metrics, :export, %{dropped: 1}, %{profile: state.config.profile})
      state |> count(:dropped_exhausted) |> export()
    else
      delay = backoff(state.config, item.attempts, retry_after)
      timer = Process.send_after(self(), :retry, delay)

      %{state | queue: :queue.in_r(item, state.queue), depth: state.depth + 1, retry_timer: timer}
      |> count(:retried)
      |> backlog()
    end
  end

  defp backoff(config, attempts, retry_after) do
    base = min(config.max_backoff_ms, config.backoff_ms * Integer.pow(2, attempts - 1))
    jitter = :rand.uniform(config.backoff_ms) - 1

    case retry_after do
      nil -> base + jitter
      seconds -> min(config.max_backoff_ms, seconds * 1_000) + jitter
    end
  end

  defp retry_after(headers) do
    with {_name, value} <- List.keyfind(headers, "retry-after", 0),
         {seconds, ""} when seconds >= 0 <- Integer.parse(String.trim(value)) do
      seconds
    else
      _absent -> nil
    end
  end

  defp redact(%Error{} = error), do: %{code: error.code, class: error.class, phase: error.phase}

  defp count(state, counter, increment \\ 1),
    do: %{state | counters: Map.update!(state.counters, counter, &(&1 + increment))}
end
