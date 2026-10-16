defmodule Wotex.Routines.Civil do
  @moduledoc """
  Adapts finite civil calendar queries into original routine points.

  Construct a `Wotex.Routines.CivilRequest`, then call
  `Wotex.Routines.Civil.page/3` with explicit
  `Wotex.Routines.Time` and `Wotex.Routines.Limits`. Success is `{:ok, page}` with
  a `Wotex.Routines.CivilPage`; failures are `{:error, error}` containing a
  `Wotex.Routines.Error`. The adapter calls only ExBooking's public civil
  operation. If that operation is absent, the error code is `:civil_unavailable`;
  its total-work limit uses `:civil_work_bound`, other refusals use
  `:civil_refused`, and producer exceptions become
  `:producer_contract_error`. There is no availability or recurrence fallback.
  Ordinary scalar temporal calculation does not require this optional producer.

  A successful page is complete only for its explicit local-date span and
  half-open UTC window. Gap/fold policies run in the producer before filtering,
  including rejection outside that window; points are never snapped, clipped or
  replaced by another fold. The maximum is 732 strictly UTC-ordered points,
  not a pagination instruction. Lower output Limits refuse the whole result
  rather than truncate it. No DTSTART, global ordinal, continuation or global
  exhaustion flag is invented. Submillisecond instants refuse rather than round.
  The producer's civil offset profile permits each component within
  `-93_599..93_599` seconds and their total within `-89_999..93_599` seconds;
  this adapter does not pass results through narrower timezone helpers.
  Complete ambiguities retain the existing `"first_fold"`/`"second_fold"`
  resolution strings; local positions 3–732 project as `["fold", index]`.
  Positions belong to the complete resolution of one nominal label and are never
  renumbered after filtering: a surviving third alternative keeps `["fold", 3]`.
  They are not recurrence ordinals; only the `"both"` policy admits positions 3–732.

  The producer's 732-localization work budget covers the whole query and counts
  every candidate before policy selection or UTC filtering. `:civil_work_bound`
  refuses the entire page, without partial output, continuation, retry or automatic
  query splitting. Consumers may explicitly split the local-date span while
  retaining the policies and original identities, and own the combined ordering.
  Original-occurrence and scalar schedules use the separate
  `Wotex.Routines.Calendar` and `Wotex.Routines.Temporal` adapters.

  Each original hashes the schedule digest, original coordinate/resolution and
  declared bases together with the database basis. A module database is identified
  by its name; an immutable provider adds a SHA-256 digest of its exact context.
  Context bytes are not projected. Query bounds/span and clock generation are
  excluded, so overlapping queries and fresh clock projections preserve the same
  original. These identities do not authenticate callback code or database data;
  the consumer owns immutable custody and callback work/runtime bounds.

  `Wotex.Routines.Civil.to_map/2` regenerates the page from retained inputs
  and requires exact equality before returning an occurrences-only map.
  `Wotex.Routines.Civil.event/6` also requires an exact member, matching current
  time grammar/UTC generation and a compiled due trigger's schedule identity
  and basis, then binds the program digest to a checked `Wotex.Routines.Event`.

  The native page retains its complete checked Time. With Time@2, due
  descriptors use `"utc_generation"`; elapsed-generation changes alone do not
  stale that UTC projection. Absent Time@2 UTC confidence refuses
  `:missing_utc_basis` before database localization or enumeration. The original
  five-member Time retains its single-generation behavior and permits inert
  calculation without UTC confidence. Neither a page, descriptor nor checked
  Event supplies current clock trust, atomic admission, durable no-repeat
  history or effect authority; those remain consumer responsibilities.
  """

  alias Wotex.Routines.{
    CivilPage,
    CivilRequest,
    ClockBasis,
    Compiler,
    Error,
    Event,
    Limits,
    Profile,
    Time,
    Validation
  }

  @naive_keys Enum.sort(Map.keys(struct(NaiveDateTime)))
  @utc_keys Enum.sort(Map.keys(struct(DateTime)))

  @doc """
  Returns the complete finite civil result or a payload-free refusal.

  At most 732 original points are accepted, with strict UTC order and the
  caller's complete output Limits. No partial page or continuation is returned.
  The selected producer may refuse unavailable; no alternate calculation runs.
  """
  @spec page(term(), term(), Limits.t()) :: {:ok, CivilPage.t()} | {:error, Error.t()}
  def page(request, time, limits) do
    with {:ok, limits} <- Limits.new(limits),
         {:ok, time} <- Time.to_map(time, limits),
         :ok <- ClockBasis.require_utc(time),
         {:ok, request} <- CivilRequest.current(request, limits),
         {:ok, database_basis} <- database_basis(request.database, limits),
         {:ok, raw} <- enumerate(request),
         {:ok, occurrences} <- project(raw, request, time, database_basis, limits),
         :ok <- Validation.bounded(%{"occurrences" => occurrences}, limits) do
      {:ok, %CivilPage{request: request, time: time, occurrences: occurrences}}
    end
  end

  @doc "Regenerates a native page before returning the closed occurrences-only JSON projection."
  @spec to_map(term(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(page, limits) do
    with {:ok, page} <- current(page, limits), do: {:ok, wire(page)}
  end

  @doc """
  Binds an exact regenerated member to a matching compiled due trigger.

  The current Time must retain the page's clock generation. A changed query
  can calculate the same original again, but a forged page, stale projection or
  different compiled schedule cannot create a checked Event.
  """
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

  defp current(%CivilPage{request: request, time: time, occurrences: _} = value, limits)
       when map_size(value) == 4 do
    with {:ok, limits} <- Limits.new(limits),
         :ok <- Validation.bounded(wire(value), limits),
         {:ok, rebuilt} <- page(request, time, limits) do
      if rebuilt == value, do: {:ok, rebuilt}, else: Error.refusal(:stale_civil_page)
    end
  end

  defp current(_, _), do: Error.refusal(:invalid_civil_page)
  defp wire(value), do: %{"occurrences" => value.occurrences}

  defp database_basis(database, limits) when is_atom(database),
    do: Validation.hash(Atom.to_string(database), limits)

  defp database_basis(%{module: module, context: context}, limits) do
    Validation.hash(
      %{
        "kind" => "ExBooking.TimeZoneProvider",
        "module" => Atom.to_string(module),
        "context_digest" => "sha256:" <> Base.encode16(:crypto.hash(:sha256, context), case: :lower)
      },
      limits
    )
  end

  defp enumerate(request) do
    {:ok, time} = Elixir.Time.from_iso8601(request.schedule["time"])
    {:ok, date} = Date.from_iso8601(request.query["first_date"])
    {:ok, from, _} = DateTime.from_iso8601(request.query["from"])
    {:ok, until, _} = DateTime.from_iso8601(request.query["until"])

    opts = [
      days: request.query["days"],
      weekdays: request.schedule["weekdays"],
      from: from,
      until: until,
      time_zone: request.schedule["time_zone"],
      time_zone_database: request.database,
      gap_policy: gap_policy(request.schedule["gap_policy"]),
      fold_policy: fold_policy(request.schedule["fold_policy"])
    ]

    arguments = [time, date, opts]

    case apply(ExBooking, :civil_occurrences, arguments) do
      {:ok, values} -> {:ok, values}
      {:error, {:limit, :civil_occurrences, :work}} -> Error.refusal(:civil_work_bound)
      {:error, _} -> Error.refusal(:civil_refused)
      _ -> Error.refusal(:producer_contract_error)
    end
  rescue
    error in UndefinedFunctionError ->
      if error.module == ExBooking and error.function == :civil_occurrences and error.arity == 3,
        do: Error.refusal(:civil_unavailable),
        else: Error.refusal(:producer_contract_error)

    _ ->
      Error.refusal(:producer_contract_error)
  end

  defp gap_policy("skip"), do: :skip
  defp gap_policy("reject"), do: :reject
  defp fold_policy("first"), do: :first
  defp fold_policy("second"), do: :second
  defp fold_policy("both"), do: :both
  defp fold_policy("reject"), do: :reject

  defp project(raw, request, time, database_basis, limits) do
    with :ok <- list_bound(raw, 0) do
      Enum.reduce_while(raw, {:ok, []}, fn value, {:ok, points} ->
        case occurrence(value, request, time, database_basis, limits) do
          {:ok, point} -> {:cont, {:ok, [point | points]}}
          error -> {:halt, error}
        end
      end)
      |> ordered()
    end
  end

  defp list_bound([], _), do: :ok
  defp list_bound([_ | rest], count) when count < 732, do: list_bound(rest, count + 1)
  defp list_bound(_, _), do: Error.refusal(:producer_contract_error)

  defp occurrence(%{__struct__: ExBooking.CivilOccurrence} = raw, request, time, basis, limits)
       when map_size(raw) == 4 do
    with :ok <- coordinates(raw, request) do
      projected(raw, request.schedule, time, basis, limits)
    end
  rescue
    _ -> Error.refusal(:producer_contract_error)
  end

  defp occurrence(_, _, _, _, _), do: Error.refusal(:producer_contract_error)

  defp coordinates(raw, request) do
    if native?(raw.nominal, NaiveDateTime, @naive_keys) and
         native?(raw.starts_at, DateTime, @utc_keys) and
         raw.starts_at.time_zone == "Etc/UTC" and raw.starts_at.utc_offset == 0 and
         raw.starts_at.std_offset == 0 and text?(raw.starts_at.zone_abbr) do
      selected_coordinate(raw, request)
    else
      Error.refusal(:producer_contract_error)
    end
  end

  defp native?(value, module, keys) do
    is_struct(value, module) and map_size(value) == length(keys) and
      Enum.sort(Map.keys(value)) == keys and value.calendar == Calendar.ISO and
      value.year in 0..9999 and
      match?({:ok, _}, Date.new(value.year, value.month, value.day)) and
      match?({:ok, _}, Elixir.Time.new(value.hour, value.minute, value.second, value.microsecond))
  end

  defp text?(value), do: is_binary(value) and byte_size(value) <= 256 and String.valid?(value)

  defp selected_coordinate(raw, request) do
    {:ok, first} = Date.from_iso8601(request.query["first_date"])
    date = NaiveDateTime.to_date(raw.nominal)
    {:ok, from, _} = DateTime.from_iso8601(request.query["from"])
    {:ok, until, _} = DateTime.from_iso8601(request.query["until"])

    cond do
      rem(elem(raw.starts_at.microsecond, 0), 1000) != 0 ->
        Error.refusal(:unsupported_temporal_precision)

      raw.nominal.microsecond != {0, 0} or raw.starts_at.microsecond != {0, 0} ->
        Error.refusal(:producer_contract_error)

      Date.diff(date, first) not in 0..(request.query["days"] - 1) or
        Date.day_of_week(date) not in request.schedule["weekdays"] or
        Elixir.Time.to_iso8601(NaiveDateTime.to_time(raw.nominal)) != request.schedule["time"] or
        DateTime.compare(raw.starts_at, from) == :lt or
        DateTime.compare(raw.starts_at, until) != :lt or
          not selected_resolution?(raw.resolution, request.schedule["fold_policy"]) ->
        Error.refusal(:producer_contract_error)

      true ->
        :ok
    end
  end

  defp selected_resolution?(:unique, _), do: true
  defp selected_resolution?(:first_fold, policy), do: policy in ["first", "both"]
  defp selected_resolution?(:second_fold, policy), do: policy in ["second", "both"]
  defp selected_resolution?({:fold, index}, "both") when index in 3..732, do: true
  defp selected_resolution?(_, _), do: false

  defp projected(raw, schedule, time, database_basis, limits) do
    due = DateTime.to_unix(raw.starts_at, :millisecond)

    coordinate = %{
      "due_ms" => due,
      "nominal" => NaiveDateTime.to_iso8601(raw.nominal),
      "starts_at" => DateTime.to_iso8601(raw.starts_at),
      "resolution" => resolution_wire(raw.resolution),
      "schedule_digest" => schedule["definition_digest"],
      "time_zone_basis" => schedule["time_zone_basis"],
      "producer_basis" => schedule["producer_basis"],
      "database_basis" => database_basis
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

  defp resolution_wire({:fold, index}), do: ["fold", index]
  defp resolution_wire(value), do: Atom.to_string(value)

  defp ordered({:ok, points}) do
    points = Enum.reverse(points)

    increasing? =
      points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.all?(fn [a, b] -> a["due_ms"] < b["due_ms"] end)

    if increasing? and fold_positions?(points, %{}),
      do: {:ok, points},
      else: Error.refusal(:producer_contract_error)
  end

  defp ordered(error), do: error

  defp fold_positions?([], _), do: true

  defp fold_positions?([point | rest], seen) do
    nominal = point["nominal"]
    position = fold_position(point["resolution"])
    previous = Map.get(seen, nominal)

    (is_nil(previous) or
       (is_integer(previous) and is_integer(position) and previous < position)) and
      fold_positions?(rest, Map.put(seen, nominal, position))
  end

  defp fold_position("unique"), do: :unique
  defp fold_position("first_fold"), do: 1
  defp fold_position("second_fold"), do: 2
  defp fold_position(["fold", index]), do: index

  defp matches(program, schedule) do
    trigger = program["ir"]["trigger"]

    if trigger["kind"] == "due" and trigger["schedule_id"] == schedule["schedule_id"] and
         trigger["schedule_basis"] == schedule["definition_digest"],
       do: :ok,
       else: Error.refusal(:schedule_program_mismatch)
  end
end
