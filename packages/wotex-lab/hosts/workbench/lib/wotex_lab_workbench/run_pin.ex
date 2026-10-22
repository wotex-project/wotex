defmodule WotexLabWorkbench.RunPin do
  @moduledoc """
  An immutable result and chart captured from an already-owned Run.

  The session resolves the Run before admission. A pin retains its exact record,
  analysis query and displayed series; it has no refresh or execution capability.
  Pinning never starts a Run, transport operation, provider or history query.
  """

  alias Wotex.Lab.{Error, Evidence.Record}
  alias Wotex.Lab.Island.Encoder
  alias WotexLabWorkbench.{Chart, Insights, Run, RunPresentation}

  @doc "Captures one admitted chart and outcome without changing its source Run."
  @spec new(Run.t(), term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def new(%Run{} = run, index, query) when is_integer(index) and index in 0..7 do
    with {:ok, charts, query, path} <- charts(run, query),
         %Chart{} = chart <- Enum.at(charts, index),
         true <- available?(run, chart) do
      chart = RunPresentation.display_chart(run, chart)
      record = Record.to_map(run.record)
      identity = {run.id, run.record_digest, index, query, chart}
      digest = :crypto.hash(:sha256, :erlang.term_to_binary(identity, [:deterministic]))

      pin = %{
        kind: :run,
        id: "pin-run-" <> Base.encode16(digest, case: :lower),
        title: chart.title,
        run_id: run.id,
        chart_index: index,
        record_digest: run.record_digest,
        record: record,
        query: query,
        path: path,
        source_mode: run.source_mode,
        started_at: DateTime.to_iso8601(run.started_at),
        captured_state: Run.state_text(run),
        outcome: Map.take(RunPresentation.result(run), [:label, :value, :unit, :note]),
        mark: chart.mark,
        unit: chart.y.title,
        result: %{chart: chart},
        paused: true,
        error: nil
      }

      with true <- byte_size(:erlang.term_to_binary(pin)) <= 65_536,
           {:ok, _} <-
             Encoder.encode("canvas", %{
               "label" => "Run capture",
               "nodes" => [],
               "edges" => [],
               "pins" => [payload(pin, 0, %{})]
             }) do
        {:ok, pin}
      else
        _ -> invalid()
      end
    else
      _ -> invalid()
    end
  end

  def new(_, _, _), do: invalid()

  @doc "Checks the captured chart and record ceilings before offering Pin."
  @spec available?(term(), term()) :: boolean()
  def available?(%Run{record: %Record{}, record_digest: digest, error: nil} = run, %Chart{} = chart) do
    is_binary(digest) and Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, digest) and
      text?(run.source_mode, 64) and match?(%DateTime{}, run.started_at) and
      match?({:ok, _}, Chart.new(Map.to_list(Map.from_struct(chart)))) and
      text?(chart.title, 128) and text?(chart.y.title, 32) and
      Enum.all?(chart.series, &text?(&1.name, 128)) and
      Enum.sum(Enum.map(chart.series, &length(&1.points))) <= 512 and
      Enum.any?(chart.series, fn series -> Enum.any?(series.points, &is_number(elem(&1, 1))) end)
  end

  def available?(_, _), do: false

  @doc "Serializes the already admitted analysis controls for the Pin form."
  @spec query(map() | nil) :: map() | nil
  def query(%{query: query, mark: mark}) do
    %{
      "series" => query.series || "",
      "from" => if(is_nil(query.from), do: "", else: to_string(query.from)),
      "to" => if(is_nil(query.to), do: "", else: to_string(query.to)),
      "mark" => mark
    }
  end

  def query(nil), do: nil

  @doc "Projects only the captured presentation fields into the closed canvas pin union."
  @spec payload(map(), non_neg_integer(), map()) :: map()
  def payload(pin, index, position) do
    chart = pin.result && pin.result.chart

    %{
      "kind" => "run",
      "id" => pin.id,
      "title" => pin.title,
      "run_id" => pin.run_id,
      "record_digest" => pin.record_digest,
      "chart_index" => pin.chart_index,
      "source_mode" => pin.source_mode,
      "state" => pin.error || "Captured · #{pin.captured_state}",
      "started_at" => pin.started_at,
      "unit" => pin.unit,
      "mark" => pin.mark,
      "outcome" =>
        if(pin.outcome,
          do: Map.new(pin.outcome, fn {k, v} -> {Atom.to_string(k), v} end),
          else: nil
        ),
      "series" =>
        if(chart,
          do:
            Enum.map(chart.series, fn s ->
              %{"name" => s.name, "points" => Enum.map(s.points, fn {x, y} -> [x, y] end)}
            end),
          else: []
        ),
      "x" => Map.get(position, "x", 1080),
      "y" => Map.get(position, "y", 80 + index * 280),
      "width" => Map.get(position, "width", 360),
      "height" => Map.get(position, "height", 340)
    }
  end

  defp charts(run, nil),
    do: {:ok, RunPresentation.charts(run), nil, RunPresentation.path(run, :result)}

  defp charts(run, query) when is_map(query) do
    with {:ok, result} <- Insights.analyze(run, query),
         do: {:ok, result.charts, query(result), Insights.path(result)}
  end

  defp charts(_, _), do: invalid()

  defp text?(value, limit),
    do: is_binary(value) and String.valid?(value) and byte_size(value) <= limit

  defp invalid,
    do:
      {:error,
       Error.new(
         :unavailable_run_pin,
         :workbench,
         "Choose a recorded Run chart with at most 512 points"
       )}
end
