defmodule Wotex.OPCUA.Binary do
  @moduledoc """
  Encodes and decodes bounded OPC UA Part 6 values and reference identities.

  `encode/2` and `decode/2` support the declared integer widths, booleans,
  single- and double-precision floating-point values, UTF-8 strings, and byte
  strings in OPC UA little-endian form. Nullable strings and byte strings retain
  their protocol distinction. Decoding returns the unconsumed binary so callers
  can compose larger structures without discarding trailing data.

  `encode_node_id/1` selects the compact numeric form where applicable and
  preserves numeric, string, globally unique identifier, and opaque identities.
  `decode_node_id/1` returns a validated `Wotex.OPCUA.Address` with the remaining
  input. Operations are pure, bounded, and independent of secure-channel or
  service ownership. Invalid lengths, encodings, and values return
  `Wotex.OPCUA.Error`.

  ExpandedNodeId codecs preserve an explicit namespace URI and remote server
  index. QualifiedName and LocalizedText codecs retain namespace, locale and
  null-versus-empty text. ReferenceDescription codecs compose those values
  without reducing references to display names or resolving remote identities.
  These structured encoders require their exact atom-keyed fields.

  Variant codecs require an explicit type and array flag, bound arrays to 1024
  elements, and retain dimensions and opaque extension identities. DataValue
  codecs preserve value presence, full status and signed 100 ns timestamp ticks.
  They normalize 10 ps fractions according to Part 6. Both complete values have
  a 1 MiB byte budget; decoding a Bad StatusCode is distinct from accepting a
  successful service response.

  ## Examples

      iex> Wotex.OPCUA.Binary.encode(:uint16, 513)
      {:ok, <<1, 2>>}
      iex> Wotex.OPCUA.Binary.decode(:uint16, <<1, 2, 99>>)
      {:ok, 513, <<99>>}

      iex> Wotex.OPCUA.Binary.encode(:string, nil)
      {:ok, <<255, 255, 255, 255>>}
      iex> Wotex.OPCUA.Binary.encode(:string, "")
      {:ok, <<0, 0, 0, 0>>}

      iex> Wotex.OPCUA.Binary.encode_localized_text(%{locale: nil, text: ""})
      {:ok, <<2, 0, 0, 0, 0>>}
      iex> Wotex.OPCUA.Binary.decode_qualified_name(<<2, 0, 1, 0, 0, 0, ?x, 99>>)
      {:ok, %{namespace: 2, name: "x"}, <<99>>}

      iex> Wotex.OPCUA.Binary.decode_variant(<<0x86, -1::32-little-signed>>)
      {:ok, %{type: "Int32", array: true, value: nil}, <<>>}
      iex> Wotex.OPCUA.Binary.decode_data_value(<<1, 0>>)
      {:ok, %{has_value: true, value: %{type: "Null", array: false, value: nil}, status: 0}, <<>>}

  """
  alias Wotex.OPCUA.{Address, Error}
  alias Wotex.OPCUA.Binary.{DataValue, Names, Reference, Variant}

  @type scalar ::
          :boolean
          | :sbyte
          | :byte
          | :int16
          | :uint16
          | :int32
          | :uint32
          | :int64
          | :uint64
          | :float
          | :double
          | :string
          | :bytestring

  @doc "Encodes an exact scalar type; integers never wrap and strings preserve null versus empty."
  @spec encode(scalar(), term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(:sbyte, value) when is_integer(value) and value >= -128 and value <= 127,
    do: {:ok, <<value::8-little-signed>>}

  def encode(:byte, value) when is_integer(value) and value >= 0 and value <= 255,
    do: {:ok, <<value::8-little-unsigned>>}

  def encode(:int16, value) when is_integer(value) and value >= -32_768 and value <= 32_767,
    do: {:ok, <<value::16-little-signed>>}

  def encode(:uint16, value) when is_integer(value) and value >= 0 and value <= 65_535,
    do: {:ok, <<value::16-little-unsigned>>}

  def encode(:int32, value)
      when is_integer(value) and value >= -2_147_483_648 and value <= 2_147_483_647,
      do: {:ok, <<value::32-little-signed>>}

  def encode(:uint32, value) when is_integer(value) and value >= 0 and value <= 4_294_967_295,
    do: {:ok, <<value::32-little-unsigned>>}

  def encode(:int64, value)
      when is_integer(value) and value >= -9_223_372_036_854_775_808 and
             value <= 9_223_372_036_854_775_807,
      do: {:ok, <<value::64-little-signed>>}

  def encode(:uint64, value)
      when is_integer(value) and value >= 0 and value <= 18_446_744_073_709_551_615,
      do: {:ok, <<value::64-little-unsigned>>}

  def encode(:boolean, value) when is_boolean(value), do: {:ok, <<if(value, do: 1, else: 0)>>}

  def encode(:float, value) when is_float(value) and abs(value) <= 3.402_823_466_385_288_6e38,
    do: {:ok, <<value::32-little-float>>}

  def encode(:double, value) when is_float(value), do: {:ok, <<value::64-little-float>>}
  def encode(type, nil) when type in [:string, :bytestring], do: {:ok, <<-1::32-little-signed>>}

  def encode(type, value)
      when type in [:string, :bytestring] and is_binary(value) and byte_size(value) <= 65_536 do
    if type == :bytestring or String.valid?(value),
      do: {:ok, <<byte_size(value)::32-little-signed, value::binary>>},
      else: {:error, Error.new(:invalid_utf8)}
  end

  def encode(_, _), do: {:error, Error.new(:invalid_value)}

  @doc "Decodes one scalar with unconsumed tail and bounded string allocation."
  @spec decode(scalar(), term()) :: {:ok, term(), binary()} | {:error, Error.t()}
  def decode(:sbyte, <<value::8-little-signed, rest::binary>>), do: {:ok, value, rest}
  def decode(:byte, <<value::8-little-unsigned, rest::binary>>), do: {:ok, value, rest}
  def decode(:int16, <<value::16-little-signed, rest::binary>>), do: {:ok, value, rest}
  def decode(:uint16, <<value::16-little-unsigned, rest::binary>>), do: {:ok, value, rest}
  def decode(:int32, <<value::32-little-signed, rest::binary>>), do: {:ok, value, rest}
  def decode(:uint32, <<value::32-little-unsigned, rest::binary>>), do: {:ok, value, rest}
  def decode(:int64, <<value::64-little-signed, rest::binary>>), do: {:ok, value, rest}
  def decode(:uint64, <<value::64-little-unsigned, rest::binary>>), do: {:ok, value, rest}
  def decode(:boolean, <<value, rest::binary>>) when value in [0, 1], do: {:ok, value == 1, rest}
  def decode(:float, <<value::32-little-float, rest::binary>>), do: {:ok, value, rest}
  def decode(:double, <<value::64-little-float, rest::binary>>), do: {:ok, value, rest}

  def decode(type, <<-1::32-little-signed, rest::binary>>) when type in [:string, :bytestring],
    do: {:ok, nil, rest}

  def decode(type, <<size::32-little-signed, value::binary-size(size), rest::binary>>)
      when type in [:string, :bytestring] and size in 0..65_536 do
    if type == :bytestring or String.valid?(value),
      do: {:ok, value, rest},
      else: {:error, Error.new(:invalid_utf8)}
  end

  def decode(_, _), do: {:error, Error.new(:invalid_binary)}

  @doc "Encodes all four NodeId identifier kinds using the shortest numeric form."
  @spec encode_node_id(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode_node_id(input) do
    with {:ok, node} <- Address.new(input), do: node_bytes(node)
  end

  @doc "Decodes a NodeId without losing trailing bytes or allocating unchecked lengths."
  @spec decode_node_id(term()) :: {:ok, Address.t(), binary()} | {:error, Error.t()}
  def decode_node_id(<<0, id, rest::binary>>), do: node(0, :numeric, id, rest)
  def decode_node_id(<<1, ns, id::16-little, rest::binary>>), do: node(ns, :numeric, id, rest)

  def decode_node_id(<<2, ns::16-little, id::32-little, rest::binary>>),
    do: node(ns, :numeric, id, rest)

  def decode_node_id(<<kind, ns::16-little, rest::binary>>) when kind in [3, 5] do
    type = if kind == 3, do: :string, else: :bytestring

    case decode(type, rest) do
      {:ok, id, rest} when is_binary(id) ->
        node(ns, if(kind == 3, do: :string, else: :opaque), id, rest)

      _ ->
        {:error, Error.new(:invalid_node_id)}
    end
  end

  def decode_node_id(
        <<4, ns::16-little, a::32-little, b::16-little, c::16-little, tail::binary-size(8),
          rest::binary>>
      ),
      do: node(ns, :guid, <<a::32, b::16, c::16, tail::binary>>, rest)

  def decode_node_id(_), do: {:error, Error.new(:invalid_node_id)}

  @doc "Encodes an explicit ExpandedNodeId; a supplied URI requires namespace index zero."
  @spec encode_expanded_node_id(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode_expanded_node_id(value), do: Names.encode(:expanded_node_id, value)

  @doc "Decodes an ExpandedNodeId, normalizing its namespace index when a URI is present."
  @spec decode_expanded_node_id(term()) ::
          {:ok, Names.expanded_node_id(), binary()} | {:error, Error.t()}
  def decode_expanded_node_id(bytes), do: Names.decode(:expanded_node_id, bytes)

  @doc "Encodes a UInt16 namespace and nullable UTF-8 name without resolving either."
  @spec encode_qualified_name(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode_qualified_name(value), do: Names.encode(:qualified_name, value)

  @doc "Decodes a QualifiedName with its original namespace, nullable text and unconsumed tail."
  @spec decode_qualified_name(term()) ::
          {:ok, Names.qualified_name(), binary()} | {:error, Error.t()}
  def decode_qualified_name(bytes), do: Names.decode(:qualified_name, bytes)

  @doc "Encodes independently nullable locale and text, retaining an explicitly empty field."
  @spec encode_localized_text(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode_localized_text(value), do: Names.encode(:localized_text, value)

  @doc "Decodes a LocalizedText mask and both nullable fields without discarding trailing bytes."
  @spec decode_localized_text(term()) ::
          {:ok, Names.localized_text(), binary()} | {:error, Error.t()}
  def decode_localized_text(bytes), do: Names.decode(:localized_text, bytes)

  @doc "Encodes the complete seven-field ReferenceDescription profile with a finite NodeClass."
  @spec encode_reference_description(term()) :: {:ok, binary()} | {:error, Error.t()}
  defdelegate encode_reference_description(value), to: Reference, as: :encode

  @doc "Decodes a reference with both expanded identities, original names and exact tail."
  @spec decode_reference_description(term()) ::
          {:ok, Reference.t(), binary()} | {:error, Error.t()}
  defdelegate decode_reference_description(bytes), to: Reference, as: :decode

  @doc "Encodes an explicit Variant, preserving scalar, null-array, empty-array and dimension identity."
  @spec encode_variant(term()) :: {:ok, binary()} | {:error, Error.t()}
  defdelegate encode_variant(value), to: Variant, as: :encode

  @doc "Decodes a Variant with a 1024-element, 1 MiB ceiling and read-only future-type preservation."
  @spec decode_variant(term()) :: {:ok, Variant.t(), binary()} | {:error, Error.t()}
  defdelegate decode_variant(bytes), to: Variant, as: :decode

  @doc "Encodes DataValue presence, StatusCode and signed 100 ns tick metadata without calendar conversion."
  @spec encode_data_value(term()) :: {:ok, binary()} | {:error, Error.t()}
  defdelegate encode_data_value(value), to: DataValue, as: :encode

  @doc "Decodes a complete DataValue and normalizes 10 ps fractions, retaining Bad or Uncertain statuses."
  @spec decode_data_value(term()) :: {:ok, DataValue.t(), binary()} | {:error, Error.t()}
  defdelegate decode_data_value(bytes), to: DataValue, as: :decode

  defp node(ns, kind, id, rest) do
    with {:ok, node} <- Address.new(%Address{namespace: ns, kind: kind, identifier: id}),
         do: {:ok, node, rest}
  end

  defp node_bytes(%Address{kind: :numeric, namespace: 0, identifier: id}) when id <= 255,
    do: {:ok, <<0, id>>}

  defp node_bytes(%Address{kind: :numeric, namespace: ns, identifier: id})
       when ns <= 255 and id <= 65_535 do
    {:ok, <<1, ns, id::16-little>>}
  end

  defp node_bytes(%Address{kind: :numeric, namespace: ns, identifier: id}),
    do: {:ok, <<2, ns::16-little, id::32-little>>}

  defp node_bytes(%Address{kind: kind, namespace: ns, identifier: id})
       when kind in [:string, :opaque],
       do:
         {:ok,
          <<if(kind == :string, do: 3, else: 5), ns::16-little, byte_size(id)::32-little-signed,
            id::binary>>}

  defp node_bytes(%Address{
         kind: :guid,
         namespace: ns,
         identifier: <<a::32, b::16, c::16, tail::binary>>
       }),
       do: {:ok, <<4, ns::16-little, a::32-little, b::16-little, c::16-little, tail::binary>>}
end
