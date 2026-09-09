defmodule Wotex.BACnet.Address do
  @moduledoc """
  Represents a validated BACnet object and Property address.

  An address contains an object type, object instance, and Property identifier.
  It may also carry an array index and a BACnet write priority. The constructor
  preserves array index zero rather than treating it as absent, and rejects
  values outside the package's documented protocol bounds.

  `new/1` constructs the value from a map. `validate_message/1` then checks that
  a read or write request contains the fields required by its operation. The
  resulting `t:t/0` is used by `Wotex.BACnet`,
  `Wotex.BACnet.Mapping`, and the selected `Wotex.BACnet.Client`.

  ## Examples

      {:ok, address} =
        Wotex.BACnet.Address.new(%{
          object_type: :analog_output,
          instance: 0,
          property: :present_value,
          array_index: 0,
          priority: 8
        })
  """
  alias Wotex.BACnet.{Error, Value}

  @objects %{
    analog_input: 0,
    analog_output: 1,
    analog_value: 2,
    binary_input: 3,
    binary_output: 4,
    binary_value: 5,
    device: 8,
    file: 10,
    multi_state_input: 13,
    multi_state_output: 14,
    schedule: 17,
    multi_state_value: 19,
    trend_log: 20
  }
  @properties %{
    present_value: 85,
    object_name: 77,
    object_type: 79,
    object_identifier: 75,
    description: 28,
    status_flags: 111,
    event_state: 36,
    reliability: 103,
    units: 117
  }
  @enforce_keys [:object_type, :instance, :property]
  defstruct [:object_type, :instance, :property, :array_index, :priority]

  @type t :: %__MODULE__{
          object_type: 0..1023,
          instance: 0..4_194_302,
          property: 0..4_194_303,
          array_index: non_neg_integer() | nil,
          priority: 1..16 | nil
        }

  @doc "Normalizes standard names or preserves numeric proprietary identifiers."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%{object_type: type, instance: instance, property: property} = input) do
    type = Map.get(@objects, type, type)
    property = Map.get(@properties, property, property)
    index = Map.get(input, :array_index)
    priority = Map.get(input, :priority)

    if bounded?(type, 0, 1023) and bounded?(instance, 0, 4_194_302) and
         bounded?(property, 0, 4_194_303) and optional?(index, 0, 4_294_967_295) and
         optional?(priority, 1, 16),
       do:
         {:ok,
          %__MODULE__{
            object_type: type,
            instance: instance,
            property: property,
            array_index: index,
            priority: priority
          }},
       else: {:error, Error.new(:invalid_address)}
  end

  def new(_), do: {:error, Error.new(:invalid_address)}

  @doc "Validates legacy message addressing and requires an explicit write value."
  @spec validate_message(map()) :: :ok | {:error, Error.t()}
  def validate_message(%{type: type} = message) when type in [:read_property, :write_property] do
    with {:ok, address} <- new(message) do
      validate_operation(type, address, message)
    end
  end

  def validate_message(_), do: {:error, Error.new(:invalid_message)}

  defp validate_operation(:read_property, %{priority: nil}, _), do: :ok

  defp validate_operation(:read_property, _, _),
    do: {:error, Error.new(:invalid_priority, :priority)}

  defp validate_operation(:write_property, _, message) do
    case Map.fetch(message, :value) do
      {:ok, value} -> Value.validate_write(value)
      :error -> {:error, Error.new(:missing_value)}
    end
  end

  defp bounded?(value, min, max), do: is_integer(value) and value >= min and value <= max
  defp optional?(nil, _, _), do: true
  defp optional?(value, min, max), do: bounded?(value, min, max)
end
