defmodule Wotex.Nx do
  @moduledoc """
  Typed W3C Web of Things observation and numerical conversion boundary.

  Wotex Nx turns accepted Thing observations into schema-ordered, bounded Nx
  inputs and turns explicitly described numerical outputs into inert values.
  It supplies the contract seam between Wotex semantics and numerical code;
  consumers retain model, backend, scheduling, policy, state, and Action
  authority.

  Conversions are deterministic and clock-free. Loading the package starts no
  process, and decoding never dispatches a Thing Action.

  `Wotex.Nx.Encoder` owns observation admission and tensor construction;
  `Wotex.Nx.Decoder` owns the return path into typed result values. Schemas,
  units, quality codes, provenance, and output meanings remain explicit inputs
  at both boundaries.
  """

  @quality_codes %{good: 0, uncertain: 1, bad: 2, missing: 3}

  @doc """
  Returns the stable quality-code mapping used in encoded batch vectors.

  The mapping is public because model contracts and explanation tooling must
  bind each numeric code to the same quality meaning as the encoder.
  """
  @spec quality_codes() :: %{good: 0, uncertain: 1, bad: 2, missing: 3}
  def quality_codes, do: @quality_codes
end
