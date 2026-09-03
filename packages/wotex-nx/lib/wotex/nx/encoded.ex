defmodule Wotex.Nx.Encoded do
  @moduledoc """
  The lazy `Nx.Batch` produced from accepted rows and a numerical schema.

  Alongside the batch, the value preserves feature order, timestamps, source
  observation identifiers, and the layout identifier. Those fields let a
  consumer bind model output back to the exact inputs without depending on map
  enumeration or implicit tensor conventions.
  """

  alias Wotex.Nx.Schema

  @typedoc "A lazy batch plus the schema, ordering, timestamps, and provenance that produced it."
  @opaque t :: %__MODULE__{
            batch: Nx.Batch.t(),
            schema: Schema.t(),
            feature_order: [String.t()],
            timestamps: [integer()],
            provenance: [map()],
            layout: atom()
          }

  @enforce_keys [:batch, :schema, :feature_order, :timestamps, :provenance, :layout]
  defstruct @enforce_keys

  @doc """
  Returns the lazy `Nx.Batch` without realizing it on a backend.

  Backend selection and execution remain consumer responsibilities.
  """
  @spec batch(t()) :: Nx.Batch.t()
  def batch(%__MODULE__{batch: batch}), do: batch

  @doc """
  Returns the exact feature order used by every row in the batch.

  Consumers should use this order when interpreting model inputs, explanations,
  or output mappings rather than reconstructing order from a map.
  """
  @spec feature_order(t()) :: [String.t()]
  def feature_order(%__MODULE__{feature_order: order}), do: order
end
