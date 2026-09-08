defmodule Wotex.Modbus.ValueTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.Modbus.Value

  test "all scalar widths, order conventions and boundaries" do
    for {kind, values} <- [
          uint16: [0, 65_535],
          int16: [-32_768, 32_767],
          uint32: [0, 4_294_967_295],
          int32: [-2_147_483_648, 2_147_483_647],
          uint64: [0, 18_446_744_073_709_551_615],
          int64: [-9_223_372_036_854_775_808, 9_223_372_036_854_775_807],
          float32: [0.0, 1.5, -22.75],
          float64: [0.0, -3.25, 1.0e300]
        ],
        value <- values,
        byte <- [:big, :little],
        word <- [:big, :little] do
      opts = [byte_order: byte, word_order: word]
      assert {:ok, registers} = Value.encode(value, kind, opts)
      assert {:ok, ^value} = Value.decode(registers, kind, opts)
    end

    assert {:ok, [0x3344, 0x1122]} = Value.encode(0x11223344, :uint32, word_order: :little)

    for {value, kind} <- [
          {-1, :uint16},
          {65_536, :uint16},
          {32_768, :int16},
          {1.0, :int32},
          {1, :float32},
          {1.0e100, :float32},
          {nil, :float64}
        ],
        do: assert(match?({:error, _}, Value.encode(value, kind)))

    for registers <- [[], [1], [1, 2, 3], [65_536, 0], nil],
        do: assert(match?({:error, _}, Value.decode(registers, :uint32)))

    for bytes <- [[0x7F80, 0], [0x7FC0, 0], [0xFF80, 0]],
        do: assert(match?({:error, _}, Value.decode(bytes, :float32)))

    assert {:error, _} = Value.encode(1, :unknown)
    assert {:error, _} = Value.decode([1], :uint16, :invalid)
    assert {:error, _} = Value.encode(1, :uint16, byte_order: :middle)
    assert {:error, _} = Value.encode(1, :uint16, [:not_keyword])
  end

  property "32-bit integers roundtrip in every order" do
    check all(
            value <- integer(-2_147_483_648..2_147_483_647),
            byte <- member_of([:big, :little]),
            word <- member_of([:big, :little])
          ) do
      opts = [byte_order: byte, word_order: word]
      assert {:ok, registers} = Value.encode(value, :int32, opts)
      assert {:ok, ^value} = Value.decode(registers, :int32, opts)
    end
  end
end
