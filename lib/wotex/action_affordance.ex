defmodule Wotex.ActionAffordance do
  @moduledoc """
  An immutable W3C WoT Action Affordance value.

  An Action Affordance describes an operation a Thing exposes. This module
  preserves the complete JSON-compatible map, including input/output schemas,
  Forms, safe/idempotent hints, and unknown extension members. It does not
  invoke the Action, authorize it, or claim that a physical effect occurred.

  Build values with `new/2` and recover the preserved representation with
  `to_map/1`. Consumers should use those functions rather than struct fields.

  `forms/1` returns validated `Wotex.Form` values in declaration order, and
  `operations/2` derives the effective Action operations for one Form. These
  accessors interpret Thing Description metadata only; selection and execution
  belong to a consuming runtime.
  """

  alias Wotex.{Form, Value}

  @type t :: %__MODULE__{value: map()}
  @enforce_keys [:value]
  defstruct [:value]

  @doc "Builds an Action Affordance value from a JSON-compatible map."
  @spec new(map(), keyword()) :: {:ok, t()} | {:error, Wotex.Error.t()}
  def new(map, opts \\ []), do: Value.build(__MODULE__, map, [], :action_affordance, opts)

  @doc "Returns the complete preserved Action Affordance map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = affordance), do: Value.to_map(affordance)

  @doc "Returns the affordance Forms validated in the Action interaction context."
  @spec forms(t()) :: {:ok, [Form.t()]} | {:error, Wotex.Error.t()}
  def forms(%__MODULE__{value: value}), do: Value.forms(value, :action)

  @doc "Returns the effective operations of one Form, applying the TD 1.1 Action default."
  @spec operations(t(), Form.t()) :: [String.t()]
  def operations(%__MODULE__{}, %Form{} = form), do: Form.operations(form, for: :action)
end
