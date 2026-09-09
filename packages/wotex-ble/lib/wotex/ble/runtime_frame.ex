defmodule Wotex.BLE.RuntimeFrame do
  @moduledoc false

  alias Wotex.BLE.BlueZ.Stream
  alias Wotex.BLE.{Characteristic, Error, Value}

  @fields [
    :service_uuid,
    :characteristic_uuid,
    :service_path,
    :object_path,
    :handle,
    :generation,
    :flags
  ]

  @doc false
  @spec validate(term(), term(), map()) :: {:ok, binary(), map()} | {:error, Error.t()} | :ignore
  def validate(
        bytes,
        %{
          source: :bluez_value_change,
          characteristic: characteristic,
          requested_mode: requested,
          effective_mode: effective
        } = metadata,
        mapping
      )
      when map_size(metadata) == 4 do
    with {:ok, bytes} <- Value.decode(bytes, :bytes, []),
         {:ok, characteristic} <- characteristic(characteristic),
         {:ok, ^effective} <- Stream.mode(characteristic.flags, requested) do
      if matches?(characteristic, mapping.address) and requested == mapping.mode do
        {:ok, bytes,
         %{
           source: :bluez_value_change,
           characteristic: Map.from_struct(characteristic),
           requested_mode: requested,
           effective_mode: effective
         }}
      else
        :ignore
      end
    else
      _ -> {:error, Error.new(:invalid_response)}
    end
  end

  def validate(_, _, _), do: {:error, Error.new(:invalid_response)}

  @doc false
  @spec decode(term(), map()) :: {:ok, term(), map()} | {:error, Error.t()} | :ignore
  def decode({:value, bytes, metadata}, mapping) do
    with {:ok, bytes, metadata} <- validate(bytes, metadata, mapping) do
      case Value.decode(bytes, mapping.value_type, byte_order: mapping.byte_order) do
        {:ok, value} -> {:ok, value, metadata}
        {:error, _} -> {:error, Error.new(:invalid_response)}
      end
    end
  end

  def decode({:error, %Error{code: code, effect: effect}}, _) when is_atom(code) do
    error = Error.new(code)
    {:error, if(effect == :unknown, do: Error.unknown_effect(error), else: error)}
  end

  def decode(_, _), do: :ignore

  defp characteristic(%Characteristic{} = characteristic) when map_size(characteristic) == 8,
    do: characteristic(Map.from_struct(characteristic))

  defp characteristic(characteristic)
       when is_map(characteristic) and map_size(characteristic) == 7 do
    with true <- Map.keys(characteristic) -- @fields == [],
         {:ok, value} <- Characteristic.new(characteristic),
         true <- Map.from_struct(value) == characteristic,
         do: {:ok, value},
         else: (_ -> :invalid)
  end

  defp characteristic(_), do: :invalid

  defp matches?(characteristic, address) do
    characteristic.service_uuid == address.service and
      characteristic.characteristic_uuid == address.characteristic and
      Enum.all?([:handle, :object_path, :generation], fn field ->
        selected = Map.fetch!(address, field)
        is_nil(selected) or selected == Map.fetch!(characteristic, field)
      end)
  end
end
