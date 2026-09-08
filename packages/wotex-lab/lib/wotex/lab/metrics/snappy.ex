defmodule Wotex.Lab.Metrics.Snappy do
  @moduledoc """
  Snappy block-format compression in pure Elixir, for remote-write bodies.

  The block format (google/snappy `format_description.txt`, BSD-3-Clause) is
  a varint preamble with the uncompressed length followed by elements whose
  tag byte selects a literal (tag `00`, length in the upper six bits or in one
  to four trailing little-endian bytes) or a back-reference copy: tag `01`
  carries a 4..11 byte length and an 11-bit offset, tag `10` a 1..64 byte
  length and a 16-bit little-endian offset, tag `11` the same length with a
  32-bit offset. This encoder emits literals and `10` copies found through a
  four-byte hash of earlier positions within a 64 KiB window, which is a
  valid Snappy stream for every decoder; `decompress/1` understands all four
  element kinds so a round trip is provable and foreign bodies can be read.
  Both directions are bounded by `:max_bytes` (16 MiB) and refuse malformed
  input with a typed error rather than raising. Framing (`sNaPpY` stream
  chunks) is deliberately not implemented: remote write uses the raw block.
  """

  import Bitwise

  alias Wotex.Lab.Error

  @max_bytes 16 * 1_048_576
  @window 65_535
  @max_copy 64
  @min_match 4

  @doc "Compresses `data` into one Snappy block."
  @spec compress(binary(), keyword()) :: {:ok, binary()} | {:error, Error.t()}
  def compress(data, opts \\ [])

  def compress(data, opts) when is_binary(data) and is_list(opts) do
    max = Keyword.get(opts, :max_bytes, @max_bytes)

    if byte_size(data) > max do
      {:error, Error.new(:oversized, :snappy, "input exceeds #{max} bytes")}
    else
      {:ok, IO.iodata_to_binary([varint(byte_size(data)) | elements(data, 0, 0, %{}, [])])}
    end
  end

  def compress(_data, _opts),
    do: {:error, Error.new(:invalid_input, :snappy, "input must be binary")}

  @doc "Decompresses one Snappy block."
  @spec decompress(binary(), keyword()) :: {:ok, binary()} | {:error, Error.t()}
  def decompress(block, opts \\ [])

  def decompress(block, opts) when is_binary(block) and is_list(opts) do
    max = Keyword.get(opts, :max_bytes, @max_bytes)

    with {:ok, length, rest} <- read_varint(block, 0, 0),
         :ok <- bounded(length, max) do
      decode(rest, <<>>, length)
    end
  end

  def decompress(_block, _opts),
    do: {:error, Error.new(:invalid_input, :snappy, "block must be binary")}

  defp elements(data, position, literal_start, _table, acc)
       when position + @min_match > byte_size(data) do
    Enum.reverse(flush(acc, data, literal_start, byte_size(data)))
  end

  defp elements(data, position, literal_start, table, acc) do
    key = binary_part(data, position, @min_match)

    case Map.fetch(table, key) do
      {:ok, previous} when position - previous <= @window ->
        length = match_length(data, previous, position)
        acc = flush(acc, data, literal_start, position)
        acc = [copy(length, position - previous) | acc]
        table = Map.put(table, key, position)
        elements(data, position + length, position + length, table, acc)

      _missing_or_far ->
        elements(data, position + 1, literal_start, Map.put(table, key, position), acc)
    end
  end

  defp match_length(data, previous, position) do
    limit = min(@max_copy, byte_size(data) - position)

    :binary.longest_common_prefix([
      binary_part(data, previous, limit),
      binary_part(data, position, limit)
    ])
  end

  defp flush(acc, _data, start, stop) when stop <= start, do: acc

  defp flush(acc, data, start, stop) do
    literal(binary_part(data, start, stop - start), acc)
  end

  defp literal(<<chunk::binary-size(65_536), rest::binary>>, acc),
    do: literal(rest, [literal_element(chunk) | acc])

  defp literal(<<>>, acc), do: acc
  defp literal(chunk, acc), do: [literal_element(chunk) | acc]

  defp literal_element(chunk) do
    length = byte_size(chunk) - 1

    cond do
      length < 60 -> [<<length::6, 0::2>>, chunk]
      length < 256 -> [<<60::6, 0::2, length::8>>, chunk]
      true -> [<<61::6, 0::2, length::little-16>>, chunk]
    end
  end

  defp copy(length, offset), do: <<length - 1::6, 2::2, offset::little-16>>

  defp varint(value) when value < 128, do: <<value>>
  defp varint(value), do: <<1::1, value::7, varint(value >>> 7)::binary>>

  defp read_varint(<<0::1, byte::7, rest::binary>>, shift, acc),
    do: {:ok, acc ||| byte <<< shift, rest}

  defp read_varint(<<1::1, byte::7, rest::binary>>, shift, acc) when shift < 35,
    do: read_varint(rest, shift + 7, acc ||| byte <<< shift)

  defp read_varint(_block, _shift, _acc),
    do: {:error, Error.new(:malformed_block, :snappy, "preamble is not a varint")}

  defp bounded(length, max) when length <= max, do: :ok

  defp bounded(_length, max),
    do: {:error, Error.new(:oversized, :snappy, "output exceeds #{max} bytes")}

  defp decode(<<>>, output, length) when byte_size(output) == length, do: {:ok, output}

  defp decode(<<length::6, 0::2, rest::binary>>, output, total) when length < 60,
    do: take_literal(rest, length + 1, output, total)

  defp decode(<<60::6, 0::2, length::8, rest::binary>>, output, total),
    do: take_literal(rest, length + 1, output, total)

  defp decode(<<61::6, 0::2, length::little-16, rest::binary>>, output, total),
    do: take_literal(rest, length + 1, output, total)

  defp decode(<<62::6, 0::2, length::little-24, rest::binary>>, output, total),
    do: take_literal(rest, length + 1, output, total)

  defp decode(<<63::6, 0::2, length::little-32, rest::binary>>, output, total),
    do: take_literal(rest, length + 1, output, total)

  defp decode(<<high::3, length::3, 1::2, low::8, rest::binary>>, output, total),
    do: take_copy(rest, length + 4, high <<< 8 ||| low, output, total)

  defp decode(<<length::6, 2::2, offset::little-16, rest::binary>>, output, total),
    do: take_copy(rest, length + 1, offset, output, total)

  defp decode(<<length::6, 3::2, offset::little-32, rest::binary>>, output, total),
    do: take_copy(rest, length + 1, offset, output, total)

  defp decode(_block, _output, _total), do: malformed()

  defp take_literal(rest, length, output, total)
       when byte_size(rest) >= length and byte_size(output) + length <= total do
    <<chunk::binary-size(^length), rest::binary>> = rest
    decode(rest, output <> chunk, total)
  end

  defp take_literal(_rest, _length, _output, _total), do: malformed()

  defp take_copy(rest, length, offset, output, total)
       when offset > 0 and offset <= byte_size(output) and byte_size(output) + length <= total do
    decode(rest, output <> copy_bytes(output, offset, length), total)
  end

  defp take_copy(_rest, _length, _offset, _output, _total), do: malformed()

  # A copy may overlap its own output (offset < length): repeat the window.
  defp copy_bytes(output, offset, length) do
    window = binary_part(output, byte_size(output) - offset, offset)
    repeats = div(length, offset) + 1
    binary_part(:binary.copy(window, repeats), 0, length)
  end

  defp malformed, do: {:error, Error.new(:malformed_block, :snappy, "block is not valid Snappy")}
end
