defmodule Wotex.OPCUA.Binary.Names do
  @moduledoc """
  Composes bounded OPC UA identity and text structures from scalar codecs.

  `Wotex.OPCUA.Binary` delegates ExpandedNodeId, QualifiedName and LocalizedText
  work to this pure helper. Decoding retains unconsumed bytes and distinguishes
  null text from empty text. An explicit namespace URI makes the encoded numeric
  namespace immaterial; decoded identities normalize that index to zero while
  retaining the URI and server index. No identity authorizes a remote connection
  or performs namespace resolution.

  Encoders require each structure's exact atom-keyed fields. URI identities are
  nonempty UTF-8 of at most 4096 bytes, names and localized strings have the
  scalar codec's 65536-byte limit, and numeric indexes retain their declared
  widths. Unsupported masks, truncated bytes and invalid values produce
  structured errors before transport or SDK allocation.
  """

  import Bitwise
  alias Wotex.OPCUA.{Address, Binary, Error}

  @type kind :: :expanded_node_id | :qualified_name | :localized_text
  @type expanded_node_id :: %{
          node_id: Address.t(),
          namespace_uri: String.t() | nil,
          server_index: 0..4_294_967_295
        }
  @type qualified_name :: %{namespace: 0..65_535, name: String.t() | nil}
  @type localized_text :: %{locale: String.t() | nil, text: String.t() | nil}

  @doc "Encodes one exact identity or text structure with explicit numeric and byte bounds."
  @spec encode(kind(), term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(:qualified_name, %{namespace: ns, name: name} = value) when map_size(value) == 2 do
    with {:ok, encoded_ns} <- Binary.encode(:uint16, ns),
         {:ok, encoded_name} <- Binary.encode(:string, name),
         do: {:ok, encoded_ns <> encoded_name}
  end

  def encode(:localized_text, %{locale: locale, text: text} = value) when map_size(value) == 2 do
    with {:ok, locale_bytes} <- optional_string(locale),
         {:ok, text_bytes} <- optional_string(text) do
      mask = if(is_nil(locale), do: 0, else: 1) + if(is_nil(text), do: 0, else: 2)
      {:ok, <<mask, locale_bytes::binary, text_bytes::binary>>}
    end
  end

  def encode(
        :expanded_node_id,
        %{node_id: input, namespace_uri: uri, server_index: server} = value
      )
      when map_size(value) == 3 do
    with {:ok, node} <- Address.new(input),
         true <- valid_uri?(uri),
         true <- is_nil(uri) or node.namespace == 0,
         {:ok, <<kind, node_bytes::binary>>} <- Binary.encode_node_id(node),
         {:ok, uri_bytes} <- optional_string(uri),
         {:ok, server_bytes} <- server_bytes(server) do
      mask = kind + if(is_nil(uri), do: 0, else: 0x80) + if(server == 0, do: 0, else: 0x40)
      {:ok, <<mask, node_bytes::binary, uri_bytes::binary, server_bytes::binary>>}
    else
      {:error, _} = error -> error
      _ -> invalid(:invalid_value)
    end
  end

  def encode(_, _), do: invalid(:invalid_value)

  @doc "Decodes one structure and its exact tail, rejecting unsupported masks and malformed fields."
  @spec decode(kind(), term()) :: {:ok, map(), binary()} | {:error, Error.t()}
  def decode(:qualified_name, bytes) do
    with {:ok, ns, rest} <- Binary.decode(:uint16, bytes),
         {:ok, name, rest} <- Binary.decode(:string, rest),
         do: {:ok, %{namespace: ns, name: name}, rest}
  end

  def decode(:localized_text, <<mask, rest::binary>>) when mask <= 3 do
    with {:ok, locale, rest} <- flagged_string(mask, 1, rest),
         {:ok, text, rest} <- flagged_string(mask, 2, rest),
         do: {:ok, %{locale: locale, text: text}, rest}
  end

  def decode(:expanded_node_id, <<mask, body::binary>>) do
    with {:ok, node, rest} <- node_prefix(mask, body),
         {:ok, uri, rest} <- flagged_string(mask, 0x80, rest),
         true <- band(mask, 0x80) == 0 or (not is_nil(uri) and valid_uri?(uri)),
         {:ok, server, rest} <- flagged_server(mask, rest) do
      node = if is_nil(uri), do: node, else: %{node | namespace: 0}
      {:ok, %{node_id: node, namespace_uri: uri, server_index: server}, rest}
    else
      {:error, _} = error -> error
      _ -> invalid(:invalid_binary)
    end
  end

  def decode(_, _), do: invalid(:invalid_binary)

  defp optional_string(nil), do: {:ok, <<>>}
  defp optional_string(value), do: Binary.encode(:string, value)

  defp server_bytes(0), do: {:ok, <<>>}
  defp server_bytes(value), do: Binary.encode(:uint32, value)

  defp valid_uri?(nil), do: true

  defp valid_uri?(value),
    do: is_binary(value) and byte_size(value) in 1..4096 and String.valid?(value)

  defp flagged_string(mask, flag, bytes) do
    if band(mask, flag) == 0, do: {:ok, nil, bytes}, else: Binary.decode(:string, bytes)
  end

  defp flagged_server(mask, bytes) do
    if band(mask, 0x40) == 0, do: {:ok, 0, bytes}, else: Binary.decode(:uint32, bytes)
  end

  defp node_prefix(mask, body) do
    # A valid NodeId consumes at most its tag, UInt16 namespace, Int32 length and
    # 4096 identifier bytes. Never copy an arbitrarily large unconsumed tail.
    size = min(byte_size(body), 4102)
    prefix = binary_part(body, 0, size)

    with {:ok, node, tail} <- Binary.decode_node_id(<<band(mask, 0x3F), prefix::binary>>) do
      consumed = size - byte_size(tail)
      {:ok, node, binary_part(body, consumed, byte_size(body) - consumed)}
    end
  end

  defp invalid(code), do: {:error, Error.new(code)}
end
