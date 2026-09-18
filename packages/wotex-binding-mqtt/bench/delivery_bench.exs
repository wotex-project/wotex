Code.require_file("support/client.exs", __DIR__)
Code.require_file("support/interactions.exs", __DIR__)

alias Wotex.Binding.MQTT.Bench.Interactions
alias Wotex.Binding.MQTT.{Delivery, JSON, Transport}

max_bytes = Interactions.max_bytes()
topic = Interactions.state_topic()
config = Interactions.config(%{})
observe = Interactions.request(:property, "state", :observeproperty, nil)

inputs =
  Enum.map(Interactions.sizes(), fn {label, count} ->
    payload = Interactions.json(Interactions.payload(count))
    delivery = Interactions.delivery(payload, retain: false)
    {label, %{payload: payload, delivery: delivery}}
  end)

Benchee.run(
  %{
    "Delivery.new/2" => fn %{payload: payload} ->
      {:ok, _} = Delivery.new(payload, topic: topic, qos: 1, retain: false)
    end,
    "JSON.decode/2" => fn %{payload: payload} -> {:ok, _} = JSON.decode(payload, max_bytes) end,
    "decode_frame/3" => fn %{delivery: delivery} ->
      {:ok, _, %{topic: ^topic}} = Transport.decode_frame(delivery, observe, config)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/delivery.md",
     title: "# Delivery decoding in the subscription owner",
     description: """
     The per-message work of an `observeproperty` subscription. A client builds
     one `Wotex.Binding.MQTT.Delivery` per received Application Message, which
     validates its Topic Name and QoS; the Runtime subscription process decodes
     it with the `c:Wotex.Runtime.Transport.decode_frame/3` callback of
     `Wotex.Binding.MQTT.Transport`, which maps the Form to its SUBSCRIBE
     command again, matches the Topic Name against the
     `things/+/properties/state` filter, decodes the JSON payload under the
     default 1 MiB limit and builds the delivery metadata.
     `Wotex.Binding.MQTT.JSON.decode/2` alone is the decoding baseline. The
     payload is a JSON object with one, 16 or 256 members.
     """}
  ]
)
