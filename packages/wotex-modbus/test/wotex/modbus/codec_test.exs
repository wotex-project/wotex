defmodule Wotex.Modbus.CodecTest do
  @moduledoc false

  use ExUnit.Case, async: true
  doctest Wotex.Modbus.Address
  use ExUnitProperties
  alias Wotex.Modbus.{Address, Codec, Command, Error}

  test "forged command structs never overflow or reach the wire" do
    {:ok, command} = Command.new(:write_holding_register, 0, 1)
    assert {:error, _} = Command.validate(nil)

    for forged <- [
          %{command | values: [65_536]},
          %{command | function: 99},
          %{command | values: []},
          %{command | address: %{command.address | offset: 65_536}}
        ],
        do: assert(match?({:error, _}, Codec.encode(forged, 1)))
  end

  test "golden request and every split boundary" do
    assert {:ok, cmd} = Command.new(:read_holding_registers, 0, 2, 1)
    assert {:ok, <<0, 7, 0, 0, 0, 6, 1, 3, 0, 0, 0, 2>> = bytes} = Codec.encode(cmd, 7)

    for count <- 0..(byte_size(bytes) - 1),
        do: assert(Codec.decode(binary_part(bytes, 0, count)) == :more)

    assert {:ok, %{transaction_id: 7, unit_id: 1, pdu: <<3, 0, 0, 0, 2>>}, <<1, 2>>} =
             Codec.decode(bytes <> <<1, 2>>)

    assert {:ok, [10, 65_535]} = response(cmd, <<3, 4, 0, 10, 255, 255>>)
  end

  test "all function limits and range overflow fail before encoding" do
    for {op, max} <- [
          read_coils: 2000,
          read_discrete_inputs: 2000,
          read_holding_registers: 125,
          read_input_registers: 125
        ] do
      assert {:ok, _} = Command.new(op, 0, max)

      for bad <- [0, -1, max + 1, nil, "1", 1.0],
          do: assert(match?({:error, %Error{}}, Command.new(op, 0, bad)))
    end

    for {op, max, value} <- [{:write_coils, 1968, true}, {:write_holding_registers, 123, 65_535}] do
      assert {:ok, _} = Command.new(op, 0, List.duplicate(value, max))
      assert {:error, _} = Command.new(op, 0, List.duplicate(value, max + 1))
      assert {:error, _} = Command.new(op, 0, [])
      assert {:error, _} = Command.new(op, 0, nil)
    end

    assert {:ok, _} = Address.new(65_535)
    assert {:error, %{code: :address_overflow}} = Address.new(65_535, 2)
    for bad <- [-1, 65_536, nil, 1.0], do: assert(match?({:error, _}, Address.new(bad)))
    for bad <- [0, 248, 254, 256, nil], do: assert(match?({:error, _}, Address.new(0, 1, bad)))
    assert {:ok, _} = Address.new(0, 1, 255)
    assert {:error, _} = Command.new(:unknown, 0, 1)
    assert {:error, _} = Command.new(:write_coil, 0, :on)
    assert {:error, _} = Command.new(:write_holding_register, 0, 65_536)
    assert {:error, _} = Codec.encode(nil, 1)
    assert {:error, _} = Codec.decode(nil)
  end

  test "function-specific encodings and echoes" do
    for {op, input, expected, reply} <- [
          {:read_coils, 3, <<1, 0, 9, 0, 3>>, <<1, 1, 5>>},
          {:read_discrete_inputs, 8, <<2, 0, 9, 0, 8>>, <<2, 1, 255>>},
          {:read_input_registers, 1, <<4, 0, 9, 0, 1>>, <<4, 2, 0, 7>>},
          {:write_coil, true, <<5, 0, 9, 255, 0>>, <<5, 0, 9, 255, 0>>},
          {:write_coil, 0, <<5, 0, 9, 0, 0>>, <<5, 0, 9, 0, 0>>},
          {:write_holding_register, 42, <<6, 0, 9, 0, 42>>, <<6, 0, 9, 0, 42>>},
          {:write_coils, [1, 0, true, false, false, false, false, false, true],
           <<15, 0, 9, 0, 9, 2, 5, 1>>, <<15, 0, 9, 0, 9>>},
          {:write_holding_registers, [1, 65_535], <<16, 0, 9, 0, 2, 4, 0, 1, 255, 255>>,
           <<16, 0, 9, 0, 2>>}
        ] do
      assert {:ok, cmd} = Command.new(op, 9, input)
      assert {:ok, bytes} = Codec.encode(cmd, 65_535)
      assert {:ok, %{pdu: ^expected}, <<>>} = Codec.decode(bytes)
      assert {:ok, _} = response(cmd, reply)
      assert {:error, _} = response(cmd, reply <> <<0>>)
    end
  end

  test "malformed and mismatched responses are rejected including nonzero coil padding" do
    {:ok, cmd} = Command.new(:read_coils, 0, 1)

    for bytes <- [<<1, 1, 2>>, <<1, 0>>, <<1, 1>>, <<2, 1, 0>>, <<129, 2, 0>>, <<129>>],
        do: assert(match?({:error, _}, response(cmd, bytes)))

    assert {:error, %{code: :remote_exception, details: %{exception_code: 222}}} =
             response(cmd, <<129, 222>>)

    assert {:error, %{code: :response_mismatch}} =
             Codec.response(%{transaction_id: 2, unit_id: 1, pdu: <<1, 1, 1>>}, cmd, 1)

    assert {:error, %{code: :response_mismatch}} =
             Codec.response(%{transaction_id: 1, unit_id: 2, pdu: <<1, 1, 1>>}, cmd, 1)

    {:ok, write} = Command.new(:write_holding_register, 1, 42)
    assert {:error, _} = response(write, <<6, 0, 1, 0, 43>>)

    for length <- [0, 1, 255, 65_535],
        do: assert(match?({:error, _}, Codec.decode(<<0::16, 0::16, length::16>>)))

    assert {:error, _} = Codec.decode(<<0::16, 1::16, 6::16>>)
  end

  property "arbitrary short and malformed frames never raise" do
    check all(bytes <- binary(max_length: 600), max_runs: 500) do
      result =
        case Codec.decode(bytes) do
          :more -> true
          {:ok, %{pdu: pdu}, _} -> byte_size(pdu) in 1..253
          {:error, %Error{}} -> true
        end

      assert result
    end
  end

  defp response(cmd, bytes),
    do: Codec.response(%{transaction_id: 1, unit_id: 1, pdu: bytes}, cmd, 1)
end
