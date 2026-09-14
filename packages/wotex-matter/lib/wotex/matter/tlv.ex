defmodule Wotex.Matter.TLV do
  @moduledoc """
  Encodes and decodes bounded Matter Type-Length-Value data for the SDK 1.6 profile.

  Elements retain their tag, exact scalar width, type, and value. Supported
  values include signed and unsigned integers, floating-point values, booleans,
  UTF-8 strings, byte strings, null, structures, arrays, and lists. Anonymous,
  context-specific, common-profile, implicit-profile, and fully qualified tags
  remain explicit; the codec does not infer a narrower type or discard a tag.

  `decode/1` requires a complete input and `encode/1` verifies its result by
  decoding it again. Both operations are limited to 64 KiB, 1024 elements, and
  eight container levels. Array children must be anonymous, and structure tags
  must be unique and non-anonymous. Invalid values return
  `Wotex.Matter.Error` without partial output.

  ## Examples

      iex> elements = [%{tag: {:context, 1}, type: :u8, value: 42}]
      iex> {:ok, bytes} = Wotex.Matter.TLV.encode(elements)
      iex> bytes
      <<36, 1, 42>>
      iex> Wotex.Matter.TLV.decode(bytes)
      {:ok, [%{tag: {:context, 1}, type: :u8, value: 42}]}
  """
  import Bitwise
  alias Wotex.Matter.Error
  @type element :: %{tag: term(), type: atom(), value: term()}

  @doc "Reconstructs one explicit element and requires an anonymous outer tag."
  @spec validate_element(term()) :: {:ok, element()} | {:error, Error.t()}
  def validate_element(%{tag: :anonymous, type: _, value: _} = element)
      when map_size(element) == 3 do
    with {:ok, bytes} <- encode([element]),
         {:ok, [normalized]} <- decode(bytes) do
      {:ok, normalized}
    else
      _ -> {:error, Error.new(:invalid_tlv)}
    end
  end

  def validate_element(_), do: {:error, Error.new(:invalid_tlv)}

  @doc "Decodes complete TLV elements, limited to 64 KiB, 1024 nodes and depth eight."
  @spec decode(term()) :: {:ok, [element()]} | {:error, Error.t()}
  def decode(bytes) when is_binary(bytes) and byte_size(bytes) <= 65_536 do
    case elements(bytes, 0, 1024, false, []) do
      {:ok, values, <<>>, _} -> {:ok, values}
      _ -> {:error, Error.new(:invalid_tlv)}
    end
  end

  def decode(bytes) when is_binary(bytes), do: {:error, Error.new(:tlv_limit)}
  def decode(_), do: {:error, Error.new(:invalid_tlv)}

  @doc "Encodes explicit TLV elements without type inference or silently discarded tags."
  @spec encode(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(values) when is_list(values) do
    with {:ok, bytes, _} <- encode_elements(values, 0, 1024),
         true <- byte_size(bytes) <= 65_536,
         {:ok, _} <- decode(bytes) do
      {:ok, bytes}
    else
      _ -> {:error, Error.new(:invalid_tlv)}
    end
  end

  def encode(_), do: {:error, Error.new(:invalid_tlv)}

  defp elements(<<>>, _, budget, false, acc), do: {:ok, Enum.reverse(acc), <<>>, budget}

  defp elements(<<24, rest::binary>>, _, budget, true, acc),
    do: {:ok, Enum.reverse(acc), rest, budget}

  defp elements(<<control, rest::binary>>, depth, budget, nested, acc)
       when depth <= 8 and budget > 0 do
    with {:ok, tag, rest} <- tag(bsr(control, 5), rest),
         {:ok, type, value, rest, budget} <- value(band(control, 31), rest, depth, budget - 1),
         true <- valid_children?(type, value) do
      elements(rest, depth, budget, nested, [%{tag: tag, type: type, value: value} | acc])
    end
  end

  defp elements(_, _, _, _, _), do: :error

  defp tag(0, rest), do: {:ok, :anonymous, rest}
  defp tag(1, <<id, rest::binary>>), do: {:ok, {:context, id}, rest}
  defp tag(2, <<id::16-little, rest::binary>>), do: {:ok, {:common, id}, rest}
  defp tag(3, <<id::32-little, rest::binary>>), do: {:ok, {:common, id}, rest}
  defp tag(4, <<id::16-little, rest::binary>>), do: {:ok, {:implicit, id}, rest}
  defp tag(5, <<id::32-little, rest::binary>>), do: {:ok, {:implicit, id}, rest}

  defp tag(6, <<vendor::16-little, profile::16-little, id::16-little, rest::binary>>),
    do: {:ok, {:qualified, vendor, profile, id}, rest}

  defp tag(7, <<vendor::16-little, profile::16-little, id::32-little, rest::binary>>),
    do: {:ok, {:qualified, vendor, profile, id}, rest}

  defp tag(_, _), do: :error
  defp value(0, <<v::8-little-signed, rest::binary>>, _, budget), do: {:ok, :i8, v, rest, budget}
  defp value(1, <<v::16-little-signed, rest::binary>>, _, budget), do: {:ok, :i16, v, rest, budget}
  defp value(2, <<v::32-little-signed, rest::binary>>, _, budget), do: {:ok, :i32, v, rest, budget}
  defp value(3, <<v::64-little-signed, rest::binary>>, _, budget), do: {:ok, :i64, v, rest, budget}
  defp value(4, <<v::8-little-unsigned, rest::binary>>, _, budget), do: {:ok, :u8, v, rest, budget}

  defp value(5, <<v::16-little-unsigned, rest::binary>>, _, budget),
    do: {:ok, :u16, v, rest, budget}

  defp value(6, <<v::32-little-unsigned, rest::binary>>, _, budget),
    do: {:ok, :u32, v, rest, budget}

  defp value(7, <<v::64-little-unsigned, rest::binary>>, _, budget),
    do: {:ok, :u64, v, rest, budget}

  defp value(8, rest, _, budget), do: {:ok, :boolean, false, rest, budget}
  defp value(9, rest, _, budget), do: {:ok, :boolean, true, rest, budget}

  defp value(10, <<v::32-little-float, rest::binary>>, _, budget),
    do: {:ok, :float32, v, rest, budget}

  defp value(11, <<v::64-little-float, rest::binary>>, _, budget),
    do: {:ok, :float64, v, rest, budget}

  defp value(type, rest, _, budget) when type in 12..19 do
    width = bsl(1, rem(type, 4))

    with true <- byte_size(rest) >= width,
         size = :binary.decode_unsigned(binary_part(rest, 0, width), :little),
         true <- size <= 65_536 and byte_size(rest) - width >= size do
      bytes = binary_part(rest, width, size)
      tail = binary_part(rest, width + size, byte_size(rest) - width - size)

      if type >= 16 or String.valid?(bytes),
        do: {:ok, if(type < 16, do: :utf8, else: :bytes), bytes, tail, budget},
        else: :error
    end
  end

  defp value(20, rest, _, budget), do: {:ok, :null, nil, rest, budget}

  defp value(type, rest, depth, budget) when type in 21..23 and depth < 8 do
    with {:ok, children, rest, budget} <- elements(rest, depth + 1, budget, true, []) do
      {:ok, %{21 => :structure, 22 => :array, 23 => :list}[type], children, rest, budget}
    end
  end

  defp value(_, _, _, _), do: :error

  defp valid_children?(:array, children), do: Enum.all?(children, &(&1.tag == :anonymous))

  defp valid_children?(:structure, children) do
    tags = Enum.map(children, & &1.tag)
    :anonymous not in tags and length(Enum.uniq(tags)) == length(tags)
  end

  defp valid_children?(_, _), do: true

  defp encode_elements([], _, budget), do: {:ok, <<>>, budget}

  defp encode_elements([%{tag: tag, type: type, value: value} = element | tail], depth, budget)
       when map_size(element) == 3 and depth <= 8 and budget > 0 do
    with {:ok, tag_control, tag_bytes} <- encode_tag(tag),
         {:ok, type_control, body, budget} <- encode_value(type, value, depth, budget - 1),
         {:ok, tail, budget} <- encode_elements(tail, depth, budget),
         true <- byte_size(body) + byte_size(tail) < 65_536 do
      {:ok,
       <<bor(bsl(tag_control, 5), type_control), tag_bytes::binary, body::binary, tail::binary>>,
       budget}
    end
  end

  defp encode_elements(_, _, _), do: :error

  defp encode_tag(:anonymous), do: {:ok, 0, <<>>}
  defp encode_tag({:context, id}) when is_integer(id) and id in 0..255, do: {:ok, 1, <<id>>}

  defp encode_tag({kind, id})
       when kind in [:common, :implicit] and is_integer(id) and id in 0..65_535,
       do: {:ok, if(kind == :common, do: 2, else: 4), <<id::16-little>>}

  defp encode_tag({kind, id})
       when kind in [:common, :implicit] and is_integer(id) and id in 0..4_294_967_295,
       do: {:ok, if(kind == :common, do: 3, else: 5), <<id::32-little>>}

  defp encode_tag({:qualified, vendor, profile, id})
       when is_integer(vendor) and vendor in 0..65_535 and is_integer(profile) and
              profile in 0..65_535 and is_integer(id) and id in 0..4_294_967_295 do
    if id <= 65_535,
      do: {:ok, 6, <<vendor::16-little, profile::16-little, id::16-little>>},
      else: {:ok, 7, <<vendor::16-little, profile::16-little, id::32-little>>}
  end

  defp encode_tag(_), do: :error

  defp encode_value(:i8, v, _, budget) when is_integer(v) and v >= -128 and v <= 127,
    do: {:ok, 0, <<v::8-little-signed>>, budget}

  defp encode_value(:i16, v, _, budget) when is_integer(v) and v >= -32_768 and v <= 32_767,
    do: {:ok, 1, <<v::16-little-signed>>, budget}

  defp encode_value(:i32, v, _, budget)
       when is_integer(v) and v >= -2_147_483_648 and v <= 2_147_483_647,
       do: {:ok, 2, <<v::32-little-signed>>, budget}

  defp encode_value(:i64, v, _, budget)
       when is_integer(v) and v >= -9_223_372_036_854_775_808 and v <= 9_223_372_036_854_775_807,
       do: {:ok, 3, <<v::64-little-signed>>, budget}

  defp encode_value(:u8, v, _, budget) when is_integer(v) and v >= 0 and v <= 255,
    do: {:ok, 4, <<v::8-little-unsigned>>, budget}

  defp encode_value(:u16, v, _, budget) when is_integer(v) and v >= 0 and v <= 65_535,
    do: {:ok, 5, <<v::16-little-unsigned>>, budget}

  defp encode_value(:u32, v, _, budget) when is_integer(v) and v >= 0 and v <= 4_294_967_295,
    do: {:ok, 6, <<v::32-little-unsigned>>, budget}

  defp encode_value(:u64, v, _, budget)
       when is_integer(v) and v >= 0 and v <= 18_446_744_073_709_551_615,
       do: {:ok, 7, <<v::64-little-unsigned>>, budget}

  defp encode_value(:boolean, v, _, budget) when is_boolean(v),
    do: {:ok, if(v, do: 9, else: 8), <<>>, budget}

  defp encode_value(:float32, v, _, budget)
       when is_float(v) and abs(v) <= 3.402_823_466_385_288_6e38,
       do: {:ok, 10, <<v::32-little-float>>, budget}

  defp encode_value(:float64, v, _, budget) when is_float(v),
    do: {:ok, 11, <<v::64-little-float>>, budget}

  defp encode_value(:null, nil, _, budget), do: {:ok, 20, <<>>, budget}

  defp encode_value(type, value, _, budget)
       when type in [:utf8, :bytes] and is_binary(value) and byte_size(value) <= 65_535 do
    base = if type == :utf8, do: 12, else: 16

    if byte_size(value) <= 255,
      do: {:ok, base, <<byte_size(value), value::binary>>, budget},
      else: {:ok, base + 1, <<byte_size(value)::16-little, value::binary>>, budget}
  end

  defp encode_value(type, values, depth, budget)
       when type in [:structure, :array, :list] and depth < 8 do
    with {:ok, body, budget} <- encode_elements(values, depth + 1, budget),
         do: {:ok, %{structure: 21, array: 22, list: 23}[type], body <> <<24>>, budget}
  end

  defp encode_value(_, _, _, _), do: :error
end
