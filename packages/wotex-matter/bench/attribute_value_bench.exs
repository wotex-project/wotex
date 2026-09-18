Code.require_file("support/values.exs", __DIR__)

alias Wotex.Matter.Bench.Values
alias Wotex.Matter.{Descriptor, TLV}

Benchee.run(
  %{
    "schema value to TLV element" => fn input ->
      {:ok, _} = Descriptor.to_element(input.kind, input.path, input.operation, input.value)
    end,
    "TLV element to schema value" => fn input ->
      {:ok, _} = Descriptor.from_element(input.kind, input.path, input.operation, input.element)
    end,
    "encode TLV bytes" => fn %{element: element} -> {:ok, _} = TLV.encode([element]) end,
    "decode TLV bytes" => fn %{bytes: bytes} -> {:ok, [_]} = TLV.decode(bytes) end
  },
  inputs: Values.inputs(),
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/attribute_value.md",
     title: "# Matter attribute values and bounded TLV",
     description: """
     `Wotex.Matter.Descriptor.to_element/4` and `from_element/4` convert between
     admitted schema values and one anonymous TLV element through the descriptor
     registry; `Wotex.Matter.TLV.encode/1` (which verifies its output by decoding
     it again) and `decode/1` convert that element to and from bytes. Inputs are
     a Thermostat OccupiedHeatingSetpoint write (one node), a Descriptor
     ServerList read of 64 clusters (65 nodes) and an AccessControl ACL write of
     32 entries, each with four CASE subjects and two targets (545 nodes).
     """}
  ]
)
