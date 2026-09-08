defmodule Wotex.Lab.Metrics.History do
  @moduledoc """
  A bounded, explicitly lossy per-instance snapshot store in ETS.

  Capacity is explicit positive configuration: `:max_snapshots` (120, hard
  ceiling 10,000) and `:max_bytes` (8 MiB of encoded snapshot bytes, hard
  ceiling 64 MiB). `put/2` serializes atomic admission through the owning
  process; hosts must bound their writer concurrency (the reference scraper
  has one writer). A synchronous call alone does not bound arbitrary callers.
  The oldest snapshots are evicted to make room, a
  snapshot larger than the whole byte budget is dropped, and every eviction,
  drop and rejection is counted in `stats/1`. A gap in a source's sequence and
  a change of its reset identity are flagged on the stored row so reads can
  show them. Nothing here is durable: the table dies with the process and the
  store never claims to be a system of record.

  `:instance_slot` (default 0) binds snapshot admission. Querying additionally
  requires an explicit `:instance` identifier; an unbound store is storage-only.
  Hosts must construct session scope from their authenticated context, never
  caller text. These bindings are not credentials or a hostile-BEAM boundary.
  Query descriptors and snapshots are revalidated; a struct is not admission.
  Matched metric types, finite labels and histogram buckets must agree with
  the catalogue. Wall-clock rollback is counted and affected queries refused.

  `query/2` answers a `Wotex.Lab.Metrics.Query` against the stored snapshots
  in the calling process, after admitting the estimated work and the session
  concurrency limit. Monitored leases also enforce `:max_queries` (32, ceiling
  128) across all sessions, disappear on caller death and retain no idle session
  keys. Indexed query buckets avoid rescanning every series for every point;
  deadline checks interrupt work and release the lease. This is a cooperative
  query deadline over bounded data, not process/OS containment.
  It supports only what ETS can answer honestly: `last`,
  `sum`, `min`, `max` and `avg` of gauges, `last`, `sum`, `increase` and `rate`
  of counters with reset awareness, and `histogram_quantile` and `increase`
  from histogram bucket counts. Anything else returns `unsupported_query`; ETS
  does not pretend to implement PromQL. Responses carry the source, interval,
  unit, freshness, loss and reset markers, the query digest and an empty
  evidence list, and keep missing, stale, dropped and zero apart: a missing
  point is absent, a stale sample is a `:stale` marker, loss is reported from
  the counters and `0` is a value.

  `freeze/2` performs the same admitted query while the owner serializes writes
  and returns the exact history watermark used. It exists for immutable
  diagnostic dataset construction; it does not make history durable or feed a
  model by itself.
  """

  use GenServer

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{Catalogue, Query, Snapshot}
  alias Wotex.Lab.Options
  alias Wotex.Lab.Telemetry

  @default_snapshots 120
  @max_snapshots 10_000
  @default_bytes 8 * 1_048_576
  @max_bytes 64 * 1_048_576
  @options ~w(id max_snapshots max_bytes instance instance_slot max_queries restart name)a
  @counters ~w(evicted dropped_oversized rejected gaps resets clock_rollbacks admitted)a

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

  @doc "Starts bounded history; bind `:instance` explicitly to enable queries."
  @spec start_link(keyword()) :: GenServer.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <- validate(opts) do
      case Keyword.get(opts, :name) do
        nil -> GenServer.start_link(__MODULE__, opts)
        name -> GenServer.start_link(__MODULE__, opts, name: name)
      end
    end
  end

  @doc "Admits one snapshot atomically; returns its history sequence and the evictions made."
  @spec put(GenServer.server(), Snapshot.t()) ::
          {:ok, %{sequence: pos_integer(), evicted: non_neg_integer()}} | {:error, Error.t()}
  def put(history, snapshot), do: GenServer.call(history, {:put, snapshot})

  @doc "Every stored snapshot in admission order with gap, reset and clock-rollback flags."
  @spec snapshots(GenServer.server()) :: [
          %{snapshot: Snapshot.t(), gap: boolean(), reset: boolean(), clock_rollback: boolean()}
        ]
  def snapshots(history) do
    history
    |> table()
    |> :ets.tab2list()
    |> Enum.map(fn {_seq, snapshot, _bytes, flags} -> Map.put(flags, :snapshot, snapshot) end)
  end

  @doc "Counts, byte usage, limits and loss counters."
  @spec stats(GenServer.server()) :: map()
  def stats(history), do: GenServer.call(history, :stats)

  @doc "Default and ceiling limits."
  @spec limits() :: %{atom() => pos_integer()}
  def limits do
    %{
      default_snapshots: @default_snapshots,
      max_snapshots: @max_snapshots,
      default_bytes: @default_bytes,
      max_bytes: @max_bytes
    }
  end

  @doc "Answers an admitted query from the stored snapshots, or explains why it cannot."
  @spec query(GenServer.server(), Query.t()) :: {:ok, map()} | {:error, Error.t()}
  def query(history, descriptor) do
    Telemetry.span(:metrics, :query, %{profile: :ets}, fn ->
      with {:ok, query} <- Query.validate(descriptor),
           {:ok, _estimate} <- Query.estimate(query),
           {:ok, metric} <- Catalogue.fetch(query.metric),
           :ok <- supported(metric, query),
           {:ok, table, token} <-
             GenServer.call(history, {:acquire, query.scope, query.limits.concurrent}) do
        try do
          answer(table, stats(history), metric, query)
        after
          GenServer.call(history, {:release, token})
        end
      end
    end)
  catch
    :throw, :history_query_deadline ->
      {:error, error(:deadline_exceeded, "query exceeded its deadline", class: :timeout)}

    :exit, _reason ->
      {:error, error(:history_unavailable, "history is unavailable")}
  end

  @doc "Atomically answers an admitted query and returns its exact history watermark."
  @spec freeze(GenServer.server(), Query.t()) ::
          {:ok, %{response: map(), watermark: map()}} | {:error, Error.t()}
  def freeze(history, descriptor) do
    Telemetry.span(:metrics, :query, %{profile: :ets_freeze}, fn ->
      with {:ok, query} <- Query.validate(descriptor),
           {:ok, _estimate} <- Query.estimate(query) do
        try do
          GenServer.call(history, {:freeze, query}, query.limits.deadline_ms + 1_000)
        catch
          :exit, _reason -> {:error, error(:history_unavailable, "history is unavailable")}
        end
      end
    end)
  end

  @impl GenServer
  def init(opts) do
    table = :ets.new(__MODULE__, [:ordered_set, :protected, read_concurrency: true])

    {:ok,
     %{
       table: table,
       queries: %{},
       instance: Keyword.get(opts, :instance),
       instance_slot: Keyword.get(opts, :instance_slot, 0),
       max_queries: Keyword.get(opts, :max_queries, 32),
       max_snapshots: Keyword.get(opts, :max_snapshots, @default_snapshots),
       max_bytes: Keyword.get(opts, :max_bytes, @default_bytes),
       sequence: 0,
       bytes: 0,
       last: nil,
       counters: Map.new(@counters, &{&1, 0})
     }}
  end

  @impl GenServer
  def handle_call({:put, %Snapshot{instance_slot: slot}}, _from, %{instance_slot: bound} = state)
      when slot != bound do
    {:reply, {:error, error(:scope_denied, "snapshot instance slot does not match history")},
     count(state, :rejected)}
  end

  def handle_call({:put, %Snapshot{} = snapshot}, _from, state) do
    bytes = Snapshot.encoded_size(snapshot)

    case admit_snapshot(snapshot, bytes, state.max_bytes) do
      {:error, reason, counter} ->
        {:reply, {:error, reason}, count(state, counter)}

      {:ok, snapshot} ->
        {state, evicted} = evict(state, bytes, 0)
        flags = flags(state.last, snapshot)
        sequence = state.sequence + 1
        :ets.insert(state.table, {sequence, snapshot, bytes, flags})

        state =
          %{state | sequence: sequence, bytes: state.bytes + bytes, last: identity(snapshot)}
          |> count(:admitted)
          |> count(:gaps, if(flags.gap, do: 1, else: 0))
          |> count(:resets, if(flags.reset, do: 1, else: 0))
          |> count(:clock_rollbacks, if(flags.clock_rollback, do: 1, else: 0))

        {:reply, {:ok, %{sequence: sequence, evicted: evicted}}, state}
    end
  end

  def handle_call({:put, _other}, _from, state) do
    state = count(state, :rejected)
    {:reply, {:error, error(:invalid_snapshot, "only admitted snapshots are stored")}, state}
  end

  def handle_call(:stats, _from, state) do
    {:reply, state_stats(state), state}
  end

  def handle_call(:table, _from, state), do: {:reply, state.table, state}

  def handle_call({:acquire, scope, limit}, {pid, _tag}, state) do
    concurrent =
      Enum.count(state.queries, fn {_ref, {_pid, session}} -> session == scope.session end)

    admission =
      if node(pid) == node() and Process.alive?(pid),
        do: admit_query(state, scope, limit, concurrent),
        else: {:error, error(:scope_denied, "query caller is no longer local and live")}

    case admission do
      :ok ->
        token = Process.monitor(pid)
        queries = Map.put(state.queries, token, {pid, scope.session})
        {:reply, {:ok, state.table, token}, %{state | queries: queries}}

      {:error, _error} = denied ->
        {:reply, denied, state}
    end
  end

  def handle_call({:release, token}, {pid, _tag}, state) do
    case Map.get(state.queries, token) do
      {^pid, _session} ->
        Process.demonitor(token, [:flush])
        {:reply, :ok, %{state | queries: Map.delete(state.queries, token)}}

      _other ->
        {:reply, {:error, error(:scope_denied, "query lease does not belong to caller")}, state}
    end
  end

  def handle_call({:freeze, descriptor}, {pid, _tag}, state) do
    concurrent =
      case descriptor do
        %Query{scope: %{session: session}} ->
          Enum.count(state.queries, fn {_ref, {_pid, active}} -> active == session end)

        _other ->
          0
      end

    result =
      with true <- node(pid) == node() and Process.alive?(pid),
           {:ok, query} <- Query.validate(descriptor),
           {:ok, _estimate} <- Query.estimate(query),
           {:ok, metric} <- Catalogue.fetch(query.metric),
           :ok <- supported(metric, query),
           :ok <- admit_query(state, query.scope, query.limits.concurrent, concurrent) do
        frozen_answer(state, metric, query)
      else
        false -> {:error, error(:scope_denied, "query caller is no longer local and live")}
        {:error, _error} = denied -> denied
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_info({:DOWN, token, :process, _pid, _reason}, state),
    do: {:noreply, %{state | queries: Map.delete(state.queries, token)}}

  defp table(history), do: GenServer.call(history, :table)

  defp admit_snapshot(_snapshot, bytes, max_bytes) when bytes > max_bytes,
    do: {:error, error(:oversized_snapshot, "snapshot exceeds the byte budget"), :dropped_oversized}

  defp admit_snapshot(snapshot, _bytes, _max_bytes) do
    case Snapshot.new(Map.from_struct(snapshot)) do
      {:ok, admitted} ->
        {:ok, admitted}

      {:error, _invalid} ->
        {:error, error(:invalid_snapshot, "snapshot descriptor is not admitted"), :rejected}
    end
  end

  defp admit_query(state, scope, limit, concurrent) do
    cond do
      state.instance == nil ->
        {:error, error(:scope_unbound, "querying requires an explicitly bound history instance")}

      state.instance != scope.instance ->
        {:error, error(:scope_denied, "query instance does not match history")}

      concurrent >= limit or map_size(state.queries) >= state.max_queries ->
        {:error, error(:too_many_queries, "query capacity reached", class: :rate_limited)}

      true ->
        :ok
    end
  end

  defp validate(opts) do
    with :ok <- Options.validate(opts, @options) do
      snapshots = Keyword.get(opts, :max_snapshots, @default_snapshots)
      bytes = Keyword.get(opts, :max_bytes, @default_bytes)
      instance = Keyword.get(opts, :instance)
      slot = Keyword.get(opts, :instance_slot, 0)
      queries = Keyword.get(opts, :max_queries, 32)

      if bounded?(snapshots, 1, @max_snapshots) and bounded?(bytes, 1, @max_bytes) and
           (instance == nil or Options.identifier?(instance)) and
           bounded?(slot, 0, 65_535) and bounded?(queries, 1, 128) do
        :ok
      else
        {:error, Error.new(:invalid_history, :construction, "limits exceed the hard ceilings")}
      end
    end
  end

  defp bounded?(value, minimum, maximum),
    do: is_integer(value) and value >= minimum and value <= maximum

  defp evict(state, incoming, evicted) do
    size = :ets.info(state.table, :size)

    if size > 0 and (size + 1 > state.max_snapshots or state.bytes + incoming > state.max_bytes) do
      first = :ets.first(state.table)
      [{^first, _snapshot, bytes, _flags}] = :ets.lookup(state.table, first)
      :ets.delete(state.table, first)
      evict(%{state | bytes: state.bytes - bytes} |> count(:evicted), incoming, evicted + 1)
    else
      {state, evicted}
    end
  end

  defp identity(snapshot), do: Map.take(snapshot, [:source, :identity, :sequence, :wall_time_ms])

  defp flags(nil, _snapshot), do: %{gap: false, reset: false, clock_rollback: false}

  defp flags(previous, snapshot) do
    reset = previous.source != snapshot.source or previous.identity != snapshot.identity

    %{
      gap: not reset and snapshot.sequence != previous.sequence + 1,
      reset: reset,
      clock_rollback: snapshot.wall_time_ms < previous.wall_time_ms
    }
  end

  defp count(state, counter, increment \\ 1),
    do: %{state | counters: Map.update!(state.counters, counter, &(&1 + increment))}

  defp edge(table, which) do
    case apply(:ets, which, [table]) do
      :"$end_of_table" -> nil
      key -> :ets.lookup_element(table, key, 2).wall_time_ms
    end
  end

  defp state_stats(state) do
    Map.merge(state.counters, %{
      count: :ets.info(state.table, :size),
      bytes: state.bytes,
      max_snapshots: state.max_snapshots,
      max_bytes: state.max_bytes,
      active_queries: map_size(state.queries),
      max_queries: state.max_queries,
      instance: state.instance,
      instance_slot: state.instance_slot,
      history_sequence: state.sequence,
      oldest_wall_time_ms: edge(state.table, :first),
      newest_wall_time_ms: edge(state.table, :last)
    })
  end

  defp frozen_answer(state, metric, query) do
    stats = state_stats(state)

    try do
      case answer(state.table, stats, metric, query) do
        {:ok, response} ->
          {:ok,
           %{
             response: response,
             watermark:
               Map.take(stats, [
                 :history_sequence,
                 :count,
                 :bytes,
                 :oldest_wall_time_ms,
                 :newest_wall_time_ms
               ])
           }}

        {:error, _error} = error ->
          error
      end
    catch
      :throw, :history_query_deadline ->
        {:error, error(:deadline_exceeded, "query exceeded its deadline", class: :timeout)}
    end
  end

  defp supported(metric, query) do
    supported? =
      case {metric.type, query.aggregation} do
        {:gauge, aggregation} -> aggregation in [:last, :sum, :min, :max, :avg]
        {:counter, aggregation} -> aggregation in [:last, :sum, :increase, :rate]
        {:histogram, aggregation} -> aggregation in [:histogram_quantile, :increase]
      end

    if supported?,
      do: :ok,
      else:
        {:error,
         error(:unsupported_query, "local history cannot answer this aggregation honestly",
           details: %{metric: metric.id, type: metric.type, aggregation: query.aggregation}
         )}
  end

  defp answer(table, history, metric, query) when is_map(history) do
    started = System.monotonic_time(:millisecond)
    start_ms = DateTime.to_unix(query.start_at, :millisecond)
    end_ms = DateTime.to_unix(query.end_at, :millisecond)
    rows = rows(table, start_ms, end_ms)
    series = matching(rows, metric, query)
    estimate = div(end_ms - start_ms, query.step_ms) + 1

    with :ok <- catalogue_samples(rows, metric, started + query.limits.deadline_ms),
         :ok <- chronology(rows),
         :ok <- ambiguity(series, query),
         :ok <- work(estimate * max(map_size(series), 1), query) do
      {points, markers} = points(series, rows, metric, query, {start_ms, end_ms}, started)

      response = %{
        source: :ets_history,
        instance: query.scope.instance,
        metric: metric.id,
        name: metric.name,
        unit: metric.unit,
        aggregation: query.aggregation,
        interval: %{start_ms: start_ms, end_ms: end_ms, step_ms: query.step_ms},
        freshness: freshness(rows, end_ms),
        points: points,
        markers: markers ++ loss_markers(rows, history, start_ms),
        loss: Map.take(history, [:evicted, :dropped_oversized, :gaps, :resets, :clock_rollbacks]),
        series_matched: map_size(series),
        digest: Query.digest(query),
        evidence: []
      }

      finish(response, query, started)
    end
  end

  defp finish(response, query, started) do
    elapsed = System.monotonic_time(:millisecond) - started

    cond do
      elapsed > query.limits.deadline_ms ->
        {:error, error(:deadline_exceeded, "query exceeded its deadline", class: :timeout)}

      :erlang.external_size(response) > query.limits.output_bytes ->
        {:error, error(:output_too_large, "response exceeds the output limit")}

      true ->
        Telemetry.event(:metrics, :query, %{points: length(response.points)}, %{profile: :ets})
        {:ok, response}
    end
  end

  defp rows(table, start_ms, end_ms) do
    table
    |> :ets.select([{{:"$1", :"$2", :_, :"$3"}, [{:is_integer, :"$1"}], [{{:"$1", :"$2", :"$3"}}]}])
    |> Enum.filter(fn {_seq, snapshot, _flags} ->
      snapshot.wall_time_ms >= start_ms and snapshot.wall_time_ms <= end_ms
    end)
  end

  defp matching(rows, metric, query) do
    filters = Map.new(query.filters, fn {k, v} -> {Atom.to_string(k), Atom.to_string(v)} end)

    rows
    |> Enum.flat_map(fn {_seq, snapshot, _flags} ->
      select_series(snapshot.series, metric.name, filters)
    end)
    |> Enum.map(& &1.labels)
    |> Enum.uniq()
    |> Map.new(&{&1, true})
  end

  defp select_series(series, name, filters) do
    Enum.filter(series, fn one ->
      one.name == name and Enum.all?(filters, fn filter -> filter in one.labels end)
    end)
  end

  defp ambiguity(series, query) do
    if map_size(series) > 1 and query.aggregation not in [:sum, :increase, :rate],
      do:
        {:error,
         error(:unsupported_query, "aggregation needs one series; add filters or use sum",
           details: %{series_matched: map_size(series)}
         )},
      else: :ok
  end

  defp chronology(rows) do
    if Enum.any?(rows, fn {_seq, _snapshot, flags} -> flags.clock_rollback end),
      do: {:error, error(:clock_rollback, "query interval contains a wall-clock rollback")},
      else: :ok
  end

  defp catalogue_samples(rows, metric, deadline) do
    dimensions = Catalogue.dimensions()

    labels =
      Map.new(metric.dimensions, fn key ->
        {Atom.to_string(key), Enum.map(dimensions[key], &Atom.to_string/1)}
      end)

    valid =
      Enum.all?(rows, fn {_seq, snapshot, _flags} ->
        check_deadline!(deadline)

        Enum.all?(snapshot.series, fn series ->
          series.name != metric.name or matching_cohort?(series, metric, labels)
        end)
      end)

    if valid,
      do: :ok,
      else: {:error, error(:invalid_metric_cohort, "stored metric does not match the catalogue")}
  end

  defp matching_cohort?(series, metric, labels) do
    series.type == metric.type and length(series.labels) == map_size(labels) and
      Enum.all?(series.labels, fn {key, value} -> value in Map.get(labels, key, []) end) and
      (metric.type != :histogram or
         Enum.map(series.sample.buckets, &elem(&1, 0)) == metric.buckets ++ [:infinity])
  end

  defp work(estimate, query) do
    if estimate <= query.limits.points,
      do: :ok,
      else: {:error, error(:query_too_large, "estimated work exceeds the point limit")}
  end

  defp freshness([], _end_ms), do: nil

  defp freshness(rows, end_ms) do
    latest =
      rows |> Enum.map(fn {_seq, snapshot, _flags} -> snapshot.wall_time_ms end) |> Enum.max()

    %{latest_ms: latest, age_ms: end_ms - latest}
  end

  defp loss_markers(rows, stats, start_ms) do
    oldest = stats.oldest_wall_time_ms

    if stats.evicted > 0 and (rows == [] or (oldest != nil and oldest > start_ms)),
      do: [%{t: start_ms, kind: :evicted}],
      else: []
  end

  defp points(series, rows, metric, query, {start_ms, end_ms}, started) do
    deadline = started + query.limits.deadline_ms
    windows = windows(rows, series, metric.name, start_ms, query.step_ms, deadline)
    steps = Stream.take_while(Stream.iterate(start_ms, &(&1 + query.step_ms)), &(&1 <= end_ms))

    flag_markers =
      Enum.flat_map(rows, fn {_seq, snapshot, flags} ->
        for {kind, true} <- flags, do: %{t: snapshot.wall_time_ms, kind: kind}
      end)

    {points, markers, _previous} =
      Enum.reduce(steps, {[], flag_markers, %{}}, fn t, {points, markers, previous} ->
        check_deadline!(deadline)
        samples = Map.get(windows, t, %{})
        {value, extra, previous} = aggregate(query, metric, samples, previous, t)

        {if(value == nil, do: points, else: [%{t: t, value: value} | points]), markers ++ extra,
         previous}
      end)

    {Enum.reverse(points), markers |> Enum.uniq() |> Enum.sort_by(& &1.t)}
  end

  defp windows(rows, labels, name, start, step, deadline) do
    rows
    |> Enum.reduce(%{}, fn {_seq, snapshot, _flags}, windows ->
      check_deadline!(deadline)
      t = start + div(snapshot.wall_time_ms - start + step - 1, step) * step
      samples = Map.get(windows, t, %{})

      samples = window_samples(snapshot, samples, name, labels)

      Map.put(windows, t, samples)
    end)
    |> Map.new(fn {t, samples} ->
      {t, Map.new(samples, fn {labels, values} -> {labels, Enum.reverse(values)} end)}
    end)
  end

  defp window_samples(snapshot, samples, name, labels) do
    Enum.reduce(snapshot.series, samples, fn series, samples ->
      if series.name == name and Map.has_key?(labels, series.labels) do
        value = {snapshot.identity, series.sample}
        Map.update(samples, series.labels, [value], &[value | &1])
      else
        samples
      end
    end)
  end

  defp check_deadline!(deadline) do
    if System.monotonic_time(:millisecond) >= deadline, do: throw(:history_query_deadline)
  end

  defp aggregate(%Query{aggregation: aggregation}, _metric, samples, previous, t)
       when aggregation in [:last, :sum, :min, :max, :avg] do
    values = samples |> Map.values() |> List.flatten() |> Enum.map(&elem(&1, 1))
    numeric = for %{value: value} <- values, is_number(value), do: value
    stale = Enum.any?(values, &(&1.value == :stale))
    markers = if stale, do: [%{t: t, kind: :stale}], else: []
    last = for {_labels, list} <- samples, list != [], do: elem(List.last(list), 1).value
    {scalar_value(aggregation, numeric, Enum.filter(last, &is_number/1)), markers, previous}
  end

  defp aggregate(%Query{aggregation: aggregation} = query, metric, samples, previous, t)
       when aggregation in [:increase, :rate] do
    {increase, markers, previous} =
      Enum.reduce(samples, {nil, [], previous}, fn {labels, list}, {acc, markers, previous} ->
        list =
          Enum.map(list, fn {identity, sample} -> {identity, counter_value(metric, sample)} end)

        {delta, reset?, previous} = delta(labels, list, previous)
        markers = if reset?, do: [%{t: t, kind: :reset} | markers], else: markers

        markers =
          if Enum.any?(list, &(elem(&1, 1) == :stale)),
            do: [%{t: t, kind: :stale} | markers],
            else: markers

        {sum_nil(acc, delta), markers, previous}
      end)

    value =
      case {aggregation, increase} do
        {_aggregation, nil} -> nil
        {:increase, increase} -> increase
        {:rate, increase} -> Snapshot.number(increase / (query.step_ms / 1_000))
      end

    {value, markers, previous}
  end

  defp aggregate(%Query{aggregation: :histogram_quantile} = query, _metric, samples, previous, t) do
    case Map.to_list(samples) do
      [] -> {nil, [], previous}
      [{labels, list}] -> histogram_delta(query, labels, list, previous, t)
    end
  end

  defp histogram_delta(query, labels, list, previous, t) do
    {deltas, markers, last} =
      Enum.reduce(list, {nil, [], Map.get(previous, labels)}, fn
        {_identity, %{stale: true}}, {deltas, markers, _prior} ->
          {deltas, [%{t: t, kind: :stale} | markers], nil}

        {identity, %{buckets: buckets, count: count}}, {deltas, markers, prior} ->
          {base_buckets, reset?} = base(prior, identity, buckets)
          added = Enum.zip_with(buckets, base_buckets, fn {le, c}, {_le, b} -> {le, c - b} end)
          markers = if reset?, do: [%{t: t, kind: :reset} | markers], else: markers
          {add_buckets(deltas, added), markers, {identity, buckets, count}}
      end)

    value = if deltas == nil, do: nil, else: quantile(deltas, query.quantile)
    {value, markers, Map.put(previous, labels, last)}
  end

  defp add_buckets(nil, added), do: added

  defp add_buckets(deltas, added),
    do: Enum.zip_with(deltas, added, fn {le, a}, {_le, b} -> {le, a + b} end)

  defp scalar_value(_aggregation, [], _last), do: nil
  defp scalar_value(:last, _numeric, last), do: List.last(last)
  defp scalar_value(:sum, _numeric, last), do: Enum.sum(last)
  defp scalar_value(:min, numeric, _last), do: Enum.min(numeric)
  defp scalar_value(:max, numeric, _last), do: Enum.max(numeric)
  defp scalar_value(:avg, numeric, _last), do: Snapshot.number(Enum.sum(numeric) / length(numeric))

  defp counter_value(%{type: :histogram}, %{stale: true}), do: :stale
  defp counter_value(%{type: :histogram}, %{count: count}), do: count
  defp counter_value(_metric, %{value: value}), do: value

  defp delta(_labels, [], previous), do: {nil, false, previous}

  defp delta(labels, list, previous) do
    {increase, reset, last} =
      Enum.reduce(list, {nil, false, Map.get(previous, labels)}, fn {identity, current},
                                                                    {total, reset, base} ->
        cond do
          not is_number(current) ->
            {total, reset, nil}

          base == nil ->
            {sum_nil(total, 0), reset, {identity, current}}

          elem(base, 0) != identity or elem(base, 1) > current ->
            {sum_nil(total, current), true, {identity, current}}

          true ->
            {sum_nil(total, current - elem(base, 1)), reset, {identity, current}}
        end
      end)

    {increase, reset, Map.put(previous, labels, last)}
  end

  defp sum_nil(nil, delta), do: delta
  defp sum_nil(acc, nil), do: acc
  defp sum_nil(acc, delta), do: acc + delta

  defp base(nil, _identity, buckets), do: {Enum.map(buckets, fn {le, _c} -> {le, 0} end), false}

  defp base({identity, previous, _count}, identity, buckets) do
    if Enum.all?(Enum.zip(previous, buckets), fn {{_l, p}, {_l2, c}} -> p <= c end),
      do: {previous, false},
      else: {Enum.map(buckets, fn {le, _c} -> {le, 0} end), true}
  end

  defp base(_other, _identity, buckets), do: {Enum.map(buckets, fn {le, _c} -> {le, 0} end), true}

  # Prometheus-style interpolation over bucket deltas; +Inf yields the last finite bound.
  defp quantile(deltas, q) do
    total = deltas |> List.last() |> elem(1)

    if total <= 0 do
      nil
    else
      rank = q * total
      index = Enum.find_index(deltas, fn {_le, count} -> count >= rank end)
      {le, count} = Enum.at(deltas, index)
      {lower, previous} = if index == 0, do: {0, 0}, else: Enum.at(deltas, index - 1)

      cond do
        le == :infinity and index == 0 -> nil
        le == :infinity -> lower
        count == previous -> Snapshot.number(le * 1.0)
        true -> Snapshot.number(lower + (le - lower) * ((rank - previous) / (count - previous)))
      end
    end
  end

  defp error(code, message, opts \\ []), do: Error.new(code, :history, message, opts)
end
