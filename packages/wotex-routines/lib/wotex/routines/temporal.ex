defmodule Wotex.Routines.Temporal do
  @moduledoc "Bounded scalar schedule pages and explicit program binding. Calculation neither reads a clock nor starts a timer."

  alias Wotex.Routines.{Compiler, Error, Event, Limits, Profile, Schedule, Time, Validation}

  @doc "Enumerates original UTC or elapsed coordinates in a finite horizon using closed-form cadence indices."
  @spec page(term(), term(), term(), term(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def page(schedule, query, time, cursor, limits) do
    with {:ok, schedule} <- Schedule.to_map(schedule, limits),
         {:ok, query, limits} <- Validation.admit(query, limits, nil),
         {:ok, time} <- Time.to_map(time, limits),
         :ok <- query(query, schedule, limits),
         :ok <- time_basis(schedule, time),
         {:ok, basis} <- basis(schedule, query, time, limits),
         {first, last} <- indices(schedule, query),
         {:ok, ordinal} <- cursor(cursor, basis, first, last, limits),
         {:ok, occurrences} <- candidates(schedule, ordinal, last, query["limit"], time, limits) do
      next = ordinal + length(occurrences)
      cursor = if next <= last, do: Map.put(basis, "next_ordinal", next), else: nil
      result = %{"occurrences" => occurrences, "next_cursor" => cursor}
      with :ok <- Validation.bounded(result, limits), do: {:ok, result}
    end
  end

  @doc "Regenerates the candidate and matches the current compiled schedule basis before returning a complete Event."
  @spec event(term(), term(), term(), term(), Profile.t(), Limits.t()) ::
          {:ok, Event.t()} | {:error, Error.t()}
  def event(schedule, occurrence, program, time, profile, limits) do
    with {:ok, schedule} <- Schedule.to_map(schedule, limits),
         {:ok, occurrence, limits} <- Validation.admit(occurrence, limits, nil),
         :ok <- Validation.fields(occurrence, ~w(original ordinal due_ms event)),
         :ok <- Validation.integer(occurrence["ordinal"], limits, "/ordinal", 1),
         {:ok, program} <- Compiler.to_map(program, profile, limits),
         {:ok, time} <- Time.to_map(time, limits),
         :ok <- time_basis(schedule, time),
         {:ok, expected} <- candidate(schedule, occurrence["ordinal"], time, limits),
         true <- occurrence == expected,
         :ok <- matches(program, schedule) do
      Event.new(Map.put(occurrence["event"], "program_digest", program["ir_digest"]), limits)
    else
      false -> Error.refusal(:stale_temporal_projection)
      error -> error
    end
  end

  defp query(data, schedule, limits) do
    minimum = if schedule["kind"] == "countdown", do: 0, else: nil

    with :ok <- Validation.fields(data, ~w(from_ms until_ms limit)),
         :ok <- Validation.integer(data["from_ms"], limits, "/from_ms", minimum),
         :ok <- Validation.integer(data["until_ms"], limits, "/until_ms", minimum),
         :ok <- Validation.integer(data["limit"], limits, "/limit", 1),
         true <- data["limit"] <= 1024 and data["from_ms"] < data["until_ms"] do
      Validation.choice(schedule["kind"], ~w(one_shot interval countdown), "/kind")
    else
      false -> Error.refusal(:invalid_temporal_query)
      error -> error
    end
  end

  defp time_basis(%{"kind" => "countdown"} = schedule, time) do
    if schedule["epoch"] == time["epoch"] and
         schedule["clock_generation"] == time["clock_generation"],
       do: :ok,
       else: Error.refusal(:changed_time_basis)
  end

  defp time_basis(_, _), do: :ok

  defp basis(schedule, query, time, limits) do
    projection = %{
      "horizon" => Map.take(query, ~w(from_ms until_ms)),
      "clock_generation" => time["clock_generation"],
      "epoch" => if(schedule["kind"] == "countdown", do: time["epoch"], else: nil)
    }

    with {:ok, digest} <- Validation.hash(projection, limits) do
      {:ok,
       %{
         "format" => "wotex.routines.temporal.cursor@1",
         "schedule_digest" => schedule["definition_digest"],
         "query_digest" => digest
       }}
    end
  end

  defp indices(%{"kind" => "interval", "first_due_ms" => start, "period_ms" => period}, query) do
    first = max(0, ceil_div(query["from_ms"] - start, period)) + 1
    last = Integer.floor_div(query["until_ms"] - 1 - start, period) + 1
    {first, last}
  end

  defp indices(schedule, query) do
    due = due(schedule, 1)
    if due >= query["from_ms"] and due < query["until_ms"], do: {1, 1}, else: {1, 0}
  end

  defp ceil_div(value, divisor), do: -Integer.floor_div(-value, divisor)

  defp cursor(nil, _, first, _, limits) do
    with :ok <- Validation.integer(first, limits, "/next_ordinal", 1), do: {:ok, first}
  end

  defp cursor(input, basis, first, last, limits) do
    with {:ok, cursor, _} <- Validation.admit(input, limits, nil),
         :ok <- Validation.fields(cursor, ~w(format schedule_digest query_digest next_ordinal)),
         true <- Map.delete(cursor, "next_ordinal") == basis,
         :ok <- Validation.integer(cursor["next_ordinal"], limits, "/next_ordinal", 1),
         true <- cursor["next_ordinal"] >= first and cursor["next_ordinal"] <= last do
      {:ok, cursor["next_ordinal"]}
    else
      false -> Error.refusal(:stale_temporal_cursor)
      error -> error
    end
  end

  defp candidates(schedule, first, last, limit, time, limits) do
    count = min(limit, max(0, last - first + 1))

    if count == 0 do
      {:ok, []}
    else
      Enum.reduce_while(first..(first + count - 1), {:ok, []}, fn ordinal, {:ok, occurrences} ->
        case candidate(schedule, ordinal, time, limits) do
          {:ok, occurrence} -> {:cont, {:ok, [occurrence | occurrences]}}
          error -> {:halt, error}
        end
      end)
      |> ordered()
    end
  end

  defp ordered({:ok, occurrences}), do: {:ok, Enum.reverse(occurrences)}
  defp ordered(error), do: error

  defp candidate(schedule, ordinal, time, limits) do
    due = due(schedule, ordinal)

    with :ok <- valid_ordinal(schedule, ordinal),
         :ok <- Validation.integer(due, limits, "/due_ms"),
         :ok <- Validation.integer(due + schedule["late_window_ms"], limits, "/window"),
         {:ok, original} <-
           Validation.hash(
             %{
               "schedule_digest" => schedule["definition_digest"],
               "ordinal" => ordinal,
               "due_ms" => due
             },
             limits
           ) do
      descriptor = %{
        "original" => original,
        "schedule_id" => schedule["schedule_id"],
        "schedule_basis" => schedule["definition_digest"],
        "late_window_ms" => schedule["late_window_ms"],
        "clock_generation" => time["clock_generation"]
      }

      descriptor = descriptor(schedule, due, descriptor)
      {:ok, %{"original" => original, "ordinal" => ordinal, "due_ms" => due, "event" => descriptor}}
    end
  end

  defp valid_ordinal(%{"kind" => kind}, ordinal)
       when kind in ~w(one_shot countdown) and ordinal != 1,
       do: Error.refusal(:invalid_ordinal)

  defp valid_ordinal(%{"kind" => kind}, _) when kind in ~w(one_shot countdown interval), do: :ok
  defp valid_ordinal(_, _), do: Error.refusal(:unsupported_schedule)

  defp descriptor(%{"kind" => "countdown"} = schedule, due, descriptor),
    do:
      Map.merge(descriptor, %{
        "kind" => "elapsed_due",
        "due_elapsed_ms" => due,
        "epoch" => schedule["epoch"],
        "time_basis" => schedule["time_basis"]
      })

  defp descriptor(schedule, due, descriptor),
    do:
      Map.merge(descriptor, %{
        "kind" => "due",
        "due_ms" => due,
        "time_zone_basis" => schedule["time_basis"]
      })

  defp due(%{"kind" => "interval"} = schedule, ordinal),
    do: schedule["first_due_ms"] + (ordinal - 1) * schedule["period_ms"]

  defp due(%{"kind" => "countdown"} = schedule, _), do: schedule["due_elapsed_ms"]
  defp due(schedule, _), do: schedule["due_ms"]

  defp matches(program, schedule) do
    trigger = program["ir"]["trigger"]
    kind = if schedule["kind"] == "countdown", do: "countdown", else: "due"

    if trigger["kind"] == kind and trigger["schedule_id"] == schedule["schedule_id"] and
         trigger["schedule_basis"] == schedule["definition_digest"],
       do: :ok,
       else: Error.refusal(:schedule_program_mismatch)
  end
end
