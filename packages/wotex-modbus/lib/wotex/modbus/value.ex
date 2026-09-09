defmodule Wotex.Modbus.Value do
  @moduledoc """
  Converts exact-width Modbus registers to and from typed scalar values.

  `decode/3` accepts the exact register count required by `t:kind/0` and returns
  a signed or unsigned integer or an IEEE 754 floating-point value. `encode/3`
  performs the inverse conversion while rejecting overflow and lossy integer
  coercion. Byte order within each 16-bit register and word order across a
  multi-register value are explicit options; both default to big-endian.

  Conversion is pure and does not infer a type, unit, scale, or semantic meaning
  from a register range. Invalid option combinations, wrong-width input,
  out-of-range registers, unsupported kinds, and non-representable values return
  `Wotex.Modbus.Error`. The consumer or Form mapping must select the conversion
  defined by the addressed data model.
  """

  alias Wotex.Modbus.Error

  @widths %{uint16: 1, int16: 1, uint32: 2, int32: 2, uint64: 4, int64: 4, float32: 2, float64: 4}
  @type kind :: :uint16 | :int16 | :uint32 | :int32 | :uint64 | :int64 | :float32 | :float64

  @doc "Decodes exact-width registers; rejects non-finite IEEE754 values."
  @spec decode(term(), kind(), keyword()) :: {:ok, number()} | {:error, Error.t()}
  def decode(registers, kind, opts \\ []) do
    with {:ok, width} <- width(kind),
         :ok <- orders(opts),
         :ok <- registers(registers, width) do
      registers
      |> reorder(opts)
      |> bytes()
      |> decode_scalar(kind)
    end
  end

  @doc "Encodes a scalar, rejecting overflow and lossy integer conversion."
  @spec encode(term(), kind(), keyword()) :: {:ok, [non_neg_integer()]} | {:error, Error.t()}
  def encode(value, kind, opts \\ []) do
    with {:ok, _width} <- width(kind),
         :ok <- orders(opts),
         {:ok, bytes} <- encode_scalar(value, kind) do
      {:ok, reorder(for(<<register::16 <- bytes>>, do: register), opts)}
    end
  end

  defp width(kind) do
    case Map.fetch(@widths, kind) do
      {:ok, width} -> {:ok, width}
      :error -> {:error, Error.new(:unsupported_type, :type)}
    end
  end

  defp orders(opts), do: orders(opts, %{})
  defp orders([], _), do: :ok

  defp orders([{key, value} | rest], seen)
       when key in [:byte_order, :word_order] and value in [:big, :little] and
              not is_map_key(seen, key),
       do: orders(rest, Map.put(seen, key, true))

  defp orders(_, _), do: {:error, Error.new(:invalid_order)}

  defp registers([], 0), do: :ok

  defp registers([value | rest], width)
       when width > 0 and is_integer(value) and value in 0..65_535,
       do: registers(rest, width - 1)

  defp registers(_, _), do: {:error, Error.new(:invalid_value, :registers)}

  defp reorder(values, opts) do
    values =
      if Keyword.get(opts, :word_order, :big) == :little, do: Enum.reverse(values), else: values

    if Keyword.get(opts, :byte_order, :big) == :little do
      Enum.map(values, fn value ->
        <<swapped::16>> = <<rem(value, 256), div(value, 256)>>
        swapped
      end)
    else
      values
    end
  end

  defp bytes(values), do: for(value <- values, into: <<>>, do: <<value::16>>)

  defp decode_scalar(<<value::16>>, :uint16), do: {:ok, value}

  defp decode_scalar(<<value::16-signed>>, :int16), do: {:ok, value}

  defp decode_scalar(<<value::32>>, :uint32), do: {:ok, value}

  defp decode_scalar(<<value::32-signed>>, :int32), do: {:ok, value}

  defp decode_scalar(<<value::64>>, :uint64), do: {:ok, value}

  defp decode_scalar(<<value::64-signed>>, :int64), do: {:ok, value}
  defp decode_scalar(<<value::32-float>>, :float32), do: {:ok, value}
  defp decode_scalar(<<value::64-float>>, :float64), do: {:ok, value}
  defp decode_scalar(_, _), do: {:error, Error.new(:invalid_value, :value)}

  defp encode_scalar(value, :uint16) when is_integer(value) and value >= 0 and value <= 65_535,
    do: {:ok, <<value::16>>}

  defp encode_scalar(value, :int16) when is_integer(value) and value >= -32_768 and value <= 32_767,
    do: {:ok, <<value::16-signed>>}

  defp encode_scalar(value, :uint32)
       when is_integer(value) and value >= 0 and value <= 4_294_967_295,
       do: {:ok, <<value::32>>}

  defp encode_scalar(value, :int32)
       when is_integer(value) and value >= -2_147_483_648 and value <= 2_147_483_647,
       do: {:ok, <<value::32-signed>>}

  defp encode_scalar(value, :uint64)
       when is_integer(value) and value >= 0 and value <= 18_446_744_073_709_551_615,
       do: {:ok, <<value::64>>}

  defp encode_scalar(value, :int64)
       when is_integer(value) and value >= -9_223_372_036_854_775_808 and
              value <= 9_223_372_036_854_775_807,
       do: {:ok, <<value::64-signed>>}

  defp encode_scalar(value, :float32)
       when is_float(value) and abs(value) <= 3.402_823_466_385_288_6e38,
       do: {:ok, <<value::32-float>>}

  defp encode_scalar(value, :float64) when is_float(value), do: {:ok, <<value::64-float>>}
  defp encode_scalar(_, _), do: {:error, Error.new(:invalid_value, :value)}
end
