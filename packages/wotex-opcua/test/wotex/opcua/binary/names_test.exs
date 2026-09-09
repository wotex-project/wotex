defmodule Wotex.OPCUA.Binary.NamesTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.OPCUA.{Address, Binary, Error}
  alias Wotex.OPCUA.Binary.Names

  @moduletag requirement_ids: ["WOP-S01", "WOP-N02", "WOP-V01", "WOP-V04"]

  test "all four LocalizedText masks preserve null, empty, Unicode and embedded NUL" do
    for locale <- [nil, "", "sv-SE", "x\0y"], text <- [nil, "", "räv", "\0"] do
      value = %{locale: locale, text: text}
      mask = if(is_nil(locale), do: 0, else: 1) + if(is_nil(text), do: 0, else: 2)
      assert {:ok, <<^mask, _::binary>> = bytes} = Binary.encode_localized_text(value)
      assert {:ok, ^value, "tail"} = Binary.decode_localized_text(bytes <> "tail")
    end

    assert {:ok, <<0>>} = Binary.encode_localized_text(%{locale: nil, text: nil})

    assert {:ok, <<3, 0::32-little, 0::32-little>>} =
             Binary.encode_localized_text(%{locale: "", text: ""})

    assert {:ok, %{locale: nil, text: nil}, "tail"} =
             Binary.decode_localized_text(<<3, -1::32-little-signed, -1::32-little-signed, "tail">>)
  end

  test "QualifiedName preserves UInt16 namespace and nullable text at both byte bounds" do
    maximum = String.duplicate("x", 65_536)

    for ns <- [0, 65_535], name <- [nil, "", "x\0y", maximum] do
      value = %{namespace: ns, name: name}
      assert {:ok, bytes} = Binary.encode_qualified_name(value)
      assert {:ok, ^value, <<99>>} = Binary.decode_qualified_name(bytes <> <<99>>)
    end

    assert {:ok, <<255, 255, -1::32-little-signed>>} =
             Binary.encode_qualified_name(%{namespace: 65_535, name: nil})

    assert {:ok, bytes} = Binary.encode_localized_text(%{locale: maximum, text: maximum})
    assert {:ok, %{locale: ^maximum, text: ^maximum}, <<>>} = Binary.decode_localized_text(bytes)
  end

  test "ExpandedNodeId retains every identifier kind, independent flags and remote server index" do
    for input <- [
          "i=1",
          "ns=2;i=500",
          "ns=65535;i=4294967295",
          "ns=2;s=a;b?x=%20",
          "ns=3;g=00112233-4455-6677-8899-aabbccddeeff",
          "ns=4;b=AP8=",
          "ns=0;s="
        ],
        server <- [0, 4_294_967_295] do
      {:ok, node} = Address.new(input)
      value = %{node_id: node, namespace_uri: nil, server_index: server}
      assert {:ok, bytes} = Binary.encode_expanded_node_id(value)
      assert {:ok, ^value, "tail"} = Binary.decode_expanded_node_id(bytes <> "tail")

      for uri <- ["urn:example:source", String.duplicate("x", 4096)] do
        value = %{value | node_id: %{node | namespace: 0}, namespace_uri: uri}
        assert {:ok, bytes} = Binary.encode_expanded_node_id(value)
        assert {:ok, ^value, "tail"} = Binary.decode_expanded_node_id(bytes <> "tail")
      end
    end

    # Part 6 URI presence makes the encoded numeric namespace immaterial.
    assert {:ok, %{node_id: %Address{namespace: 0}, namespace_uri: "urn:x", server_index: 2},
            "tail"} =
             Binary.decode_expanded_node_id(
               <<0xC1, 99, 1::16-little, 5::32-little, "urn:x", 2::32-little, "tail">>
             )
  end

  test "maximum ExpandedNodeId retains an arbitrarily larger unconsumed tail without copying it" do
    maximum = String.duplicate("x", 4096)
    tail = :binary.copy(<<0xFF>>, 2_097_152)
    value = %{node_id: {65_535, maximum}, namespace_uri: nil, server_index: 4_294_967_295}
    assert {:ok, bytes} = Binary.encode_expanded_node_id(value)

    assert {:ok, %{node_id: %Address{identifier: ^maximum}}, ^tail} =
             Binary.decode_expanded_node_id(bytes <> tail)
  end

  test "structured encoders reject unknown or missing keys, improper values and numeric overflow" do
    invalid_text = [<<255>>, String.duplicate("x", 65_537), 1, []]

    for input <- invalid_text do
      assert {:error, %Error{}} = Binary.encode_qualified_name(%{namespace: 0, name: input})
      assert {:error, %Error{}} = Binary.encode_localized_text(%{locale: input, text: nil})
      assert {:error, %Error{}} = Binary.encode_localized_text(%{locale: nil, text: input})
    end

    for ns <- [-1, 65_536, 0.0, nil] do
      assert {:error, %Error{code: :invalid_value}} =
               Binary.encode_qualified_name(%{namespace: ns, name: "x"})
    end

    for {kind, valid} <- [
          qualified_name: %{namespace: 0, name: nil},
          localized_text: %{locale: nil, text: nil},
          expanded_node_id: %{node_id: "i=0", namespace_uri: nil, server_index: 0}
        ] do
      for invalid <- [
            nil,
            [],
            Map.put(valid, :extra, 1) | Enum.map(Map.keys(valid), &Map.delete(valid, &1))
          ] do
        assert {:error, %Error{code: :invalid_value}} = Names.encode(kind, invalid)
      end
    end

    for uri <- ["", <<255>>, String.duplicate("x", 4097), 1, []] do
      assert {:error, %Error{code: :invalid_value}} =
               Binary.encode_expanded_node_id(%{
                 node_id: "i=1",
                 namespace_uri: uri,
                 server_index: 0
               })
    end

    for server <- [-1, 4_294_967_296, 0.0, nil] do
      assert {:error, %Error{code: :invalid_value}} =
               Binary.encode_expanded_node_id(%{
                 node_id: "i=1",
                 namespace_uri: nil,
                 server_index: server
               })
    end

    assert {:error, %Error{code: :invalid_value}} =
             Binary.encode_expanded_node_id(%{
               node_id: "ns=2;i=1",
               namespace_uri: "urn:x",
               server_index: 0
             })

    assert {:error, %Error{code: :invalid_node_id}} =
             Binary.encode_expanded_node_id(%{node_id: "bad", namespace_uri: nil, server_index: 0})

    assert {:error, %Error{code: :invalid_value}} = Names.encode(:unknown, %{})
  end

  test "each truncated structure and invalid field mask fails with a finite structured error" do
    values = [
      qualified_name: %{namespace: 2, name: "abc"},
      localized_text: %{locale: "sv", text: "abc"},
      expanded_node_id: %{node_id: "ns=0;s=abc", namespace_uri: "urn:x", server_index: 1}
    ]

    for {kind, value} <- values do
      {:ok, bytes} = Names.encode(kind, value)

      for size <- 0..(byte_size(bytes) - 1) do
        assert {:error, %Error{effect: :none, details: %{}}} =
                 Names.decode(kind, binary_part(bytes, 0, size))
      end
    end

    for mask <- 4..255 do
      assert {:error, %Error{code: :invalid_binary}} =
               Binary.decode_localized_text(<<mask, 0::64>>)
    end

    for mask <- 0..255, Bitwise.band(mask, 0x3F) > 5 do
      assert {:error, %Error{code: :invalid_node_id}} =
               Binary.decode_expanded_node_id(<<mask, 0::64>>)
    end

    for length <- [-2, -1, 0, 4097] do
      assert {:error, %Error{}} =
               Binary.decode_expanded_node_id(<<0x80, 1, length::32-little-signed, 0::32>>)
    end

    assert {:error, %Error{code: :invalid_utf8}} =
             Binary.decode_expanded_node_id(<<0x80, 1, 1::32-little, 255>>)

    assert {:error, %Error{code: :invalid_binary}} = Names.decode(:unknown, <<>>)
  end

  property "all identity decoders terminate for arbitrary bytes and preserve only an input suffix" do
    check all(bytes <- binary(max_length: 1024)) do
      for kind <- [:qualified_name, :localized_text, :expanded_node_id] do
        case Names.decode(kind, bytes) do
          {:ok, _, tail} ->
            assert byte_size(tail) <= byte_size(bytes)
            assert binary_part(bytes, byte_size(bytes) - byte_size(tail), byte_size(tail)) == tail

          {:error, %Error{effect: :none, details: %{}}} ->
            :ok
        end
      end
    end
  end
end
