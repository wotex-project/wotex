defmodule Wotex.BLE.CoreBluetooth.Characteristic do
  @moduledoc """
  Carries a generation-scoped discovered CoreBluetooth characteristic route.

  Duplicate UUIDs retain distinct tokens. Properties describe SDK capabilities,
  not security or authority. Use `address/1` to retain the exact route in a request.
  """

  alias Wotex.BLE.{Address, Error, UUID}

  @fields ~w(service characteristic generation route read write write_without_response notify indicate)a
  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          service: String.t(),
          characteristic: String.t(),
          generation: pos_integer(),
          route: 1..256,
          read: boolean(),
          write: boolean(),
          write_without_response: boolean(),
          notify: boolean(),
          indicate: boolean()
        }

  @doc "Validates a complete immutable discovery value without protocol I/O."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = value) when map_size(value) == 10, do: new(Map.from_struct(value))

  def new(value) when is_map(value) and not is_struct(value) do
    with true <- Enum.sort(Map.keys(value)) == Enum.sort(@fields),
         {:ok, service} <- UUID.normalize(value.service),
         {:ok, characteristic} <- UUID.normalize(value.characteristic),
         true <- is_integer(value.generation) and value.generation in 1..0xFFFF_FFFF_FFFF_FFFF,
         true <- is_integer(value.route) and value.route in 1..256,
         true <-
           Enum.all?(~w(read write write_without_response notify indicate)a, &is_boolean(value[&1])) do
      {:ok, struct!(__MODULE__, %{value | service: service, characteristic: characteristic})}
    else
      _ -> {:error, Error.new(:invalid_characteristic)}
    end
  end

  def new(_), do: {:error, Error.new(:invalid_characteristic)}

  @doc "Retains this route and generation as a shared GATT Address."
  @spec address(term()) :: {:ok, Address.t()} | {:error, Error.t()}
  def address(value) do
    with {:ok, value} <- new(value),
         do:
           Address.new(%{
             service: value.service,
             characteristic: value.characteristic,
             generation: value.generation,
             native_route: {:core_bluetooth, value.route}
           })
  end
end
