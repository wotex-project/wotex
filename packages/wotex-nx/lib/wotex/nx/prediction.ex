defmodule Wotex.Nx.Prediction do
  @moduledoc """
  An inert prediction associated with a Property or Event affordance.

  `produced_at` and `target_at` are caller-supplied integer time coordinates;
  the library does not read a clock or interpret their unit. A prediction is
  advisory data until the consumer validates and admits it.
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
end
