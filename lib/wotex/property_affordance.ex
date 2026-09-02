defmodule Wotex.PropertyAffordance do
  @moduledoc "Immutable, extension-preserving W3C WoT Property Affordance value."

  alias Wotex.Value

  @opaque t :: %__MODULE__{value: map()}
  @enforce_keys [:value]
  defstruct [:value]

  @doc "Builds a Property Affordance value from a JSON-compatible map."
  @spec new(map(), keyword()) :: {:ok, t()} | {:error, Wotex.Error.t()}
  def new(map, opts \\ []), do: Value.build(__MODULE__, map, [], opts)

  @doc "Returns the complete preserved Property Affordance map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = affordance), do: Value.to_map(affordance)
end
