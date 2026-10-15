defmodule Wotex.Routines.Time do
  @moduledoc """
  Carries an explicit elapsed coordinate and optional UTC confidence interval.

  `new/2` validates a complete map or native value under
  `Wotex.Routines.Limits`, returning `{:ok, time}` or `{:error, error}` with a
  `Wotex.Routines.Error`. The five required fields are `"epoch"`,
  `"elapsed_ms"`, `"clock_generation"`, `"utc_low_ms"` and `"utc_high_ms"`.
  Epoch and generation are nonempty identities; elapsed milliseconds are
  nonnegative. UTC bounds are ordered signed integer milliseconds or both
  explicitly `nil`. All integers obey the selected magnitude bound.

  `to_map/2` revalidates before returning the complete data map. Neither operation
  reads a clock, infers a timezone or establishes the truth of supplied confidence.
  The consumer owns sampling, epoch replacement and clock qualification.

  `Wotex.Routines.Kernel.advance/7` uses this basis for elapsed deadlines and
  freshness. A UTC due window requires the entire supplied confidence interval
  to fit its half-open bounds. Absent UTC confidence is valid input, but cannot
  satisfy that check or a fact's required source-age check. Clock-generation or
  epoch replacement and elapsed regression expire unsent continuation of an
  ongoing run; they do not authorize repeating handed-off work.
  """

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
