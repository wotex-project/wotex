defmodule WotexLabWorkbench.HistoryPanels do
  @moduledoc """
  Query-backed history for saved metric panels in one session room.

  `load/4` accepts a room history binding from `WotexLabWorkbench.Room.history/1`,
  1–16 catalogue panel IDs admitted by `WotexLabWorkbench.Observability.Panels`
  and one closed range: `"5m"`, `"15m"` or `"1h"` with 5-, 15- or 60-second steps.
  The panel's metric type selects the aggregation. Counters show the per-second
  rate of the increase inside each step. Gauges show the last value in each step.
  Histograms show the bucket-derived p95 of the observations inside each step.
  Each distinct label set is a separate `Wotex.Lab.Metrics.Query` with filters
  for every dimension. At most eight label sets per panel are queried, in label
  order, and the result states how many exist.

  Every query carries the binding's server-owned scope and reduced limits: a
  one-hour range, 5-second minimum step, 2,000 points, 256 KiB output, a
  250 ms deadline and two concurrent queries. The whole load stops starting
  queries after 1.5 seconds; later panels report `not_queried`. A step without
  a stored sample is a chart gap, never zero. Rates start at the first capture
  inside the range. Responses keep freshness, query digests and gap, reset,
  stale, evicted and clock-rollback markers. A panel without captured series
  in the range is unavailable.

  The history holds only events attributed to the room's process tree. Things
  and shared processes started under the host instance, and every other
  session, are outside it. Loading reads no host-wide PromEx history, starts no
  collector and dispatches no Action.
  """

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{Catalogue, History, Query}
  alias WotexLabWorkbench.Chart
  alias WotexLabWorkbench.Observability.Panels

  @ranges %{
    "5m" => %{range_ms: 300_000, step_ms: 5_000},
    "15m" => %{range_ms: 900_000, step_ms: 15_000},
    "1h" => %{range_ms: 3_600_000, step_ms: 60_000}
  }
  @range_order ~w(5m 15m 1h)
  @max_series 8
  @budget_ms 1_500
  @limits %{
    range_ms: 3_600_000,
    min_step_ms: 5_000,
    points: 2_000,
    output_bytes: 262_144,
    deadline_ms: 250,
    concurrent: 2
  }
  @marker_kinds ~w(gap reset stale evicted clock_rollback)a

  @type status :: :available | :unavailable | :refused | :not_queried
  @type panel :: %{
          id: String.t(),
          title: String.t(),
          aggregation: String.t(),
          display_unit: String.t(),
          status: status(),
          chart: Chart.t() | nil,
          series_total: non_neg_integer(),
          series_shown: non_neg_integer(),
          freshness_ms: non_neg_integer() | nil,
          markers: %{atom() => non_neg_integer()},
          digests: [String.t()],
          error: String.t() | nil
        }
  @type result :: %{
          range: String.t(),
          start_ms: integer(),
          end_ms: integer(),
          step_ms: pos_integer(),
          panels: [panel()]
        }

  @doc "The closed range identifiers, shortest first."
  @spec ranges() :: [String.t()]
  def ranges, do: @range_order

  @doc "The range used when the page first offers history."
  @spec default_range() :: String.t()
  def default_range, do: "15m"

  @doc """
  Queries the room history for each admitted panel over one closed range.

  `:now` (a UTC `DateTime`) and `:budget_ms` (0 to 1,500) are test seams.
  Unknown ranges, panel IDs and malformed bindings return structured errors.
  """
  @spec load(term(), term(), term(), keyword()) :: {:ok, result()} | {:error, Error.t()}
  def load(binding, panel_ids, range, opts \\ [])

  def load(%{history: history, scope: scope}, panel_ids, range, opts)
      when is_pid(history) and is_list(opts) do
    with {:ok, window} <- range(range),
         {:ok, panels} <- Panels.select(panel_ids),
         {:ok, budget} <- budget(opts),
         {:ok, now} <- now(opts),
         {:ok, rows} <- rows(history) do
      step = window.step_ms
      end_ms = div(DateTime.to_unix(now, :millisecond) + step - 1, step) * step
      start_ms = end_ms - window.range_ms
      deadline = System.monotonic_time(:millisecond) + budget

      context = %{
        now_ms: DateTime.to_unix(now, :millisecond),
        history: history,
        scope: scope,
        start_ms: start_ms,
        end_ms: end_ms,
        step_ms: step,
        deadline: deadline,
        rows: Enum.filter(rows, &(&1.wall_time_ms >= start_ms and &1.wall_time_ms <= end_ms))
      }

      {:ok,
       %{
         range: range,
         start_ms: start_ms,
         end_ms: end_ms,
         step_ms: step,
         panels: Enum.map(panels, &panel(&1, context))
       }}
    end
  end

  def load(_, _, _, _),
    do: {:error, Error.new(:history_unavailable, :metrics, "room history is unavailable")}

  defp range(range) when is_binary(range) do
    case Map.fetch(@ranges, range) do
      {:ok, window} -> {:ok, window}
      :error -> invalid_range()
    end
  end

  defp range(_), do: invalid_range()

  defp invalid_range,
    do: {:error, Error.new(:invalid_range, :metrics, "history range is not admitted")}

  defp budget(opts) do
    case Keyword.get(opts, :budget_ms, @budget_ms) do
      budget when is_integer(budget) and budget in 0..@budget_ms -> {:ok, budget}
      _ -> {:error, Error.new(:invalid_budget, :metrics, "history budget is not admitted")}
    end
  end

  defp now(opts) do
    case Keyword.get(opts, :now, DateTime.utc_now()) do
      %DateTime{time_zone: "Etc/UTC"} = now -> {:ok, now}
      _ -> {:error, Error.new(:invalid_range, :metrics, "history end must be UTC")}
    end
  end

  defp rows(history) do
    {:ok, Enum.map(History.snapshots(history), & &1.snapshot)}
  catch
    :exit, _ ->
      {:error, Error.new(:history_unavailable, :metrics, "room history is unavailable")}
  end

  defp panel(descriptor, context) do
    {:ok, metric} = Catalogue.fetch(String.to_existing_atom(descriptor.id))
    label_sets = label_sets(context.rows, metric.name)
    shown = Enum.take(label_sets, @max_series)

    base = %{
      id: descriptor.id,
      title: descriptor.title,
      aggregation: aggregation_text(metric.type),
      display_unit: descriptor.display_unit,
      status: :unavailable,
      chart: nil,
      series_total: length(label_sets),
      series_shown: length(shown),
      freshness_ms: nil,
      markers: Map.new(@marker_kinds, &{&1, 0}),
      digests: [],
      error: nil
    }

    cond do
      shown == [] ->
        base

      System.monotonic_time(:millisecond) >= context.deadline ->
        %{base | status: :not_queried, error: "budget_exhausted"}

      true ->
        query_panel(base, metric, shown, context)
    end
  end

  defp label_sets(rows, name) do
    rows
    |> Enum.flat_map(fn snapshot ->
      for %{name: ^name, labels: labels} <- snapshot.series, do: labels
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp query_panel(base, metric, label_sets, context) do
    queried =
      Enum.reduce_while(label_sets, {[], []}, fn labels, {answers, _} ->
        case query(metric, labels, context) do
          {:ok, answer} -> {:cont, {[{labels, answer} | answers], []}}
          {:error, %Error{code: code}} -> {:halt, {answers, [Atom.to_string(code)]}}
        end
      end)

    case queried do
      {_, ["budget_exhausted"]} ->
        %{base | status: :not_queried, error: "budget_exhausted"}

      {_, [code]} ->
        %{base | status: :refused, error: code}

      {answers, []} ->
        answers = Enum.reverse(answers)
        chart_panel(base, answers, context)
    end
  end

  defp query(metric, labels, context) do
    if System.monotonic_time(:millisecond) >= context.deadline do
      {:error, Error.new(:budget_exhausted, :metrics, "history budget is exhausted")}
    else
      with {:ok, query} <-
             Query.new(
               scope: context.scope,
               metric: metric.id,
               aggregation: aggregation(metric.type),
               quantile: if(metric.type == :histogram, do: 0.95),
               filters: filters(labels),
               start_at: DateTime.from_unix!(context.start_ms, :millisecond),
               end_at: DateTime.from_unix!(context.end_ms, :millisecond),
               step_ms: context.step_ms,
               limits: @limits
             ) do
        History.query(context.history, query)
      end
    end
  end

  defp filters(labels) do
    dimensions = Catalogue.dimensions()

    Map.new(labels, fn {dimension, value} ->
      key = Enum.find(Map.keys(dimensions), &(Atom.to_string(&1) == dimension))
      {key, Enum.find(Map.fetch!(dimensions, key), &(Atom.to_string(&1) == value))}
    end)
  end

  defp chart_panel(base, answers, context) do
    steps = Enum.to_list(context.start_ms..context.end_ms//context.step_ms)

    series =
      answers
      |> Enum.with_index(1)
      |> Enum.map(fn {{labels, answer}, index} ->
        values = Map.new(answer.points, &{&1.t, &1.value})

        %{
          name: series_name(labels, index),
          points: Enum.map(steps, &{div(&1 - context.end_ms, 1_000), Map.get(values, &1)})
        }
      end)

    {:ok, chart} =
      Chart.new(
        title: "#{base.title} (#{base.aggregation})",
        mark: "line",
        x: %{field: "offset_s", title: "Seconds before the range end"},
        y: %{field: "value", title: base.display_unit},
        series: series
      )

    markers =
      answers
      |> Enum.flat_map(fn {_, answer} -> answer.markers end)
      |> Enum.uniq()
      |> Enum.frequencies_by(& &1.kind)

    %{
      base
      | status: :available,
        chart: chart,
        freshness_ms: freshness(answers, context.now_ms),
        markers: Map.new(@marker_kinds, &{&1, Map.get(markers, &1, 0)}),
        digests: Enum.map(answers, fn {_, answer} -> answer.digest end)
    }
  end

  defp series_name(labels, index) do
    name = Enum.map_join(labels, " ", fn {key, value} -> "#{key}=#{value}" end)
    if name != "" and byte_size(name) <= 128, do: name, else: "series #{index}"
  end

  defp freshness(answers, now_ms) do
    answers
    |> Enum.flat_map(fn {_, answer} ->
      if answer.freshness, do: [max(now_ms - answer.freshness.latest_ms, 0)], else: []
    end)
    |> Enum.min(fn -> nil end)
  end

  defp aggregation(:counter), do: :rate
  defp aggregation(:gauge), do: :last
  defp aggregation(:histogram), do: :histogram_quantile

  defp aggregation_text(:counter), do: "rate per step"
  defp aggregation_text(:gauge), do: "last value per step"
  defp aggregation_text(:histogram), do: "p95 per step"
end
