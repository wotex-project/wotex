defmodule Wotex.OPCUA.Binary.Variant do
  @moduledoc """
  Encodes explicitly typed OPC UA Variants with finite array and byte budgets.

  `Wotex.OPCUA.Binary` delegates Variant operations to this pure codec. Every
  value declares its type name, Boolean `array` flag and payload. A scalar null,
  null array and empty array remain distinct. Multidimensional arrays retain a
  flat element list and two through eight positive dimensions whose product
  equals the element count; one-dimensional arrays omit dimensions.

  Arrays contain at most 1024 elements and a complete Variant consumes at most
  1 MiB. Decoding exposes only that bounded prefix to element codecs, then
  restores the exact original suffix. Unsupported nested Variant/DataValue
  types cannot introduce recursive structures; supported values remain below
  the profile's depth-eight ceiling. Reserved IDs 26 through 31 retain their
  original ID and nullable byte payloads on decode and are rejected on encode.
  No type is inferred from a payload, and no process or SDK object is created.
  """

  import Bitwise
  alias Wotex.OPCUA.Binary.Element
  alias Wotex.OPCUA.Error

  @limit 1_048_576
  @type t :: %{
          required(:type) => String.t(),
          required(:array) => boolean(),
          required(:value) => term(),
          optional(:dimensions) => [pos_integer()],
          optional(:type_id) => 26..31
        }

  @doc "Encodes a closed typed envelope, rejecting unknown fields and all inferred array shapes."
  @spec encode(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(%{type: "Reserved"}), do: error(:unsupported_type)

  def encode(%{type: name, array: array, value: payload} = value)
      when is_boolean(array) and map_size(value) in [3, 4] do
    with true <- Enum.all?(Map.keys(value), &(&1 in [:type, :array, :value, :dimensions])),
         {:ok, id} <- Element.type(name),
         true <- id != 0 or not array,
         {:ok, body, count} <- encode_payload(id, array, payload),
         {:ok, dimensions, flag} <- encode_dimensions(value, count),
         true <- 1 + byte_size(body) + byte_size(dimensions) <= @limit do
      mask = id + if(array, do: 0x80, else: 0) + flag
      {:ok, <<mask, body::binary, dimensions::binary>>}
    else
      {:error, _} = error -> error
      _ -> error(:invalid_value)
    end
  end

  def encode(_), do: error(:invalid_value)

  @doc "Decodes one Variant within a 1 MiB prefix and returns the exact unconsumed original tail."
  @spec decode(term()) :: {:ok, t(), binary()} | {:error, Error.t()}
  def decode(bytes) when is_binary(bytes) do
    prefix_size = min(byte_size(bytes), @limit)

    with {:ok, value, tail} <- decode_prefix(binary_part(bytes, 0, prefix_size)) do
      consumed = prefix_size - byte_size(tail)
      {:ok, value, binary_part(bytes, consumed, byte_size(bytes) - consumed)}
    end
  end

  def decode(_), do: error(:invalid_binary)

  defp encode_payload(id, false, value) do
    with {:ok, bytes} <- Element.encode(id, value), do: {:ok, bytes, :scalar}
  end

  defp encode_payload(_, true, nil), do: {:ok, <<-1::32-little-signed>>, :null}

  defp encode_payload(id, true, values) do
    with {:ok, pieces, count} <- encode_items(id, values, [], 0, @limit - 5) do
      {:ok, IO.iodata_to_binary([<<count::32-little-signed>> | Enum.reverse(pieces)]), count}
    end
  end

  defp encode_items(_, [], pieces, count, _), do: {:ok, pieces, count}

  defp encode_items(id, [value | rest], pieces, count, remaining) when count < 1024 do
    with {:ok, bytes} <- Element.encode(id, value),
         true <- byte_size(bytes) <= remaining do
      encode_items(id, rest, [bytes | pieces], count + 1, remaining - byte_size(bytes))
    else
      {:error, _} = error -> error
      _ -> error(:invalid_value)
    end
  end

  defp encode_items(_, _, _, _, _), do: error(:invalid_value)

  defp encode_dimensions(%{dimensions: dimensions}, count) when is_integer(count) and count > 0 do
    with {:ok, axes} <- dimension_list(dimensions, [], 1, count) do
      bytes = Enum.map(axes, fn axis -> <<axis::32-little-signed>> end)
      {:ok, IO.iodata_to_binary([<<length(axes)::32-little-signed>> | bytes]), 0x40}
    end
  end

  defp encode_dimensions(value, _) do
    if Map.has_key?(value, :dimensions), do: error(:invalid_value), else: {:ok, <<>>, 0}
  end

  defp dimension_list([], axes, product, count) when product == count and length(axes) in 2..8,
    do: {:ok, Enum.reverse(axes)}

  defp dimension_list([axis | rest], axes, product, count)
       when is_integer(axis) and axis in 1..1024 and length(axes) < 8 and product * axis <= count do
    dimension_list(rest, [axis | axes], product * axis, count)
  end

  defp dimension_list(_, _, _, _), do: error(:invalid_value)

  defp decode_prefix(<<mask, rest::binary>>) do
    id = band(mask, 0x3F)
    array = band(mask, 0x80) != 0
    dimensions = band(mask, 0x40) != 0

    with {:ok, name} <- Element.name(id),
         true <- (not dimensions or array) and (id != 0 or mask == 0),
         {:ok, value, count, rest} <- decode_payload(id, array, rest),
         {:ok, axes, rest} <- decode_dimensions(dimensions, count, rest) do
      envelope = %{type: name, array: array, value: value}
      envelope = if id in 26..31, do: Map.put(envelope, :type_id, id), else: envelope
      envelope = if is_nil(axes), do: envelope, else: Map.put(envelope, :dimensions, axes)
      {:ok, envelope, rest}
    else
      {:error, _} = error -> error
      _ -> error(:invalid_binary)
    end
  end

  defp decode_prefix(_), do: error(:invalid_binary)

  defp decode_payload(id, false, bytes) do
    with {:ok, value, rest} <- Element.decode(id, bytes), do: {:ok, value, :scalar, rest}
  end

  defp decode_payload(_, true, <<-1::32-little-signed, rest::binary>>),
    do: {:ok, nil, :null, rest}

  defp decode_payload(id, true, <<count::32-little-signed, rest::binary>>) when count in 0..1024 do
    with {:ok, values, rest} <- decode_items(id, count, rest, []),
         do: {:ok, values, count, rest}
  end

  defp decode_payload(_, _, _), do: error(:invalid_binary)

  defp decode_items(_, 0, rest, values), do: {:ok, Enum.reverse(values), rest}

  defp decode_items(id, remaining, bytes, values) do
    with {:ok, value, rest} <- Element.decode(id, bytes),
         do: decode_items(id, remaining - 1, rest, [value | values])
  end

  defp decode_dimensions(false, _, rest), do: {:ok, nil, rest}

  defp decode_dimensions(true, count, <<size::32-little-signed, rest::binary>>)
       when is_integer(count) and count > 0 and size in 2..8 do
    with {:ok, axes, rest} <- decode_items(6, size, rest, []),
         {:ok, ^axes} <- dimension_list(axes, [], 1, count) do
      {:ok, axes, rest}
    else
      _ -> error(:invalid_binary)
    end
  end

  defp decode_dimensions(_, _, _), do: error(:invalid_binary)
  defp error(code), do: {:error, Error.new(code)}
end
