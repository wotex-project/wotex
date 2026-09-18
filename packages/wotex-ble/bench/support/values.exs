defmodule Wotex.BLE.Bench.Values do
  @moduledoc false

  # Synthetic GATT attribute values for the Runtime and mapping benchmarks.
  # The Environmental Sensing service (0x181A) and Temperature characteristic
  # (0x2A6E) are Bluetooth SIG assigned numbers; the 128-bit identities are
  # synthetic. Text is deterministic UTF-8.

  alias Wotex.BLE.Value

  @codecs %{"int16" => :int16, "float64" => :float64, "utf8" => :utf8}

  @spec cases() :: [{String.t(), String.t(), String.t(), String.t(), term()}]
  def cases do
    [
      {"int16, 2 bytes", "181a", "2a6e", "int16", -1234},
      {"float64, 8 bytes", "181a", "2a6e", "float64", 21.375},
      {"UTF-8 text, 512 bytes", "a1b2c3d4-0001-4e5f-8a9b-0123456789ab",
       "a1b2c3d4-0002-4e5f-8a9b-0123456789ab", "utf8", text(512)}
    ]
  end

  @spec text(pos_integer()) :: binary()
  def text(size), do: binary_part(:binary.copy("Zone 4 supply air ", div(size, 18) + 1), 0, size)

  @spec href(String.t(), String.t()) :: String.t()
  def href(service, characteristic), do: "ble://peer/#{service}/#{characteristic}"

  @spec form(String.t(), String.t(), String.t()) :: map()
  def form(service, characteristic, type) do
    %{
      "href" => href(service, characteristic),
      "op" => ["readproperty", "writeproperty"],
      "wotex:bleValueType" => type,
      "wotex:bleByteOrder" => "little",
      "example:note" => %{"retain" => true}
    }
  end

  @spec bytes!(term(), String.t()) :: binary()
  def bytes!(value, type) do
    {:ok, bytes} = Value.encode(value, Map.fetch!(@codecs, type), byte_order: :little)
    bytes
  end
end
