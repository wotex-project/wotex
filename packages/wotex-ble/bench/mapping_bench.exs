Code.require_file("support/values.exs", __DIR__)

alias Wotex.BLE.{Address, Mapping}
alias Wotex.BLE.Bench.Values

inputs =
  Map.new(Values.cases(), fn {label, service, characteristic, type, value} ->
    {:ok, form} = Wotex.Form.new(Values.form(service, characteristic, type))
    {:ok, %{message: message}} = Mapping.command(form, :writeproperty, value)
    {label, %{form: form, value: value, message: message}}
  end)

Benchee.run(
  %{
    "map readproperty Form" => fn %{form: form} ->
      {:ok, _} = Mapping.command(form, :readproperty, nil)
    end,
    "map writeproperty Form" => fn %{form: form, value: value} ->
      {:ok, _} = Mapping.command(form, :writeproperty, value)
    end,
    "admit mapped write message" => fn %{message: message} ->
      :ok = Address.validate_message(message)
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
     title: "# Form mapping and message admission",
     description: """
     `Wotex.BLE.Mapping.command/4` over `ble://peer/<service>/<characteristic>`
     Forms with explicit `wotex:bleValueType` and `wotex:bleByteOrder` selectors
     and an unknown extension term: the Environmental Sensing Temperature
     characteristic (SIG UUIDs 0x181A and 0x2A6E) as `int16` and as `float64`,
     and 512 bytes of `utf8` text on a characteristic with 128-bit vendor UUIDs.
     Mapping revalidates the Form for its context, checks the operation and
     selectors, parses the device and both UUIDs from the href, and for
     `writeproperty` encodes the input with the selected codec.
     `Wotex.BLE.Address.validate_message/1` is the facade's admission of the
     mapped write message, including the 512-byte value limit.
     """}
  ]
)
