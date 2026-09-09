defmodule Wotex.BLE.Value do
  @moduledoc """
  Encodes and decodes bounded scalar GATT attribute values.

  `encode/3` and `decode/3` require an explicit `t:codec/0`. Integer widths,
  IEEE 754 floating-point widths, booleans, UTF-8 text, and opaque bytes are
  supported. Multi-byte values use caller-selected `:little` or `:big` byte
  order; little-endian is the documented default. Input and output are limited
  to 512 bytes, and exact-width codecs reject mismatched binaries.

  Conversion is pure and never infers a scalar type, unit, scale, or semantic
  meaning from the bytes. Malformed UTF-8, out-of-range integers, non-finite or
  wrongly sized values, unsupported codecs, and invalid options return
  `Wotex.BLE.Error`. The consumer remains responsible for selecting a codec that
  matches the characteristic specification.
  """

  import Bitwise
  alias Wotex.BLE.Error

  @integers %{
    uint8: {8, false},
    int8: {8, true},
    uint16: {16, false},
    int16: {16, true},
    uint32: {32, false},
    int32: {32, true},
    uint64: {64, false},
    int64: {64, true}
  }
  @type codec ::
          :uint8
          | :int8
          | :uint16
          | :int16
          | :uint32
          | :int32
          | :uint64
          | :int64
          | :float32
          | :float64
          | :boolean
          | :utf8
          | :bytes

  @doc "Encodes a selected scalar or at most 512 bytes, defaulting to little-endian."
  @spec encode(term(), term(), term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value, type, options) do
    with {:ok, order} <- byte_order(options), do: encode_value(value, type, order)
  end

  @doc "Decodes an exact-width scalar or at most 512 bytes without inferring its type."
  @spec decode(term(), term(), term()) :: {:ok, term()} | {:error, Error.t()}
  def decode(bytes, type, options) when is_binary(bytes) and byte_size(bytes) <= 512 do
    with {:ok, order} <- byte_order(options), do: decode_value(bytes, type, order)
  end

  def decode(_, _, _), do: invalid()

  defp byte_order([]), do: {:ok, :little}
  defp byte_order(byte_order: order) when order in [:little, :big], do: {:ok, order}
  defp byte_order(_), do: invalid()

  defp encode_value(value, type, order)
       when is_atom(type) and is_map_key(@integers, type) and is_integer(value) do
    {bits, signed?} = Map.fetch!(@integers, type)
    sign_bits = if signed?, do: 1, else: 0
    min = if signed?, do: -(1 <<< (bits - 1)), else: 0
    max = (1 <<< (bits - sign_bits)) - 1

    if value >= min and value <= max,
      do: {:ok, ordered(<<value::size(bits)>>, order)},
      else: invalid()
  end

  defp encode_value(value, :float32, order)
       when is_float(value) and abs(value) <= 3.402_823_466_385_288_6e38,
       do: {:ok, ordered(<<value::float-32>>, order)}

  defp encode_value(value, :float64, order) when is_float(value),
    do: {:ok, ordered(<<value::float-64>>, order)}

  defp encode_value(true, :boolean, _), do: {:ok, <<1>>}
  defp encode_value(false, :boolean, _), do: {:ok, <<0>>}

  defp encode_value(value, type, _)
       when type in [:bytes, :utf8] and is_binary(value) and byte_size(value) <= 512 do
    if type == :bytes or String.valid?(value), do: {:ok, value}, else: invalid()
  end

  defp encode_value(_, _, _), do: invalid()

  defp decode_value(bytes, type, order) when is_atom(type) and is_map_key(@integers, type) do
    {bits, signed?} = Map.fetch!(@integers, type)

    if byte_size(bytes) * 8 == bits do
      value = :binary.decode_unsigned(bytes, order)
      value = if signed? and value >= 1 <<< (bits - 1), do: value - (1 <<< bits), else: value
      {:ok, value}
    else
      invalid()
    end
  end

  defp decode_value(bytes, type, order) when type in [:float32, :float64],
    do: decode_float(ordered(bytes, order), type)

  defp decode_value(<<1>>, :boolean, _), do: {:ok, true}
  defp decode_value(<<0>>, :boolean, _), do: {:ok, false}
  defp decode_value(bytes, type, order), do: encode_value(bytes, type, order)

  defp decode_float(<<value::float-32>>, :float32), do: {:ok, value}
  defp decode_float(<<value::float-64>>, :float64), do: {:ok, value}
  defp decode_float(_, _), do: invalid()

  defp ordered(bytes, :big), do: bytes

  defp ordered(bytes, :little) do
    bytes
    |> :binary.bin_to_list()
    |> Enum.reverse()
    |> :binary.list_to_bin()
  end

  defp invalid, do: {:error, Error.new(:invalid_value)}
end
