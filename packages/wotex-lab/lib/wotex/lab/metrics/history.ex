defmodule Wotex.Lab.Metrics.History do
  @moduledoc """
  A bounded, explicitly lossy per-instance snapshot store in ETS.

  Capacity is explicit positive configuration: `:max_snapshots` (120, hard
  ceiling 10,000) and `:max_bytes` (8 MiB of encoded snapshot bytes, hard
  ceiling 64 MiB). `put/2` is a call serialized through the owning process, so
  admission is atomic and a burst of writers is held back rather than piling
  into an unbounded mailbox; the oldest snapshots are evicted to make room, a
  snapshot larger than the whole byte budget is dropped, and every eviction,
  drop and rejection is counted in `stats/1`. A gap in a source's sequence and
  a change of its reset identity are flagged on the stored row so reads can
  show them. Nothing here is durable: the table dies with the process and the
  store never claims to be a system of record.

  `query/2` answers a `Wotex.Lab.Metrics.Query` against the stored snapshots
  in the calling process, after admitting the estimated work and the session
  concurrency limit. It supports only what ETS can answer honestly: `last`,
  `sum`, `min`, `max` and `avg` of gauges, `last`, `sum`, `increase` and `rate`
  of counters with reset awareness, and `histogram_quantile` and `increase`
  from histogram bucket counts. Anything else returns `unsupported_query`; ETS
  does not pretend to implement PromQL. Responses carry the source, interval,
  unit, freshness, loss and reset markers, the query digest and an empty
  evidence list, and keep missing, stale, dropped and zero apart: a missing
  point is absent, a stale sample is a `:stale` marker, loss is reported from
  the counters and `0` is a value.
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
  @options ~w(id max_snapshots max_bytes restart name)a
  @counters ~w(evicted dropped_oversized rejected gaps resets admitted)a

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

  @doc "Starts a history with `:max_snapshots` (120) and `:max_bytes` (8 MiB)."
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

  @doc "Every stored snapshot in admission order with its gap and reset flags."
  @spec snapshots(GenServer.server()) :: [
          %{snapshot: Snapshot.t(), gap: boolean(), reset: boolean()}
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
  def query(history, %Query{} = query) do
    Telemetry.span(:metrics, :query, %{profile: :ets}, fn ->
      with {:ok, _estimate} <- Query.estimate(query),
           {:ok, metric} <- Catalogue.fetch(query.metric),
           :ok <- supported(metric, query),
           {table, inflight} = tables(history),
           :ok <- acquire(inflight, query) do
        try do
          answer(table, history, metric, query)
        after
          release(inflight, query)
        end
      end
    end)
  end

  @impl GenServer
  def init(opts) do
    table = :ets.new(__MODULE__, [:ordered_set, :public, read_concurrency: true])
    inflight = :ets.new(__MODULE__, [:set, :public, write_concurrency: true])

    {:ok,
     %{
       table: table,
       inflight: inflight,
       max_snapshots: Keyword.get(opts, :max_snapshots, @default_snapshots),
       max_bytes: Keyword.get(opts, :max_bytes, @default_bytes),
       sequence: 0,
       bytes: 0,
       last: nil,
       counters: Map.new(@counters, &{&1, 0})
     }}
  end

  @impl GenServer
  def handle_call({:put, %Snapshot{} = snapshot}, _from, state) do
    bytes = Snapshot.encoded_size(snapshot)

    if bytes > state.max_bytes do
      state = count(state, :dropped_oversized)
      {:reply, {:error, error(:oversized_snapshot, "snapshot exceeds the byte budget")}, state}
    else
      {state, evicted} = evict(state, bytes, 0)
      flags = flags(state.last, snapshot)
      sequence = state.sequence + 1
      :ets.insert(state.table, {sequence, snapshot, bytes, flags})

      state =
        %{state | sequence: sequence, bytes: state.bytes + bytes, last: identity(snapshot)}
        |> count(:admitted)
        |> count(:gaps, if(flags.gap, do: 1, else: 0))
        |> count(:resets, if(flags.reset, do: 1, else: 0))

      {:reply, {:ok, %{sequence: sequence, evicted: evicted}}, state}
    end
  end

  def handle_call({:put, _other}, _from, state) do
    state = count(state, :rejected)
    {:reply, {:error, error(:invalid_snapshot, "only admitted snapshots are stored")}, state}
  end

  def handle_call(:stats, _from, state) do
    stats =
      Map.merge(state.counters, %{
        count: :ets.info(state.table, :size),
        bytes: state.bytes,
        max_snapshots: state.max_snapshots,
        max_bytes: state.max_bytes,
        oldest_wall_time_ms: edge(state.table, :first),
        newest_wall_time_ms: edge(state.table, :last)
      })

    {:reply, stats, state}
  end

  def handle_call(:tables, _from, state), do: {:reply, {state.table, state.inflight}, state}

  defp table(history), do: history |> tables() |> elem(0)

  defp tables(history), do: GenServer.call(history, :tables)

  defp validate(opts) do
    with :ok <- Options.validate(opts, @options) do
      snapshots = Keyword.get(opts, :max_snapshots, @default_snapshots)
      bytes = Keyword.get(opts, :max_bytes, @default_bytes)

      if is_integer(snapshots) and snapshots in 1..@max_snapshots and is_integer(bytes) and
           bytes in 1..@max_bytes do
        :ok
      else
        {:error, Error.new(:invalid_history, :construction, "limits exceed the hard ceilings")}
      end
    end
  end

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

  defp identity(snapshot), do: {snapshot.source, snapshot.identity, snapshot.sequence}

  defp flags(nil, _snapshot), do: %{gap: false, reset: false}

  defp flags({source, identity, sequence}, snapshot) do
    reset = source != snapshot.source or identity != snapshot.identity
    %{gap: not reset and snapshot.sequence != sequence + 1, reset: reset}
  end

  defp count(state, counter, increment \\ 1),
    do: %{state | counters: Map.update!(state.counters, counter, &(&1 + increment))}

  defp edge(table, which) do
    case apply(:ets, which, [table]) do
      :"$end_of_table" -> nil
      key -> :ets.lookup_element(table, key, 2).wall_time_ms
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

  defp acquire(table, query) do
    key = {:inflight, query.scope.session}

    if :ets.update_counter(table, key, {2, 1}, {key, 0}) > query.limits.concurrent do
      :ets.update_counter(table, key, {2, -1})
      {:error, error(:too_many_queries, "session concurrency limit reached", class: :rate_limited)}
    else
      :ok
    end
  end

  defp release(table, query),
    do: :ets.update_counter(table, {:inflight, query.scope.session}, {2, -1})

  defp answer(table, history, metric, query) do
    started = System.monotonic_time(:millisecond)
    start_ms = DateTime.to_unix(query.start_at, :millisecond)
    end_ms = DateTime.to_unix(query.end_at, :millisecond)
    rows = rows(table, start_ms, end_ms)
    series = matching(rows, metric, query)
    estimate = div(end_ms - start_ms, query.step_ms) + 1

    with :ok <- ambiguity(series, query),
         :ok <- work(estimate * max(map_size(series), 1), query) do
      {points, markers} = points(series, rows, metric, query, start_ms, end_ms)
      stats = stats(history)

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
        markers: markers ++ loss_markers(rows, stats, start_ms),
        loss: Map.take(stats, [:evicted, :dropped_oversized, :gaps, :resets]),
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

  defp points(series, rows, metric, query, start_ms, end_ms) do
    labels = Map.keys(series)
    steps = Enum.take_while(Stream.iterate(start_ms, &(&1 + query.step_ms)), &(&1 <= end_ms))

    flag_markers =
      Enum.flat_map(rows, fn {_seq, snapshot, flags} ->
        for {kind, true} <- flags, do: %{t: snapshot.wall_time_ms, kind: kind}
      end)

    {points, markers, _previous} =
      Enum.reduce(steps, {[], flag_markers, %{}}, fn t, {points, markers, previous} ->
        window =
          Enum.filter(rows, fn {_s, snapshot, _f} -> in_window?(snapshot, t, query.step_ms) end)

        samples = samples(window, labels, metric.name)
        {value, extra, previous} = aggregate(query, metric, samples, previous, t)

        {if(value == nil, do: points, else: [%{t: t, value: value} | points]), markers ++ extra,
         previous}
      end)

    {Enum.reverse(points), markers |> Enum.uniq() |> Enum.sort_by(& &1.t)}
  end

  defp in_window?(snapshot, t, step),
    do: snapshot.wall_time_ms > t - step and snapshot.wall_time_ms <= t

  defp samples(window, labels, name) do
    Map.new(labels, fn label_set ->
      values =
        Enum.flat_map(window, fn {_seq, snapshot, _flags} ->
          find_sample(snapshot, name, label_set)
        end)

      {label_set, values}
    end)
  end

  defp find_sample(snapshot, name, labels) do
    case Enum.find(snapshot.series, &(&1.name == name and &1.labels == labels)) do
      nil -> []
      series -> [{snapshot.identity, series.sample}]
    end
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
    [{labels, list}] = Map.to_list(samples)

    numeric =
      for {identity, %{buckets: buckets, count: count}} <- list, do: {identity, buckets, count}

    case numeric do
      [] ->
        {nil, [], previous}

      _list ->
        {identity, buckets, count} = List.last(numeric)
        {base_buckets, reset?} = base(Map.get(previous, labels), identity, buckets)
        deltas = Enum.zip_with(buckets, base_buckets, fn {le, c}, {_le, b} -> {le, c - b} end)
        markers = if reset?, do: [%{t: t, kind: :reset}], else: []
        value = quantile(deltas, query.quantile)
        {value, markers, Map.put(previous, labels, {identity, buckets, count})}
    end
  end

  defp scalar_value(_aggregation, [], _last), do: nil
  defp scalar_value(:last, _numeric, last), do: List.last(last)
  defp scalar_value(:sum, _numeric, last), do: Enum.sum(last)
  defp scalar_value(:min, numeric, _last), do: Enum.min(numeric)
  defp scalar_value(:max, numeric, _last), do: Enum.max(numeric)
  defp scalar_value(:avg, numeric, _last), do: Snapshot.number(Enum.sum(numeric) / length(numeric))

  defp counter_value(%{type: :histogram}, %{count: count}), do: count
  defp counter_value(_metric, %{value: value}), do: value

  defp delta(_labels, [], previous), do: {nil, false, previous}

  defp delta(labels, list, previous) do
    {identity, current} = List.last(list)
    base = Map.get(previous, labels)
    previous = Map.put(previous, labels, {identity, current})

    cond do
      not is_number(current) -> {nil, false, previous}
      base == nil -> {first_delta(list, current), false, previous}
      elem(base, 0) != identity or elem(base, 1) > current -> {current, true, previous}
      true -> {current - elem(base, 1), false, previous}
    end
  end

  defp first_delta(list, current) do
    case Enum.find(list, fn {_identity, value} -> is_number(value) end) do
      {_identity, first} when first <= current -> current - first
      _other -> current
    end
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
