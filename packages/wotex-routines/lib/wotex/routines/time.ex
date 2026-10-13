defmodule Wotex.Routines.Time do
  @moduledoc "Explicit caller-owned elapsed coordinate and UTC confidence interval. No clock is read."

  alias Wotex.Routines.{Error, Limits, Validation}

  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Validates a complete time basis with paired UTC bounds or explicit absence."
  @spec new(term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, limits) do
    with {:ok, data, limits} <- Validation.admit(input, limits, __MODULE__),
         :ok <-
           Validation.fields(data, ~w(epoch elapsed_ms clock_generation utc_low_ms utc_high_ms)),
         :ok <- Validation.text(data["epoch"], "/epoch"),
         :ok <- Validation.text(data["clock_generation"], "/clock_generation"),
         :ok <- Validation.integer(data["elapsed_ms"], limits, "/elapsed_ms", 0),
         :ok <- utc(data, limits) do
      {:ok, %__MODULE__{data: data}}
    end
  end

  @doc "Revalidates time before projecting the complete coordinate."
  @spec to_map(term(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(time, limits) do
    with {:ok, time} <- new(time, limits), do: {:ok, time.data}
  end

  defp utc(%{"utc_low_ms" => nil, "utc_high_ms" => nil}, _), do: :ok

  defp utc(data, limits) do
    with :ok <- Validation.integer(data["utc_low_ms"], limits, "/utc_low_ms"),
         :ok <- Validation.integer(data["utc_high_ms"], limits, "/utc_high_ms") do
      if data["utc_low_ms"] <= data["utc_high_ms"],
        do: :ok,
        else: Error.refusal(:invalid_clock_interval, "/utc_high_ms")
    end
  end
end
