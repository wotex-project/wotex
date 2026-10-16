defmodule Wotex.Routines.Time do
  @moduledoc """
  Explicit elapsed time and optional UTC confidence with a retained clock grammar.

  `Wotex.Routines.Time.new/2` validates a complete string-keyed map or native
  value under `Wotex.Routines.Limits`. Success is `{:ok, time}`; refusals are
  `{:error, error}` with a `Wotex.Routines.Error`.
  `Wotex.Routines.Time.to_map/2` repeats validation and preserves the complete
  selected representation.

  The original five-member grammar contains `"epoch"`, `"elapsed_ms"`,
  `"clock_generation"`, `"utc_low_ms"` and `"utc_high_ms"`. It has no
  `"format"` member and uses one generation for elapsed and UTC checks. The
  distinct seven-member grammar adds `"format" => "wotex.routines.time@2"`
  and `"utc_generation"`. Its `"clock_generation"` identifies the elapsed
  clock; `"utc_generation"` independently identifies qualified UTC confidence.

  Epoch and elapsed generation are nonempty identities; elapsed milliseconds
  are nonnegative. UTC bounds are ordered signed integer milliseconds or both
  explicitly `nil`. In the seven-member grammar, integer UTC bounds require a
  nonempty UTC generation and absent bounds require a `nil` UTC generation.
  All coordinates obey the selected integer magnitude bound. Missing, mixed or
  additional members refuse rather than selecting a different grammar.

  `Wotex.Routines.Kernel.advance/7` uses the elapsed basis for waits, delays,
  run/step deadlines and countdown windows. Under the seven-member grammar,
  UTC correction or loss alone does not replace that elapsed basis. A live UTC
  due window separately requires its original UTC generation and the entire
  current confidence interval within its half-open bounds. Replacement of a
  non-null UTC generation expires that window with `"clock_changed"`; absent
  confidence or a non-fitting interval yields `"window_closed"`. Required
  source-UTC age checks also need the current confidence interval.

  The consumer owns sampling, clock qualification, generation replacement and
  durable original history. Construction reads no clock, infers no timezone
  and establishes no confidence in the supplied coordinates. Clock changes do
  not authorize repeating handed-off work.
  """

  alias Wotex.Routines.{Error, Limits, Validation}

  @fields ~w(epoch elapsed_ms clock_generation utc_low_ms utc_high_ms)
  @enforce_keys [:data]
  defstruct [:data]
  @type t :: %__MODULE__{data: map()}

  @doc "Validates a complete time basis with paired UTC bounds or explicit absence."
  @spec new(term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, limits) do
    with {:ok, data, limits} <- Validation.admit(input, limits, __MODULE__),
         :ok <- fields(data),
         :ok <- Validation.text(data["epoch"], "/epoch"),
         :ok <- Validation.text(data["clock_generation"], "/clock_generation"),
         :ok <- Validation.integer(data["elapsed_ms"], limits, "/elapsed_ms", 0),
         :ok <- utc(data, limits),
         :ok <- utc_generation(data) do
      {:ok, %__MODULE__{data: data}}
    end
  end

  @doc "Revalidates time before projecting the complete coordinate."
  @spec to_map(term(), Limits.t()) :: {:ok, map()} | {:error, Error.t()}
  def to_map(time, limits) do
    with {:ok, time} <- new(time, limits), do: {:ok, time.data}
  end

  defp fields(%{"format" => "wotex.routines.time@2"} = data),
    do: Validation.fields(data, @fields ++ ~w(format utc_generation))

  defp fields(data), do: Validation.fields(data, @fields)

  defp utc_generation(%{
         "format" => "wotex.routines.time@2",
         "utc_low_ms" => nil,
         "utc_generation" => nil
       }),
       do: :ok

  defp utc_generation(%{"format" => "wotex.routines.time@2", "utc_low_ms" => nil}),
    do: Error.refusal(:invalid_clock_interval, "/utc_generation")

  defp utc_generation(%{"format" => "wotex.routines.time@2"} = data),
    do: Validation.text(data["utc_generation"], "/utc_generation")

  defp utc_generation(_), do: :ok

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
