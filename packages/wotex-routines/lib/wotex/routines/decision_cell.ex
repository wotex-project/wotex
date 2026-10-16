defmodule Wotex.Routines.DecisionCell do
  @moduledoc false

  alias Wotex.Routines.{ClockBasis, Error, ExecutionTree, Limits, Validation}

  # Internal component: the decision verifier must establish the complete point
  # relation and validate Time before either operation. This does not verify a
  # Collection, authenticate its inputs or grant current effect admission.
  @doc false
  @spec derive(map(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def derive(collection, %Limits{data: limits} = selected) do
    time = collection["input"]["time"]
    maximum = limits["max_integer"]

    state = %{
      elapsed: axis(time["elapsed_ms"], 0, maximum),
      utc_low: utc_axis(time["utc_low_ms"], maximum),
      utc_high: utc_axis(time["utc_high_ms"], maximum),
      relevant: false
    }

    results = Map.new(collection["transitions"], &{&1["program_digest"], &1["result"]})

    state =
      Enum.reduce(collection["input"]["entries"], state, fn entry, state ->
        entry(state, entry, results[entry["program"]["ir_digest"]])
      end)

    mode = utc_mode(state, time)

    cell = %{
      "format" => "wotex.routines.time-cell@1",
      "time_format" => ClockBasis.format(time),
      "epoch" => time["epoch"],
      "clock_generation" => time["clock_generation"],
      "utc_generation" => if(mode == "ignored", do: nil, else: ClockBasis.utc_generation(time)),
      "utc_mode" => mode,
      "elapsed" => interval(state.elapsed, true),
      "utc_low" => utc_interval(state.utc_low, mode),
      "utc_high" => utc_interval(state.utc_high, mode)
    }

    with :ok <- Validation.bounded(cell, selected), do: {:ok, cell}
  end

  @doc false
  @spec check(map(), map()) :: :ok | {:error, Error.t()}
  def check(cell, time) do
    with :ok <- equal(cell["time_format"], ClockBasis.format(time), "/cell/time_format"),
         :ok <- equal(cell["epoch"], time["epoch"], "/cell/epoch"),
         :ok <-
           equal(cell["clock_generation"], time["clock_generation"], "/cell/clock_generation"),
         :ok <- inside(cell["elapsed"], time["elapsed_ms"], "/cell/elapsed") do
      check_utc(cell, time)
    end
  end

  defp entry(state, entry, result) do
    program = entry["program"]
    nodes = Map.new(ExecutionTree.nodes(program["ir"]["steps"]), &{&1["path"], &1})
    bases = Map.new(program["context"]["bases"], &{&1["id"], &1})
    state = relevant(state, program["ir"]["trigger"]["kind"] == "due")

    state =
      Enum.reduce(program["context"]["bindings"], state, fn {name, binding}, state ->
        fact(state, entry["snapshot"]["facts"][name], bases[binding["basis"]["id"]])
      end)

    state = temporal(state, entry["event"])
    state = edge(state, entry["prior"]["edge"], program["ir"]["trigger"])
    state = edge(state, result && result["edge"], program["ir"]["trigger"])

    [entry["prior"]["original"], entry["prior"]["busy"], result && result["run"]]
    |> Enum.reduce(state, &run(&2, &1, nodes))
  end

  defp fact(state, fact, basis) do
    evidence = basis["evidence"]
    state = relevant(state, evidence["require_source_time"])
    fact_coordinates(state, fact, evidence)
  end

  defp fact_coordinates(state, nil, _), do: state

  defp fact_coordinates(state, fact, evidence) do
    state
    |> cut(:elapsed, fact["receipt_ms"])
    |> cut(:elapsed, fact["receipt_ms"] + evidence["freshness_ms"] + 1)
    |> cut(:elapsed, fact["expires_ms"])
    |> source_coordinates(fact, evidence)
  end

  defp source_coordinates(
         state,
         %{"source_time" => source, "source_uncertainty_ms" => uncertainty},
         %{"require_source_time" => true} = evidence
       )
       when is_binary(source) and is_integer(uncertainty) do
    {:ok, instant, _} = DateTime.from_iso8601(source)
    center = DateTime.to_unix(instant, :millisecond)

    state
    |> cut(:utc_low, center + uncertainty)
    |> cut(:utc_high, center - uncertainty + evidence["freshness_ms"] + 1)
  end

  defp source_coordinates(state, _, _), do: state

  defp run(state, nil, _), do: state

  defp run(state, run, nodes) do
    state =
      state
      |> cut(:elapsed, run["last_ms"])
      |> cut(:elapsed, run["deadline_ms"])
      |> temporal(run["window"])

    Enum.reduce(run["steps"], state, fn record, state ->
      state
      |> cut(:elapsed, record["deadline_ms"])
      |> started(record, nodes[record["path"]])
    end)
  end

  defp started(state, %{"started_ms" => nil}, _), do: state

  defp started(state, record, %{"kind" => "delay", "duration_ms" => duration}),
    do: cut(state, :elapsed, record["started_ms"] + duration)

  defp started(state, record, %{"kind" => "wait", "timeout_ms" => duration}),
    do: cut(state, :elapsed, record["started_ms"] + duration)

  defp started(state, record, %{"kind" => "invoke", "run_ms" => duration}),
    do: cut(state, :elapsed, record["started_ms"] + duration)

  defp started(state, _, _), do: state

  defp temporal(state, %{"due_elapsed_ms" => due, "late_window_ms" => late}) do
    state
    |> cut(:elapsed, due)
    |> cut(:elapsed, due + late)
  end

  defp temporal(state, %{"due_ms" => due, "late_window_ms" => late}) do
    state
    |> relevant(true)
    |> cut(:utc_low, due)
    |> cut(:utc_high, due + late)
  end

  defp temporal(state, _), do: state

  defp edge(state, nil, _), do: state

  defp edge(state, edge, trigger) do
    state =
      state
      |> cut(:elapsed, edge["last_elapsed_ms"])
      |> cut(:elapsed, edge["cooldown_until_ms"])

    if edge["candidate_since_ms"] == nil,
      do: state,
      else: cut(state, :elapsed, edge["candidate_since_ms"] + trigger["debounce_ms"])
  end

  defp relevant(state, true), do: %{state | relevant: true}
  defp relevant(state, _), do: state

  defp axis(point, minimum, maximum), do: {point, minimum, maximum, minimum, maximum}
  defp utc_axis(nil, _), do: nil
  defp utc_axis(point, maximum), do: axis(point, -maximum, maximum)

  defp cut(state, _, nil), do: state
  defp cut(state, name, value), do: Map.update!(state, name, &nearest(&1, value))

  defp nearest(nil, _), do: nil

  defp nearest({point, minimum, maximum, lower, upper} = axis, cut) do
    cond do
      cut < minimum or cut > maximum -> axis
      cut <= point -> {point, minimum, maximum, max(lower, cut), upper}
      true -> {point, minimum, maximum, lower, min(upper, cut - 1)}
    end
  end

  defp interval({point, _, _, lower, upper}, forward),
    do: %{"min" => if(forward, do: point, else: lower), "max" => upper}

  defp utc_mode(%{relevant: false}, _), do: "ignored"
  defp utc_mode(_, %{"utc_low_ms" => nil}), do: "absent"
  defp utc_mode(_, _), do: "present"
  defp utc_interval(axis, "present"), do: interval(axis, false)
  defp utc_interval(_, _), do: nil

  defp check_utc(%{"utc_mode" => "ignored"}, _), do: :ok

  defp check_utc(cell, time) do
    mode = if time["utc_low_ms"] == nil, do: "absent", else: "present"

    with :ok <- equal(cell["utc_mode"], mode, "/cell/utc_mode"),
         :ok <-
           equal(cell["utc_generation"], ClockBasis.utc_generation(time), "/cell/utc_generation") do
      if mode == "absent" do
        :ok
      else
        with :ok <- inside(cell["utc_low"], time["utc_low_ms"], "/cell/utc_low"),
             do: inside(cell["utc_high"], time["utc_high_ms"], "/cell/utc_high")
      end
    end
  end

  defp equal(value, value, _), do: :ok
  defp equal(_, _, path), do: Error.refusal(:stale_decision_time, path)

  defp inside(%{"min" => low, "max" => high}, value, _) when low <= value and value <= high,
    do: :ok

  defp inside(_, _, path), do: Error.refusal(:stale_decision_time, path)
end
