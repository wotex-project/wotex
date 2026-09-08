defmodule Wotex.OPCUA.Binary do
  @moduledoc "Bounded OPC UA Part 6 scalar and NodeId binary values, independent of channel ownership."
  alias Wotex.OPCUA.{Address, Error}

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

  defp node(ns, kind, id, rest) do
    with {:ok, node} <- Address.new(%Address{namespace: ns, kind: kind, identifier: id}),
         do: {:ok, node, rest}
  end

  defp node_bytes(%Address{kind: :numeric, namespace: 0, identifier: id}) when id <= 255,
    do: {:ok, <<0, id>>}

  defp node_bytes(%Address{kind: :numeric, namespace: ns, identifier: id})
       when ns <= 255 and id <= 65_535, do: {:ok, <<1, ns, id::16-little>>}

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
