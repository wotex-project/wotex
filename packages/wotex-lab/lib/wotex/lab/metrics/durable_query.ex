defmodule Wotex.Lab.Metrics.DurableQuery do
  @moduledoc """
  Answers an admitted `Wotex.Lab.Metrics.Query` from a PromQL-compatible durable
  receiver through fixed read templates.

  `template/2` turns the descriptor into one PromQL expression and a range
  request. Every selector carries `instance="<scope instance>"` and one exact
  matcher per filter. Metric names, label names and values come from the closed
  catalogue, so caller text never reaches the expression. The supported
  aggregations mirror `Wotex.Lab.Metrics.History`, except gauge `:avg`, whose
  per-sample average PromQL cannot reproduce across series:

  | Type | Aggregation | Template |
  | --- | --- | --- |
  | gauge | `:last` | `last_over_time(m[w])` |
  | gauge | `:sum`, `:min`, `:max` | `sum(last_over_time(m[w]))`, `min(min_over_time(m[w]))`, `max(max_over_time(m[w]))` |
  | counter | `:last`, `:sum` | `last_over_time(m[w])`, `sum(last_over_time(m[w]))` |
  | counter | `:increase`, `:rate` | `sum(increase(m[r]))`, `sum(rate(m[r]))` |
  | histogram | `:increase` | `sum(increase(m_count[r]))` |
  | histogram | `:histogram_quantile` | `histogram_quantile(q, sum by (le) (increase(m_bucket[r])))` |

  The window `w` equals the step, so a step without a stored sample is missing
  rather than filled by the receiver's lookback. PromQL needs two samples inside
  a window to compute an increase, so `r` is the larger of the step and three
  capture intervals (`:capture_interval_ms`, default 5,000, 1,000 to 60,000).
  Steps must be whole seconds, and the start must be a whole multiple of the
  step in Unix time. GreptimeDB 1.1.4 omits range-function values at some
  evaluation times when the grid is not aligned that way and the window equals
  the step, even though a stored sample lies inside the window; an unaligned
  start is therefore refused rather than answered with silently missing steps.
  Increases are the receiver's extrapolated PromQL values over that trailing
  window; they are not the exact per-step deltas of local history.

  `query/3` sends the request through a host executor and admits the matrix
  answer. A `:last` answer with several series is refused as ambiguous, like
  local history. `NaN` and infinite values are omitted and marked
  `nonfinite`. The descriptor's point and output limits apply to the admitted
  answer; the executor must bound the response body it reads. Receiver error
  text is never returned. Responses carry the source, instance, unit, interval
  with window, freshness, points, markers, matched series and both the query
  and template digests. This module performs no network access; database
  selection, credentials and endpoints belong to the host executor.
  """

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.{Catalogue, Query, Snapshot}

  @path "/v1/prometheus/api/v1/query_range"
  @default_interval 5_000
  @nonfinite ~w(NaN +Inf -Inf Inf -inf +inf inf nan)

  @type template :: %{
          path: String.t(),
          expression: String.t(),
          params: [{String.t(), String.t()}],
          window_ms: pos_integer(),
          digest: String.t()
        }

  @doc "Builds the fixed PromQL request for an admitted descriptor."
  @spec template(Query.t(), keyword()) :: {:ok, template()} | {:error, Error.t()}
  def template(query, opts \\ []) do
    with :ok <- Options.validate(opts, [:capture_interval_ms]),
         {:ok, interval} <- capture_interval(opts),
         {:ok, query} <- Query.validate(query),
         {:ok, _} <- Query.estimate(query),
         {:ok, metric} <- Catalogue.fetch(query.metric),
         {:ok, shape} <- shape(metric.type, query.aggregation),
         :ok <- whole_seconds(query.step_ms),
         :ok <- aligned(query) do
      window = window(shape, query.step_ms, interval)
      expression = expression(shape, metric, query, seconds(window))

      {:ok,
       %{
         path: @path,
         expression: expression,
         params: [
           {"query", expression},
           {"start", unix(query.start_at)},
           {"end", unix(query.end_at)},
           {"step", seconds(query.step_ms)}
         ],
         window_ms: window,
         digest: "sha256:" <> Base.encode16(:crypto.hash(:sha256, expression), case: :lower)
       }}
    end
  end

  @doc """
  Answers the descriptor through `executor`, a function of the template.

  The executor returns `{:ok, decoded_json}` or `{:error, reason}`.
  """
  @spec query(Query.t(), (template() -> {:ok, term()} | {:error, term()}), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def query(query, executor, opts \\ []) when is_function(executor, 1) do
    with {:ok, template} <- template(query, opts),
         {:ok, query} <- Query.validate(query),
         {:ok, body} <- execute(executor, template),
         {:ok, series} <- matrix(body),
         :ok <- ambiguity(series, query),
         {:ok, points, markers} <- points(series, query) do
      {:ok, metric} = Catalogue.fetch(query.metric)
      end_ms = DateTime.to_unix(query.end_at, :millisecond)

      response = %{
        source: :durable_promql,
        instance: query.scope.instance,
        metric: metric.id,
        name: metric.name,
        unit: metric.unit,
        aggregation: query.aggregation,
        interval: %{
          start_ms: DateTime.to_unix(query.start_at, :millisecond),
          end_ms: end_ms,
          step_ms: query.step_ms,
          window_ms: template.window_ms
        },
        freshness: freshness(points, end_ms),
        points: points,
        markers: markers,
        series_matched: length(series),
        digest: Query.digest(query),
        template_digest: template.digest,
        evidence: []
      }

      if :erlang.external_size(response) > query.limits.output_bytes,
        do: {:error, error(:output_too_large, "response exceeds the output limit")},
        else: {:ok, response}
    end
  end

  defp capture_interval(opts) do
    case Keyword.get(opts, :capture_interval_ms, @default_interval) do
      interval when is_integer(interval) and interval in 1_000..60_000 -> {:ok, interval}
      _ -> {:error, error(:invalid_options, "capture interval is outside its bounds")}
    end
  end

  defp shape(:gauge, aggregation) when aggregation in [:last, :sum, :min, :max],
    do: {:ok, {:sample, aggregation}}

  defp shape(:counter, aggregation) when aggregation in [:last, :sum],
    do: {:ok, {:sample, aggregation}}

  defp shape(:counter, aggregation) when aggregation in [:increase, :rate],
    do: {:ok, {:delta, aggregation, ""}}

  defp shape(:histogram, :increase), do: {:ok, {:delta, :increase, "_count"}}
  defp shape(:histogram, :histogram_quantile), do: {:ok, :quantile}

  defp shape(type, aggregation),
    do:
      {:error,
       error(:unsupported_query, "durable templates cannot answer this aggregation honestly",
         details: %{type: type, aggregation: aggregation}
       )}

  defp whole_seconds(step) when rem(step, 1_000) == 0, do: :ok

  defp whole_seconds(_),
    do: {:error, error(:unsupported_query, "durable templates need a whole-second step")}

  defp aligned(query) do
    if rem(DateTime.to_unix(query.start_at, :millisecond), query.step_ms) == 0,
      do: :ok,
      else:
        {:error,
         error(:unsupported_query, "durable templates need a start on a whole multiple of the step")}
  end

  defp window({:sample, _}, step, _), do: step
  defp window(_, step, interval), do: max(step, div(3 * interval + 999, 1_000) * 1_000)

  defp expression({:sample, :last}, metric, query, w),
    do: "last_over_time(#{selector(metric.name, query)}[#{w}])"

  defp expression({:sample, :sum}, metric, query, w),
    do: "sum(last_over_time(#{selector(metric.name, query)}[#{w}]))"

  defp expression({:sample, :min}, metric, query, w),
    do: "min(min_over_time(#{selector(metric.name, query)}[#{w}]))"

  defp expression({:sample, :max}, metric, query, w),
    do: "max(max_over_time(#{selector(metric.name, query)}[#{w}]))"

  defp expression({:delta, function, suffix}, metric, query, w),
    do: "sum(#{function}(#{selector(metric.name <> suffix, query)}[#{w}]))"

  defp expression(:quantile, metric, query, w) do
    "histogram_quantile(#{query.quantile}, sum by (le) " <>
      "(increase(#{selector(metric.name <> "_bucket", query)}[#{w}])))"
  end

  defp selector(name, query) do
    matchers =
      [{"instance", query.scope.instance}] ++
        (query.filters
         |> Enum.map(fn {key, value} -> {Atom.to_string(key), Atom.to_string(value)} end)
         |> Enum.sort())

    name <> "{" <> Enum.map_join(matchers, ",", fn {k, v} -> ~s(#{k}="#{v}") end) <> "}"
  end

  defp seconds(ms), do: "#{div(ms, 1_000)}s"

  defp unix(datetime) do
    ms = DateTime.to_unix(datetime, :millisecond)
    "#{div(ms, 1_000)}.#{String.pad_leading(Integer.to_string(rem(ms, 1_000)), 3, "0")}"
  end

  defp execute(executor, template) do
    case executor.(template) do
      {:ok, body} -> {:ok, body}
      _ -> {:error, error(:durable_unavailable, "durable receiver is unavailable")}
    end
  end

  defp matrix(%{"status" => "success", "data" => %{"resultType" => "matrix", "result" => result}})
       when is_list(result) do
    if Enum.all?(result, &series?/1),
      do: {:ok, result},
      else: {:error, error(:durable_invalid_response, "durable answer is not an admitted matrix")}
  end

  defp matrix(%{"status" => "success"}),
    do: {:error, error(:durable_invalid_response, "durable answer is not an admitted matrix")}

  defp matrix(%{"status" => _}),
    do: {:error, error(:durable_refused, "durable receiver refused the query")}

  defp matrix(_),
    do: {:error, error(:durable_invalid_response, "durable answer is not an admitted matrix")}

  defp series?(%{"metric" => metric, "values" => values}) when is_map(metric) and is_list(values),
    do: Enum.all?(values, &match?([t, v] when is_number(t) and is_binary(v), &1))

  defp series?(_), do: false

  defp ambiguity(series, query) do
    if length(series) > 1 and query.aggregation == :last,
      do:
        {:error,
         error(:unsupported_query, "aggregation needs one series; add filters or use sum",
           details: %{series_matched: length(series)}
         )},
      else: :ok
  end

  defp points(series, query) do
    samples =
      series
      |> Enum.flat_map(& &1["values"])
      |> Enum.map(fn [t, v] -> {round(t * 1_000), v} end)
      |> Enum.sort_by(&elem(&1, 0))

    if length(samples) > query.limits.points do
      {:error, error(:query_too_large, "durable answer exceeds the point limit")}
    else
      {points, markers} =
        Enum.reduce(samples, {[], []}, fn {t, value}, {points, markers} ->
          case number(value) do
            {:ok, number} -> {[%{t: t, value: number} | points], markers}
            :nonfinite -> {points, [%{t: t, kind: :nonfinite} | markers]}
            :invalid -> {points, [%{t: t, kind: :invalid} | markers]}
          end
        end)

      {:ok, Enum.reverse(points), Enum.reverse(markers)}
    end
  end

  defp number(value) when value in @nonfinite, do: :nonfinite

  defp number(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, Snapshot.number(float)}
      _ -> :invalid
    end
  end

  defp freshness([], _), do: nil

  defp freshness(points, end_ms) do
    latest = Enum.max(Enum.map(points, & &1.t))
    %{latest_ms: latest, age_ms: end_ms - latest}
  end

  defp error(code, message, opts \\ []), do: Error.new(code, :durable_query, message, opts)
end
