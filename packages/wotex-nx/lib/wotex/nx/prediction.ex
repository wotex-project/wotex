defmodule Wotex.Nx.Prediction do
  @moduledoc "Inert numerical prediction for a Property or Event affordance."

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
