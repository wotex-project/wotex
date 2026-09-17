defmodule Wotex.Lab.Metrics.Collector do
  @moduledoc """
  An instance-owned collector that aggregates WLB.06 telemetry into the
  catalogue's series inside the emitter, with bounded work only.

  Starting a collector attaches one `:telemetry` handler (id `{Collector, pid}`
  unless `:handler_id` is given) to every source event of the catalogue and
  detaches it on terminate. The handler runs synchronously in the emitting
  process and touches nothing but a public ETS table owned by the collector:
  counters use `:ets.update_counter`, gauges overwrite, histograms increment
  their cumulative buckets, sum and count in one atomic call. No network,
  disk, model call or blocking query happens there, and a failure inside the
  handler is counted as an invalid sample rather than raised into the caller.

  Capacity is reserved atomically before a series is created: the default
  budget is 256 active scalar series (`:series_budget`, hard ceiling 4096) and
  a histogram costs its bucket count plus `+Inf`, sum and count. A series
  beyond the budget is dropped and counted; the samples it would have taken
  are counted as dropped samples. Counters are cumulative and keep a reset
  identity of `started_at` plus `generation`; `reset/1` clears every series
  and bumps the generation. Durations arrive in native units, become seconds
  through the explicit conversion, and a negative duration from a clock
  problem is rejected and counted, never recorded. Dimension values come from
  `Wotex.Lab.Metrics.Catalogue.dimension_value/4`, so an outcome atom, a
  profile or an operation is always mapped to a closed enum before it becomes
  a label; `:backend_class` is the finite configured class for this instance.

  `:attribute_to` optionally binds the collector to one owner process. The
  handler then records only events emitted by that process, by a process whose
  `$ancestors` include it (a process it started with an OTP start function) or
  by a process whose `$callers` include it (a task it started). Every other
  event is ignored without touching the table, so an attributed collector
  counts nothing about unrelated emitters. Attribution follows the standard
  OTP process dictionary conventions; a process started without them, such as
  a raw `spawn/1` or a process started by another owner, is not attributed.
  It is a collection filter for trusted same-BEAM code, not an authorization
  or isolation boundary. Each attributed collector still receives every
  catalogue event and discards unrelated ones in constant work.

  `snapshot/1` returns an admitted `Wotex.Lab.Metrics.Snapshot` with the
  instance slot, a sequence, monotonic and wall time, sorted series and the
  drop, reject and reset counters.
  """

  use GenServer

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{Catalogue, Snapshot}
  alias Wotex.Lab.Options

  @default_budget 256
  @max_budget 4_096
  @nanoseconds_per_second 1_000_000_000
  @counters ~w(dropped_series dropped_samples invalid_samples negative_durations resets)a
  @options ~w(id series_budget backend_class instance_slot attribute_to handler_id restart name)a

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

  @doc """
  Starts a collector with `:series_budget` (256), `:backend_class`, `:instance_slot` (0)
  and an optional `:attribute_to` owner process.
  """
  @spec start_link(keyword()) :: GenServer.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <- validate(opts) do
      case Keyword.get(opts, :name) do
        nil -> GenServer.start_link(__MODULE__, opts)
        name -> GenServer.start_link(__MODULE__, opts, name: name)
      end
    end
  end

  @doc "Returns an admitted snapshot of every active series."
  @spec snapshot(GenServer.server()) :: {:ok, Snapshot.t()} | {:error, Error.t()}
  def snapshot(collector), do: GenServer.call(collector, :snapshot)

  @doc "Clears every series and starts a new counter generation."
  @spec reset(GenServer.server()) :: :ok
  def reset(collector), do: GenServer.call(collector, :reset)

  @doc "Counters, budget, active series capacity and reset identity."
  @spec stats(GenServer.server()) :: map()
  def stats(collector), do: GenServer.call(collector, :stats)

  @doc "The default series budget per instance."
  @spec default_series_budget() :: pos_integer()
  def default_series_budget, do: @default_budget

  @doc "The hard ceiling a host may raise the series budget to."
  @spec max_series_budget() :: pos_integer()
  def max_series_budget, do: @max_budget

  @doc false
  @spec handle_event([atom()], map(), map(), map()) :: :ok
  def handle_event(event, measurements, metadata, config) do
    if attributed?(config.attribute_to) do
      Enum.each(Map.get(config.index, event, []), fn metric ->
        record(config.table, metric, event, measurements, metadata, config.context)
      end)
    end

    :ok
  catch
    _, _ ->
      invalid(config.table)
      :ok
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)
    table = :ets.new(__MODULE__, [:set, :public, write_concurrency: true, read_concurrency: true])
    :ets.insert(table, {:series_count, 0})
    :ets.insert(table, {:series_budget, Keyword.get(opts, :series_budget, @default_budget)})
    Enum.each(@counters, &:ets.insert(table, {&1, 0}))

    index = index()
    handler_id = {__MODULE__, Keyword.get(opts, :handler_id, self())}
    context = %{backend_class: Keyword.get(opts, :backend_class, :other)}

    config = %{
      table: table,
      index: index,
      context: context,
      attribute_to: Keyword.get(opts, :attribute_to)
    }

    case :telemetry.attach_many(handler_id, Map.keys(index), &__MODULE__.handle_event/4, config) do
      :ok ->
        {:ok,
         %{
           table: table,
           handler_id: handler_id,
           budget: Keyword.get(opts, :series_budget, @default_budget),
           instance_slot: Keyword.get(opts, :instance_slot, 0),
           started_at: System.system_time(:millisecond),
           generation: 0,
           sequence: 0
         }}

      {:error, :already_exists} ->
        {:stop, Error.new(:handler_exists, :construction, "telemetry handler id is taken")}
    end
  end

  @impl GenServer
  def handle_call(:snapshot, _, state) do
    sequence = state.sequence + 1

    fields = %{
      source: :collector,
      instance_slot: state.instance_slot,
      sequence: sequence,
      monotonic_ms: System.monotonic_time(:millisecond),
      wall_time_ms: System.system_time(:millisecond),
      identity: %{started_at: state.started_at, generation: state.generation},
      series: series(state.table),
      counters: counters(state.table)
    }

    {:reply, Snapshot.new(fields), %{state | sequence: sequence}}
  end

  def handle_call(:reset, _, state) do
    delete_rows(state.table)
    :ets.insert(state.table, {:series_count, 0})
    :ets.update_counter(state.table, :resets, 1)
    {:reply, :ok, %{state | generation: state.generation + 1}}
  end

  def handle_call(:stats, _, state) do
    stats =
      state.table
      |> counters()
      |> Map.merge(%{
        series_budget: state.budget,
        series_used: lookup(state.table, :series_count),
        started_at: state.started_at,
        generation: state.generation,
        sequence: state.sequence
      })

    {:reply, stats, state}
  end

  @impl GenServer
  def terminate(_, state) do
    :telemetry.detach(state.handler_id)
    :ok
  end

  defp delete_rows(table) do
    table
    |> :ets.tab2list()
    |> Enum.each(fn row ->
      case elem(row, 0) do
        {kind, _, _} when kind in [:c, :g, :h] -> :ets.delete(table, elem(row, 0))
        _ -> :ok
      end
    end)
  end

  defp validate(opts) do
    with :ok <- Options.validate(opts, @options) do
      budget = Keyword.get(opts, :series_budget, @default_budget)
      slot = Keyword.get(opts, :instance_slot, 0)
      attribute_to = Keyword.get(opts, :attribute_to)

      if is_integer(budget) and budget in 1..@max_budget and is_integer(slot) and
           slot in 0..65_535 and is_atom(Keyword.get(opts, :backend_class, :other)) and
           (is_nil(attribute_to) or is_pid(attribute_to)) do
        :ok
      else
        {:error, Error.new(:invalid_collector, :construction, "budget or slot is out of range")}
      end
    end
  end

  defp attributed?(nil), do: true

  defp attributed?(owner) do
    self() == owner or owner in Process.get(:"$ancestors", []) or
      owner in Process.get(:"$callers", [])
  end

  defp index do
    Catalogue.metrics()
    |> Enum.flat_map(fn metric -> Enum.map(metric.events, &{&1, compact(metric)}) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp compact(metric) do
    %{
      id: metric.id,
      name: metric.name,
      type: metric.type,
      unit: metric.unit,
      dimensions: Enum.sort(metric.dimensions),
      measurement: metric.measurement,
      only: metric.only,
      buckets: metric.buckets,
      thresholds: thresholds(metric)
    }
  end

  defp thresholds(%{type: :histogram, unit: :seconds, buckets: buckets}),
    do: Enum.map(buckets, &round(&1 * @nanoseconds_per_second))

  defp thresholds(%{type: :histogram, buckets: buckets}), do: buckets
  defp thresholds(_), do: nil

  defp record(table, metric, event, measurements, metadata, context) do
    with true <- selected?(metric, event, metadata, context),
         {:ok, value} <- value(table, metric, measurements) do
      labels =
        Enum.map(metric.dimensions, fn dimension ->
          value = Catalogue.dimension_value(dimension, event, metadata, context)
          {Atom.to_string(dimension), Atom.to_string(value)}
        end)

      key = {kind(metric.type), metric.id, labels}

      if :ets.member(table, key) or reserve(table, metric, key) do
        update(table, metric, key, value)
      else
        :ets.update_counter(table, :dropped_samples, 1)
      end
    end

    :ok
  end

  defp selected?(metric, event, metadata, context) do
    Enum.all?(metric.only, fn {dimension, allowed} ->
      Catalogue.dimension_value(dimension, event, metadata, context) in allowed
    end)
  end

  defp value(_, %{measurement: nil}, _), do: {:ok, 1}

  defp value(table, %{measurement: :duration}, measurements) do
    case Map.get(measurements, :duration) do
      native when is_integer(native) and native >= 0 ->
        {:ok, System.convert_time_unit(native, :native, :nanosecond)}

      native when is_integer(native) ->
        :ets.update_counter(table, :negative_durations, 1)
        :skip

      nil ->
        :skip

      _ ->
        invalid(table)
    end
  end

  defp value(table, metric, measurements) do
    case Map.get(measurements, metric.measurement) do
      nil -> :skip
      value when is_number(value) and metric.type == :gauge -> {:ok, value}
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _ -> invalid(table)
    end
  end

  defp kind(:counter), do: :c
  defp kind(:gauge), do: :g
  defp kind(:histogram), do: :h

  defp cost(%{type: :histogram, buckets: buckets}), do: length(buckets) + 3
  defp cost(_), do: 1

  defp reserve(table, metric, key) do
    cost = cost(metric)
    budget = :ets.lookup_element(table, :series_budget, 2)

    if :ets.update_counter(table, :series_count, {2, cost}) > budget do
      :ets.update_counter(table, :series_count, {2, -cost})
      :ets.update_counter(table, :dropped_series, 1)
      false
    else
      if :ets.insert_new(table, initial(metric, key)) do
        true
      else
        :ets.update_counter(table, :series_count, {2, -cost})
        true
      end
    end
  end

  defp initial(%{type: :histogram, buckets: buckets}, key),
    do: List.to_tuple([key | List.duplicate(0, length(buckets) + 3)])

  defp initial(_, key), do: {key, 0}

  defp update(table, %{type: :counter}, key, value),
    do: :ets.update_counter(table, key, {2, value})

  defp update(table, %{type: :gauge}, key, value), do: :ets.insert(table, {key, value})

  defp update(table, %{type: :histogram} = metric, key, value) do
    thresholds = metric.thresholds
    count = length(thresholds)
    first = Enum.find_index(thresholds, &(value <= &1)) || count
    buckets = for position <- (first + 2)..(count + 2), do: {position, 1}
    :ets.update_counter(table, key, buckets ++ [{count + 3, value}, {count + 4, 1}])
  end

  defp invalid(table) do
    :ets.update_counter(table, :invalid_samples, 1)
    :skip
  catch
    _, _ -> :ok
  end

  defp series(table) do
    metrics = Map.new(Catalogue.metrics(), &{&1.id, &1})

    table
    |> :ets.tab2list()
    |> Enum.flat_map(fn row ->
      case elem(row, 0) do
        {:c, id, labels} -> [one(metrics[id], labels, %{value: elem(row, 1)})]
        {:g, id, labels} -> [one(metrics[id], labels, %{value: Snapshot.number(elem(row, 1))})]
        {:h, id, labels} -> [one(metrics[id], labels, histogram(metrics[id], row))]
        _ -> []
      end
    end)
  end

  defp one(metric, labels, sample),
    do: %{name: metric.name, type: metric.type, labels: labels, sample: sample}

  defp histogram(metric, row) do
    count = length(metric.buckets)
    counts = for position <- 1..(count + 1), do: elem(row, position)
    les = Enum.map(metric.buckets, &Snapshot.number/1) ++ [:infinity]
    sum = elem(row, count + 2)

    %{
      buckets: Enum.zip(les, counts),
      sum: sum(metric.unit, sum),
      count: elem(row, count + 3)
    }
  end

  defp sum(:seconds, nanoseconds), do: Snapshot.number(nanoseconds / @nanoseconds_per_second)
  defp sum(_, value), do: value

  defp counters(table), do: Map.new(@counters, &{&1, lookup(table, &1)})

  defp lookup(table, key), do: :ets.lookup_element(table, key, 2)
end
