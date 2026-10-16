defmodule Wotex.Routines.Kernel do
  @moduledoc """
  Advances retained routine state and returns ordered, inert effect proposals.

  Call `Wotex.Routines.Kernel.advance/7` with a compiled
  `Wotex.Routines.Program`, a `Wotex.Routines.Event`, a complete
  `Wotex.Routines.Snapshot`, explicit `Wotex.Routines.Time`, prior state,
  `Wotex.Routines.Profile` and `Wotex.Routines.Limits`. Every input is
  revalidated before transition.
  Success is `{:ok, result}`; invalid inputs or correspondence failures return
  `{:error, error}` with a `Wotex.Routines.Error`.

  Prior state has exactly `"original"`, `"busy"` and `"edge"`. The first two
  contain complete retained run data or explicit `nil`; the last contains the
  retained reported-edge baseline or `nil`. The consumer retrieves the original's
  history and any busy run. Supplying `nil` does not prove an original is new.
  A different original while a run is nonterminal produces `"skipped-busy"`.

  To reevaluate an existing run, supply a `"resume"` event with that run's
  `"original"` and `"program_digest"`, the current snapshot/time, and the exact
  retained run in prior `"original"`. Missing original history returns
  `:missing_original`, including when prior `"busy"` contains that run. Resume
  creates no run, consumes no reported-edge sample and returns the unchanged
  retained edge. A live run applies current membership, conditions, selected
  paths, wait/delay progress and the original window/deadlines. A terminal run
  returns exactly its retained data with no proposals after input validation.

  Starting with Time@2 produces `"wotex.routines.run@2"` with its selected
  `"time_format"`; the original five-member Time starts Run@1. A retained run
  must continue under its original time grammar, including on resume. A
  grammar switch refuses `:clock_format_mismatch` before changing history.

  Time@2's `"epoch"`/`"clock_generation"` govern elapsed work independently of
  `"utc_generation"`. UTC correction or loss alone preserves elapsed waits,
  delays and countdowns. A live UTC due window retains its original UTC
  generation: replacement by a non-null generation yields `"clock_changed"`;
  absent confidence or a non-fitting interval yields `"window_closed"`.
  Elapsed-basis replacement, regression and deadlines retain their earlier
  expiry precedence. The complete checked Time remains in the transition basis.

  The result contains `"run"`, `"proposals"`, `"outcome"`, `"edge"` and
  `"basis"`. Run data is absent for `"no-edge"` and `"skipped-busy"` outcomes;
  the updated edge baseline still needs retention. Otherwise the returned run
  preserves step identities, receipts and spent admission references. Admission,
  handoff and result events advance distinct stages; a protocol response does
  not complete a step requiring a reported match.

  A `"satisfied"` event can complete an already proposed or reserved absolute
  Property write requiring `"reported_match"`. It needs the exact existing
  original, selected path, installed report contract and named current Fact.
  The Fact must pass the unchanged identity, source, quality, continuity,
  receipt/source-age and exact unit/domain checks, with its known typed value
  equal to the compiled input. Current root/invocation conditions must permit
  that path. Inactive or expired live runs follow ordinary cancellation/expiry
  before a fresh match is recorded. Other invalid matches refuse, and a fresh
  receipt on a terminal or handed-off step is `:out_of_order_receipt`.

  Success retains a `"matched"` satisfied receipt and progresses normal
  sequence/parallel ancestors. Newly reached later effects may emit proposals.
  Held admission and spent references remain unchanged; no admission, handoff
  or result-stage receipt is fabricated. An exact duplicate replays its first
  receipt even if the Fact has expired or disappeared. A terminal duplicate
  returns the exact run; a live duplicate still applies current expiry and
  conditions to later unsent work. A changed event at an occupied satisfied
  slot refuses `:conflicting_receipt`. Accepted satisfaction alone promotes
  Run@1 to Run@2 while preserving its Time@1 grammar and unrelated history.

  Retain the complete transition before acting on its proposals, and supply
  that state on the next call. Proposals describe newly reached unsent effects;
  previously proposed or reserved steps remain in the retained run and are not
  newly emitted proposals. The consumer owns complete active membership,
  durable originals, skipped events, atomic revalidation/admission and physical
  handoff. Cancellation or clock/deadline expiry stops unsent continuation
  without reversing handoffs or refunding spent roots. Recomputing a transition
  is not an instruction to repeat a physical effect. This module performs no
  I/O, clock reads or persistence.
  """

  alias Wotex.Routines.{
    ClockBasis,
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
    Satisfaction,
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
         :ok <- correspondence(program, event, snapshot, prior, time),
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
          "prior" => prior,
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

  defp correspondence(program, event, snapshot, prior, time) do
    with :ok <- correspondence(program, event, snapshot, prior) do
      matching_time(prior["original"], time)
    end
  end

  defp matching_time(nil, _), do: :ok

  defp matching_time(run, time) do
    if Map.get(run, "time_format", "wotex.routines.time@1") == ClockBasis.format(time),
      do: :ok,
      else: Error.refusal(:clock_format_mismatch)
  end

  defp correspondence(program, event, snapshot, prior) do
    cond do
      program["ir_digest"] != event["program_digest"] ->
        Error.refusal(:foreign_event)

      event["kind"] in ~w(resume satisfied) and prior["original"] == nil ->
        Error.refusal(:missing_original)

      program["ir_digest"] not in snapshot["active_programs"] and prior["original"] == nil ->
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

      event["kind"] in ~w(admission handoff result cancel resume satisfied) ->
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
    format =
      if ClockBasis.format(time) == "wotex.routines.time@2",
        do: "wotex.routines.run@2",
        else: "wotex.routines.run@1"

    with :ok <- trigger(program["ir"]["trigger"], event),
         :ok <-
           Validation.integer(time["elapsed_ms"] + program["ir"]["run_ms"], limits, "/deadline_ms"),
         {:ok, steps} <- ExecutionTree.records(program, event["original"], limits, format) do
      run = %{
        "format" => format,
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

      continue(ClockBasis.bind_format(run, time), program, event, snapshot, time, profile, limits)
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

  defp continue(%{"status" => status} = run, _, %{"kind" => "resume"}, _, _, _, _)
       when status in @terminal,
       do: {:ok, run, [], status}

  defp continue(run, program, %{"kind" => "satisfied"} = event, snapshot, time, profile, limits) do
    with {:ok, freshness} <- Satisfaction.classify(run, event, limits) do
      cond do
        freshness == :duplicate and run["status"] in @terminal ->
          {:ok, run, [], run["status"]}

        freshness == :duplicate ->
          continue_live(run, program, event, snapshot, time, profile, limits)

        run["status"] in @terminal ->
          Error.refusal(:out_of_order_receipt)

        program["ir_digest"] not in snapshot["active_programs"] or
            continuation_expiry(run, time) != nil ->
          continue_live(run, program, event, snapshot, time, profile, limits)

        true ->
          values = ObservationView.values(program, snapshot, time, limits)

          with {:ok, run} <-
                 Satisfaction.apply(run, event, program, snapshot, values, profile, limits) do
            continue_live(run, program, event, snapshot, time, profile, limits)
          end
      end
    end
  end

  defp continue(run, program, event, snapshot, time, profile, limits) do
    continue_live(run, program, event, snapshot, time, profile, limits)
  end

  defp continue_live(run, program, event, snapshot, time, profile, limits) do
    reason = continuation_expiry(run, time)

    with :ok <- repeat_trigger(run, program, event),
         {:ok, run} <- Receipt.apply(run, event, program, limits) do
      run = %{run | "last_ms" => max(run["last_ms"], time_coordinate(run, time))}
      values = ObservationView.values(program, snapshot, time, limits)

      cond do
        event["kind"] == "cancel" ->
          run = Execution.halt(run, "cancelled", "cancelled")
          {:ok, run, [], run["status"]}

        program["ir_digest"] not in snapshot["active_programs"] and run["status"] not in @terminal ->
          run = Execution.halt(run, "cancelled", "inactive_program")
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

  defp continuation_expiry(run, time),
    do: expiry(run, time) || if(Execution.expired_step?(run, time), do: "deadline_elapsed")

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

      true ->
        window_expiry(run["window"], time)
    end
  end

  defp window_expiry(%{"due_ms" => _, "clock_generation" => generation} = window, time) do
    if ClockBasis.format(time) == "wotex.routines.time@2" and
         ClockBasis.utc_generation(time) != nil and generation != ClockBasis.utc_generation(time),
       do: "clock_changed",
       else: closed_window(window, time)
  end

  defp window_expiry(window, time), do: closed_window(window, time)

  defp closed_window(window, time),
    do: if(window_open?(window, time), do: nil, else: "window_closed")

  defp window_open?(nil, _), do: true

  defp window_open?(%{"due_elapsed_ms" => due} = window, time) do
    window["epoch"] == time["epoch"] and window["clock_generation"] == time["clock_generation"] and
      time["elapsed_ms"] >= due and time["elapsed_ms"] < due + window["late_window_ms"]
  end

  defp window_open?(window, time) do
    low = time["utc_low_ms"]
    high = time["utc_high_ms"]

    is_integer(low) and is_integer(high) and
      window["clock_generation"] == ClockBasis.utc_generation(time) and
      low >= window["due_ms"] and high < window["due_ms"] + window["late_window_ms"]
  end

  defp window(%{"kind" => "due"} = event), do: Map.take(event, @due)
  defp window(%{"kind" => "elapsed_due"} = event), do: Map.take(event, @elapsed)
  defp window(_), do: nil
end
