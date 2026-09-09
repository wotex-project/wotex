defmodule Wotex.BLE.Peer do
  @moduledoc """
  Represents an explicit BLE adapter path and peer identity.

  A `t:t/0` combines a validated D-Bus adapter path, a six-octet Bluetooth
  address, and an explicit `:public` or `:random` address type. `new/1`
  normalizes the address to uppercase and rejects extra struct state, malformed
  addresses, invalid adapter paths, and missing address-type information.

  This value identifies a caller-selected peer; it does not perform scanning,
  resolve a resolvable private address, establish a connection, or express an
  authorization decision. Consumers retain ownership of discovery results and
  identity policy.

  ## Examples

      iex> {:ok, peer} = Wotex.BLE.Peer.new(%{adapter: "/org/bluez/hci0", address: "aa:bb:cc:dd:ee:ff", address_type: :public})
      iex> {peer.adapter, peer.address, peer.address_type}
      {"/org/bluez/hci0", "AA:BB:CC:DD:EE:FF", :public}
  """

  alias Wotex.BLE.{Error, ObjectPath}

  @enforce_keys [:adapter, :address, :address_type]
  defstruct [:adapter, :address, :address_type]

  @type t :: %__MODULE__{
          adapter: String.t(),
          address: String.t(),
          address_type: :public | :random
        }

  @doc "Validates an adapter path, six-octet address and explicit public/random address type."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%{adapter: adapter, address: address, address_type: type} = input) do
    cond do
      not admitted?(input) ->
        {:error, Error.new(:invalid_peer)}

      not ObjectPath.valid?(adapter) ->
        {:error, Error.new(:invalid_peer, :adapter)}

      not valid_address?(address) ->
        {:error, Error.new(:invalid_peer, :address)}

      type not in [:public, :random] ->
        {:error, Error.new(:invalid_peer, :address_type)}

      true ->
        {:ok, %__MODULE__{adapter: adapter, address: String.upcase(address), address_type: type}}
    end
  end

  def new(_), do: {:error, Error.new(:invalid_peer)}

  defp admitted?(%__MODULE__{} = input), do: map_size(input) == 4
  defp admitted?(input), do: map_size(input) == 3

  defp valid_address?(address) when is_binary(address) and byte_size(address) == 17,
    do: Regex.match?(~r/\A[0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5}\z/, address)

  defp valid_address?(_), do: false
end
