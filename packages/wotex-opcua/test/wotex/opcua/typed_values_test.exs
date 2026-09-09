defmodule Wotex.OPCUA.TypedValuesTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.OPCUA.{Address, Binary, Error}
  alias Wotex.OPCUA.Binary.Element

  @moduletag requirement_ids: ["WOP-S01", "WOP-N02", "WOP-V01", "WOP-V02", "WOP-V03", "WOP-V04"]
  @types [
    {"Null", nil},
    {"Boolean", false},
    {"SByte", -128},
    {"Byte", 255},
    {"Int16", -32_768},
    {"UInt16", 65_535},
    {"Int32", -2_147_483_648},
    {"UInt32", 4_294_967_295},
    {"Int64", -9_223_372_036_854_775_808},
    {"UInt64", 18_446_744_073_709_551_615},
    {"Float", -0.0},
    {"Double", -0.0},
    {"String", "x\0é"},
    {"DateTime", 132_541_920_000_000_001},
    {"Guid", "00112233-4455-6677-8899-aabbccddeeff"},
    {"ByteString", <<0, 255>>},
    {"NodeId", %Address{namespace: 65_535, kind: :numeric, identifier: 4_294_967_295}},
    {"ExpandedNodeId",
     %{
       node_id: %Address{namespace: 0, kind: :string, identifier: "x"},
       namespace_uri: "urn:x",
       server_index: 2
     }},
    {"StatusCode", 0xFFFFFFFF},
    {"QualifiedName", %{namespace: 3, name: nil}},
    {"LocalizedText", %{locale: nil, text: ""}},
    {"ExtensionObject",
     %{
       encoding_id: %Address{namespace: 2, kind: :numeric, identifier: 5000},
       encoding: "binary",
       body: <<255, 0>>
     }}
  ]

  for {type, payload} <- @types do
    test "#{type} scalar and explicit arrays retain their declared values and tails" do
      type = unquote(type)
      payload = unquote(Macro.escape(payload))

      shapes =
        if type == "Null",
          do: [{false, payload}],
          else: [{false, payload}, {true, nil}, {true, []}, {true, [payload, payload]}]

      for {array, value} <- shapes do
        envelope = %{type: type, array: array, value: value}
        assert {:ok, bytes} = Binary.encode_variant(envelope)
        assert {:ok, ^envelope, "tail"} = Binary.decode_variant(bytes <> "tail")
      end
    end
  end

  test "WOP-V01 GUID byte order, exact adjacent 100 ns ticks and signed floating zero are preserved" do
    guid =
      <<14, 0x33, 0x22, 0x11, 0, 0x55, 0x44, 0x77, 0x66, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE,
        0xFF>>

    assert {:ok, ^guid} =
             Binary.encode_variant(%{
               type: "Guid",
               array: false,
               value: "00112233-4455-6677-8899-aabbccddeeff"
             })

    for tick <- [
          -9_223_372_036_854_775_808,
          132_541_920_000_000_001,
          132_541_920_000_000_002,
          9_223_372_036_854_775_807
        ] do
      envelope = %{type: "DateTime", array: false, value: tick}
      assert {:ok, <<13, ^tick::64-little-signed>> = bytes} = Binary.encode_variant(envelope)
      assert {:ok, ^envelope, <<>>} = Binary.decode_variant(bytes)
    end

    for {type, bits, size} <- [{"Float", 0x80000000, 32}, {"Double", 0x8000000000000000, 64}] do
      assert {:ok, bytes} = Binary.encode_variant(%{type: type, array: false, value: -0.0})
      assert binary_part(bytes, 1, byte_size(bytes) - 1) == <<bits::little-size(size)>>
      assert {:ok, %{value: value}, <<>>} = Binary.decode_variant(bytes)
      assert <<value::little-float-size(size)>> == <<bits::little-size(size)>>
    end
  end

  test "WOP-V02 null and empty byte bodies and opaque ExtensionObject encodings remain distinct" do
    {:ok, id} = Address.new("ns=2;i=60000")

    for type <- ["String", "ByteString"], payload <- [nil, ""] do
      value = %{type: type, array: false, value: payload}
      assert {:ok, bytes} = Binary.encode_variant(value)
      assert {:ok, ^value, <<>>} = Binary.decode_variant(bytes)
    end

    for {encoding, bodies} <- [
          {"none", [nil]},
          {"binary", [nil, "", <<255>>]},
          {"xml", [nil, "", "<x>é</x>"]}
        ],
        body <- bodies do
      value = %{
        type: "ExtensionObject",
        array: false,
        value: %{encoding_id: id, encoding: encoding, body: body}
      }

      assert {:ok, bytes} = Binary.encode_variant(value)
      assert {:ok, ^value, "tail"} = Binary.decode_variant(bytes <> "tail")
    end
  end

  test "WOP-V02 flat dimensions use exact positive products and two through eight axes" do
    for dimensions <- [[2, 3], [1, 1], List.duplicate(1, 8), [32, 32]] do
      values = List.duplicate(1, Enum.product(dimensions))
      value = %{type: "Int32", array: true, value: values, dimensions: dimensions}
      assert {:ok, <<0xC6, _::binary>> = bytes} = Binary.encode_variant(value)
      assert {:ok, ^value, "tail"} = Binary.decode_variant(bytes <> "tail")
    end

    base = %{type: "Int32", array: true, value: [1, 2]}

    for dimensions <- [
          nil,
          [],
          [2],
          [1, 3],
          [0, 2],
          [-1, -2],
          [1.0, 2],
          [1, 1, 1, 1, 1, 1, 1, 1, 2],
          [1025, 1],
          [1 | 2]
        ] do
      assert {:error, %Error{code: :invalid_value}} =
               Binary.encode_variant(Map.put(base, :dimensions, dimensions))
    end

    for value <- [%{base | value: nil}, %{base | value: []}, %{base | array: false, value: 1}] do
      assert {:error, %Error{code: :invalid_value}} =
               Binary.encode_variant(Map.put(value, :dimensions, [1, 1]))
    end
  end

  test "WOP-V04 element count and aggregate byte budgets are exact and do not include an input tail" do
    scalar = %{type: "Byte", array: true, value: List.duplicate(0, 1024)}
    assert {:ok, _} = Binary.encode_variant(scalar)

    assert {:error, %Error{code: :invalid_value}} =
             Binary.encode_variant(%{scalar | value: List.duplicate(0, 1025)})

    assert {:error, %Error{code: :invalid_value}} =
             Binary.encode_variant(%{scalar | value: [0 | :improper]})

    assert {:error, %Error{code: :invalid_value}} =
             Binary.encode_variant(%{scalar | value: :not_a_list})

    large = String.duplicate("x", 65_536)
    final = String.duplicate("x", 65_467)
    value = %{type: "String", array: true, value: Enum.reverse([final | List.duplicate(large, 15)])}
    assert {:ok, bytes} = Binary.encode_variant(value)
    assert byte_size(bytes) == 1_048_576
    tail = :binary.copy(<<255>>, 1_048_576)
    assert {:ok, ^value, ^tail} = Binary.decode_variant(bytes <> tail)
    oversized = %{value | value: Enum.reverse([final <> "x" | List.duplicate(large, 15)])}
    assert {:error, %Error{code: :invalid_value}} = Binary.encode_variant(oversized)

    prefix = binary_part(bytes, 0, byte_size(bytes) - 65_471)
    oversized_bytes = prefix <> <<65_468::32-little>> <> final <> "x"
    assert {:error, %Error{code: :invalid_binary}} = Binary.decode_variant(oversized_bytes)
  end

  test "WOP-V04 invalid typed inputs reject missing flags, unknown keys, overflow and unsupported nested types" do
    base = %{type: "Int32", array: false, value: 1}

    for invalid <- [
          nil,
          [],
          %{},
          Map.delete(base, :type),
          Map.delete(base, :array),
          Map.delete(base, :value),
          Map.put(base, :extra, 1),
          %{base | array: 0},
          %{base | value: 2_147_483_648},
          %{base | value: [1]},
          %{type: "Null", array: true, value: nil},
          %{type: "Null", array: false, value: 0}
        ] do
      assert {:error, %Error{code: :invalid_value}} = Binary.encode_variant(invalid)
    end

    for type <- [
          "Reserved",
          "XmlElement",
          "DataValue",
          "Variant",
          "DiagnosticInfo",
          "unknown",
          :Int32,
          nil
        ] do
      assert {:error, %Error{code: :unsupported_type}} = Binary.encode_variant(%{base | type: type})
    end

    for value <- [
          nil,
          "",
          "00112233-4455-6677-8899-AABBCCDDEEFF",
          "invalid-invalid-invalid-invalid-xxxx",
          String.duplicate("x", 36)
        ] do
      assert {:error, %Error{code: :invalid_value}} =
               Binary.encode_variant(%{type: "Guid", array: false, value: value})
    end

    for value <- [
          nil,
          %{encoding_id: "i=1", encoding: "none", body: ""},
          %{encoding_id: "i=1", encoding: "unknown", body: nil},
          %{encoding_id: "i=1", encoding: "xml", body: <<255>>},
          %{encoding_id: "bad", encoding: "binary", body: nil},
          %{encoding_id: "i=1", encoding: "binary", body: nil, extra: true}
        ] do
      assert {:error, %Error{}} =
               Binary.encode_variant(%{type: "ExtensionObject", array: false, value: value})
    end

    assert {:error, %Error{code: :unsupported_type}} = Element.encode(26, nil)
    assert {:error, %Error{code: :invalid_binary}} = Element.decode(64, <<>>)
    assert {:error, %Error{code: :invalid_binary}} = Element.decode(0, nil)
    assert {:error, %Error{code: :invalid_binary}} = Element.name(0.0)
  end

  test "WOP-V04 every scalar truncation and unsupported selector returns a structured error" do
    for {type, payload} <- @types do
      {:ok, bytes} = Binary.encode_variant(%{type: type, array: false, value: payload})

      for size <- 0..(byte_size(bytes) - 1) do
        assert {:error, %Error{effect: :none}} = Binary.decode_variant(binary_part(bytes, 0, size))
      end
    end

    for id <- [16, 23, 24, 25] do
      assert {:error, %Error{code: :unsupported_type}} = Binary.decode_variant(<<id>>)
    end

    for id <- 32..63 do
      assert {:error, %Error{code: :invalid_binary}} = Binary.decode_variant(<<id>>)
    end

    for bytes <- [
          <<0x80, -1::32-little-signed>>,
          <<0x46, 1::32-little>>,
          <<0x86, -2::32-little-signed>>,
          <<0x86, 1025::32-little>>,
          <<0x86, 1::32-little>>,
          <<22, 0, 1, 3>>,
          <<0xC6, 0::32-little, 2::32-little, 1::32-little, 1::32-little>>,
          <<0xC6, -1::32-little-signed, 2::32-little, 1::32-little, 1::32-little>>
        ] do
      assert {:error, %Error{code: :invalid_binary}} = Binary.decode_variant(bytes)
    end

    for dimensions <- [
          <<1::32-little, 2::32-little>>,
          <<2::32-little, 1::32-little, 3::32-little>>,
          <<2::32-little, 0::32-little, 2::32-little>>,
          <<2::32-little, 1::32-little>>
        ] do
      assert {:error, %Error{code: :invalid_binary}} =
               Binary.decode_variant(
                 <<0xC6, 2::32-little, 1::32-little, 2::32-little, dimensions::binary>>
               )
    end

    assert {:error, %Error{code: :invalid_binary}} = Binary.decode_variant(nil)
  end

  test "WOP-V02 future Variant IDs retain numeric identity and null, empty, opaque array payloads" do
    for id <- 26..31,
        {body, value} <- [
          {<<-1::32-little-signed>>, nil},
          {<<0::32-little>>, ""},
          {<<2::32-little, 0xDE, 0xAD>>, <<0xDE, 0xAD>>}
        ] do
      expected = %{type: "Reserved", type_id: id, array: false, value: value}
      assert {:ok, ^expected, "tail"} = Binary.decode_variant(<<id, body::binary, "tail">>)
      assert {:error, %Error{code: :unsupported_type}} = Binary.encode_variant(expected)
      expected = %{expected | array: true, value: [value, value]}

      assert {:ok, ^expected, <<>>} =
               Binary.decode_variant(<<id + 0x80, 2::32-little, body::binary, body::binary>>)
    end
  end

  test "WOP-V03 masks preserve presence, Good/Uncertain/Bad status and tick endpoints" do
    null = %{type: "Null", array: false, value: nil}

    value = %{
      has_value: true,
      value: null,
      status: 0xC0000000,
      source_timestamp: -9_223_372_036_854_775_808,
      source_picoseconds: 9999,
      server_timestamp: 9_223_372_036_854_775_807,
      server_picoseconds: 0
    }

    bytes =
      <<63, 0, 0xC0000000::32-little, -9_223_372_036_854_775_808::64-little-signed, 9999::16-little,
        9_223_372_036_854_775_807::64-little-signed, 0::16-little>>

    assert {:ok, ^bytes} = Binary.encode_data_value(value)

    assert {:ok, ^value, "tail"} = Binary.decode_data_value(bytes <> "tail")

    for present <- [false, true],
        status <- [0, 0x40000000, 0x80000000, 0xFFFFFFFF],
        source <- [false, true],
        server <- [false, true],
        fractions <- [false, true] do
      expected = %{has_value: present, status: status}
      expected = if present, do: Map.put(expected, :value, null), else: expected

      expected =
        if source, do: Map.put(expected, :source_timestamp, 132_541_920_000_000_001), else: expected

      expected =
        if server, do: Map.put(expected, :server_timestamp, 132_541_920_000_000_002), else: expected

      expected =
        if source and fractions, do: Map.put(expected, :source_picoseconds, 1), else: expected

      expected =
        if server and fractions, do: Map.put(expected, :server_picoseconds, 2), else: expected

      assert {:ok, bytes} = Binary.encode_data_value(expected)
      assert {:ok, ^expected, "tail"} = Binary.decode_data_value(bytes <> "tail")
    end

    assert {:ok, <<0>>} = Binary.encode_data_value(%{has_value: false, status: 0})
    assert {:ok, <<1, 0>>} = Binary.encode_data_value(%{has_value: true, value: null, status: 0})
  end

  test "WOP-V03 fractions clamp independently and orphan fractions are consumed without becoming metadata" do
    expected = %{
      has_value: false,
      status: 0,
      source_timestamp: 1,
      source_picoseconds: 9999,
      server_timestamp: 2,
      server_picoseconds: 9999
    }

    assert {:ok, ^expected, "tail"} =
             Binary.decode_data_value(
               <<60, 1::64-little-signed, 10_000::16-little, 2::64-little-signed, 65_535::16-little,
                 "tail">>
             )

    assert {:ok, %{has_value: false, status: 0}, "tail"} =
             Binary.decode_data_value(<<48, 1::16-little, 65_535::16-little, "tail">>)
  end

  test "WOP-V04 DataValue field validation and every truncation fail without hidden defaults" do
    base = %{
      has_value: true,
      value: %{type: "Boolean", array: false, value: false},
      status: 1,
      source_timestamp: 1,
      source_picoseconds: 1,
      server_timestamp: 2,
      server_picoseconds: 2
    }

    {:ok, bytes} = Binary.encode_data_value(base)

    for size <- 0..(byte_size(bytes) - 1) do
      assert {:error, %Error{effect: :none}} = Binary.decode_data_value(binary_part(bytes, 0, size))
    end

    for invalid <- [
          nil,
          [],
          Map.delete(base, :value),
          Map.delete(base, :has_value),
          Map.delete(base, :status),
          Map.delete(base, :source_timestamp),
          Map.delete(base, :server_timestamp),
          Map.put(base, :unknown, 1),
          %{base | has_value: false},
          %{base | has_value: 1},
          %{base | value: nil},
          %{base | status: -1},
          %{base | status: 4_294_967_296},
          %{base | source_timestamp: 1.0},
          %{base | server_timestamp: 9_223_372_036_854_775_808},
          %{base | source_picoseconds: -1},
          %{base | source_picoseconds: 10_000},
          %{base | server_picoseconds: nil}
        ] do
      assert {:error, %Error{code: :invalid_value}} = Binary.encode_data_value(invalid)
    end

    assert {:error, %Error{code: :invalid_value}} =
             Binary.encode_data_value(%{has_value: false, status: 0, unknown: 1})

    assert {:error, %Error{code: :invalid_binary}} = Binary.decode_data_value(nil)

    for mask <- 64..255 do
      assert {:error, %Error{code: :invalid_binary}} = Binary.decode_data_value(<<mask, 0::128>>)
    end
  end

  test "WOP-V04 DataValue includes metadata in the exact 1 MiB consumed-value budget" do
    values =
      Enum.reverse([
        String.duplicate("x", 65_466) | List.duplicate(String.duplicate("x", 65_536), 15)
      ])

    variant = %{type: "String", array: true, value: values}
    value = %{has_value: true, value: variant, status: 0}
    assert {:ok, bytes} = Binary.encode_data_value(value)
    assert byte_size(bytes) == 1_048_576
    assert {:ok, ^value, "tail"} = Binary.decode_data_value(bytes <> "tail")

    assert {:error, %Error{code: :invalid_value}} =
             Binary.encode_data_value(Map.put(value, :source_timestamp, 0))

    <<1, body::binary>> = bytes

    assert {:error, %Error{code: :invalid_binary}} =
             Binary.decode_data_value(<<5, body::binary, 0::64-little-signed>>)
  end

  property "WOP-V04 typed decoders are total on arbitrary framed data" do
    check all(bytes <- binary(max_length: 4096)) do
      for decoder <- [&Binary.decode_variant/1, &Binary.decode_data_value/1] do
        case decoder.(bytes) do
          {:ok, _, tail} -> assert byte_size(tail) <= byte_size(bytes)
          {:error, %Error{effect: :none}} -> :ok
        end
      end
    end
  end
end
