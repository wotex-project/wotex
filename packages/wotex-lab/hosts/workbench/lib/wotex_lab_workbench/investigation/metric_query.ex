defmodule WotexLabWorkbench.Investigation.MetricQuery do
  @moduledoc """
  Room-bound investigation queries and compact summaries of their exact charts.

  The server supplies the room. The model can select a catalogue metric and its
  type-appropriate aggregation only. The retained result is the same executed
  history result used to construct the summary; pinning never queries again.
  """

  alias Wotex.Lab.Metrics.Catalogue
  alias WotexLabWorkbench.{Board, HistoryPanels, Room}

  @aggregations %{counter: "rate", gauge: "last", histogram: "histogram_quantile"}

  @doc "Queries five minutes of the supplied room's attributed history."
  @spec load(pid(), String.t(), String.t()) :: {:ok, map(), map()} | {:error, atom()}
  def load(room, metric_id, aggregation) when is_pid(room) do
    metric = Enum.find(Catalogue.metrics(), &(Atom.to_string(&1.id) == metric_id))

    with true <- metric != nil and aggregation == @aggregations[metric.type],
         {:ok, binding} <- Room.history(room),
         {:ok, history} <- HistoryPanels.load(binding, [metric_id], "5m") do
      history = Map.put(history, :queried_at, System.system_time(:millisecond))
      {:ok, summary(history), history}
    else
      false -> {:error, :invalid_request}
      {:error, %{code: code}} -> {:error, code}
    end
  catch
    :exit, _ -> {:error, :history_unavailable}
  end

  def load(_, _, _), do: {:error, :history_unavailable}

  defp summary(%{panels: [panel]} = history) do
    %{
      available: Board.measured?(panel),
      source: "Room history",
      metric: panel.id,
      aggregation: panel.aggregation,
      unit: panel.display_unit,
      interval: Map.take(history, [:start_ms, :end_ms, :step_ms]),
      freshness_ms: panel.freshness_ms,
      series_shown: panel.series_shown,
      series_total: panel.series_total,
      markers: panel.markers,
      queries: Enum.map(panel.digests, &%{digest: &1}),
      series: if(panel.chart, do: Enum.map(panel.chart.series, &series_summary/1), else: []),
      error: panel.error
    }
  end

  defp series_summary(series) do
    measured = Enum.filter(series.points, &is_number(elem(&1, 1)))
    values = Enum.map(measured, &elem(&1, 1))

    %{
      name: series.name,
      samples: length(values),
      missing: length(series.points) - length(values),
      min: Enum.min(values, fn -> nil end),
      max: Enum.max(values, fn -> nil end),
      latest:
        case List.last(measured) do
          nil -> nil
          {offset, value} -> %{offset_s: offset, value: value}
        end
    }
  end
end
