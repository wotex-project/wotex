defmodule Wotex.Nx.Anomaly do
  @moduledoc """
  An inert anomaly assessment for a Property or Event affordance.

  The value preserves the score, threshold, and comparison rule used to derive
  `anomalous?`, so a consumer can audit the numerical interpretation without
  treating it as canonical Thing state or an Event emitted by the Thing.
  """

  @typedoc "An auditable anomaly score and the explicit rule used to classify it."
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
