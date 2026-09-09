defmodule Wotex.Nx.NumericalSchema do
  @moduledoc """
  Derives the package's numerical representation from a supported DataSchema map.

  This implementation helper maps number, integer and boolean scalars to
  `{:f, 32}`, `{:s, 64}` and `{:u, 8}` respectively. Nested arrays require one
  item schema and equal positive `minItems` and `maxItems`; their lengths form
  the tensor shape. Other schema categories return `Wotex.Nx.Error`.

  Feature and output constructors use this helper after core DataSchema
  admission. Dtype checks preserve the scalar category, normalization requires
  a floating-point dtype, and `width/1` multiplies admitted shape dimensions.
  Nx templates validate representation without allocating observation tensors.
  This is the package's numerical subset, not a general DataSchema validator.

  ## Examples

      iex> Wotex.Nx.NumericalSchema.infer(%{"type" => "integer"})
      {:ok, {}, {:s, 64}}
  """

  alias Wotex.Nx.Error

  @spec infer(map()) :: {:ok, tuple(), Nx.Type.t()} | {:error, Error.t()}
  def infer(%{"type" => "number"}), do: {:ok, {}, {:f, 32}}
  def infer(%{"type" => "integer"}), do: {:ok, {}, {:s, 64}}
  def infer(%{"type" => "boolean"}), do: {:ok, {}, {:u, 8}}

  def infer(%{
        "type" => "array",
        "items" => items,
        "minItems" => count,
        "maxItems" => count
      })
      when is_map(items) and is_integer(count) and count > 0 do
    with {:ok, child_shape, dtype} <- infer(items) do
      {:ok, List.to_tuple([count | Tuple.to_list(child_shape)]), dtype}
    end
  end

  def infer(_) do
    {:error,
     Error.new(
       :unsupported_data_schema,
       :construction,
       "DataSchema must be numeric, boolean, or a fixed-size array of supported values"
     )}
  end

  @spec normalize_dtype(term(), tuple()) :: {:ok, Nx.Type.t()} | {:error, Error.t()}
  def normalize_dtype(dtype, shape) when is_tuple(shape) do
    template = Nx.template(shape, dtype)
    {:ok, Nx.type(template)}
  rescue
    _ in [ArgumentError, FunctionClauseError] ->
      {:error, Error.new(:invalid_dtype, :construction, "numerical dtype is invalid")}
  end

  def normalize_dtype(_, _) do
    {:error, Error.new(:invalid_shape, :construction, "numerical shape must be a tuple")}
  end

  @spec validate_dtype(map(), Nx.Type.t()) :: :ok | {:error, Error.t()}
  def validate_dtype(%{"type" => "array", "items" => items}, dtype) when is_map(items),
    do: validate_dtype(items, dtype)

  def validate_dtype(%{"type" => "number"}, {class, _}) when class in [:f, :bf],
    do: :ok

  def validate_dtype(%{"type" => "integer"}, {class, _}) when class in [:s, :u],
    do: :ok

  def validate_dtype(%{"type" => "boolean"}, {class, _}) when class in [:s, :u],
    do: :ok

  def validate_dtype(_, _) do
    {:error,
     Error.new(
       :dtype_schema_mismatch,
       :construction,
       "numerical dtype would change the DataSchema value category"
     )}
  end

  @spec validate_normalization(:none | tuple(), Nx.Type.t()) ::
          :ok | {:error, Error.t()}
  def validate_normalization(:none, _), do: :ok

  def validate_normalization(_, {class, _}) when class in [:f, :bf],
    do: :ok

  def validate_normalization(_, _) do
    {:error,
     Error.new(
       :normalization_dtype_mismatch,
       :construction,
       "normalization requires a floating-point dtype"
     )}
  end

  @spec width(tuple()) :: pos_integer()
  def width({}), do: 1

  def width(shape) do
    shape
    |> Tuple.to_list()
    |> Enum.reduce(1, fn dimension, width ->
      dimension * width
    end)
  end
end
