Code.require_file("support/client.exs", __DIR__)
Code.require_file("support/interactions.exs", __DIR__)

alias Wotex.Binding.HTTP.Bench.Interactions
alias Wotex.Binding.HTTP.SSE.Event
alias Wotex.Binding.HTTP.Transport

config = Interactions.config(%{})
observe = Interactions.request(:property, "state", :observeproperty, nil)
fields = [event: "state", id: "event-000042", retry: 3_000]

inputs =
  Enum.map(Interactions.sizes(), fn {label, count} ->
    data = Interactions.json(Interactions.payload(count))
    {:ok, event} = Event.new(data, fields)
    {label, %{data: data, event: event}}
  end)

Benchee.run(
  %{
    "Event.new/2" => fn %{data: data} -> {:ok, _} = Event.new(data, fields) end,
    "decode_frame/3" => fn %{event: event} ->
      {:ok, _, %{operation: :observeproperty}} = Transport.decode_frame(event, observe, config)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/sse.md",
     title: "# Server-Sent Event decoding",
     description: """
     The per-event work of an open Server-Sent Events stream. A client builds
     one `Wotex.Binding.HTTP.SSE.Event` per dispatched event, with an event
     type, identifier and retry hint; the Runtime subscription process decodes
     it with `Wotex.Binding.HTTP.Transport.decode_frame/3` for an
     `observeproperty` stream, which applies the default 1 MiB event limit,
     decodes the JSON data and builds the delivery metadata. The event data is
     a JSON object with one, 16 or 256 members.
     """}
  ]
)
