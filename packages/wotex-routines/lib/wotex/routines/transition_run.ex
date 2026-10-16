defmodule Wotex.Routines.TransitionRun do
  @moduledoc false

  alias Wotex.Routines.{
    ClockBasis,
    ExecutionTree,
    TransitionChecks,
    TransitionReceipts,
    TransitionTree
  }

  @stopped ~w(partial completed refused failed unknown cancelled expired)
  @terminal ~w(completed refused failed unknown cancelled)
  @due ~w(schedule_id schedule_basis due_ms late_window_ms clock_generation time_zone_basis)
  @elapsed ~w(schedule_id schedule_basis due_elapsed_ms late_window_ms epoch clock_generation time_basis)

  @doc false
  @spec verify(map(), boolean()) :: :ok | {:error, Wotex.Routines.Error.t()}
  def verify(%{before: nil} = c, eligible) do
    cond do
      not eligible ->
        empty_result(c, "no-edge")

      busy?(c.prior["busy"]) ->
        empty_result(c, "skipped-busy")

      true ->
        with :ok <- trigger(c.program["ir"]["trigger"], c.event),
             :ok <- TransitionChecks.condition(is_map(c.result["run"]), "/run") do
          relation(c, :none)
        end
    end
  end

  def verify(c, _) do
    with :ok <- TransitionChecks.condition(is_map(c.result["run"]), "/run"),
         :ok <- repeated(c),
         {:ok, satisfaction} <- satisfaction(c) do
      relation(c, satisfaction)
    end
  end

  defp empty_result(c, outcome) do
    with :ok <- TransitionChecks.equal(c.result["run"], nil, "/run"),
         :ok <- TransitionChecks.equal(c.result["proposals"], [], "/proposals") do
      TransitionChecks.equal(c.result["outcome"], outcome, "/outcome")
    end
  end

  defp relation(c, satisfaction) do
    run = c.result["run"]
    mode = phase(c, run, satisfaction)

    with :ok <- header(c, run, satisfaction, mode),
         :ok <- TransitionChecks.equal(c.result["outcome"], run["status"], "/outcome") do
      if mode == :same do
        with :ok <- TransitionChecks.equal(run, c.before, "/run"),
             do: TransitionChecks.equal(c.result["proposals"], [], "/proposals")
      else
        with {:ok, statuses} <-
               TransitionReceipts.verify(c.program, c.before, run, c.event, satisfaction, c.limits),
             :ok <- root(c, run, mode) do
          TransitionTree.verify(c, run, statuses, tree_mode(mode))
        end
      end
    end
  end

  defp satisfaction(%{event: %{"kind" => "satisfied"}} = c) do
    with {:ok, kind} <- TransitionReceipts.satisfaction(c.before, c.event, c.limits) do
      cond do
        kind == :duplicate ->
          {:ok, :duplicate}

        c.before["status"] in @stopped ->
          TransitionChecks.refuse("/event/path")

        not active?(c) or expiry(c.before, c.time, c.before["steps"]) != nil ->
          {:ok, :ignored}

        true ->
          with :ok <- matched(c), do: {:ok, :apply}
      end
    end
  end

  defp satisfaction(_), do: {:ok, :none}

  defp matched(c) do
    node =
      Enum.find(ExecutionTree.nodes(c.program["ir"]["steps"]), &(&1["path"] == c.event["path"]))

    basis = if node, do: ExecutionTree.basis(c.program, node)
    fact = if node, do: c.snapshot["facts"][node["binding"]]

    TransitionChecks.condition(
      node != nil and node["kind"] == "effect" and node["completion"] == "reported_match" and
        basis["affordance"]["type"] == "property" and
        basis["affordance"]["operation"] == "writeproperty" and
        c.event["report_contract"] == node["evidence_contract"] and
        TransitionTree.eligible?(c.program, c.before, c.values, c.event["path"]) and
        is_map(fact) and fact["id"] == c.event["fact_id"] and
        c.values[node["binding"]] === {:known, node["input"]},
      "/event"
    )
  end

  defp phase(%{before: %{"status" => status}, event: %{"kind" => "resume"}}, _, _)
       when status in @stopped, do: :same

  defp phase(%{before: %{"status" => status}}, _, :duplicate) when status in @stopped, do: :same
  defp phase(%{event: %{"kind" => "cancel"}}, _, _), do: {:halt, "cancelled", "cancelled"}

  defp phase(c, run, _) do
    status = if c.before, do: c.before["status"], else: "running"
    initial = c.before || run
    records = if c.before, do: c.before["steps"], else: []
    reason = expiry(initial, c.time, records)

    cond do
      not active?(c) and status not in @stopped -> {:halt, "cancelled", "inactive_program"}
      reason != nil and status not in @stopped -> {:halt, "expired", reason}
      status in @stopped -> :stopped
      true -> :execute
    end
  end

  defp header(%{before: nil} = c, run, _, _) do
    format =
      if ClockBasis.format(c.time) == "wotex.routines.time@2",
        do: "wotex.routines.run@2",
        else: "wotex.routines.run@1"

    required = %{
      "format" => format,
      "original" => c.event["original"],
      "program_digest" => c.program["ir_digest"],
      "source_digest" => c.program["source_digest"],
      "compiler_basis" => c.program["context"]["compiler_basis"],
      "epoch" => c.time["epoch"],
      "clock_generation" => c.time["clock_generation"],
      "start_ms" => c.time["elapsed_ms"],
      "last_ms" => c.time["elapsed_ms"],
      "deadline_ms" => c.time["elapsed_ms"] + c.program["ir"]["run_ms"],
      "window" => window(c.event)
    }

    required =
      if format == "wotex.routines.run@2",
        do: Map.put(required, "time_format", ClockBasis.format(c.time)),
        else: required

    TransitionChecks.equal(Map.drop(run, ~w(status reason steps spent)), required, "/run")
  end

  defp header(c, run, satisfaction, mode) do
    old = Map.drop(c.before, ~w(status reason steps spent last_ms))

    old =
      if satisfaction == :apply and c.before["format"] == "wotex.routines.run@1",
        do:
          Map.merge(old, %{
            "format" => "wotex.routines.run@2",
            "time_format" => "wotex.routines.time@1"
          }),
        else: old

    last =
      if mode == :same or c.before["epoch"] != c.time["epoch"],
        do: c.before["last_ms"],
        else: max(c.before["last_ms"], c.time["elapsed_ms"])

    TransitionChecks.equal(
      Map.drop(run, ~w(status reason steps spent)),
      Map.put(old, "last_ms", last),
      "/run"
    )
  end

  defp root(_, run, {:halt, status, reason}),
    do: TransitionChecks.fields(run, %{"status" => status, "reason" => reason}, "/run")

  defp root(c, run, :stopped),
    do: TransitionChecks.fields(run, Map.take(c.before, ~w(status reason)), "/run")

  defp root(_, _, :execute), do: :ok
  defp tree_mode({:halt, _, _}), do: :halt
  defp tree_mode(mode), do: mode

  defp expiry(run, time, records) do
    cond do
      run["epoch"] != time["epoch"] or run["clock_generation"] != time["clock_generation"] ->
        "clock_changed"

      time["elapsed_ms"] < run["last_ms"] ->
        "clock_regressed"

      time["elapsed_ms"] >= run["deadline_ms"] ->
        "deadline_elapsed"

      window_reason(run["window"], time) != nil ->
        window_reason(run["window"], time)

      Enum.any?(records, fn r ->
        r["kind"] in ~w(effect invoke) and r["status"] not in @terminal and
          is_integer(r["deadline_ms"]) and time["elapsed_ms"] >= r["deadline_ms"]
      end) ->
        "deadline_elapsed"

      true ->
        nil
    end
  end

  defp window_reason(nil, _), do: nil

  defp window_reason(%{"due_elapsed_ms" => due} = w, t) do
    if w["epoch"] == t["epoch"] and w["clock_generation"] == t["clock_generation"] and
         t["elapsed_ms"] >= due and t["elapsed_ms"] < due + w["late_window_ms"],
       do: nil,
       else: "window_closed"
  end

  defp window_reason(w, t) do
    generation = ClockBasis.utc_generation(t)

    cond do
      ClockBasis.format(t) == "wotex.routines.time@2" and generation != nil and
          generation != w["clock_generation"] ->
        "clock_changed"

      generation == w["clock_generation"] and is_integer(t["utc_low_ms"]) and
        is_integer(t["utc_high_ms"]) and t["utc_low_ms"] >= w["due_ms"] and
          t["utc_high_ms"] < w["due_ms"] + w["late_window_ms"] ->
        nil

      true ->
        "window_closed"
    end
  end

  defp repeated(%{before: before, event: %{"kind" => kind} = event} = c)
       when kind in ~w(manual due elapsed_due fact) do
    with :ok <- trigger(c.program["ir"]["trigger"], event) do
      TransitionChecks.condition(
        kind not in ~w(due elapsed_due) or window(event) == before["window"],
        "/event"
      )
    end
  end

  defp repeated(_), do: :ok
  defp active?(c), do: c.program["ir_digest"] in c.snapshot["active_programs"]
  defp busy?(nil), do: false
  defp busy?(run), do: run["status"] not in @stopped
  defp trigger(%{"kind" => "manual"}, %{"kind" => "manual"}), do: :ok

  defp trigger(%{"kind" => "edge", "binding" => name}, %{"kind" => "fact", "binding" => name}),
    do: :ok

  defp trigger(%{"kind" => kind, "schedule_id" => id, "schedule_basis" => basis}, %{
         "kind" => event,
         "schedule_id" => id,
         "schedule_basis" => basis
       })
       when (kind == "due" and event == "due") or (kind == "countdown" and event == "elapsed_due"),
       do: :ok

  defp trigger(_, _), do: TransitionChecks.refuse("/event/kind")
  defp window(%{"kind" => "due"} = event), do: Map.take(event, @due)
  defp window(%{"kind" => "elapsed_due"} = event), do: Map.take(event, @elapsed)
  defp window(_), do: nil
end
