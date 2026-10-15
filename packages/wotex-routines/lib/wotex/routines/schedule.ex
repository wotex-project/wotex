defmodule Wotex.Routines.Schedule do
  @moduledoc """
  Closed immutable definitions for UTC, elapsed and local-calendar schedules.

  Compute `semantic_digest/2` over the definition without its digest, put the result in
  `"definition_digest"`, then call `new/2` with explicit `Wotex.Routines.Limits`.
  Hashing alone does not validate the schedule. `new/2` checks the closed selected
  shape and exact digest; `to_map/2` repeats validation before projection.
  Successful operations return `{:ok, value}`; refusals contain a
  `Wotex.Routines.Error` in `{:error, error}`.

  Every definition has `"format"` equal to `"wotex.routines.schedule@1"`,
  `"kind"`, `"schedule_id"`, `"definition_digest"` and positive `"late_window_ms"`.
  Supported kinds add exactly these fields:

    * `"one_shot"`: `"due_ms"` (UTC) and `"time_basis"`.
    * `"interval"`: `"first_due_ms"`, positive `"period_ms"` and `"time_basis"`.
    * `"countdown"`: nonnegative `"due_elapsed_ms"`, `"epoch"`,
      `"clock_generation"` and `"time_basis"`, bound to one boot.
    * `"calendar"`: `"rule"` (RRULE, at most 4,096 bytes), offset-bearing
      `"dtstart"`, `"time_zone"`, `"time_zone_basis"` and `"producer_basis"`;
      enumerate through `Wotex.Routines.Calendar`.
    * `"civil"`: `"time"` (exact `HH:MM:SS`), `"weekdays"` (nonempty ascending
      unique ISO integers 1–7), `"time_zone"` (UTF-8, 1–256 bytes),
      `"time_zone_basis"`, `"producer_basis"`, `"gap_policy"` and `"fold_policy"`;
      enumerate through `Wotex.Routines.Civil` using an independent finite query.

  Digests use `sha256:` followed by 64 lowercase hex characters. UTC coordinates
  may be signed; elapsed coordinates are nonnegative. The selected Limits bound
  every input member.

  Civil gap policy is explicitly `"skip"` or `"reject"`; fold policy is `"first"`,
  `"second"`, `"both"` or `"reject"`. There are no civil policy defaults. A civil
  definition has no DTSTART, RRULE or ordinal. Calendar/civil construction does
  not resolve timezones or prove the optional producer operation is available.
  Use `Wotex.Routines.Temporal` for scalar UTC and elapsed calculation.

  The definition digest covers every member except itself, including policy,
  pattern, declared bases and late window. Changing those values changes the
  compiled trigger correspondence. A digest identifies data; it grants no
  producer authenticity, trusted clock, scheduling process or execution authority.
  Consumers own immutable database/code custody, current guards, persistence and
  effects.
  """

  alias Wotex.Routines.{Error, Limits, Validation}

  @common ~w(format kind schedule_id definition_digest late_window_ms)
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Validates the complete selected schedule shape and its canonical definition identity."
  @spec new(term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, limits) do
    with {:ok, data, limits} <- Validation.admit(input, limits, __MODULE__),
         :ok <- Validation.fields(data, @common ++ fields(data)),
         :ok <- Validation.choice(data["format"], ["wotex.routines.schedule@1"], "/format"),
         :ok <- Validation.text(data["schedule_id"], "/schedule_id"),
         :ok <- Validation.integer(data["late_window_ms"], limits, "/late_window_ms", 1),
         :ok <- Validation.digest(data["definition_digest"], "/definition_digest"),
         :ok <- schedule(data, limits),
         {:ok, digest} <- semantic_digest(data, limits) do
      if digest == data["definition_digest"],
        do: {:ok, %__MODULE__{data: data}},
        else: Error.refusal(:schedule_digest_mismatch)
    end
  end

  @doc "Hashes the bounded complete schedule projection without definition_digest; hashing does not admit it."
  @spec semantic_digest(term(), Limits.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def semantic_digest(input, limits) do
    with {:ok, data, limits} <- Validation.admit(input, limits, __MODULE__),
         true <- is_map(data) do
      Validation.hash(Map.delete(data, "definition_digest"), limits)
    else
      false -> Error.refusal(:invalid_type)
      error -> error
    end
  end

  @doc "Revalidates a schedule before projecting its complete data."
  @spec to_map(term(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(schedule, limits) do
    with {:ok, schedule} <- new(schedule, limits), do: {:ok, schedule.data}
  end

  defp fields(%{"kind" => "one_shot"}), do: ~w(due_ms time_basis)
  defp fields(%{"kind" => "interval"}), do: ~w(first_due_ms period_ms time_basis)
  defp fields(%{"kind" => "countdown"}), do: ~w(due_elapsed_ms epoch clock_generation time_basis)

  defp fields(%{"kind" => "calendar"}),
    do: ~w(rule dtstart time_zone time_zone_basis producer_basis)

  defp fields(%{"kind" => "civil"}),
    do: ~w(time weekdays time_zone time_zone_basis producer_basis gap_policy fold_policy)

  defp fields(_), do: []

  defp schedule(%{"kind" => "one_shot"} = data, limits) do
    with :ok <- Validation.integer(data["due_ms"], limits, "/due_ms"),
         :ok <- Validation.integer(data["due_ms"] + data["late_window_ms"], limits, "/window") do
      Validation.digest(data["time_basis"], "/time_basis")
    end
  end

  defp schedule(%{"kind" => "interval"} = data, limits) do
    with :ok <- Validation.integer(data["first_due_ms"], limits, "/first_due_ms"),
         :ok <- Validation.integer(data["period_ms"], limits, "/period_ms", 1) do
      Validation.digest(data["time_basis"], "/time_basis")
    end
  end

  defp schedule(%{"kind" => "countdown"} = data, limits) do
    with :ok <- Validation.integer(data["due_elapsed_ms"], limits, "/due_elapsed_ms", 0),
         :ok <-
           Validation.integer(data["due_elapsed_ms"] + data["late_window_ms"], limits, "/window"),
         :ok <- Validation.text(data["epoch"], "/epoch"),
         :ok <- Validation.text(data["clock_generation"], "/clock_generation") do
      Validation.digest(data["time_basis"], "/time_basis")
    end
  end

  defp schedule(%{"kind" => "calendar"} = data, _) do
    with :ok <- Validation.text(data["rule"], "/rule"),
         true <- byte_size(data["rule"]) <= 4096,
         {:ok, _} <- Validation.timestamp(data["dtstart"], "/dtstart"),
         :ok <- Validation.text(data["time_zone"], "/time_zone"),
         :ok <- Validation.digest(data["time_zone_basis"], "/time_zone_basis") do
      Validation.digest(data["producer_basis"], "/producer_basis")
    else
      false -> Error.refusal(:rule_bound)
      error -> error
    end
  end

  defp schedule(%{"kind" => "civil"} = data, _) do
    with true <- civil_time?(data["time"]),
         true <- weekdays?(data["weekdays"], 0, 0),
         :ok <- Validation.text(data["time_zone"], "/time_zone"),
         true <- byte_size(data["time_zone"]) <= 256,
         :ok <- Validation.digest(data["time_zone_basis"], "/time_zone_basis"),
         :ok <- Validation.digest(data["producer_basis"], "/producer_basis"),
         :ok <- Validation.choice(data["gap_policy"], ~w(skip reject), "/gap_policy") do
      Validation.choice(data["fold_policy"], ~w(first second both reject), "/fold_policy")
    else
      false -> Error.refusal(:out_of_domain)
      error -> error
    end
  end

  defp schedule(_, _), do: Error.refusal(:unsupported_schedule)

  defp civil_time?(value) when is_binary(value) and byte_size(value) == 8,
    do: match?({:ok, %Time{microsecond: {0, 0}}}, Time.from_iso8601(value))

  defp civil_time?(_), do: false

  defp weekdays?([], _, count), do: count > 0

  defp weekdays?([day | rest], previous, count) when day in 1..7 and day > previous and count < 7,
    do: weekdays?(rest, day, count + 1)

  defp weekdays?(_, _, _), do: false
end
