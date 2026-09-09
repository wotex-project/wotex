defmodule Wotex.Nx.UnitConverter do
  @moduledoc """
  Consumer-supplied port for explicit unit conversion.

  Wotex Nx never guesses conversion rules or depends on a unit library. When
  an observation unit differs from the accepted feature unit, the encoder calls
  this port with the value, source unit, target unit, exact DataSchema, and
  consumer configuration. The returned value is validated again before tensor
  construction.

  Implementations return `{:ok, value}` or `{:error, reason}`. The encoder
  translates error tuples to `:unit_conversion_failed` and validates successful
  values against the feature's DataSchema, shape and finite-value policy. The
  callback has no implicit deadline or exception isolation. It is never called
  when source and target units already match.
  """

  alias Wotex.DataSchema

  @doc """
  Converts a value between two explicitly named units.

  Return `{:ok, value}` for a converted DataSchema-compatible value or
  `{:error, reason}` when the conversion is unavailable. Do not perform Thing
  Actions or mutate canonical state from this callback.
  """
  @callback convert(term(), String.t(), String.t(), DataSchema.t(), term()) ::
              {:ok, term()} | {:error, term()}
end
