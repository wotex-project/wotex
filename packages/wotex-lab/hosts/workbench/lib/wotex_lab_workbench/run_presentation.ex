defmodule WotexLabWorkbench.RunPresentation do
  @moduledoc """
  Inert presentation of an already owned Run.

  View links select one task without executing it. Display charts use elapsed
  seconds from the original run's first event; recorded timestamps, values,
  masks, quality and query inputs remain unchanged.
  """

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.{Chart, Preview, Run}

  @views %{
    "result" => :result,
    "data" => :data,
    "analysis" => :analysis,
    "details" => :details,
    "review" => :review,
    "ask" => :ask
  }

  @doc "Admits a closed Run view; legacy exact-analysis links open Analysis."
  @spec view(map()) :: {:ok, atom()} | {:error, Error.t()}
  def view(params) do
    value =
      Map.get(params, "view", if(Map.has_key?(params, "analysis"), do: "analysis", else: "result"))

    with true <- Enum.all?(Map.keys(params), &(&1 in ~w(id view analysis))),
         {:ok, view} <- Map.fetch(@views, value) do
      {:ok, view}
    else
      _ -> {:error, Error.new(:invalid_run_view, :workbench, "Run view is unavailable")}
    end
  end

  @doc "Returns the contextual destination for one known Run view."
  @spec path(Run.t(), atom()) :: String.t()
  def path(run, :result), do: "/runs/" <> URI.encode(run.id)
  def path(run, view), do: path(run, :result) <> "?" <> URI.encode_query(%{"view" => view})

  @doc "Returns the explicit download destination for the selected Run only."
  @spec report_path(Run.t()) :: String.t()
  def report_path(run), do: "/evidence/report.json?" <> URI.encode_query(%{"run" => run.id})

  @doc "Names the experiment or its current contextual task."
  @spec title(Run.t() | nil, atom()) :: String.t()
  def title(nil, _), do: "Run unavailable"
  def title(%{experiment: "thermal"}, :result), do: "Thermal result"
  def title(%{experiment: "window_anomaly"}, :result), do: "Anomaly result"
  def title(%{experiment: "smart_room"}, :result), do: "Smart room result"
  def title(_, :data), do: "Run data"
  def title(_, :analysis), do: "Analysis"
  def title(_, :details), do: "Run details"
  def title(_, :review), do: "Review Action"
  def title(_, :ask), do: "Ask about this run"
  def title(_, _), do: "Run result"

  @doc "Projects the decoded outcome and a few human-readable facts."
  @spec result(Run.t()) :: map()
  def result(%Run{experiment: "window_anomaly"} = run) do
    summary = Map.new(run.summary)

    %{
      label: "Anomaly score",
      value: Map.get(summary, "Score", "—"),
      unit: "",
      note: if(summary["Anomaly"] == "no", do: "Below threshold", else: "Anomaly detected"),
      facts: [
        {"Prediction", display_unit(summary["Persistence prediction"])},
        {"Threshold", Preview.format(run.params[:threshold])},
        {"Window", summary["Window"]}
      ]
    }
  end

  def result(%Run{proposal: %{"input" => input}} = run) when is_number(input) do
    summary = Map.new(run.summary)

    %{
      label: "Proposed target",
      value: Preview.format(input),
      unit: "°C",
      note: if(run.status == :awaiting_approval, do: "Pending review", else: "Inert proposal"),
      facts:
        if(run.experiment == "smart_room",
          do: [
            {"Temperature", summary["Temperature"]},
            {"Power", summary["Meter"]},
            {"Budget", summary["Power budget"]}
          ],
          else: [{"Rows", summary["Rows"]}]
        )
    }
  end

  def result(_), do: %{label: "Result", value: "—", unit: "", note: "Unavailable", facts: []}

  @doc "Projects chart time for display while retaining every admitted y value and gap."
  @spec display_chart(Run.t(), Chart.t()) :: Chart.t()
  def display_chart(run, chart) do
    origin =
      run.timeseries
      |> Enum.flat_map(& &1.points)
      |> Enum.map(&elem(&1, 0))
      |> Enum.min(fn -> 0 end)

    series =
      Enum.map(chart.series, fn series ->
        %{series | points: Enum.map(series.points, fn {x, y} -> {(x - origin) / 1_000, y} end)}
      end)

    %{
      chart
      | title: display_unit(chart.title),
        x: %{chart.x | title: "Elapsed (s)"},
        y: %{chart.y | title: display_unit(chart.y.title)},
        series: series
    }
  end

  defp display_unit(nil), do: "—"
  defp display_unit(value), do: String.replace(value, "Cel", "°C")
end
