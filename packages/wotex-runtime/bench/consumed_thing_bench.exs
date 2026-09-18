Code.require_file("support/things.exs", __DIR__)
Code.require_file("support/echo_transport.exs", __DIR__)

alias Wotex.Runtime.Bench.{EchoTransport, Things}
alias Wotex.Runtime.{ConsumedThing, Context, Result}

profiles = Things.profiles()

options = [
  profiles: profiles,
  transports: %{mqtt: {EchoTransport, []}, https: {EchoTransport, []}},
  credentials: {EchoTransport, []}
]

context =
  Context.new!(
    request_id: "urn:example:request:0001",
    deadline: System.monotonic_time(:millisecond) + 5_000,
    metadata: %{trace_id: "trace-0001"}
  )

inputs =
  Map.new(Things.property_sizes(), fn {label, count} ->
    td = Things.thing_description(count)
    {:ok, consumed} = ConsumedThing.new(td, options)
    {label, %{td: td, consumed: consumed, names: Things.property_names(count)}}
  end)

Benchee.run(
  %{
    "new (validates the Thing Description)" => fn %{td: td} ->
      {:ok, _} = ConsumedThing.new(td, options)
    end,
    "read_property" => fn %{consumed: consumed} ->
      {:ok, %Result{}} = ConsumedThing.read_property(consumed, "p1", context)
    end,
    "invoke_action" => fn %{consumed: consumed} ->
      {:ok, %Result{}} = ConsumedThing.invoke_action(consumed, "calibrate", 21.5, context)
    end,
    "read_multiple_properties (every Property)" => fn %{consumed: consumed, names: names} ->
      {:ok, %Result{}} = ConsumedThing.read_multiple_properties(consumed, names, context)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/consumed_thing.md",
     title: "# ConsumedThing construction and short operations",
     description: """
     `Wotex.Runtime.ConsumedThing` over synthetic Thing Descriptions with one, 24
     and 240 Properties, one Action and one Event, each with a single relative
     `https` Form. Construction includes Thing Description validation. The short
     operations run the full caller-side path (Form and binding-profile selection
     against two profiles, request construction, credential resolution, port
     isolation, the `[:wotex, :runtime, :request]` telemetry span and Result
     validation) through an in-process transport that answers at once, so no
     protocol exchange is measured.
     """}
  ]
)
