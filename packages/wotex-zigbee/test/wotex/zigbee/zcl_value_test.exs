defmodule Wotex.Zigbee.ZCLValueTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.Error
  alias Wotex.Zigbee.ZCL.Value

  @profile Path.expand("../../support/profiles/zcl-global-r8.json", __DIR__)

  test "encoding agrees with pinned endpoint and non-value bytes rather than a round-trip oracle" do
    profile = :json.decode(File.read!(@profile))

    for type <- profile["adoption"]["types"] do
      vectors = [
        {:null, type["non_value_hex"]},
        {type["minimum"], type["minimum_hex"]},
        {type["maximum"], type["maximum_hex"]}
      ]

      for {value, hex} <- vectors, hex != nil do
        expected = Base.decode16!(hex, case: :mixed)
        assert {:ok, ^expected} = Value.encode(type["id"], value)
      end

      if Map.has_key?(type, "full_range_non_value") do
        raw = Base.decode16!(type["non_value_hex"], case: :mixed)

        assert {:error, %Error{kind: :invalid_value}} =
                 Value.encode(type["id"], type["full_range_non_value"])

        assert {:ok, ^raw} = Value.encode(type["id"], type["full_range_non_value"], true)
        assert {:error, _} = Value.encode(type["id"], :null, true)
      end
    end
  end

  test "integer bounds, forbidden booleans, unknown types and policy errors do not wrap or coerce" do
    for {type, invalid} <- [
          {0x20, -1},
          {0x20, 256},
          {0x21, 65_536},
          {0x23, 0x100000000},
          {0x28, -129},
          {0x28, 128},
          {0x29, -32_769},
          {0x29, 32_768},
          {0x10, 0},
          {0x10, 1},
          {0x10, 2},
          {0x10, "true"},
          {0x41, 1},
          {0x42, nil},
          {0xF0, <<0::64>>}
        ] do
      assert {:error, %Error{kind: :invalid_value}} = Value.encode(type, invalid)
    end

    for type <- [0x10, 0x41, 0x42], do: assert({:error, _} = Value.encode(type, :null, true))
    assert {:error, _} = Value.encode(0x20, 1, "credential-canary")
    assert {:error, _} = Value.encode(0x42, :binary.copy("x", 65))
    raw = :binary.copy(<<0xFF>>, 64)
    assert {:ok, <<64, ^raw::binary>>} = Value.encode(0x42, raw)
  end

  test "standalone decode validates byte type, length and policy while retaining unknown remainder" do
    assert {:ok, :analog} = Value.category(0x29)
    assert {:ok, :discrete} = Value.category(0x42)
    assert {:error, _} = Value.category(0xF0)
    assert {:ok, {:unsupported, 0xF0}, <<1, 2>>, <<>>} = Value.decode(0xF0, <<1, 2>>)
    assert {:ok, 255, <<255>>, <<42>>} = Value.decode(0x20, <<255, 42>>, true)

    for {type, bytes, policy} <- [
          {-1, <<>>, false},
          {256, <<>>, false},
          {nil, <<>>, false},
          {0x20, nil, false},
          {0x20, <<1>>, nil},
          {0x20, :binary.copy(<<0>>, 129), false},
          {0x10, <<1>>, true}
        ] do
      assert {:error, %Error{kind: :invalid_frame}} = Value.decode(type, bytes, policy)
    end
  end
end
