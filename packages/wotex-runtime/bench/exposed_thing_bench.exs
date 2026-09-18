Code.require_file("support/things.exs", __DIR__)

alias Wotex.Runtime.Bench.Things
alias Wotex.Runtime.{Context, ExposedThing}

context =
  Context.new!(
    request_id: "urn:example:request:0001",
    deadline: System.monotonic_time(:millisecond) + 5_000
  )

inputs =
  Map.new(Things.property_sizes(), fn {label, count} ->
    td = Things.thing_description(count)

    handlers =
      count
      |> Things.property_names()
      |> Map.new(&{{:readproperty, &1}, fn _, _ -> {:ok, 21.5} end})
      |> Map.put({:invokeaction, "calibrate"}, fn input, _ -> {:ok, input} end)
      |> Map.put(:readallproperties, fn _, _ -> {:ok, %{}} end)

    {:ok, exposed} = ExposedThing.new(td, handlers)
    {label, %{td: td, handlers: handlers, exposed: exposed, last: "p#{count}"}}
  end)

Benchee.run(
  %{
    "new (validates the Thing Description and handlers)" => fn %{td: td, handlers: handlers} ->
      {:ok, _} = ExposedThing.new(td, handlers)
    end,
    "dispatch readproperty" => fn %{exposed: exposed, last: name} ->
      {:ok, _} = ExposedThing.dispatch(exposed, :readproperty, name, nil, context)
    end,
    "dispatch invokeaction" => fn %{exposed: exposed} ->
      {:ok, _} = ExposedThing.dispatch(exposed, :invokeaction, "calibrate", 21.5, context)
    end,
    "dispatch_thing readallproperties" => fn %{exposed: exposed} ->
      {:ok, _} = ExposedThing.dispatch_thing(exposed, :readallproperties, nil, context)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/exposed_thing.md",
     title: "# ExposedThing construction and dispatch",
     description: """
     `Wotex.Runtime.ExposedThing` over the Thing Descriptions of the
     ConsumedThing benchmark, with a `readproperty` handler for every Property,
     an `invokeaction` handler and a Thing-level `readallproperties` handler.
     Construction includes Thing Description and handler validation. Dispatch
     checks the declared operation and Interaction Affordance (or top-level
     Form) and calls a handler that returns at once.
     """}
  ]
)
