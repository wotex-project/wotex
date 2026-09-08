defmodule WotexLabWorkbench.Insights do
  @moduledoc """
  Server admission for interactive analysis of an already-owned run.

  The caller supplies the session-owned run, never a browser-selected instance.
  Controls select a series, inclusive event-time range and line/point/area mark.
  The shared optional Lab analytics profile computes summaries in Explorer;
  this adapter only admits form values and builds the closed chart descriptors.
  """

  alias Wotex.Lab.Analytics
  alias Wotex.Lab.Error
  alias WotexLabWorkbench.{Chart, Run}

  @doc "Analyzes an existing run without changing its parameters, evidence or effects."
  @spec analyze(Run.t(), term()) :: {:ok, map()} | {:error, Error.t()}
  def analyze(%Run{} = run, params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in ~w(series from to mark))),
         mark when mark in ~w(line point area) <- Map.get(params, "mark", "line"),
         {:ok, from} <- number(Map.get(params, "from", "")),
         {:ok, to} <- number(Map.get(params, "to", "")),
         series = Map.get(params, "series", ""),
         {:ok, result} <-
           Analytics.analyze(run.timeseries,
             series: if(series == "", do: nil, else: series),
             from: from,
             to: to
           ),
         {:ok, charts} <- charts(result.plots, mark) do
      {:ok, result |> Map.merge(%{charts: charts, mark: mark, run_id: run.id})}
    else
      {:error, error} -> {:error, error}
      _invalid -> invalid()
    end
  end

  def analyze(%Run{}, _params), do: invalid()

  defp charts(plots, mark) do
    plots
    |> Enum.group_by(& &1.unit)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, []}, fn {unit, series}, {:ok, charts} ->
      case Chart.new(
             title: "Run comparison (#{unit})",
             mark: mark,
             x: %{field: "time", title: "event time"},
             y: %{field: "value", title: unit},
             series: Enum.map(series, &Map.take(&1, [:name, :points]))
           ) do
        {:ok, chart} -> {:cont, {:ok, charts ++ [chart]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp number(""), do: {:ok, nil}

  defp number(value) when is_binary(value) and byte_size(value) <= 64 do
    case Float.parse(value) do
      {number, ""} when abs(number) <= 1.0e100 -> {:ok, number}
      _invalid -> invalid()
    end
  end

  defp number(_value), do: invalid()

  defp invalid,
    do: {:error, Error.new(:invalid_analysis_query, :analytics, "analysis controls are malformed")}
end
