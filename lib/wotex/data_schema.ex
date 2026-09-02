defmodule Wotex.DataSchema do
  @moduledoc "Immutable, extension-preserving W3C WoT DataSchema value."

  alias Wotex.Value

  @opaque t :: %__MODULE__{value: map()}
  @enforce_keys [:value]
  defstruct [:value]

  @doc "Builds a DataSchema value from a JSON-compatible map."
  @spec new(map(), keyword()) :: {:ok, t()} | {:error, Wotex.Error.t()}
  def new(map, opts \\ []), do: Value.build(__MODULE__, map, [], opts)

  @doc "Returns the complete preserved DataSchema map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = schema), do: Value.to_map(schema)
end
