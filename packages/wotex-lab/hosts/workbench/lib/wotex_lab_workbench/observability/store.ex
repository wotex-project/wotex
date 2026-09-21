defmodule WotexLabWorkbench.Observability.Store do
  @moduledoc """
  Bounded PromEx storage adapter for the exact generated Lab plugin cohort.

  Only its admitted Telemetry.Metrics definitions are accepted. Handlers update
  a fixed-capacity ETS aggregate synchronously; histogram samples are never
  buffered. Inclusive fixed buckets and nanosecond integer sums preserve the
  catalogue's seconds semantics. No PromEx/Peep private state is accessed.

  This is one explicitly activated host collector for the Workbench Lab
  instance, not a tenant-isolated store or a public metrics listener. Instance
  slots and tenant history are not inferred from browser metadata.
  """

  @behaviour PromEx.Storage

  use GenServer

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.{Catalogue, Exposition, Snapshot}
  alias WotexLabWorkbench.Observability.Definitions

  @counters [:dropped_series, :dropped_samples, :invalid_samples]
  @nanos 1_000_000_000
  @max_scrape 1_048_576

  @impl PromEx.Storage
  def child_spec(name, metrics) do
    %{id: name, start: {__MODULE__, :start_link, [[name: name, metrics: metrics]]}}
  end

  @doc "Starts an exact-cohort collector with a 256-series budget (ceiling 4,096)."
  @spec start_link(keyword()) :: GenServer.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <- Options.validate(opts, [:name, :metrics, :series_budget]), do: start(opts)
  end

  defp start(opts) do
    budget = Keyword.get(opts, :series_budget, 256)
    metrics = Keyword.get(opts, :metrics)
    name = Keyword.get(opts, :name)

    if is_atom(name) and name not in [nil, true, false] and is_integer(budget) and
         budget in 1..4_096 and
         metrics == Definitions.metrics() do
      GenServer.start_link(__MODULE__, {metrics, budget, name}, name: name)
    else
      {:error,
       Error.new(:invalid_metric_cohort, :metrics, "collector definition or budget is not admitted")}
    end
  end

  @impl PromEx.Storage
  def scrape(name) do
    GenServer.call(name, :scrape, 2_000)
  catch
    :exit, _ -> :prom_ex_down
  end

  @doc "Budget, capacity, drops and native-admission failures for this collector."
  @spec stats(GenServer.server()) :: map()
  def stats(server), do: GenServer.call(server, :stats, 2_000)

  @doc "Metadata for the latest matching public scrape; a superseded body is refused."
  @spec receipt(GenServer.server(), binary()) :: {:ok, map()} | {:error, Error.t()}
  def receipt(server, text) when is_binary(text) and byte_size(text) <= @max_scrape do
    GenServer.call(server, {:receipt, :crypto.hash(:sha256, text)}, 2_000)
  catch
    :exit, _ -> {:error, Error.new(:collector_unavailable, :metrics, "collector unavailable")}
  end

  def receipt(_, _),
    do: {:error, Error.new(:invalid_scrape, :metrics, "scrape body exceeds its bound")}

  @impl GenServer
  def init({metrics, budget, name}) do
    Process.flag(:trap_exit, true)
    table = :ets.new(__MODULE__, [:set, :public, write_concurrency: true])
    :ets.insert(table, [{:used, 0}, {:budget, budget} | Enum.map(@counters, &{&1, 0})])

    index =
      Map.new(metrics, fn definition ->
        id = Keyword.fetch!(definition.reporter_options, :catalogue_id)
        {:ok, metric} = Catalogue.fetch(id)
        {definition.event_name, metric}
      end)

    handler = {__MODULE__, name}
    # Reclaim only this fixed host collector's handler after an untrappable exit.
    :telemetry.detach(handler)

    :ok =
      :telemetry.attach_many(handler, Map.keys(index), &__MODULE__.handle_event/4, %{
        table: table,
        index: index,
        handler: handler
      })

    {:ok,
     %{
       table: table,
       metrics: Map.new(Catalogue.metrics(), &{&1.id, &1}),
       handler: handler,
       started_at: System.system_time(:millisecond),
       generation: System.unique_integer([:positive, :monotonic]),
       sequence: 0,
       receipt: nil,
       scrape_failures: 0
     }}
  end

  @doc "Bounded aggregation in the emitter; malformed diagnostics never escape."
  @spec handle_event([atom()], map(), map(), map()) :: :ok
  def handle_event(event, measurements, metadata, config) do
    metric = Map.fetch!(config.index, event)

    with true <- is_map(measurements) and map_size(measurements) == 1,
         {:ok, labels} <- labels(metric, metadata),
         {:ok, value} <- value(metric, measurements) do
      key = {metric.id, labels}

      if reserve(config.table, key, metric),
        do: update(config.table, key, metric, value),
        else: increment(config.table, :dropped_samples)
    else
      _ -> increment(config.table, :invalid_samples)
    end

    :ok
  catch
    _, _ ->
      increment(config.table, :invalid_samples)
      :ok
  end

  @impl GenServer
  def handle_call(:scrape, _, state) do
    sequence = state.sequence + 1

    fields = %{
      source: :collector,
      instance_slot: 0,
      sequence: sequence,
      monotonic_ms: System.monotonic_time(:millisecond),
      wall_time_ms: System.system_time(:millisecond),
      identity: %{started_at: state.started_at, generation: state.generation},
      counters: counters(state.table),
      series: series(state)
    }

    with {:ok, snapshot} <- Snapshot.new(fields),
         text = Exposition.render(snapshot),
         true <- byte_size(text) <= @max_scrape do
      receipt = %{
        digest: :crypto.hash(:sha256, text),
        fields: Map.delete(Map.from_struct(snapshot), :series)
      }

      {:reply, text, %{state | sequence: sequence, receipt: receipt}}
    else
      _ ->
        {:reply, :prom_ex_down, %{state | scrape_failures: state.scrape_failures + 1, receipt: nil}}
    end
  end

  def handle_call({:receipt, digest}, _, %{receipt: %{digest: digest, fields: fields}} = state),
    do: {:reply, {:ok, fields}, state}

  def handle_call({:receipt, _}, _, state),
    do:
      {:reply, {:error, Error.new(:scrape_superseded, :metrics, "scrape receipt unavailable")},
       state}

  def handle_call(:stats, _, state) do
    stats =
      Map.merge(counters(state.table), %{
        series_used: :ets.lookup_element(state.table, :used, 2),
        series_budget: :ets.lookup_element(state.table, :budget, 2),
        started_at: state.started_at,
        generation: state.generation,
        sequence: state.sequence,
        scrape_failures: state.scrape_failures
      })

    {:reply, stats, state}
  end

  @impl GenServer
  def terminate(_, state), do: :telemetry.detach(state.handler)

  defp labels(metric, metadata) when is_map(metadata) and map_size(metadata) <= 8 do
    enums = Catalogue.dimensions()

    if Enum.sort(Map.keys(metadata)) == Enum.sort(metric.dimensions) and
         Enum.all?(metadata, fn {key, value} -> value in enums[key] end) do
      {:ok,
       metadata
       |> Enum.map(fn {key, value} -> {Atom.to_string(key), Atom.to_string(value)} end)
       |> Enum.sort()}
    else
      :error
    end
  end

  defp labels(_, _), do: :error

  defp value(%{type: :counter, measurement: nil}, %{value: 1}), do: {:ok, 1}
  defp value(%{type: :counter, measurement: nil}, _), do: :error

  defp value(%{type: :gauge}, %{value: value}) when is_number(value) and abs(value) <= 1.0e100,
    do: {:ok, value}

  defp value(%{type: :histogram, unit: :seconds}, %{value: value})
       when is_number(value) and value >= 0 and value <= 1.0e100,
       do: {:ok, round(value * @nanos)}

  defp value(_, %{value: value}) when is_integer(value) and value >= 0 and value <= 1.0e100,
    do: {:ok, value}

  defp value(_, _), do: :error

  defp reserve(table, key, metric) do
    if :ets.member(table, key) do
      true
    else
      reserve_new(table, key, metric)
    end
  end

  defp reserve_new(table, key, metric) do
    cost = if metric.type == :histogram, do: length(metric.buckets) + 3, else: 1
    budget = :ets.lookup_element(table, :budget, 2)

    if :ets.update_counter(table, :used, {2, cost}) <= budget do
      if not :ets.insert_new(table, initial(key, metric)),
        do: :ets.update_counter(table, :used, {2, -cost})

      true
    else
      :ets.update_counter(table, :used, {2, -cost})
      increment(table, :dropped_series)
      false
    end
  end

  defp initial(key, %{type: :histogram, buckets: buckets}),
    do: List.to_tuple([key | List.duplicate(0, length(buckets) + 3)])

  defp initial(key, _), do: {key, 0}

  defp update(table, key, %{type: :gauge}, value), do: :ets.insert(table, {key, value})
  defp update(table, key, %{type: :counter}, value), do: :ets.update_counter(table, key, {2, value})

  defp update(table, key, metric, value) do
    thresholds = Enum.map(metric.buckets, &scale(&1, metric.unit))
    n = length(thresholds)
    first = Enum.find_index(thresholds, &(value <= &1)) || n
    updates = Enum.map((first + 2)..(n + 2), &{&1, 1}) ++ [{n + 3, value}, {n + 4, 1}]
    :ets.update_counter(table, key, updates)
  end

  defp scale(value, :seconds), do: round(value * @nanos)
  defp scale(value, _), do: value

  defp series(state) do
    state.table
    |> :ets.tab2list()
    |> Enum.flat_map(fn row ->
      case elem(row, 0) do
        {id, labels} ->
          metric = state.metrics[id]
          [%{name: metric.name, type: metric.type, labels: labels, sample: sample(metric, row)}]

        _ ->
          []
      end
    end)
  end

  defp sample(%{type: :histogram} = metric, row) do
    n = length(metric.buckets)
    sum = elem(row, n + 2)
    sum = if metric.unit == :seconds, do: sum / @nanos, else: sum

    %{
      buckets:
        Enum.zip(Enum.concat(metric.buckets, [:infinity]), Enum.map(1..(n + 1), &elem(row, &1))),
      sum: sum,
      count: elem(row, n + 3)
    }
  end

  defp sample(_, row), do: %{value: elem(row, 1)}

  defp counters(table), do: Map.new(@counters, &{&1, :ets.lookup_element(table, &1, 2)})

  defp increment(table, counter) do
    :ets.update_counter(table, counter, 1)
  catch
    _, _ -> :ok
  end
end
