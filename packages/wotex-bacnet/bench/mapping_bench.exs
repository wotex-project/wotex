Code.require_file("support/values.exs", __DIR__)

alias Wotex.BACnet.{Address, Mapping}
alias Wotex.BACnet.Bench.Values

# Forms of the draft BACnet profile for device 1234 and analog-value 1. The
# write Forms carry an explicit `bacv:hasDataType` and an unknown extension.
inputs =
  Map.new(Values.cases(), fn {label, type, value, property} ->
    {:ok, form} =
      Wotex.Form.new(%{
        "href" => "bacnet://1234/2,1/#{property}",
        "op" => ["readproperty", "writeproperty"],
        "bacv:hasDataType" => %{"@type" => type},
        "example:note" => %{"retain" => true}
      })

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
     `Wotex.BACnet.Mapping.command/4` over `bacnet://1234/2,1/<property>` Forms
     for a Real present-value and CharacterString object-name (64 bytes) and
     description (1 KiB), each with a `bacv:hasDataType` selector and an
     unknown extension term. Mapping checks the operation and type selector,
     parses the device, object and Property address, and for `writeproperty`
     encodes the input as the declared type and validates it as a native write.
     `Wotex.BACnet.Address.validate_message/1` is the facade's admission of the
     mapped write message before a client is called.
     """}
  ]
)
