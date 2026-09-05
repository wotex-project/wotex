defmodule Wotex.PropertyAffordance do
  @moduledoc """
  An immutable W3C WoT Property Affordance value.

  A Property Affordance combines a DataSchema with readable, writable, and
  observable interaction metadata. The preserved map is a declaration from a
  Thing Description; it is not canonical device state and does not prove that a
  read, write, observation, or physical change occurred.

  Unknown extension members survive `new/2` and `to_map/1` unchanged at native
  JSON-value semantics.
  """

  alias Wotex.Value

  @type t :: %__MODULE__{value: map()}
  @enforce_keys [:value]
  defstruct [:value]

  @doc "Builds a Property Affordance value from a JSON-compatible map."
  @spec new(map(), keyword()) :: {:ok, t()} | {:error, Wotex.Error.t()}
  def new(map, opts \\ []), do: Value.build(__MODULE__, map, [], :property_affordance, opts)

  @doc "Returns the complete preserved Property Affordance map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = affordance), do: Value.to_map(affordance)
end
