defmodule Wotex.PropertyAffordance do
  @moduledoc """
  An immutable W3C WoT Property Affordance value.

  A Property Affordance combines a DataSchema with readable, writable, and
  observable interaction metadata. The preserved map is a declaration from a
  Thing Description; it is not canonical device state and does not prove that a
  read, write, observation, or physical change occurred.

  Unknown extension members survive `new/2` and `to_map/1` unchanged at native
  JSON-value semantics.

  The read-only, write-only, and observable predicates report declared flags,
  not verified device behavior. `forms/1` preserves Form order and
  `operations/2` applies the Property default-operation rules before a runtime
  performs binding-profile selection.
  """

  alias Wotex.{Form, Value}

  @type t :: %__MODULE__{value: map()}
  @enforce_keys [:value]
  defstruct [:value]

  @doc "Builds a Property Affordance value from a JSON-compatible map."
  @spec new(map(), keyword()) :: {:ok, t()} | {:error, Wotex.Error.t()}
  def new(map, opts \\ []), do: Value.build(__MODULE__, map, [], :property_affordance, opts)

  @doc "Returns the complete preserved Property Affordance map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = affordance), do: Value.to_map(affordance)

  @doc "Returns whether the affordance declares `readOnly: true`."
  @spec read_only?(t()) :: boolean()
  def read_only?(%__MODULE__{value: value}), do: Map.get(value, "readOnly") == true

  @doc "Returns whether the affordance declares `writeOnly: true`."
  @spec write_only?(t()) :: boolean()
  def write_only?(%__MODULE__{value: value}), do: Map.get(value, "writeOnly") == true

  @doc "Returns whether the affordance declares `observable: true`."
  @spec observable?(t()) :: boolean()
  def observable?(%__MODULE__{value: value}), do: Map.get(value, "observable") == true

  @doc "Returns the affordance Forms validated in the Property interaction context."
  @spec forms(t()) :: {:ok, [Form.t()]} | {:error, Wotex.Error.t()}
  def forms(%__MODULE__{value: value}), do: Value.forms(value, :property)

  @doc "Returns the effective operations of one Form, applying TD 1.1 Property defaults."
  @spec operations(t(), Form.t()) :: [String.t()]
  def operations(%__MODULE__{} = affordance, %Form{} = form) do
    Form.operations(form,
      for: :property,
      read_only: read_only?(affordance),
      write_only: write_only?(affordance)
    )
  end
end
