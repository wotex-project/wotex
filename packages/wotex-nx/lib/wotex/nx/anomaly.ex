defmodule Wotex.Nx.Anomaly do
  @moduledoc """
  An inert anomaly assessment for a Property or Event affordance.

  The value preserves the score, threshold, and comparison rule used to derive
  `anomalous?`, so a consumer can audit the numerical interpretation without
  treating it as canonical Thing state or an Event emitted by the Thing.

  `Wotex.Nx.Decoder` derives the classification from an explicit anomaly
  `Wotex.Nx.OutputSchema`. Alongside the numerical result, the value records
  caller-supplied identity, Thing and affordance identity, the production time
  coordinate, and metadata for the admitted output.

  The four comparison rules distinguish strict and inclusive upper or lower
  thresholds. The stored boolean therefore remains reproducible from the score,
  threshold, and rule. Consumers decide how to investigate or act on the
  assessment; construction alone emits no Event and changes no Thing state.
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

  @doc "Returns the anomaly fields as a plain map; a read-only view, not an admission boundary."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value), do: Map.from_struct(value)
end
