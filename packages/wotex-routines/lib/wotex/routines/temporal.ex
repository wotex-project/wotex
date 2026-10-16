defmodule Wotex.Routines.Temporal do
  @moduledoc """
  Enumerates bounded scalar schedule pages and binds exact original events.

  `Wotex.Routines.Temporal.page/5` takes a checked scalar
  `Wotex.Routines.Schedule`, a string-keyed `"from_ms"`/`"until_ms"`/`"limit"`
  query, explicit `Wotex.Routines.Time`, a returned cursor or `nil`, and
  `Wotex.Routines.Limits`. One-shot, interval and countdown schedules use a
  half-open finite horizon and a page limit of 1 through 1,024. Success is
  `{:ok, result}` with `"occurrences"` and `"next_cursor"`; failures return
  `{:error, error}` with a `Wotex.Routines.Error`. The complete page and cursor
  must fit the supplied limits; a bound failure returns no partial result.

  Each occurrence retains its original identity, ordinal, due coordinate and
  inert event descriptor. A Time@2 occurrence additionally carries
  `"time_format" => "wotex.routines.time@2"`. Originals bind schedule and due
  coordinates independently of the query or clock projection. Reuse a cursor
  only with its original schedule, horizon, time grammar and relevant clock
  basis; a mismatch refuses `:stale_temporal_cursor`.

  UTC schedules use Time@2's `"utc_generation"` for descriptors and cursor
  binding. Absent Time@2 UTC confidence refuses `:missing_utc_basis` before
  enumeration. Countdown schedules use only elapsed epoch/generation and may
  operate without UTC. The original five-member Time retains its existing
  single-generation behavior, including inert UTC calculation without confidence.

  `Wotex.Routines.Temporal.event/6` takes the schedule, an exact occurrence,
  compiled program, current Time, Profile and Limits. It regenerates the
  occurrence and checks the compiled trigger, selected time grammar and
  relevant generation before returning `{:ok, event}` with a
  `Wotex.Routines.Event`. A stale projection is refused, never silently rebased.

  Calculation reads no clock and starts no timer or effect. The consumer owns
  clock trust, immutable schedule bases, cursor custody, durable no-repeat
  originals and atomic execution admission.
  """

  alias Wotex.Routines.{
    ClockBasis,
    Compiler,
    Error,
    Event,
    Limits,
    Profile,
    Schedule,
    Time,
    Validation
  }

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
         :ok <- occurrence_fields(occurrence),
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

  defp occurrence_fields(%{"time_format" => "wotex.routines.time@2"} = occurrence),
    do: Validation.fields(occurrence, ~w(original ordinal due_ms event time_format))

  defp occurrence_fields(occurrence),
    do: Validation.fields(occurrence, ~w(original ordinal due_ms event))

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

  defp time_basis(_, time), do: ClockBasis.require_utc(time)

  defp generation(%{"kind" => "countdown"}, time), do: time["clock_generation"]
  defp generation(_, time), do: ClockBasis.utc_generation(time)

  defp basis(schedule, query, time, limits) do
    projection = %{
      "horizon" => Map.take(query, ~w(from_ms until_ms)),
      "clock_generation" => generation(schedule, time),
      "epoch" => if(schedule["kind"] == "countdown", do: time["epoch"], else: nil)
    }

    with {:ok, digest} <- Validation.hash(ClockBasis.bind_format(projection, time), limits) do
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
        "clock_generation" => generation(schedule, time)
      }

      descriptor = descriptor(schedule, due, descriptor)

      occurrence = %{
        "original" => original,
        "ordinal" => ordinal,
        "due_ms" => due,
        "event" => descriptor
      }

      {:ok, ClockBasis.bind_format(occurrence, time)}
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
