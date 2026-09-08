defmodule Wotex.Modbus.Address do
  @moduledoc "Validated zero-based register or coil range for a unicast Unit Identifier."

  alias Wotex.Modbus.Error

  @enforce_keys [:offset, :quantity, :unit_id]
  defstruct [:offset, :quantity, :unit_id]

  @type t :: %__MODULE__{offset: 0..65_535, quantity: pos_integer(), unit_id: 1..247 | 255}

  @doc "Validates a range without inferring a register table or human address base."
  @spec new(term(), term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def new(offset, quantity \\ 1, unit_id \\ 1) do
    cond do
      not is_integer(offset) or offset not in 0..65_535 ->
        {:error, Error.new(:invalid_address, :offset)}

      not is_integer(quantity) or quantity < 1 or quantity > 2000 ->
        {:error, Error.new(:invalid_quantity, :quantity)}

      offset + quantity > 65_536 ->
        {:error, Error.new(:address_overflow, :quantity)}

      not is_integer(unit_id) or (unit_id not in 1..247 and unit_id != 255) ->
        {:error, Error.new(:invalid_unit, :unit_id)}

      true ->
        {:ok, %__MODULE__{offset: offset, quantity: quantity, unit_id: unit_id}}
    end
  end
end
