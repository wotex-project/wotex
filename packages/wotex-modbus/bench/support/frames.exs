defmodule Wotex.Modbus.Bench.Frames do
  @moduledoc false

  # Synthetic Modbus TCP register and coil ranges, validated commands and the
  # exact response ADUs a conforming server returns for them. Every value is
  # deterministic so repeated runs measure identical inputs.

  import Bitwise

  alias Wotex.Modbus.Command

  @transaction_id 0x2A17
  @unit_id 17

  @spec transaction_id() :: 0..65_535
  def transaction_id, do: @transaction_id

  @spec register_sizes() :: %{String.t() => pos_integer()}
  def register_sizes, do: %{"1 register" => 1, "16 registers" => 16, "123 registers" => 123}

  @spec coil_sizes() :: %{String.t() => pos_integer()}
  def coil_sizes, do: %{"8 coils" => 8, "256 coils" => 256, "1968 coils" => 1968}

  @spec registers(pos_integer()) :: [0..65_535]
  def registers(count), do: Enum.map(1..count, &rem(&1 * 7919, 65_536))

  @spec coils(pos_integer()) :: [boolean()]
  def coils(count), do: Enum.map(1..count, &(rem(&1 * 5, 3) == 0))

  @spec command!(atom(), non_neg_integer(), term()) :: Command.t()
  def command!(operation, offset, input) do
    {:ok, command} = Command.new(operation, offset, input, @unit_id)
    command
  end

  @spec read_registers_response([0..65_535]) :: binary()
  def read_registers_response(registers) do
    data = for register <- registers, into: <<>>, do: <<register::16>>
    adu(<<3, byte_size(data), data::binary>>)
  end

  @spec read_coils_response([boolean()]) :: binary()
  def read_coils_response(coils) do
    data =
      coils
      |> Enum.chunk_every(8)
      |> Enum.map(&pack/1)
      |> :erlang.list_to_binary()

    adu(<<1, byte_size(data), data::binary>>)
  end

  @spec write_echo(Command.t()) :: binary()
  def write_echo(%Command{function: function, address: address}),
    do: adu(<<function, address.offset::16, address.quantity::16>>)

  defp adu(pdu), do: <<@transaction_id::16, 0::16, byte_size(pdu) + 1::16, @unit_id, pdu::binary>>

  defp pack(group) do
    group
    |> Enum.with_index()
    |> Enum.reduce(0, fn
      {true, index}, byte -> bor(byte, bsl(1, index))
      {false, _}, byte -> byte
    end)
  end
end
