defmodule Wotex.Routines.CivilRequest do
  @moduledoc """
  An explicit finite civil query joined to an immutable timezone database.

  Use `new/4` with a civil `Wotex.Routines.Schedule`, a closed query, the selected
  database and complete `Wotex.Routines.Limits`. It returns `{:ok, request}` or
  `{:error, error}` with a `Wotex.Routines.Error`. The native request retains
  exactly `:schedule`, `:query` and `:database`; `current/2` reconstructs these
  arguments instead of trusting a caller-built struct.

  The query has exactly the string keys `"first_date"`, `"days"`, `"from"` and
  `"until"`. The first date is an ISO `YYYY-MM-DD`; days is an integer 1–366 and its
  complete inclusive local span must fit years 0000–9999. Both UTC-window boundaries are
  offset-bearing ISO timestamps, normalized to UTC with fractional precision
  preserved, within the same year range and strictly increasing. The local span
  and the half-open UTC window are independent; neither supplies defaults for
  the other. Input JSON and provider context obey the selected Limits.

  The database is an explicit existing `Calendar.TimeZoneDatabase` module or a
  native immutable ExBooking.TimeZoneProvider value checked through its public
  producer API. Its context obeys both the producer's 1 MiB ceiling and the
  caller's byte limit. No string selects a module, and no application setting
  supplies a database.
  A database module name or provider context identifies supplied input, not the
  authenticity or immutability of installed code/data. Those obligations and
  callback runtime bounds remain consumer-owned.

  A request is inert: it starts no query, process or effect. Pass it to
  `Wotex.Routines.Civil.page/3` for bounded calculation. Constructing it does not
  establish producer capability, trusted time, global completeness or execution
  authority.
  """

  alias Wotex.Routines.{Error, Limits, Schedule, Validation}

  @enforce_keys [:schedule, :query, :database]
  defstruct [:schedule, :query, :database]

  @type t :: %__MODULE__{schedule: map(), query: map(), database: module() | map()}

  @doc """
  Checks the complete civil schedule, finite query and selected database.

  Query keys are `first_date` (ISO date), `days` (1–366), `from` and `until`
  (offset-bearing ISO timestamps). The complete local span and normalized UTC
  endpoints stay in years 0000–9999. Unknown fields, reversed horizons and
  invalid native providers refuse. Provider contexts also obey `limits.max_bytes`.
  """
  @spec new(term(), term(), term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(schedule, query, database, limits) do
    with {:ok, limits} <- Limits.new(limits),
         {:ok, schedule} <- Schedule.to_map(schedule, limits),
         true <- schedule["kind"] == "civil",
         {:ok, query} <- query(query, limits),
         true <- database?(database, limits) do
      {:ok, %__MODULE__{schedule: schedule, query: query, database: database}}
    else
      false -> Error.refusal(:invalid_civil_request)
      error -> error
    end
  end

  @doc "Reconstructs all retained arguments and rejects extra or missing native fields."
  @spec current(term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def current(%__MODULE__{schedule: schedule, query: query, database: database} = request, limits)
      when map_size(request) == 4,
      do: new(schedule, query, database, limits)

  def current(_, _), do: Error.refusal(:invalid_civil_request)

  defp query(input, limits) do
    with {:ok, data, limits} <- Validation.admit(input, limits, nil),
         :ok <- Validation.fields(data, ~w(first_date days from until)),
         {:ok, date} <- date(data["first_date"]),
         :ok <- Validation.integer(data["days"], limits, "/days", 1),
         true <- data["days"] <= 366 and Date.diff(~D[9999-12-31], date) >= data["days"] - 1,
         {:ok, from} <- timestamp(data["from"]),
         {:ok, until} <- timestamp(data["until"]),
         true <- DateTime.compare(from, until) == :lt do
      {:ok, %{data | "from" => DateTime.to_iso8601(from), "until" => DateTime.to_iso8601(until)}}
    else
      false -> Error.refusal(:invalid_civil_query)
      error -> error
    end
  end

  defp date(value) when is_binary(value) and byte_size(value) == 10 do
    case Date.from_iso8601(value) do
      {:ok, %{year: year} = date} when year in 0..9999 -> {:ok, date}
      _ -> Error.refusal(:invalid_civil_query)
    end
  end

  defp date(_), do: Error.refusal(:invalid_civil_query)

  defp timestamp(<<a, b, c, d, ?-, _::binary>> = value)
       when a in ?0..?9 and b in ?0..?9 and c in ?0..?9 and d in ?0..?9 do
    case DateTime.from_iso8601(value) do
      {:ok, %{year: year} = datetime, _} when year in 0..9999 -> {:ok, datetime}
      _ -> Error.refusal(:invalid_civil_query)
    end
  end

  defp timestamp(_), do: Error.refusal(:invalid_civil_query)

  defp database?(database, _) when is_atom(database),
    do:
      Code.ensure_loaded?(database) and
        function_exported?(database, :time_zone_periods_from_wall_datetime, 2) and
        function_exported?(database, :time_zone_period_from_utc_iso_days, 2)

  defp database?(%{__struct__: ExBooking.TimeZoneProvider, context: context} = provider, limits)
       when is_binary(context) do
    arguments = [provider]

    byte_size(context) <= limits.data["max_bytes"] and
      apply(ExBooking.TimeZoneProvider, :valid?, arguments)
  rescue
    _ -> false
  end

  defp database?(_, _), do: false
end
