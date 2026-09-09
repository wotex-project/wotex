defmodule Wotex.OPCUA.Binary.Element do
  @moduledoc """
  Encodes one element from the finite OPC UA Variant type profile.

  `Wotex.OPCUA.Binary.Variant` selects a type through this module's fixed table
  before processing a scalar or array. Integers retain their exact width,
  DateTime remains signed 100 ns ticks, GUIDs use canonical lowercase text, and
  NodeId values use `Wotex.OPCUA.Address`. Opaque ExtensionObjects retain their
  encoding identity and nullable body without loading or instantiating a type.

  Strings and byte bodies have the scalar codec's 65536-byte ceiling. Structured
  identities use the bounded name codecs. Reserved IDs 26 through 31 decode as
  ByteString payloads for the read-only Variant envelope; encoders reject those
  IDs. Unsupported known types and malformed selectors produce structured
  errors. This module owns no transport, clock, SDK memory or namespace lookup.
  """

  alias Wotex.OPCUA.{Address, Binary, Error}
  alias Wotex.OPCUA.Binary.Names

  @types [
    {0, "Null", :null},
    {1, "Boolean", :boolean},
    {2, "SByte", :sbyte},
    {3, "Byte", :byte},
    {4, "Int16", :int16},
    {5, "UInt16", :uint16},
    {6, "Int32", :int32},
    {7, "UInt32", :uint32},
    {8, "Int64", :int64},
    {9, "UInt64", :uint64},
    {10, "Float", :float},
    {11, "Double", :double},
    {12, "String", :string},
    {13, "DateTime", :int64},
    {14, "Guid", :guid},
    {15, "ByteString", :bytestring},
    {17, "NodeId", :node_id},
    {18, "ExpandedNodeId", :expanded_node_id},
    {19, "StatusCode", :uint32},
    {20, "QualifiedName", :qualified_name},
    {21, "LocalizedText", :localized_text},
    {22, "ExtensionObject", :extension_object}
  ]

  @doc "Looks up an explicit type name without converting input to atoms."
  @spec type(term()) :: {:ok, 0..22} | {:error, Error.t()}
  def type(name) do
    case List.keyfind(@types, name, 1) do
      {id, _, _} -> {:ok, id}
      nil -> error(:unsupported_type)
    end
  end

  @doc "Returns a supported wire type name or the read-only Reserved classification."
  @spec name(term()) :: {:ok, String.t()} | {:error, Error.t()}
  def name(id) when is_integer(id) and id in 26..31, do: {:ok, "Reserved"}

  def name(id) when is_integer(id) do
    case List.keyfind(@types, id, 0) do
      {_, name, _} -> {:ok, name}
      nil when id in [16, 23, 24, 25] -> error(:unsupported_type)
      nil -> error(:invalid_binary)
    end
  end

  def name(_), do: error(:invalid_binary)

  @doc "Encodes one element with explicit type, numeric and byte limits."
  @spec encode(non_neg_integer(), term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(0, nil), do: {:ok, <<>>}
  def encode(0, _), do: error(:invalid_value)
  def encode(14, value), do: encode_guid(value)
  def encode(17, value), do: Binary.encode_node_id(value)
  def encode(22, value), do: encode_extension(value)

  for {id, _, kind} <- @types, id not in [0, 14, 17, 22] do
    if kind in [:expanded_node_id, :qualified_name, :localized_text] do
      def encode(unquote(id), value), do: Names.encode(unquote(kind), value)
    else
      def encode(unquote(id), value), do: Binary.encode(unquote(kind), value)
    end
  end

  def encode(_, _), do: error(:unsupported_type)

  @doc "Decodes one bounded element, preserving its original unconsumed suffix."
  @spec decode(non_neg_integer(), term()) :: {:ok, term(), binary()} | {:error, Error.t()}
  def decode(0, bytes) when is_binary(bytes), do: {:ok, nil, bytes}
  def decode(14, bytes), do: decode_guid(bytes)
  def decode(17, bytes), do: Binary.decode_node_id(bytes)
  def decode(22, bytes), do: decode_extension(bytes)
  def decode(id, bytes) when id in 26..31, do: Binary.decode(:bytestring, bytes)

  for {id, _, kind} <- @types, id not in [0, 14, 17, 22] do
    if kind in [:expanded_node_id, :qualified_name, :localized_text] do
      def decode(unquote(id), bytes), do: Names.decode(unquote(kind), bytes)
    else
      def decode(unquote(id), bytes), do: Binary.decode(unquote(kind), bytes)
    end
  end

  def decode(_, _), do: error(:invalid_binary)

  defp encode_guid(value) when is_binary(value) and byte_size(value) == 36 do
    with true <- value == String.downcase(value),
         {:ok, node} <- Address.new("g=" <> value),
         {:ok, <<4, 0, 0, guid::binary>>} <- Binary.encode_node_id(node) do
      {:ok, guid}
    else
      _ -> error(:invalid_value)
    end
  end

  defp encode_guid(_), do: error(:invalid_value)

  defp decode_guid(<<guid::binary-size(16), rest::binary>>) do
    {:ok, node, <<>>} = Binary.decode_node_id(<<4, 0, 0, guid::binary>>)
    <<"ns=0;g=", text::binary>> = Address.to_string(node)
    {:ok, text, rest}
  end

  defp decode_guid(_), do: error(:invalid_binary)

  defp encode_extension(%{encoding_id: id, encoding: encoding, body: body} = value)
       when map_size(value) == 3 do
    with {:ok, id} <- Binary.encode_node_id(id),
         {:ok, body} <- extension_body(encoding, body) do
      {:ok, id <> body}
    end
  end

  defp encode_extension(_), do: error(:invalid_value)

  defp extension_body("none", nil), do: {:ok, <<0>>}

  defp extension_body(encoding, body) when encoding in ["binary", "xml"] do
    kind = if encoding == "binary", do: :bytestring, else: :string

    with {:ok, bytes} <- Binary.encode(kind, body),
         do: {:ok, <<if(encoding == "binary", do: 1, else: 2), bytes::binary>>}
  end

  defp extension_body(_, _), do: error(:invalid_value)

  defp decode_extension(bytes) do
    with {:ok, id, rest} <- Binary.decode_node_id(bytes),
         {:ok, encoding, body, rest} <- decoded_body(rest),
         do: {:ok, %{encoding_id: id, encoding: encoding, body: body}, rest}
  end

  defp decoded_body(<<0, rest::binary>>), do: {:ok, "none", nil, rest}

  defp decoded_body(<<mask, rest::binary>>) when mask in [1, 2] do
    kind = if mask == 1, do: :bytestring, else: :string

    with {:ok, body, rest} <- Binary.decode(kind, rest),
         do: {:ok, if(mask == 1, do: "binary", else: "xml"), body, rest}
  end

  defp decoded_body(_), do: error(:invalid_binary)
  defp error(code), do: {:error, Error.new(code)}
end
