alias Wotex.Modbus.Value

swapped = [byte_order: :little, word_order: :little]

inputs =
  Map.new(
    [
      {"int16, 1 register", :int16, -1234},
      {"float32, 2 registers", :float32, 21.375},
      {"float64, 4 registers", :float64, 101_325.062_5}
    ],
    fn {label, kind, value} ->
      {:ok, big} = Value.encode(value, kind)
      {:ok, little} = Value.encode(value, kind, swapped)
      {label, %{kind: kind, value: value, big: big, little: little}}
    end
  )

Benchee.run(
  %{
    "decode big-endian" => fn %{kind: kind, big: registers} ->
      {:ok, _} = Value.decode(registers, kind)
    end,
    "decode little-endian bytes and words" => fn %{kind: kind, little: registers} ->
      {:ok, _} = Value.decode(registers, kind, swapped)
    end,
    "encode big-endian" => fn %{kind: kind, value: value} ->
      {:ok, _} = Value.encode(value, kind)
    end,
    "encode little-endian bytes and words" => fn %{kind: kind, value: value} ->
      {:ok, _} = Value.encode(value, kind, swapped)
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
     title: "# Typed register value conversion",
     description: """
     `Wotex.Modbus.Value.decode/3` and `Wotex.Modbus.Value.encode/3` for a
     signed 16-bit integer, an IEEE 754 single-precision value in two registers
     and a double-precision value in four registers, with the default big-endian
     byte and word order and with both orders swapped. Each call validates the
     order options and the exact register width.
     """}
  ]
)
