defmodule Wotex.EventAffordance do
  @moduledoc """
  An immutable W3C WoT Event Affordance value.

  An Event Affordance describes asynchronous data a Thing may emit and the
  Forms used to subscribe or unsubscribe. This value preserves data,
  subscription, cancellation, and extension terms. It owns no process,
  subscription lifecycle, transport connection, or delivery guarantee.

  Use `new/2` to validate JSON-value semantics and `to_map/1` to recover the
  complete declaration.

  `forms/1` preserves declaration order as validated `Wotex.Form` values, while
  `operations/2` determines the effective subscription or cancellation
  operation for a selected Form. Neither function opens a stream or interprets
  an Event payload.
  """

  alias Wotex.{Form, Value}

  @type t :: %__MODULE__{value: map()}
  @enforce_keys [:value]
  defstruct [:value]

  @doc "Builds an Event Affordance value from a JSON-compatible map."
  @spec new(map(), keyword()) :: {:ok, t()} | {:error, Wotex.Error.t()}
  def new(map, opts \\ []), do: Value.build(__MODULE__, map, [], :event_affordance, opts)

  @doc "Returns the complete preserved Event Affordance map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = affordance), do: Value.to_map(affordance)

  @doc "Returns the affordance Forms validated in the Event interaction context."
  @spec forms(t()) :: {:ok, [Form.t()]} | {:error, Wotex.Error.t()}
  def forms(%__MODULE__{value: value}), do: Value.forms(value, :event)

  @doc "Returns the effective operations of one Form, applying the TD 1.1 Event defaults."
  @spec operations(t(), Form.t()) :: [String.t()]
  def operations(%__MODULE__{}, %Form{} = form), do: Form.operations(form, for: :event)
end
