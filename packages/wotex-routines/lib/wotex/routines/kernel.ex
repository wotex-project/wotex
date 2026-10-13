defmodule Wotex.Routines.Kernel do
  @moduledoc "Pure retained-run transitions and inert proposals. The consumer owns admission, clocks and effects."

  alias Wotex.Routines.{
    Compiler,
    Edge,
    Error,
    Event,
    Execution,
    ExecutionPrior,
    ExecutionTree,
    Limits,
    ObservationView,
    Profile,
    Receipt,
    Run,
    Snapshot,
    Time,
    Validation
  }

  @terminal ~w(partial completed refused failed unknown cancelled expired)
  @due ~w(schedule_id schedule_basis due_ms late_window_ms clock_generation time_zone_basis)
  @elapsed ~w(schedule_id schedule_basis due_elapsed_ms late_window_ms epoch clock_generation time_basis)

  @doc "Checks complete inputs and advances one original without performing or authorizing any effect."
  @spec advance(term(), term(), term(), term(), term(), Profile.t(), Limits.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def advance(program, event, snapshot, time, prior, profile, limits) do
    with {:ok, profile} <- Profile.new(profile),
         {:ok, limits} <- Limits.new(limits),
         {:ok, program} <- Compiler.to_map(program, profile, limits),
         {:ok, event} <- Event.to_map(event, limits),
         {:ok, snapshot} <- Snapshot.to_map(snapshot, program, profile, limits),
         {:ok, time} <- Time.to_map(time, limits),
         {:ok, prior} <- ExecutionPrior.new(prior, program, profile, limits),
         :ok <- correspondence(program, event, snapshot, prior),
         {:ok, edge} <- edge(program, event, snapshot, time, prior, profile, limits),
         {:ok, run, proposals, outcome} <-
           transition(program, event, snapshot, time, prior, edge, profile, limits) do
      result = %{
        "run" => run,
        "proposals" => proposals,
        "outcome" => outcome,
        "edge" => edge["edge"],
        "basis" => %{
          "program_digest" => program["ir_digest"],
          "source_digest" => program["source_digest"],
          "compiler_basis" => program["context"]["compiler_basis"],
          "event" => event,
          "snapshot" => snapshot,
          "time" => time
        }
      }

      with :ok <- checked_run(run, program, profile, limits),
           :ok <- Validation.bounded(result, limits) do
        {:ok, result}
      end
    end
  end

  defp checked_run(nil, _, _, _), do: :ok

  defp checked_run(run, program, profile, limits) do
    case Run.new(run, program, profile, limits) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp edge(program, %{"kind" => "fact"} = event, snapshot, time, prior, profile, limits),
    do: Edge.advance(program, event, snapshot, time, prior["edge"], profile, limits)

  defp edge(_, _, _, _, prior, _, _), do: {:ok, %{"edge" => prior["edge"], "eligible" => true}}

  defp correspondence(program, event, snapshot, prior) do
    cond do
      program["ir_digest"] != event["program_digest"] ->
        Error.refusal(:foreign_event)

      program["ir_digest"] not in snapshot["active_programs"] ->
        Error.refusal(:inactive_program)

      prior["original"] != nil and prior["original"]["original"] != event["original"] ->
        Error.refusal(:foreign_original)

      prior["original"] == nil and prior["busy"] != nil and
          prior["busy"]["original"] == event["original"] ->
        Error.refusal(:missing_original)

      true ->
        :ok
    end
  end

  defp transition(program, event, snapshot, time, prior, edge, profile, limits) do
    cond do
      prior["original"] != nil ->
        continue(prior["original"], program, event, snapshot, time, profile, limits)

      event["kind"] in ~w(admission handoff result cancel) ->
        Error.refusal(:missing_original)

      not edge["eligible"] ->
        {:ok, nil, [], "no-edge"}

      busy?(prior["busy"], event) ->
        {:ok, nil, [], "skipped-busy"}

      true ->
        begin(program, event, snapshot, time, profile, limits)
    end
  end

  defp busy?(nil, _), do: false

  defp busy?(busy, event),
    do: busy["status"] not in @terminal and busy["original"] != event["original"]

  defp begin(program, event, snapshot, time, profile, limits) do
    with :ok <- trigger(program["ir"]["trigger"], event),
         :ok <-
           Validation.integer(time["elapsed_ms"] + program["ir"]["run_ms"], limits, "/deadline_ms"),
         {:ok, steps} <- ExecutionTree.records(program, event["original"], limits) do
      run = %{
        "format" => "wotex.routines.run@1",
        "original" => event["original"],
        "program_digest" => program["ir_digest"],
        "source_digest" => program["source_digest"],
        "compiler_basis" => program["context"]["compiler_basis"],
        "epoch" => time["epoch"],
        "clock_generation" => time["clock_generation"],
        "start_ms" => time["elapsed_ms"],
        "last_ms" => time["elapsed_ms"],
        "deadline_ms" => time["elapsed_ms"] + program["ir"]["run_ms"],
        "status" => "running",
        "steps" => steps,
        "spent" => [],
        "window" => window(event),
        "reason" => nil
      }

      continue(run, program, event, snapshot, time, profile, limits)
    end
  end

  defp trigger(%{"kind" => "manual"}, %{"kind" => "manual"}), do: :ok

  defp trigger(%{"kind" => "edge", "binding" => binding}, %{"kind" => "fact", "binding" => binding}),
       do: :ok

  defp trigger(%{"kind" => "due", "schedule_id" => id, "schedule_basis" => basis}, %{
         "kind" => "due",
         "schedule_id" => id,
         "schedule_basis" => basis
       }),
       do: :ok

  defp trigger(%{"kind" => "countdown", "schedule_id" => id, "schedule_basis" => basis}, %{
         "kind" => "elapsed_due",
         "schedule_id" => id,
         "schedule_basis" => basis
       }),
       do: :ok

  defp trigger(_, _), do: Error.refusal(:trigger_mismatch)

  defp continue(run, program, event, snapshot, time, profile, limits) do
    with :ok <- repeat_trigger(run, program, event),
         {:ok, run} <- Receipt.apply(run, event, program, limits) do
      run = %{run | "last_ms" => max(run["last_ms"], time_coordinate(run, time))}
      reason = expiry(run, time)
      values = ObservationView.values(program, snapshot, time, limits)

      cond do
        event["kind"] == "cancel" ->
          run = Execution.halt(run, "cancelled", "cancelled")
          {:ok, run, [], run["status"]}

        reason != nil and run["status"] not in @terminal ->
          run = Execution.halt(run, "expired", reason)
          {:ok, run, [], run["status"]}

        true ->
          with {:ok, run, proposals} <-
                 Execution.advance(run, program, values, time, profile, limits) do
            {:ok, run, proposals, run["status"]}
          end
      end
    end
  end

  defp repeat_trigger(run, program, %{"kind" => kind} = event)
       when kind in ~w(manual due elapsed_due fact) do
    with :ok <- trigger(program["ir"]["trigger"], event) do
      if kind not in ~w(due elapsed_due) or window(event) == run["window"],
        do: :ok,
        else: Error.refusal(:stale_due_window)
    end
  end

  defp repeat_trigger(_, _, _), do: :ok

  defp time_coordinate(run, time),
    do: if(run["epoch"] == time["epoch"], do: time["elapsed_ms"], else: run["last_ms"])

  defp expiry(run, time) do
    cond do
      run["epoch"] != time["epoch"] or run["clock_generation"] != time["clock_generation"] ->
        "clock_changed"

      time["elapsed_ms"] < run["last_ms"] ->
        "clock_regressed"

      time["elapsed_ms"] >= run["deadline_ms"] ->
        "deadline_elapsed"

      not window_open?(run["window"], time) ->
        "window_closed"

      true ->
        nil
    end
  end

  defp window_open?(nil, _), do: true

  defp window_open?(%{"due_elapsed_ms" => due} = window, time) do
    window["epoch"] == time["epoch"] and window["clock_generation"] == time["clock_generation"] and
      time["elapsed_ms"] >= due and time["elapsed_ms"] < due + window["late_window_ms"]
  end

  defp window_open?(window, time) do
    low = time["utc_low_ms"]
    high = time["utc_high_ms"]

    is_integer(low) and is_integer(high) and window["clock_generation"] == time["clock_generation"] and
      low >= window["due_ms"] and high < window["due_ms"] + window["late_window_ms"]
  end

  defp window(%{"kind" => "due"} = event), do: Map.take(event, @due)
  defp window(%{"kind" => "elapsed_due"} = event), do: Map.take(event, @elapsed)
  defp window(_), do: nil
end
