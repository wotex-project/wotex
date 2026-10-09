defmodule Wotex.Matter.Bridge.ClockProjection do
  @moduledoc """
  Conservatively projects a native bridge deadline onto a qualified BEAM clock.

  `new/5` takes one exchange: a BEAM sample before sending a probe, a BEAM
  sample after receiving its reply, and the native sample in that reply. All
  samples are whole milliseconds. The native sample must round down with less
  than one millisecond of error; BEAM sampling error must be less than one
  millisecond. The exchange belongs to the explicit 16-byte process generation.

  The caller must supply a qualified lower bound `{numerator, denominator}`
  on the BEAM/native elapsed-time rate, valid from the first BEAM sample through
  the native deadline. Both terms are positive, at most one million, and the
  ratio is at most one. Matching units, one measured exchange or a shared host
  does not establish this bound. This pure value does not qualify clocks,
  authenticate a probe, read time or open a Port.

  Projection covers at most 500 native milliseconds after the probe. It starts
  from the earlier BEAM sample, rounds the qualified remaining duration down,
  and subtracts one millisecond in each clock domain for sampling quantization.
  Transit and processing consume the original budget. A fresh probe is required
  for deadlines beyond the covered interval; an elapsed budget is refused.
  Exchanges longer than 500 BEAM milliseconds are also refused.

      iex> generation = :binary.copy(<<1>>, 16)
      iex> {:ok, projection} = Wotex.Matter.Bridge.ClockProjection.new(generation, -1000, -990, 100, {98, 100})
      iex> Wotex.Matter.Bridge.ClockProjection.deadline(projection, generation, 600, -980)
      {:ok, -512}
  """

  alias Wotex.Matter.Error

  @uint64 0xFFFFFFFFFFFFFFFF
  @int64_min -0x8000000000000000
  @int64_max 0x7FFFFFFFFFFFFFFF
  @enforce_keys [:generation, :beam_before_ms, :beam_after_ms, :native_ms, :minimum_rate]
  defstruct [:generation, :beam_before_ms, :beam_after_ms, :native_ms, :minimum_rate]

  @typedoc "An explicit exchange and caller-qualified lower rate bound."
  @type t :: %__MODULE__{
          generation: binary(),
          beam_before_ms: integer(),
          beam_after_ms: integer(),
          native_ms: non_neg_integer(),
          minimum_rate: {pos_integer(), pos_integer()}
        }

  @doc "Builds a generation-scoped exchange with an explicit qualified rate."
  @spec new(term(), term(), term(), term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def new(generation, before_ms, after_ms, native_ms, rate) do
    projection = %__MODULE__{
      generation: generation,
      beam_before_ms: before_ms,
      beam_after_ms: after_ms,
      native_ms: native_ms,
      minimum_rate: rate
    }

    if valid?(projection), do: {:ok, projection}, else: {:error, Error.new(:invalid_options)}
  end

  @doc "Returns an unexpired conservative deadline for the exact generation."
  @spec deadline(term(), term(), term(), term()) :: {:ok, integer()} | {:error, Error.t()}
  def deadline(%__MODULE__{} = projection, generation, native_deadline, now) do
    cond do
      not valid?(projection) or generation !== projection.generation or not beam_time?(now) or
        now < projection.beam_after_ms or not native_time?(native_deadline) ->
        {:error, Error.new(:invalid_transport_context)}

      native_deadline <= projection.native_ms ->
        {:error, Error.new(:deadline_exceeded)}

      native_deadline - projection.native_ms > 500 ->
        {:error, Error.new(:probe_required)}

      true ->
        project(projection, native_deadline, now)
    end
  end

  def deadline(_, _, _, _), do: {:error, Error.new(:invalid_transport_context)}

  defp project(projection, native_deadline, now) do
    {numerator, denominator} = projection.minimum_rate
    remaining = native_deadline - projection.native_ms - 1
    deadline = projection.beam_before_ms + div(remaining * numerator, denominator) - 1

    if beam_time?(deadline) and deadline > now,
      do: {:ok, deadline},
      else: {:error, Error.new(:deadline_exceeded)}
  end

  defp valid?(projection) do
    generation = Map.get(projection, :generation)
    before_ms = Map.get(projection, :beam_before_ms)
    after_ms = Map.get(projection, :beam_after_ms)

    is_binary(generation) and byte_size(generation) == 16 and
      beam_time?(before_ms) and beam_time?(after_ms) and after_ms >= before_ms and
      after_ms - before_ms <= 500 and native_time?(Map.get(projection, :native_ms)) and
      rate?(Map.get(projection, :minimum_rate))
  end

  defp rate?({numerator, denominator}),
    do:
      is_integer(numerator) and is_integer(denominator) and
        numerator in 1..1_000_000 and denominator in numerator..1_000_000

  defp rate?(_), do: false
  defp native_time?(value), do: is_integer(value) and value in 0..@uint64
  defp beam_time?(value), do: is_integer(value) and value in @int64_min..@int64_max
end
