defmodule Wotex.Nx.Anomaly do
  @moduledoc "Inert anomaly score for a Property or Event affordance."

  @opaque t :: %__MODULE__{
            id: String.t(),
            thing_id: String.t(),
            affordance_type: :property | :event,
            affordance_name: String.t(),
            score: number(),
            anomalous?: boolean(),
            threshold: number(),
            rule: :above | :at_or_above | :below | :at_or_below,
            produced_at: integer(),
            metadata: map()
          }

  @enforce_keys [
    :id,
    :thing_id,
    :affordance_type,
    :affordance_name,
    :score,
    :anomalous?,
    :threshold,
    :rule,
    :produced_at,
    :metadata
  ]
  defstruct @enforce_keys
end
