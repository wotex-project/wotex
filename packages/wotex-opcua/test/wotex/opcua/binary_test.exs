defmodule Wotex.OPCUA.BinaryTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.OPCUA.{Address, Binary, Frame}

  test "scalar widths, null strings and tails are exact" do
    vectors = [
      sbyte: -128,
      byte: 255,
      int16: -32_768,
      uint16: 65_535,
      int32: -2_147_483_648,
      uint32: 4_294_967_295,
      int64: -9_223_372_036_854_775_808,
      uint64: 18_446_744_073_709_551_615,
      boolean: true,
      boolean: false,
      float: 1.5,
      double: -1.5,
      string: "héllo",
      bytestring: <<255, 0>>,
      string: nil,
      bytestring: nil,
      string: ""
    ]

    for {type, value} <- vectors do
      assert {:ok, bytes} = Binary.encode(type, value)
      assert {:ok, ^value, "tail"} = Binary.decode(type, bytes <> "tail")
    end

    assert {:ok, <<0, 128>>} = Binary.encode(:int16, -32_768)
    assert {:ok, <<255, 255, 255, 255>>} = Binary.encode(:string, nil)

    for {type, value} <- [
          byte: 256,
          sbyte: -129,
          boolean: 1,
          float: 1.0e100,
          string: <<255>>,
          string: String.duplicate("x", 65_537),
          unknown: 0
        ],
        do: assert(match?({:error, _}, Binary.encode(type, value)))

    for {type, bytes} <- [
          boolean: <<2>>,
          string: <<-2::32-little-signed>>,
          string: <<1::32-little, 255>>,
          double: <<0, 0, 0, 0, 0, 0, 240, 127>>,
          int32: <<0>>
        ],
        do: assert(match?({:error, _}, Binary.decode(type, bytes)))
  end

  test "all NodeId encodings and textual reserved characters round trip" do
    for input <- [
          "i=42",
          "ns=2;i=500",
          "ns=256;i=70000",
          "ns=2;s=a;b?x=%20",
          "ns=1;g=00112233-4455-6677-8899-aabbccddeeff",
          "ns=3;b=AP8=",
          {0, ""}
        ] do
      assert {:ok, node} = Address.new(input)
      assert {:ok, ^node} = Address.new(Address.to_string(node))
      assert {:ok, bytes} = Binary.encode_node_id(node)
      assert {:ok, ^node, "tail"} = Binary.decode_node_id(bytes <> "tail")
    end

    assert {:ok, <<0, 42>>} = Binary.encode_node_id("i=42")

    assert {:ok, <<4, 1, 0, 0x33, 0x22, 0x11, 0, 0x55, 0x44, 0x77, 0x66, _::binary>>} =
             Binary.encode_node_id("ns=1;g=00112233-4455-6677-8899-aabbccddeeff")

    for input <- [
          nil,
          "",
          "i=not-number",
          "i=-1",
          "b=???",
          "g=00112233445566778899aabbccddeeff",
          "ns=65536;i=1",
          {0, <<255>>},
          {0, String.duplicate("x", 4097)},
          %Address{namespace: 0, kind: :invalid, identifier: 0}
        ] do
      assert {:error, _} = Address.new(input)
      assert {:error, _} = Binary.encode_node_id(input)
    end

    for bytes <- [<<>>, <<255>>, <<3, 0, 0, -1::32-little-signed>>, <<5, 0, 0, 1, 0, 0, 0>>],
        do: assert(match?({:error, _}, Binary.decode_node_id(bytes)))

    assert {:error, _} = Address.validate_message(%{type: :write, node_id: "i=1"})
  end

  test "UA frame limits reject invalid headers before waiting for bodies" do
    assert :more = Frame.decode("HEL")
    assert :more = Frame.decode(<<"HELF", 12::32-little, 0>>)

    assert {:ok, %{type: "HEL", chunk: ?F, body: <<1, 2, 3, 4>>}, "tail"} =
             Frame.decode(<<"HELF", 12::32-little, 1, 2, 3, 4, "tail">>)

    for bytes <- [
          <<"BADF", 8::32-little>>,
          <<"HELC", 8::32-little>>,
          <<"MSGX", 8::32-little>>,
          <<"MSGF", 7::32-little>>,
          <<"MSGF", 1_048_577::32-little>>
        ],
        do: assert(match?({:error, _}, Frame.decode(bytes)))

    assert {:error, _} = Frame.decode(nil)
  end

  property "arbitrary input never escapes bounded binary parsers" do
    check all(bytes <- binary(max_length: 256)) do
      assert match?({:ok, _, _}, Binary.decode_node_id(bytes)) or
               match?({:error, _}, Binary.decode_node_id(bytes))

      result = Frame.decode(bytes)
      assert result == :more or match?({:ok, _, _}, result) or match?({:error, _}, result)
    end
  end
end
