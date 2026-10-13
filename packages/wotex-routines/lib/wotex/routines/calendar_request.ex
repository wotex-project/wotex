defmodule Wotex.Routines.CalendarRequest do
  @moduledoc "Explicit calendar calculation input with a caller-selected database and native producer continuation."

  alias Wotex.Routines.{CalendarCursor, Error, Limits, Schedule, Validation}

  @enforce_keys [:schedule, :query, :database, :cursor]
  defstruct [:schedule, :query, :database, :cursor]

  @type t :: %__MODULE__{
          schedule: map(),
          query: map(),
          database: module() | map(),
          cursor: CalendarCursor.t() | nil
        }

  @doc "Checks a calendar schedule, canonical finite query, explicit database module and cursor envelope."
  @spec new(term(), term(), term(), term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(schedule, query, database, cursor, limits) do
    with {:ok, limits} <- Limits.new(limits),
         {:ok, schedule} <- Schedule.to_map(schedule, limits),
         true <- schedule["kind"] == "calendar",
         {:ok, query} <- query(query, limits),
         true <- database?(database, limits),
         :ok <- cursor(cursor, limits) do
      {:ok, %__MODULE__{schedule: schedule, query: query, database: database, cursor: cursor}}
    else
      false -> Error.refusal(:invalid_calendar_request)
      error -> error
    end
  end

  @doc "Revalidates the exact native request shape and every retained argument."
  @spec current(term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def current(%__MODULE__{} = request, limits) when map_size(request) == 5,
    do: new(request.schedule, request.query, request.database, request.cursor, limits)

  def current(_, _), do: Error.refusal(:invalid_calendar_request)

  defp database?(database, _) when is_atom(database), do: database != nil

  defp database?(%{__struct__: ExBooking.TimeZoneProvider, context: context} = provider, limits)
       when is_binary(context) do
    arguments = [provider]

    byte_size(context) <= limits.data["max_bytes"] and
      apply(ExBooking.TimeZoneProvider, :valid?, arguments)
  rescue
    _ -> false
  end

  defp database?(_, _), do: false

  defp query(input, limits) do
    with {:ok, data, limits} <- Validation.admit(input, limits, nil),
         :ok <- Validation.fields(data, ~w(from until limit work_limit)),
         {:ok, from} <- Validation.timestamp(data["from"], "/from"),
         {:ok, until} <- Validation.timestamp(data["until"], "/until"),
         {:ok, left, _} <- DateTime.from_iso8601(from),
         {:ok, right, _} <- DateTime.from_iso8601(until),
         :ok <- Validation.integer(data["limit"], limits, "/limit", 1),
         :ok <- Validation.integer(data["work_limit"], limits, "/work_limit", 1),
         true <-
           DateTime.compare(left, right) == :lt and data["limit"] <= 1024 and
             data["work_limit"] <= 100_000 do
      {:ok, %{data | "from" => from, "until" => until}}
    else
      false -> Error.refusal(:invalid_calendar_query)
      error -> error
    end
  end

  defp cursor(nil, _), do: :ok

  defp cursor(%CalendarCursor{} = cursor, limits) when map_size(cursor) == 4 do
    data = %{"basis_digest" => cursor.basis_digest, "clock_generation" => cursor.clock_generation}

    with true <- cursor.producer_cursor != nil,
         {:ok, _, _} <- Validation.admit(data, limits, nil),
         :ok <- Validation.digest(cursor.basis_digest, "/cursor/basis_digest") do
      Validation.text(cursor.clock_generation, "/cursor/clock_generation")
    else
      false -> Error.refusal(:invalid_calendar_cursor)
      error -> error
    end
  end

  defp cursor(_, _), do: Error.refusal(:invalid_calendar_cursor)
end
