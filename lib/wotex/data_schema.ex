defmodule Wotex.DataSchema do
  @moduledoc """
  An immutable W3C WoT DataSchema value.

  DataSchema terms describe the shape and constraints of data exchanged through
  Interaction Affordances. Wotex retains every JSON-compatible member,
  including unknown vocabulary extensions, without translating the schema into
  an Elixir validation library or consumer storage type.

  Use `new/2` at a value boundary and `to_map/1` when serializing or projecting
  the schema. Consumers should use those functions rather than struct fields.
  """

  alias Wotex.Value

  @type t :: %__MODULE__{value: map()}
  @enforce_keys [:value]
  defstruct [:value]

  @doc "Builds a DataSchema value from a JSON-compatible map."
  @spec new(map(), keyword()) :: {:ok, t()} | {:error, Wotex.Error.t()}
  def new(map, opts \\ []), do: Value.build(__MODULE__, map, [], :data_schema, opts)

  @doc "Returns the complete preserved DataSchema map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = schema), do: Value.to_map(schema)
end
