Code.require_file("support/values.exs", __DIR__)
Code.require_file("support/client.exs", __DIR__)
Code.require_file("support/credentials.exs", __DIR__)

alias Wotex.BACnet.Bench.{Client, Credentials, Values}
alias Wotex.Runtime.{ConsumedThing, Context}

profile = Wotex.BACnet.profile()

inputs =
  Map.new(Values.cases(), fn {label, type, value, property} ->
    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:example:bacnet:bench",
        "title" => "BACnet benchmark Thing",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{
          "value" => %{
            "forms" => [
              %{
                "href" => "bacnet://1234/2,1/#{property}",
                "op" => ["readproperty", "writeproperty"],
                "bacv:hasDataType" => %{"@type" => type}
              }
            ]
          }
        }
      })

    config = [client: Client, target: "1234", reply: Values.encode!(value, type), timeout: 1000]

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{bacnet: {Wotex.BACnet.Transport, config}},
        credentials: {Credentials, []}
      )

    {label, %{consumed: consumed, value: value}}
  end)

context = Context.new!(request_id: "bench-1")

Benchee.run(
  %{
    "readproperty" => fn %{consumed: consumed, value: value} ->
      {:ok, %{payload: ^value}} = ConsumedThing.read_property(consumed, "value", context)
    end,
    "writeproperty" => fn %{consumed: consumed, value: value} ->
      {:ok, _} = ConsumedThing.write_property(consumed, "value", value, context)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/runtime.md",
     title: "# Runtime Property interactions through the BACnet Transport",
     description: """
     `Wotex.Runtime.ConsumedThing.read_property/3` and `write_property/4` with
     `Wotex.BACnet.Transport` and a pure in-process `Wotex.BACnet.Client` that
     returns the value or the write acknowledgement without a process or socket.
     The values are a Real present-value and CharacterString values of 64 bytes
     and 1 KiB. Each interaction covers Form selection, `nosec` credential
     resolution, the Runtime request and deadline budget, Form mapping, session
     open and close, facade admission, native value validation and the Runtime
     result, so it is the complete in-process cost of one Property interaction
     apart from the BACnet/IP exchange.
     """}
  ]
)
