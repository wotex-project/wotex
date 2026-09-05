defmodule Wotex.EventAffordance do
  @moduledoc """
  An immutable W3C WoT Event Affordance value.

  An Event Affordance describes asynchronous data a Thing may emit and the
  Forms used to subscribe or unsubscribe. This value preserves data,
  subscription, cancellation, and extension terms. It owns no process,
  subscription lifecycle, transport connection, or delivery guarantee.

  Use `new/2` to validate JSON-value semantics and `to_map/1` to recover the
  complete declaration.
  """

  alias Wotex.Value

  @type t :: %__MODULE__{value: map()}
  @enforce_keys [:value]
  defstruct [:value]

  @doc "Builds an Event Affordance value from a JSON-compatible map."
  @spec new(map(), keyword()) :: {:ok, t()} | {:error, Wotex.Error.t()}
  def new(map, opts \\ []), do: Value.build(__MODULE__, map, [], :event_affordance, opts)

  @doc "Returns the complete preserved Event Affordance map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = affordance), do: Value.to_map(affordance)
end
