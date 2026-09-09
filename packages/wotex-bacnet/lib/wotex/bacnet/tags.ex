defmodule Wotex.BACnet.Tags do
  @moduledoc """
  Decodes bounded BACnet application tags while retaining character-set bytes.

  BACstack supplies scalar decoding, while this parser handles constructed
  nesting and CharacterString values explicitly. Each CharacterString retains
  its original selector and bytes through `Wotex.BACnet.CharacterString`,
  avoiding the pinned SDK's loss of that selector during text conversion.

  The decoder requires a complete tag sequence within 65,536 input bytes,
  eight nesting levels, and 4096 tags. Mismatched closing tags, truncated lengths,
  invalid character strings, or incomplete scalar values return an error.
  Parsing is pure and does not establish the service-level meaning of the tags.

  ## Examples

      iex> {:ok, [{:character_string, value}]} = Wotex.BACnet.Tags.decode(<<0x72, 5, 233>>)
      iex> {value.character_set, value.bytes}
      {5, <<233>>}

  """

  alias BACnet.Protocol.ApplicationTags
  alias Wotex.BACnet.{CharacterString, Error}

  @doc false
  @spec decode(term()) :: {:ok, list()} | {:error, Error.t()}
  def decode(bytes) when is_binary(bytes) and byte_size(bytes) <= 65_536 do
    case sequence(bytes, nil, 0, 0, []) do
      {:ok, values, <<>>, _} -> {:ok, values}
      _ -> {:error, Error.new(:invalid_tags)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_tags)}
  end

  def decode(_), do: {:error, Error.new(:value_limit)}

  defp sequence(_, _, depth, _, _) when depth > 8, do: :error
  defp sequence(<<>>, nil, _, count, values), do: {:ok, Enum.reverse(values), <<>>, count}

  defp sequence(bytes, closing, depth, count, values) when count <= 4096 do
    with {:ok, tag, context, length, rest} <- header(bytes) do
      cond do
        context == 1 and length == 7 and tag == closing -> {:ok, Enum.reverse(values), rest, count}
        context == 1 and length == 7 -> :error
        count == 4096 -> :error
        context == 1 and length == 6 -> constructed(tag, rest, closing, depth, count, values)
        true -> scalar(bytes, rest, {tag, context, length}, closing, depth, count, values)
      end
    end
  end

  defp sequence(_, _, _, _, _), do: :error

  defp constructed(tag, rest, closing, depth, count, values) do
    with {:ok, children, rest, count} <- sequence(rest, tag, depth + 1, count + 1, []) do
      value =
        case children do
          [single] -> single
          other -> other
        end

      sequence(rest, closing, depth, count, [{:constructed, {tag, value, 0}} | values])
    end
  end

  defp scalar(_, rest, {7, 0, length}, closing, depth, count, values) do
    with {:ok, length, rest} <- size(length, rest),
         true <- length >= 1 and byte_size(rest) >= length,
         <<character_set, bytes::binary-size(^length - 1), rest::binary>> <- rest,
         {:ok, value} <- CharacterString.new(character_set, bytes) do
      sequence(rest, closing, depth, count + 1, [{:character_string, value} | values])
    else
      _ -> :error
    end
  end

  defp scalar(original, _, _, closing, depth, count, values) do
    case ApplicationTags.decode(original) do
      {:ok, value, rest} -> sequence(rest, closing, depth, count + 1, [value | values])
      _ -> :error
    end
  end

  defp header(<<15::4, context::1, length::3, tag, rest::binary>>),
    do: {:ok, tag, context, length, rest}

  defp header(<<tag::4, context::1, length::3, rest::binary>>),
    do: {:ok, tag, context, length, rest}

  defp header(_), do: :error
  defp size(length, rest) when length in 0..4, do: {:ok, length, rest}
  defp size(5, <<254, length::16, rest::binary>>), do: {:ok, length, rest}
  defp size(5, <<255, length::32, rest::binary>>), do: {:ok, length, rest}
  defp size(5, <<length, rest::binary>>) when length < 254, do: {:ok, length, rest}
  defp size(_, _), do: :error
end
