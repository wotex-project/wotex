defmodule Wotex.Routines.Schedule do
  @moduledoc "Closed immutable calendar, UTC cadence and boot-scoped countdown definitions. Schedules grant no execution authority."

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

  defp schedule(_, _), do: Error.refusal(:unsupported_schedule)
end
