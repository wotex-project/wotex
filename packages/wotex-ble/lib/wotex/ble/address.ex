defmodule Wotex.BLE.Address do
  @moduledoc "A GATT target preserves service, characteristic and optional instance handle."
  alias Wotex.BLE.{Error, ObjectPath, UUID}
  @enforce_keys [:service, :characteristic]
  defstruct [:service, :characteristic, :handle, :object_path, :generation]

  @type t :: %__MODULE__{
          service: String.t(),
          characteristic: String.t(),
          handle: 1..65_535 | nil,
          object_path: String.t() | nil,
          generation: 0..0xFFFF_FFFF_FFFF_FFFF | nil
        }

  @doc "Validates UUID identities and optional ATT handle without discovering hardware."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%{service: service, characteristic: characteristic} = map) do
    with {:ok, service} <- UUID.normalize(service),
         {:ok, characteristic} <- UUID.normalize(characteristic),
         :ok <- validate_selection(map) do
      {:ok,
       %__MODULE__{
         service: service,
         characteristic: characteristic,
         handle: Map.get(map, :handle),
         object_path: Map.get(map, :object_path),
         generation: Map.get(map, :generation)
       }}
    end
  end

  def new(_), do: {:error, Error.new(:invalid_address)}

  @doc "Parses exactly two UUIDs separated by one slash without default identities."
  @spec from_topic(term()) :: {:ok, t()} | {:error, Error.t()}
  def from_topic(topic) when is_binary(topic) and byte_size(topic) <= 73 do
    with [service, characteristic] <- String.split(topic, "/", parts: 3),
         {:ok, address} <- new(%{service: service, characteristic: characteristic}) do
      {:ok, address}
    else
      _ -> {:error, Error.new(:invalid_address)}
    end
  end

  def from_topic(_), do: {:error, Error.new(:invalid_address)}

  @doc "Validates a GATT request and the 512-byte attribute value limit."
  @spec validate_message(term()) :: :ok | {:error, Error.t()}
  def validate_message(%{type: type} = message) when type in [:read, :write] do
    with {:ok, _} <- new(message) do
      value = Map.get(message, :value)

      if type == :write and (not is_binary(value) or byte_size(value) > 512),
        do: {:error, Error.new(:invalid_value)},
        else: :ok
    end
  end

  def validate_message(_), do: {:error, Error.new(:invalid_message)}

  defp validate_selection(map) do
    handle = Map.get(map, :handle)
    path = Map.get(map, :object_path)
    generation = Map.get(map, :generation)

    cond do
      not (is_nil(handle) or (is_integer(handle) and handle in 1..65_535)) ->
        {:error, Error.new(:invalid_handle)}

      not (is_nil(path) or ObjectPath.valid?(path)) ->
        {:error, Error.new(:invalid_object_path, :object_path)}

      not (is_nil(generation) or
               (is_integer(generation) and generation in 0..0xFFFF_FFFF_FFFF_FFFF)) ->
        {:error, Error.new(:invalid_generation, :generation)}

      true ->
        :ok
    end
  end
end
