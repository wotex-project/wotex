defmodule Wotex.BLE.Characteristic do
  @moduledoc """
  Represents a characteristic reported by an explicitly selected GATT peer.

  The value retains service and characteristic UUIDs, both D-Bus object paths,
  the optional Attribute Protocol handle, flags and discovery generation.
  Construction validates these fields without performing discovery. The
  persistent BlueZ owner separately verifies their live device associations.
  Unknown flag names remain bounded strings and never become atoms.

  `address/1` converts a validated discovery result into the generation-bound
  `Wotex.BLE.Address` used for later I/O. A generation change invalidates that
  address, preventing a stale object path from being silently retargeted to a
  different characteristic.
  """

  alias Wotex.BLE.{Address, Error, ObjectPath}

  @enforce_keys [
    :service_uuid,
    :characteristic_uuid,
    :service_path,
    :object_path,
    :flags,
    :generation
  ]
  defstruct [:handle | @enforce_keys]

  @type t :: %__MODULE__{
          service_uuid: String.t(),
          characteristic_uuid: String.t(),
          service_path: String.t(),
          object_path: String.t(),
          flags: [String.t()],
          generation: 0..0xFFFF_FFFF_FFFF_FFFF,
          handle: 1..65_535 | nil
        }

  @doc "Validates discovery fields and up to 64 distinct UTF-8 flags of 1..64 bytes each."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(
        %{
          service_uuid: service,
          characteristic_uuid: characteristic,
          service_path: service_path,
          object_path: object_path,
          flags: flags,
          generation: generation
        } = input
      ) do
    with true <- ObjectPath.valid?(service_path) and ObjectPath.valid?(object_path),
         true <- not is_nil(generation),
         true <- valid_flags?(flags, %{}),
         {:ok, address} <-
           Address.new(%{
             service: service,
             characteristic: characteristic,
             handle: Map.get(input, :handle),
             object_path: object_path,
             generation: generation
           }) do
      {:ok,
       %__MODULE__{
         service_uuid: address.service,
         characteristic_uuid: address.characteristic,
         service_path: service_path,
         object_path: object_path,
         handle: address.handle,
         flags: flags,
         generation: generation
       }}
    else
      _ -> {:error, Error.new(:invalid_characteristic)}
    end
  end

  def new(_), do: {:error, Error.new(:invalid_characteristic)}

  @doc "Returns the complete generation-bound address after revalidating the discovery value."
  @spec address(term()) :: {:ok, Address.t()} | {:error, Error.t()}
  def address(value) do
    with {:ok, characteristic} <- new(value) do
      Address.new(%{
        service: characteristic.service_uuid,
        characteristic: characteristic.characteristic_uuid,
        handle: characteristic.handle,
        object_path: characteristic.object_path,
        generation: characteristic.generation
      })
    end
  end

  defp valid_flags?([], _), do: true

  defp valid_flags?([flag | rest], seen) when is_binary(flag) and byte_size(flag) in 1..64 do
    map_size(seen) < 64 and String.valid?(flag) and not Map.has_key?(seen, flag) and
      valid_flags?(rest, Map.put(seen, flag, true))
  end

  defp valid_flags?(_, _), do: false
end
