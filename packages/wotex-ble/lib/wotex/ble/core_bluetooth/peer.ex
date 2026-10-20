defmodule Wotex.BLE.CoreBluetooth.Peer do
  @moduledoc """
  Identifies an explicitly selected CoreBluetooth peripheral route.

  The UUID is private macOS routing data, not a portable Thing identity or
  authentication decision. Construction is pure; inspection hides the identifier.
  """

  alias Wotex.BLE.Error

  @enforce_keys [:identifier]
  @derive {Inspect, only: []}
  defstruct [:identifier]
  @opaque t :: %__MODULE__{identifier: String.t()}

  @doc "Normalizes one canonical UUID without retrieving or discovering a peripheral."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{identifier: identifier} = peer) when map_size(peer) == 2,
    do: new(identifier)

  def new(identifier) when is_binary(identifier) and byte_size(identifier) == 36 do
    if Regex.match?(
         ~r/\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/,
         identifier
       ),
       do: {:ok, %__MODULE__{identifier: String.downcase(identifier)}},
       else: {:error, Error.new(:invalid_peer)}
  end

  def new(_), do: {:error, Error.new(:invalid_peer)}
end
