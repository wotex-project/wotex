defmodule Wotex.Nx.Encoded do
  @moduledoc "Immutable encoded `Nx.Batch` and conversion provenance."

  alias Wotex.Nx.Schema

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

  @doc "Returns the lazy `Nx.Batch`."
  @spec batch(t()) :: Nx.Batch.t()
  def batch(%__MODULE__{batch: batch}), do: batch

  @doc "Returns the exact feature order used by the batch container."
  @spec feature_order(t()) :: [String.t()]
  def feature_order(%__MODULE__{feature_order: order}), do: order
end
