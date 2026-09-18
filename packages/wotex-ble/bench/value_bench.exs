alias Wotex.BLE.Value

inputs =
  Map.new(
    [
      {"int16, 2 bytes", :int16, -1234},
      {"float64, 8 bytes", :float64, 101_325.062_5},
      {"UTF-8 text, 512 bytes", :utf8, binary_part(:binary.copy("Zone 4 supply air ", 29), 0, 512)}
    ],
    fn {label, codec, value} ->
      {:ok, little} = Value.encode(value, codec, [])
      {:ok, big} = Value.encode(value, codec, byte_order: :big)
      {label, %{codec: codec, value: value, little: little, big: big}}
    end
  )

Benchee.run(
  %{
    "encode little-endian" => fn %{codec: codec, value: value} ->
      {:ok, _} = Value.encode(value, codec, [])
    end,
    "decode little-endian" => fn %{codec: codec, little: bytes} ->
      {:ok, _} = Value.decode(bytes, codec, [])
    end,
    "encode big-endian" => fn %{codec: codec, value: value} ->
      {:ok, _} = Value.encode(value, codec, byte_order: :big)
    end,
    "decode big-endian" => fn %{codec: codec, big: bytes} ->
      {:ok, _} = Value.decode(bytes, codec, byte_order: :big)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/value.md",
     title: "# GATT attribute value conversion",
     description: """
     `Wotex.BLE.Value.encode/3` and `Wotex.BLE.Value.decode/3` for a signed
     16-bit integer, an IEEE 754 double and 512 bytes of UTF-8 text (the
     attribute value limit), with the default little-endian and with big-endian
     byte order. Integer codecs check the range, floating-point codecs the exact
     width, and text is checked as valid UTF-8; byte order does not apply to
     text.
     """}
  ]
)
