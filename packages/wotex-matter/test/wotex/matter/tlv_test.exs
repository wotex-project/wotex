defmodule Wotex.Matter.TLVTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.Matter.{Address, TLV}

  test "SDK TLV scalar vectors preserve explicit widths and all tag controls" do
    values = [
      i8: -128,
      i16: -32_768,
      i32: -2_147_483_648,
      i64: -9_223_372_036_854_775_808,
      u8: 255,
      u16: 65_535,
      u32: 4_294_967_295,
      u64: 18_446_744_073_709_551_615,
      boolean: false,
      boolean: true,
      float32: 1.5,
      float64: -1.5,
      utf8: "héllo",
      bytes: <<255, 0>>,
      null: nil,
      utf8: String.duplicate("x", 256)
    ]

    tags = [
      :anonymous,
      {:context, 255},
      {:common, 42},
      {:common, 70_000},
      {:implicit, 42},
      {:implicit, 70_000},
      {:qualified, 1, 2, 42},
      {:qualified, 1, 2, 70_000}
    ]

    for {type, value} <- values, tag <- tags do
      element = %{tag: tag, type: type, value: value}
      assert {:ok, bytes} = TLV.encode([element])
      assert {:ok, [^element]} = TLV.decode(bytes)
    end

    assert {:ok, <<0x24, 1, 42>>} = TLV.encode([%{tag: {:context, 1}, type: :u8, value: 42}])

    for width <- [1, 2, 4, 8] do
      control = 12 + %{1 => 0, 2 => 1, 4 => 2, 8 => 3}[width]
      assert {:ok, [%{value: "x"}]} = TLV.decode(<<control, 1::little-size(width * 8), "x">>)
    end
  end

  test "containers retain unknown context tags and enforce structure and array rules" do
    child = %{tag: {:context, 250}, type: :utf8, value: "future"}
    anonymous = %{child | tag: :anonymous}

    for {type, children} <- [structure: [child], array: [anonymous], list: [child, anonymous]] do
      values = [%{tag: :anonymous, type: type, value: children}]
      assert {:ok, bytes} = TLV.encode(values)
      assert {:ok, ^values} = TLV.decode(bytes)
    end

    for values <- [
          [%{tag: :anonymous, type: :structure, value: [child, child]}],
          [%{tag: :anonymous, type: :array, value: [child]}],
          [%{tag: :anonymous, type: :structure, value: [anonymous]}],
          [%{tag: {:context, 256}, type: :u8, value: 1}],
          [%{tag: :anonymous, type: :u8, value: 256}],
          [%{tag: :anonymous, type: :utf8, value: <<255>>}],
          [nil],
          nil
        ],
        do: assert(match?({:error, _}, TLV.encode(values)))

    for bytes <- [
          <<24>>,
          <<21>>,
          <<31>>,
          <<0xE4>>,
          <<12, 2, 1>>,
          <<12, 1, 255>>,
          <<11, 0, 0, 0, 0, 0, 0, 240, 127>>,
          :binary.copy(<<21>>, 9) <> :binary.copy(<<24>>, 9),
          :binary.copy(<<20>>, 1025),
          :binary.copy(<<20>>, 65_537)
        ],
        do: assert(match?({:error, _}, TLV.decode(bytes)))
  end

  test "operational paths reject reserved and overflowing identifiers" do
    base = %{fabric_id: 1, node_id: 1, endpoint: 1, cluster: 6, member: 0}
    assert {:ok, _} = Address.new(base)

    for {key, value} <- [
          fabric_id: 0,
          node_id: 0,
          endpoint: 65_535,
          cluster: 0xFFFF_0000,
          cluster: 0x8000,
          member: 0xFFFF_FFFF
        ],
        do: assert(match?({:error, _}, Address.new(Map.put(base, key, value))))

    assert {:error, _} = Address.new(nil)
    assert {:error, _} = Address.validate_message(Map.put(base, :type, :write))
  end

  property "arbitrary TLV bytes produce bounded structured outcomes" do
    check all(bytes <- binary(max_length: 256)) do
      assert match?({:ok, _}, TLV.decode(bytes)) or match?({:error, _}, TLV.decode(bytes))
    end
  end
end
