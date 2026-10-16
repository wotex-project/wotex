defmodule Wotex.Routines.Calendar do
  @moduledoc """
  Adapts an optional original-occurrence producer into bounded routine pages.

  Construct a request with `Wotex.Routines.CalendarRequest.new/5`, explicitly
  selecting the calendar schedule, finite UTC query, immutable database and
  native continuation or `nil`. `Wotex.Routines.Calendar.page/3` takes that
  request, `Wotex.Routines.Time` and `Wotex.Routines.Limits`. It returns
  `{:ok, page}` with a `Wotex.Routines.CalendarPage`, or `{:error, error}` with
  a `Wotex.Routines.Error`. It calls ExBooking's public original-occurrence
  operation; an absent operation refuses `:recurrence_unavailable`. Work-bound
  exhaustion refuses `:recurrence_work_bound`, other producer refusals use
  `:recurrence_refused`, and malformed producer results or exceptions use
  `:producer_contract_error`.

  Requests select 1 through 1,024 results and at most 100,000 producer work
  units in a half-open UTC horizon. Output limits cover the complete result.
  Returned originals retain their schedule, original coordinate/ordinal,
  resolution and declared bases. No availability interval supplies a trigger.
  Submillisecond instants refuse rather than round.

  With Time@2, UTC descriptors and the native cursor use `"utc_generation"`;
  cursor correspondence also binds the selected time grammar. Absent Time@2
  UTC confidence refuses `:missing_utc_basis` before database localization or
  enumeration. The original five-member Time keeps its single-generation
  behavior and permits inert calculation without UTC confidence. A page retains
  its complete checked Time; changing only the elapsed generation does not
  stale a Time@2 UTC projection.

  `Wotex.Routines.Calendar.to_map/2` regenerates the native page and returns
  `{:ok, data}` containing only `"occurrences"` and `"has_more"`. The native
  cursor has no wire codec. `Wotex.Routines.Calendar.event/6` regenerates the
  page, requires an exact member, matching time grammar/UTC generation and
  matching compiled schedule, then returns a checked `Wotex.Routines.Event`.
  A changed cursor or projection refuses instead of retrying on a new basis.

  The consumer owns database and callback custody/work bounds, trusted clock
  sampling, original ledgers and atomic execution admission. A page or Event
  reads no ambient clock and supplies no physical handoff or effect authority.
  """

  alias Wotex.Routines.{
    CalendarCursor,
    CalendarPage,
    CalendarRequest,
    ClockBasis,
    Compiler,
    Error,
    Event,
    Limits,
    Profile,
    Time,
    Validation
  }

  @doc "Calls the public original-occurrence facade with explicit finite bounds, database and continuation."
  @spec page(term(), term(), Limits.t()) :: {:ok, CalendarPage.t()} | {:error, Error.t()}
  def page(request, time, limits) do
    with {:ok, limits} <- Limits.new(limits),
         {:ok, time} <- Time.to_map(time, limits),
         :ok <- ClockBasis.require_utc(time),
         {:ok, request} <- CalendarRequest.current(request, limits),
         {:ok, digest} <- basis(request, time, limits),
         {:ok, cursor} <- cursor(request.cursor, digest, time),
         {:ok, start} <- start(request),
         {:ok, from, _} <- DateTime.from_iso8601(request.query["from"]),
         {:ok, until, _} <- DateTime.from_iso8601(request.query["until"]),
         {:ok, raw} <- enumerate(request, start, from, until, cursor),
         {:ok, occurrences} <- project(raw, request, time, limits),
         {:ok, next_cursor} <- next_cursor(raw, digest, time) do
      result = %CalendarPage{
        request: request,
        time: time,
        occurrences: occurrences,
        next_cursor: next_cursor
      }

      with :ok <- Validation.bounded(wire(result), limits), do: {:ok, result}
    end
  end

  @doc "Regenerates complete retained input before projecting occurrences and has_more; opaque cursors have no wire codec."
  @spec to_map(term(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(page, limits) do
    with {:ok, page} <- current(page, limits), do: {:ok, wire(page)}
  end

  @doc "Regenerates the page and matches an exact occurrence, current clock projection and compiled schedule basis."
  @spec event(term(), term(), term(), term(), Profile.t(), Limits.t()) ::
          {:ok, Event.t()} | {:error, Error.t()}
  def event(page, occurrence, program, time, profile, limits) do
    with {:ok, page} <- current(page, limits),
         {:ok, occurrence, _} <- Validation.admit(occurrence, limits, nil),
         {:ok, program} <- Compiler.to_map(program, profile, limits),
         {:ok, time} <- Time.to_map(time, limits),
         true <-
           occurrence in page.occurrences and
             ClockBasis.utc_projection(time) == ClockBasis.utc_projection(page.time),
         :ok <- matches(program, page.request.schedule) do
      Event.new(Map.put(occurrence["event"], "program_digest", program["ir_digest"]), limits)
    else
      false -> Error.refusal(:stale_temporal_projection)
      error -> error
    end
  end

  defp current(%CalendarPage{} = page, limits) when map_size(page) == 5 do
    with :ok <- Validation.bounded(wire(page), limits),
         {:ok, rebuilt} <- page(page.request, page.time, limits) do
      if rebuilt == page, do: {:ok, rebuilt}, else: Error.refusal(:stale_calendar_page)
    end
  end

  defp current(_, _), do: Error.refusal(:invalid_calendar_page)
  defp wire(page), do: %{"occurrences" => page.occurrences, "has_more" => page.next_cursor != nil}

  defp basis(request, time, limits) do
    Validation.hash(
      ClockBasis.bind_format(
        %{
          "schedule_digest" => request.schedule["definition_digest"],
          "horizon" => Map.take(request.query, ~w(from until)),
          "database" => database_basis(request.database)
        },
        time
      ),
      limits
    )
  end

  defp database_basis(database) when is_atom(database), do: Atom.to_string(database)

  defp database_basis(%{module: module, context: context}) do
    %{
      "provider" => "ExBooking.TimeZoneProvider",
      "module" => Atom.to_string(module),
      "context_digest" => "sha256:" <> Base.encode16(:crypto.hash(:sha256, context), case: :lower)
    }
  end

  defp cursor(nil, _, _), do: {:ok, nil}

  defp cursor(cursor, digest, time) do
    if cursor.basis_digest == digest and cursor.clock_generation == ClockBasis.utc_generation(time),
      do: {:ok, cursor.producer_cursor},
      else: Error.refusal(:stale_calendar_cursor)
  end

  defp start(request) do
    with {:ok, utc, supplied_offset} <- DateTime.from_iso8601(request.schedule["dtstart"]),
         {:ok, local} <- localize(utc, request.schedule["time_zone"], request.database),
         true <- local.utc_offset + local.std_offset == supplied_offset do
      {:ok, local}
    else
      _ -> Error.refusal(:invalid_calendar_start)
    end
  rescue
    _ -> Error.refusal(:invalid_calendar_start)
  end

  defp localize(utc, zone, database) when is_atom(database),
    do: DateTime.shift_zone(utc, zone, database)

  defp localize(utc, zone, provider) do
    arguments = [utc, zone, provider]
    apply(ExBooking.TimeZoneProvider, :shift_zone, arguments)
  end

  defp enumerate(request, start, from, until, cursor) do
    options = [
      from: from,
      until: until,
      limit: request.query["limit"],
      work_limit: request.query["work_limit"],
      cursor: cursor,
      time_zone_database: request.database,
      time_zone_basis: request.schedule["time_zone_basis"]
    ]

    arguments = [request.schedule["rule"], start, options]
    producer_result(apply(ExBooking, :occurrences, arguments))
  rescue
    error in UndefinedFunctionError ->
      if error.module == ExBooking and error.function == :occurrences and error.arity == 3,
        do: Error.refusal(:recurrence_unavailable),
        else: Error.refusal(:producer_contract_error)

    _ ->
      Error.refusal(:producer_contract_error)
  end

  defp producer_result({:ok, %{__struct__: ExBooking.OccurrencePage} = page})
       when map_size(page) == 3,
       do: {:ok, page}

  defp producer_result({:error, {:limit, :occurrences, :work}}),
    do: Error.refusal(:recurrence_work_bound)

  defp producer_result({:error, {:stale, :occurrences, :cursor_basis}}),
    do: Error.refusal(:stale_calendar_cursor)

  defp producer_result({:error, _}), do: Error.refusal(:recurrence_refused)
  defp producer_result(_), do: Error.refusal(:producer_contract_error)

  defp project(raw, request, time, limits) do
    if is_list(raw.occurrences) and length(raw.occurrences) <= request.query["limit"] do
      Enum.reduce_while(raw.occurrences, {:ok, []}, fn value, {:ok, values} ->
        case occurrence(value, request.schedule, time, limits) do
          {:ok, value} -> {:cont, {:ok, [value | values]}}
          error -> {:halt, error}
        end
      end)
      |> ordered(request.query)
    else
      Error.refusal(:producer_contract_error)
    end
  end

  defp ordered({:ok, values}, query) do
    values = Enum.reverse(values)
    {:ok, from, _} = DateTime.from_iso8601(query["from"])
    {:ok, until, _} = DateTime.from_iso8601(query["until"])
    bounds = {DateTime.to_unix(from, :microsecond), DateTime.to_unix(until, :microsecond)}
    if ordered?(values, bounds), do: {:ok, values}, else: Error.refusal(:producer_contract_error)
  end

  defp ordered(error, _), do: error

  defp ordered?(values, {from, until}) do
    instants = Enum.map(values, &(&1["due_ms"] * 1000))
    ordinals = Enum.map(values, & &1["ordinal"])

    Enum.all?(instants, &(&1 >= from and &1 < until)) and
      increasing?(instants) and increasing?(ordinals)
  end

  defp increasing?(values) do
    values
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [left, right] -> left < right end)
  end

  defp occurrence(%{__struct__: ExBooking.Occurrence} = raw, schedule, time, limits)
       when map_size(raw) == 5 do
    with :ok <- coordinates(raw),
         :ok <- Validation.integer(raw.ordinal, limits, "/ordinal", 1),
         :ok <-
           Validation.choice(raw.resolution, [:unique, :first_fold, :second_fold], "/resolution") do
      projected(raw, schedule, time, limits)
    else
      error -> error
    end
  rescue
    _ -> Error.refusal(:producer_contract_error)
  end

  defp occurrence(_, _, _, _), do: Error.refusal(:producer_contract_error)

  defp coordinates(raw) do
    valid =
      is_struct(raw.nominal, NaiveDateTime) and raw.nominal.calendar == Calendar.ISO and
        is_struct(raw.starts_at, DateTime) and raw.starts_at.calendar == Calendar.ISO and
        raw.starts_at.time_zone == "Etc/UTC"

    cond do
      not valid ->
        Error.refusal(:producer_contract_error)

      rem(elem(raw.starts_at.microsecond, 0), 1000) != 0 ->
        Error.refusal(:unsupported_temporal_precision)

      true ->
        :ok
    end
  end

  defp projected(raw, schedule, time, limits) do
    due = DateTime.to_unix(raw.starts_at, :millisecond)

    coordinate = %{
      "ordinal" => raw.ordinal,
      "due_ms" => due,
      "nominal" => NaiveDateTime.to_iso8601(raw.nominal),
      "starts_at" => DateTime.to_iso8601(raw.starts_at),
      "resolution" => Atom.to_string(raw.resolution),
      "schedule_digest" => schedule["definition_digest"],
      "time_zone_basis" => schedule["time_zone_basis"],
      "producer_basis" => schedule["producer_basis"]
    }

    with :ok <- Validation.integer(due, limits, "/due_ms"),
         :ok <- Validation.integer(due + schedule["late_window_ms"], limits, "/window"),
         {:ok, original} <- Validation.hash(coordinate, limits) do
      descriptor = %{
        "kind" => "due",
        "original" => original,
        "schedule_id" => schedule["schedule_id"],
        "schedule_basis" => schedule["definition_digest"],
        "due_ms" => due,
        "late_window_ms" => schedule["late_window_ms"],
        "clock_generation" => ClockBasis.utc_generation(time),
        "time_zone_basis" => schedule["time_zone_basis"]
      }

      {:ok, Map.merge(coordinate, %{"original" => original, "event" => descriptor})}
    end
  end

  defp next_cursor(%{next_cursor: nil}, _, _), do: {:ok, nil}

  defp next_cursor(%{next_cursor: %{__struct__: ExBooking.OccurrenceCursor} = cursor}, digest, time)
       when map_size(cursor) == 4 do
    {:ok,
     %CalendarCursor{
       basis_digest: digest,
       clock_generation: ClockBasis.utc_generation(time),
       producer_cursor: cursor
     }}
  end

  defp next_cursor(_, _, _), do: Error.refusal(:producer_contract_error)

  defp matches(program, schedule) do
    trigger = program["ir"]["trigger"]

    if trigger["kind"] == "due" and trigger["schedule_id"] == schedule["schedule_id"] and
         trigger["schedule_basis"] == schedule["definition_digest"],
       do: :ok,
       else: Error.refusal(:schedule_program_mismatch)
  end
end
