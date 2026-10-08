defmodule Wotex.Zigbee.ZCL.Value do
  @moduledoc """
  Inert values for the finite ZCL revision 8 scalar and short-string profile.

  Boolean, uint8/16/32, int8/16 and short octet/character strings retain their
  exact type, non-value and wire bytes. Character strings remain encoded
  bytes; the consumer supplies descriptor and manufacturer interpretation.
  A numeric full-range definition requires explicit `full_range` policy.
  These values grant no authority to write or configure an attribute.
  """

  import Bitwise

  alias Wotex.Zigbee.Error

  @numeric %{
    0x20 => {1, :unsigned},
    0x21 => {2, :unsigned},
    0x23 => {4, :unsigned},
    0x28 => {1, :signed},
    0x29 => {2, :signed}
  }

  @doc "Returns the admitted reporting category, refusing uncatalogued types."
  @spec category(byte()) :: {:ok, :analog | :discrete} | {:error, Error.t()}
  def category(type) when is_map_key(@numeric, type), do: {:ok, :analog}
  def category(type) when type in [0x10, 0x41, 0x42], do: {:ok, :discrete}
  def category(_), do: failure(:invalid_value)

  @doc "Encodes one admitted value, including an explicit standard `:null`."
  @spec encode(byte(), term(), boolean()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(type, value, full_range \\ false)

  def encode(type, value, full) when is_boolean(full) and is_map_key(@numeric, type) do
    {width, sign} = Map.fetch!(@numeric, type)
    {low, high, non} = limits(width, sign)

    cond do
      value == :null and not full ->
        {:ok, pack(non, width, sign)}

      is_integer(value) and value >= low and value <= high and (full or value != non) ->
        {:ok, pack(value, width, sign)}

      true ->
        failure(:invalid_value)
    end
  end

  def encode(0x10, :null, false), do: {:ok, <<0xFF>>}
  def encode(0x10, false, false), do: {:ok, <<0>>}
  def encode(0x10, true, false), do: {:ok, <<1>>}
  def encode(type, :null, false) when type in [0x41, 0x42], do: {:ok, <<0xFF>>}

  def encode(type, value, false)
      when type in [0x41, 0x42] and is_binary(value) and byte_size(value) <= 64,
      do: {:ok, <<byte_size(value), value::binary>>}

  def encode(_, _, _), do: failure(:invalid_value)

  @doc """
  Decodes a value prefix from at most 128 bytes, returning value, raw bytes and tail.

  Standard non-values become `:null`. Explicit numeric full-range policy keeps
  the otherwise reserved integer. An uncatalogued byte type returns
  `{:unsupported, type}` with the whole opaque remainder and no inferred tail.
  Truncated or forbidden known values fail.
  """
  @spec decode(byte(), binary(), boolean()) ::
          {:ok, term(), binary(), binary()} | {:error, Error.t()}
  def decode(type, bytes, full_range \\ false)

  def decode(type, bytes, full)
      when is_integer(type) and type in 0..255 and
             is_binary(bytes) and byte_size(bytes) <= 128 and is_boolean(full) do
    decode_value(type, bytes, full)
  end

  def decode(_, _, _), do: failure(:invalid_frame)

  defp decode_value(type, bytes, full) when is_map_key(@numeric, type) do
    {width, sign} = Map.fetch!(@numeric, type)

    if byte_size(bytes) >= width do
      <<raw::binary-size(^width), tail::binary>> = bytes
      value = unpack(raw, width, sign)
      {_, _, non} = limits(width, sign)
      {:ok, if(value == non and not full, do: :null, else: value), raw, tail}
    else
      failure(:invalid_frame)
    end
  end

  defp decode_value(_, _, true), do: failure(:invalid_frame)
  defp decode_value(0x10, <<0xFF, tail::binary>>, false), do: {:ok, :null, <<0xFF>>, tail}

  defp decode_value(0x10, <<value, tail::binary>>, false) when value in [0, 1],
    do: {:ok, value == 1, <<value>>, tail}

  defp decode_value(type, <<0xFF, tail::binary>>, false) when type in [0x41, 0x42],
    do: {:ok, :null, <<0xFF>>, tail}

  defp decode_value(type, <<length, bytes::binary>>, false)
       when type in [0x41, 0x42] and
              length <= 64 and byte_size(bytes) >= length do
    <<value::binary-size(^length), tail::binary>> = bytes
    {:ok, value, <<length, value::binary>>, tail}
  end

  defp decode_value(type, bytes, false) when type not in [0x10, 0x41, 0x42],
    do: {:ok, {:unsupported, type}, bytes, <<>>}

  defp decode_value(_, _, _), do: failure(:invalid_frame)

  defp limits(width, :unsigned), do: {0, (1 <<< (width * 8)) - 1, (1 <<< (width * 8)) - 1}

  defp limits(width, :signed),
    do: {-(1 <<< (width * 8 - 1)), (1 <<< (width * 8 - 1)) - 1, -(1 <<< (width * 8 - 1))}

  defp pack(value, width, :unsigned), do: <<value::little-unsigned-size(width * 8)>>
  defp pack(value, width, :signed), do: <<value::little-signed-size(width * 8)>>
  defp unpack(raw, _, :unsigned), do: :binary.decode_unsigned(raw, :little)

  defp unpack(raw, width, :signed) do
    value = :binary.decode_unsigned(raw, :little)
    if value >= 1 <<< (width * 8 - 1), do: value - (1 <<< (width * 8)), else: value
  end

  defp failure(kind), do: {:error, %Error{kind: kind, operation: :zcl_value}}
end
