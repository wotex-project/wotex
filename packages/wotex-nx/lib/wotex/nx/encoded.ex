defmodule Wotex.Nx.Encoded do
  @moduledoc """
  The lazy `Nx.Batch` produced from accepted rows and a numerical schema.

  Alongside the batch, the value preserves feature order, timestamps, source
  observation identifiers, and the layout identifier. Those fields let a
  consumer bind model output back to the exact inputs without depending on map
  enumeration or implicit tensor conventions.

  ## Batch axis and serving

  Axis 0 of every tensor in the batch is the window row (time step) of one
  sample: an encoded window is one sample sequence, not `row_count/1`
  independent samples. The Nx serving abstraction splits batches along axis 0
  at its batch size, so a serving must receive the whole window (batch size at
  least `row_count/1`) or a function that reduces over axis 0 silently changes
  its answer. Masks use `1` for observed and `0` for filled, so a row added by
  `Nx.Batch.pad/2` reads as unobserved with quality code `0`; treat padded rows
  through the mask, never through the quality vector alone.

  Every value tensor is realized on the backend that was the default at encode
  time; only the stack is deferred. The struct implements `Nx.LazyContainer`,
  so it can be passed directly to `Nx.Defn.jit_apply/3`.
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

  @doc "Returns the accepted schema the batch was encoded with."
  @spec schema(t()) :: Schema.t()
  def schema(%__MODULE__{schema: schema}), do: schema

  @doc "Returns the row timestamps in batch order."
  @spec timestamps(t()) :: [integer()]
  def timestamps(%__MODULE__{timestamps: timestamps}), do: timestamps

  @doc "Returns the per-row provenance maps (feature name to source observation id) in batch order."
  @spec provenance(t()) :: [map()]
  def provenance(%__MODULE__{provenance: provenance}), do: provenance

  @doc "Returns the layout identifier of each batch entry."
  @spec layout(t()) :: atom()
  def layout(%__MODULE__{layout: layout}), do: layout

  @doc "Returns the number of window rows stacked along axis 0."
  @spec row_count(t()) :: pos_integer()
  def row_count(%__MODULE__{timestamps: timestamps}), do: length(timestamps)

  @doc """
  Returns the stacked batch entry as `Nx.template/2` containers.

  The result has the same `{values_tuple, masks_tuple, quality_vector}` shape
  as a realized entry, with `row_count/1` as the leading axis, so a consumer can
  build a model input declaration or a serving contract without realizing
  tensors.
  """
  @spec template(t()) :: {tuple(), tuple(), Nx.Tensor.t()}
  def template(%__MODULE__{schema: schema, timestamps: timestamps}) do
    rows = length(timestamps)
    features = Schema.features(schema)
    values = Enum.map(features, &Nx.template(Tuple.insert_at(&1.shape, 0, rows), &1.dtype))
    masks = Enum.map(features, &Nx.template(Tuple.insert_at(&1.shape, 0, rows), :u8))
    quality = Nx.template({rows, length(features)}, :u8)
    {List.to_tuple(values), List.to_tuple(masks), quality}
  end
end
