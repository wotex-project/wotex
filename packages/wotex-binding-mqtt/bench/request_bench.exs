Code.require_file("support/client.exs", __DIR__)
Code.require_file("support/interactions.exs", __DIR__)

alias Wotex.Binding.MQTT.Bench.Interactions
alias Wotex.Binding.MQTT.{JSON, Mapping, Transport}

max_bytes = Interactions.max_bytes()
context = Interactions.execution_context()

inputs =
  Enum.map(Interactions.sizes(), fn {label, count} ->
    payload = Interactions.payload(count)
    retained = Interactions.delivery(Interactions.json(payload))

    {label,
     %{
       payload: payload,
       config: Interactions.config(%{publish: :ok, read: {:ok, retained}}),
       write: Interactions.request(:property, "state", :writeproperty, payload),
       read: Interactions.request(:property, "state", :readproperty, nil)
     }}
  end)

Benchee.run(
  %{
    "JSON.encode/2" => fn %{payload: payload} -> {:ok, _} = JSON.encode(payload, max_bytes) end,
    "Mapping.command/2 for writeproperty" => fn %{write: request} ->
      {:ok, _} = Mapping.command(request, max_bytes)
    end,
    "writeproperty: map, encode and publish" => fn %{write: request, config: config} ->
      {:ok, _} = Transport.request(request, context, config)
    end,
    "readproperty: retained read and decode" => fn %{read: request, config: config} ->
      {:ok, _} = Transport.request(request, context, config)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/request.md",
     title: "# Form mapping and Runtime transport requests",
     description: """
     The `c:Wotex.Runtime.Transport.request/3` callback of
     `Wotex.Binding.MQTT.Transport` for Runtime requests selected from a
     synthetic Thing Description, against an in-memory client port. A
     `writeproperty` request maps its Form to a PUBLISH
     `Wotex.Binding.MQTT.Command`, encodes the value and returns the
     `:accepted` result the client acknowledgement produces; a `readproperty`
     request maps a retained SUBSCRIBE command, checks the retained delivery
     against its Topic Filter and decodes it. The value is a JSON object with
     one, 16 or 256 members. `Wotex.Binding.MQTT.Mapping.command/2` and
     `Wotex.Binding.MQTT.JSON.encode/2` alone show the mapping and encoding
     shares of a publish.
     """}
  ]
)
