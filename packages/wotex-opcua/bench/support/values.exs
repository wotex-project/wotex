defmodule Wotex.OPCUA.Bench.Values do
  @moduledoc false

  # Typed DataValues of growing size with source and server timestamps, in the
  # atom-keyed form of `Wotex.OPCUA.Binary` and in the native JSON form that
  # `Wotex.OPCUA.Value.native_result/1` projects.

  # 2026-01-01T00:00:00Z in 100 ns ticks since 1601-01-01T00:00:00Z.
  @source_ticks 134_116_128_000_000_000
  @server_ticks @source_ticks + 25_000

  @spec inputs() :: %{String.t() => map()}
  def inputs do
    %{
      "Double scalar" => input("Double", false, 21.5),
      "ByteString array of 64 x 32 bytes" => input("ByteString", true, byte_strings(64, 32)),
      "Double array of 1024" => input("Double", true, Enum.map(1..1024, &(&1 * 0.25)))
    }
  end

  @spec data_value(String.t(), boolean(), term()) :: map()
  def data_value(type, array, value) do
    %{
      has_value: true,
      value: %{type: type, array: array, value: value},
      status: 0,
      source_timestamp: @source_ticks,
      server_timestamp: @server_ticks
    }
  end

  @spec native_data_value(String.t(), boolean(), term()) :: map()
  def native_data_value(type, array, value) do
    %{
      "has_value" => true,
      "value" => %{"type" => type, "array" => array, "value" => native(type, array, value)},
      "status" => 0,
      "source_timestamp" => @source_ticks,
      "server_timestamp" => @server_ticks
    }
  end

  @spec byte_strings(pos_integer(), pos_integer()) :: [binary()]
  def byte_strings(count, size) do
    Enum.map(1..count, fn index ->
      for offset <- 1..size, into: <<>>, do: <<rem(index * 131 + offset * 29, 256)>>
    end)
  end

  defp input(type, array, value) do
    data_value = data_value(type, array, value)
    {:ok, bytes} = Wotex.OPCUA.Binary.encode_data_value(data_value)

    %{
      data_value: data_value,
      bytes: bytes,
      native: native_data_value(type, array, value)
    }
  end

  defp native("ByteString", true, values), do: Enum.map(values, &bytes_envelope/1)
  defp native("ByteString", false, value), do: bytes_envelope(value)
  defp native(_, _, value), do: value

  defp bytes_envelope(bytes), do: %{"type" => "bytes", "base64" => Base.encode64(bytes)}
end
