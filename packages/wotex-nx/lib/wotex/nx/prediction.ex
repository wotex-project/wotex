defmodule Wotex.Nx.Prediction do
  @moduledoc """
  An inert prediction associated with a Property or Event affordance.

  `produced_at` and `target_at` are caller-supplied integer time coordinates;
  the library does not read a clock or interpret their unit. A prediction is
  advisory data until the consumer validates and admits it.

  `Wotex.Nx.Decoder` constructs this value only after an output tensor satisfies
  its `Wotex.Nx.OutputSchema`. The value preserves the caller-supplied result
  identity, Thing and affordance identity, decoded value, optional unit, and
  metadata associated with that output contract.

  The struct records what a numerical process predicted, not what a Thing
  reported or what later occurred. Consumers remain responsible for checking
  freshness, provenance, model revision, current Thing state, and any policy
  that governs use of the prediction.
  """

  @typedoc "A timestamped numerical prediction that has no canonical-state authority."
  @opaque t :: %__MODULE__{
            id: String.t(),
            thing_id: String.t(),
            affordance_type: :property | :event,
            affordance_name: String.t(),
            value: term(),
            produced_at: integer(),
            target_at: integer(),
            unit: String.t() | nil,
            metadata: map()
          }

  @enforce_keys [
    :id,
    :thing_id,
    :affordance_type,
    :affordance_name,
    :value,
    :produced_at,
    :target_at,
    :unit,
    :metadata
  ]
  defstruct @enforce_keys

  @doc "Returns the prediction fields as a plain map; a read-only view, not an admission boundary."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value), do: Map.from_struct(value)
end
