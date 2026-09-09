defmodule Wotex.Modbus.Address do
  @moduledoc """
  Represents a validated Modbus register or coil range.

  A `t:t/0` contains a zero-based offset, a positive quantity, and a unicast
  Unit Identifier. `new/3` accepts offsets within the 16-bit address space and
  rejects a range whose final element would exceed that space. Unit Identifiers
  1 through 247 and 255 are admitted by the package profile.

  The value is independent of a function code. Function-specific quantity
  limits are applied by `Wotex.Modbus.Command`, which combines an address with
  a read or write operation. Construction performs no socket I/O and does not
  resolve one-based references from a Form; that conversion belongs to
  `Wotex.Modbus.Mapping`.

  ## Examples

      iex> Wotex.Modbus.Address.new(0, 2, 1)
      {:ok, %Wotex.Modbus.Address{offset: 0, quantity: 2, unit_id: 1}}
  """

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
