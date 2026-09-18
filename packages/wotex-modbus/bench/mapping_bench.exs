Code.require_file("support/frames.exs", __DIR__)

alias Wotex.Modbus.Bench.Frames
alias Wotex.Modbus.{Codec, Mapping}

tid = Frames.transaction_id()

# Forms of the draft Modbus profile. Endpoints use the 192.0.2.0/24
# documentation range; no connection is opened.
cases = [
  {"read 64 coils",
   %{
     "href" => "modbus+tcp://192.0.2.10/17/1?quantity=64",
     "op" => "readproperty",
     "modv:entity" => "Coil"
   }, :readproperty, nil, Frames.coils(64)},
  {"read float32 holding registers",
   %{
     "href" => "modbus+tcp://192.0.2.10:1502/17/40?quantity=2",
     "op" => "readproperty",
     "modv:entity" => "HoldingRegister",
     "modv:type" => "xsd:float",
     "vendor:calibration" => %{"offset" => 0.5}
   }, :readproperty, nil, [0x41AB, 0]},
  {"write float64 with swapped words",
   %{
     "href" => "modbus+tcp://192.0.2.10/17/101?quantity=4",
     "op" => "writeproperty",
     "modv:entity" => "HoldingRegister",
     "modv:type" => "xsd:double",
     "modv:mostSignificantWord" => false
   }, :writeproperty, 101_325.062_5, :written}
]

inputs =
  Map.new(cases, fn {label, form, operation, input, raw} ->
    {:ok, mapping} = Mapping.command(form, operation, input)

    response =
      case raw do
        :written -> Frames.write_echo(mapping.command)
        [bit | _] = coils when is_boolean(bit) -> Frames.read_coils_response(coils)
        registers -> Frames.read_registers_response(registers)
      end

    {label,
     %{
       form: form,
       operation: operation,
       input: input,
       mapping: mapping,
       raw: raw,
       response: response
     }}
  end)

Benchee.run(
  %{
    "map Form to command" => fn %{form: form, operation: operation, input: input} ->
      {:ok, _} = Mapping.command(form, operation, input)
    end,
    "convert mapped result" => fn %{mapping: mapping, raw: raw} ->
      {:ok, _} = Mapping.decode(mapping, raw)
    end,
    "map, encode, parse and convert" => fn context ->
      %{form: form, operation: operation, input: input, response: response} = context
      {:ok, mapping} = Mapping.command(form, operation, input)
      {:ok, _} = Codec.encode(mapping.command, tid)
      {:ok, frame, ""} = Codec.decode(response)
      {:ok, raw} = Codec.response(frame, mapping.command, tid)
      {:ok, _} = Mapping.decode(mapping, raw)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/mapping.md",
     title: "# Form mapping and in-process exchange",
     description: """
     `Wotex.Modbus.Mapping.command/4` over three Forms of the draft Modbus
     profile: a 64-coil `readproperty`, a `readproperty` of an `xsd:float`
     holding-register pair with an unknown extension term, and a
     `writeproperty` of an `xsd:double` in four registers with swapped word
     order. Mapping validates the Form, the operation, the `modbus+tcp`
     endpoint and one-based address, and encodes typed input.
     `Wotex.Modbus.Mapping.decode/2` converts the raw result. The combined job
     adds `Wotex.Modbus.Codec` request encoding and response parsing, which is
     the in-process work of one Runtime interaction without the socket.
     """}
  ]
)
