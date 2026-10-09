defmodule Wotex.Matter.Bridge.Arguments do
  @moduledoc false

  import Bitwise

  # Match the SDK reader's structural rules without an implicit profile.
  # Command fields, profile identifiers and scalar values remain opaque.
  @doc false
  @spec valid?(term()) :: boolean()
  def valid?(<<control, rest::binary>> = bytes) when byte_size(bytes) <= 65_536 do
    with 21 <- band(control, 31),
         {:ok, :anonymous, tail} <- tag(bsr(control, 5), rest) do
      walk(tail, [21], 1)
    else
      _ -> false
    end
  end

  def valid?(_), do: false

  defp walk(<<control, rest::binary>>, [container | _] = stack, nodes) do
    type = band(control, 31)

    case tag(bsr(control, 5), rest) do
      {:ok, :anonymous, tail} when type == 24 ->
        close(tail, stack, nodes)

      {:ok, kind, tail} when type < 24 and nodes < 4096 ->
        valid_tag?(container, kind) and value(type, tail, stack, nodes + 1)

      _ ->
        false
    end
  end

  defp walk(_, _, _), do: false

  defp close(<<>>, [_], _), do: true
  defp close(rest, [_, _ | _] = stack, nodes), do: walk(rest, tl(stack), nodes)
  defp close(_, _, _), do: false

  defp valid_tag?(21, kind), do: kind == :tagged
  defp valid_tag?(22, kind), do: kind == :anonymous
  defp valid_tag?(23, _), do: true

  defp tag(0, rest), do: {:ok, :anonymous, rest}
  defp tag(control, _) when control in [4, 5], do: :error

  defp tag(control, rest) do
    width = elem({0, 1, 2, 4, 2, 4, 6, 8}, control)

    if byte_size(rest) >= width do
      <<bytes::binary-size(^width), tail::binary>> = rest
      kind = tag_kind(bytes)
      if kind == :unknown, do: :error, else: {:ok, kind, tail}
    else
      :error
    end
  end

  # The SDK represents qualified profile 0xFFFFFFFF tags 256 and 257 as
  # AnonymousTag and UnknownImplicitTag respectively, in both wire widths.
  defp tag_kind(<<0xFFFFFFFF::little-32, number::little-16>>), do: special_tag(number)
  defp tag_kind(<<0xFFFFFFFF::little-32, number::little-32>>), do: special_tag(number)
  defp tag_kind(_), do: :tagged

  defp special_tag(256), do: :anonymous
  defp special_tag(257), do: :unknown
  defp special_tag(_), do: :tagged

  defp value(type, rest, stack, nodes) when type in 0..7,
    do: skip(rest, bsl(1, rem(type, 4)), stack, nodes)

  defp value(type, rest, stack, nodes) when type in [8, 9, 20], do: walk(rest, stack, nodes)
  defp value(10, rest, stack, nodes), do: skip(rest, 4, stack, nodes)
  defp value(11, rest, stack, nodes), do: skip(rest, 8, stack, nodes)

  defp value(type, rest, stack, nodes) when type in 12..19 do
    width = bsl(1, rem(type, 4))

    if byte_size(rest) >= width do
      length = :binary.decode_unsigned(binary_part(rest, 0, width), :little)
      tail = binary_part(rest, width, byte_size(rest) - width)
      skip(tail, length, stack, nodes)
    else
      false
    end
  end

  defp value(type, rest, stack, nodes) when type in 21..23 and length(stack) < 24,
    do: walk(rest, [type | stack], nodes)

  defp value(_, _, _, _), do: false

  defp skip(rest, count, stack, nodes) when count <= byte_size(rest),
    do: walk(binary_part(rest, count, byte_size(rest) - count), stack, nodes)

  defp skip(_, _, _, _), do: false
end
