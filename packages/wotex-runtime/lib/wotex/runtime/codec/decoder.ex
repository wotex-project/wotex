defmodule Wotex.Runtime.Codec.Decoder do
  @moduledoc """
  Pure trusted decoder of bounded bytes under a registered immutable contract.

  The callback receives only bytes, flat metadata and admitted non-secret
  configuration. It performs no I/O or state mutation. Trusted BEAM code is
  not a sandbox. Contract owners validate their own input and output schemas.
  """
  @type refusal :: :invalid_input | :unsupported_format | :unsupported_value | :output_limit
  @doc "Decodes deterministically or returns a fixed contract refusal."
  @callback decode(binary(), map(), map()) :: {:ok, map()} | {:error, refusal()}
end
