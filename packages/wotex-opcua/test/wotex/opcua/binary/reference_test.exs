defmodule Wotex.OPCUA.Binary.ReferenceTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.OPCUA.{Address, Binary, Error}

  @moduletag requirement_ids: ["WOP-N02", "WOP-S01", "WOP-V01", "WOP-V04"]

  test "complete references retain namespace, locale, class, direction and both expanded identities" do
    for class <- [0, 1, 2, 4, 8, 16, 32, 64, 128], direction <- [false, true] do
      value = %{reference() | node_class: class, is_forward: direction}
      assert {:ok, bytes} = Binary.encode_reference_description(value)
      assert {:ok, ^value, "tail"} = Binary.decode_reference_description(bytes <> "tail")
    end
  end

  test "every wire direction byte decodes with Boolean semantics and canonical reencoding" do
    forward = reference()
    {:ok, prefix} = Binary.encode_node_id(forward.reference_type_id)
    {:ok, canonical_forward} = Binary.encode_reference_description(forward)
    prefix_size = byte_size(prefix)
    <<^prefix::binary-size(^prefix_size), 1, suffix::binary>> = canonical_forward

    for byte <- 0..255 do
      expected = %{forward | is_forward: byte != 0}
      canonical = if byte == 0, do: 0, else: 1

      assert {:ok, ^expected, "tail"} =
               Binary.decode_reference_description(<<prefix::binary, byte, suffix::binary, "tail">>)

      assert {:ok, <<^prefix::binary-size(^prefix_size), ^canonical, ^suffix::binary>>} =
               Binary.encode_reference_description(expected)
    end
  end

  test "missing, extra, mistyped and unsupported reference fields fail before any transport" do
    valid = reference()

    invalid = [
      nil,
      [],
      Map.put(valid, :extra, 1) | Enum.map(Map.keys(valid), &Map.delete(valid, &1))
    ]

    for value <- invalid do
      assert {:error, %Error{code: :invalid_value}} = Binary.encode_reference_description(value)
    end

    for class <- [-1, 3, 255, 256, 4_294_967_296, 0.0] do
      assert {:error, %Error{code: :invalid_value}} =
               Binary.encode_reference_description(%{valid | node_class: class})
    end

    for key <- [
          :reference_type_id,
          :is_forward,
          :node_id,
          :browse_name,
          :display_name,
          :type_definition
        ] do
      assert {:error, %Error{effect: :none}} =
               Binary.encode_reference_description(Map.put(valid, key, :invalid))
    end
  end

  test "every truncated field and invalid wire NodeClass is rejected without consuming a suffix" do
    value = reference()
    {:ok, bytes} = Binary.encode_reference_description(value)

    for size <- 0..(byte_size(bytes) - 1) do
      assert {:error, %Error{effect: :none}} =
               Binary.decode_reference_description(binary_part(bytes, 0, size))
    end

    {:ok, definition} = Binary.encode_expanded_node_id(value.type_definition)
    prefix_size = byte_size(bytes) - 4 - byte_size(definition)
    prefix = binary_part(bytes, 0, prefix_size)
    rest = definition

    for class <- [3, 255, 256, 4_294_967_295] do
      assert {:error, %Error{code: :invalid_binary}} =
               Binary.decode_reference_description(
                 <<prefix::binary, class::32-little, rest::binary>>
               )
    end

    for input <- [nil, [], %{}, 1] do
      assert {:error, %Error{}} = Binary.decode_reference_description(input)
    end
  end

  property "arbitrary reference bytes cannot escape the pure boundary" do
    check all(bytes <- binary(max_length: 1024)) do
      assert match?({:ok, %{}, _}, Binary.decode_reference_description(bytes)) or
               match?({:error, %Error{}}, Binary.decode_reference_description(bytes))
    end
  end

  defp reference do
    {:ok, type} = Address.new("i=47")
    {:ok, target} = Address.new("ns=0;s=a;b?c=%20")
    {:ok, null} = Address.new("i=0")

    %{
      reference_type_id: type,
      is_forward: true,
      node_id: %{node_id: target, namespace_uri: "urn:example:remote", server_index: 2},
      browse_name: %{namespace: 65_535, name: "temperature"},
      display_name: %{locale: "sv-SE", text: "temperatur"},
      node_class: 2,
      type_definition: %{node_id: null, namespace_uri: nil, server_index: 0}
    }
  end
end
