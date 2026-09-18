Code.require_file("support/values.exs", __DIR__)
Code.require_file("support/client.exs", __DIR__)
Code.require_file("support/credentials.exs", __DIR__)

alias Wotex.BLE.Bench.{Client, Credentials, Values}
alias Wotex.Runtime.{ConsumedThing, Context}

profile = Wotex.BLE.profile()

inputs =
  Map.new(Values.cases(), fn {label, service, characteristic, type, value} ->
    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:example:ble:bench",
        "title" => "BLE benchmark Thing",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{"value" => %{"forms" => [Values.form(service, characteristic, type)]}}
      })

    config = [client: Client, target: "peer", reply: Values.bytes!(value, type), timeout: 1000]

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{ble: {Wotex.BLE.Transport, config}},
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
      {:ok, %{payload: :written}} =
        ConsumedThing.write_property(consumed, "value", value, context)
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
     title: "# Runtime Property interactions through the BLE Transport",
     description: """
     `Wotex.Runtime.ConsumedThing.read_property/3` and `write_property/4` with
     `Wotex.BLE.Transport` on the one-shot profile and a pure in-process
     `Wotex.BLE.Client` that returns the attribute bytes or the write
     acknowledgement without a process, Port or D-Bus call. The values are an
     `int16`, a `float64` and 512 bytes of `utf8` text. Each interaction covers
     Form selection, `nosec` credential resolution, the Runtime request and
     deadline budget, Form mapping and value encoding, session open and close,
     facade admission, value decoding and the Runtime result, so it is the
     complete in-process cost of one Property interaction apart from the GATT
     procedure.
     """}
  ]
)
