defmodule Wotex.BLE.Address do
  @moduledoc "A GATT target preserves service, characteristic and optional instance handle."
  alias Wotex.BLE.{Error, UUID}
  @enforce_keys [:service, :characteristic]
  defstruct [:service, :characteristic, :handle]
  @type t :: %__MODULE__{service: String.t(), characteristic: String.t(), handle: 1..65_535 | nil}

  @doc "Validates UUID identities and optional ATT handle without discovering hardware."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%{service: service, characteristic: characteristic} = map) do
    with {:ok, service} <- UUID.normalize(service),
         {:ok, characteristic} <- UUID.normalize(characteristic) do
      handle = Map.get(map, :handle)

      if is_nil(handle) or (is_integer(handle) and handle in 1..65_535),
        do: {:ok, %__MODULE__{service: service, characteristic: characteristic, handle: handle}},
        else: {:error, Error.new(:invalid_handle)}
    end
  end

  def new(_), do: {:error, Error.new(:invalid_address)}

  @doc "Validates a GATT request and the 512-byte attribute value limit."
  @spec validate_message(map()) :: :ok | {:error, Error.t()}
  def validate_message(message) do
    with {:ok, _} <- new(message) do
      value = Map.get(message, :value)

      if message.type == :write and (not is_binary(value) or byte_size(value) > 512),
        do: {:error, Error.new(:invalid_value)},
        else: :ok
    end
  end
end
