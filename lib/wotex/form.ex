defmodule Wotex.Form do
  @moduledoc "Immutable, extension-preserving W3C WoT Form value."

  alias Wotex.Value

  @opaque t :: %__MODULE__{value: map()}
  @enforce_keys [:value]
  defstruct [:value]

  @doc "Builds a Form value. A non-empty `href` is required."
  @spec new(map(), keyword()) :: {:ok, t()} | {:error, Wotex.Error.t()}
  def new(map, opts \\ []) do
    Value.build(
      __MODULE__,
      map,
      [
        {"href", &non_empty_binary?/1, "Form href must be non-empty"},
        {"op", &valid_operation?/1, "Form op must be a string or a list of strings when present"}
      ],
      opts
    )
  end

  @doc "Returns the complete preserved Form map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = form), do: Value.to_map(form)

  @doc "Returns the unresolved Form href."
  @spec href(t()) :: String.t()
  def href(%__MODULE__{value: value}), do: Map.fetch!(value, "href")

  @doc "Returns declared operation names in source order."
  @spec operations(t()) :: [String.t()]
  def operations(%__MODULE__{value: %{"op" => operation}}) when is_binary(operation),
    do: [operation]

  def operations(%__MODULE__{value: %{"op" => operations}}) when is_list(operations),
    do: operations

  def operations(%__MODULE__{}), do: []

  defp non_empty_binary?(value), do: is_binary(value) and byte_size(String.trim(value)) > 0
  defp valid_operation?(nil), do: true
  defp valid_operation?(value) when is_binary(value), do: byte_size(value) > 0

  defp valid_operation?(values) when is_list(values),
    do: values != [] and Enum.all?(values, &(is_binary(&1) and byte_size(&1) > 0))

  defp valid_operation?(_value), do: false
end
