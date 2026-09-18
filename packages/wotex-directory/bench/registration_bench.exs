Code.require_file("support/things.exs", __DIR__)
Code.require_file("support/snapshot_ports.exs", __DIR__)

alias Wotex.Directory
alias Wotex.Directory.Bench.{SnapshotPorts, Things}
alias Wotex.Directory.{Context, Entry, Event, Mutation}

context = Context.new!("urn:example:principal:operator")
registered = Things.identifier(1)
unregistered = Things.identifier(2)

inputs =
  Map.new(Things.sizes(), fn {label, count} ->
    stored = Things.thing_description(registered, count)
    service = SnapshotPorts.service([SnapshotPorts.entry(stored)], Things.introduction())
    {:ok, mutation} = Directory.replace(service, registered, stored, context)

    {label,
     %{
       service: service,
       new: Things.thing_description(unregistered, count),
       replacement: stored,
       mutation: mutation
     }}
  end)

Benchee.run(
  %{
    "register (named, created)" => fn %{service: service, new: td} ->
      {:ok, %Mutation{status: :created}} = Directory.register(service, td, context)
    end,
    "replace" => fn %{service: service, replacement: td} ->
      {:ok, %Mutation{status: :replaced}} = Directory.replace(service, registered, td, context)
    end,
    "get" => fn %{service: service} ->
      {:ok, %Entry{}} = Directory.get(service, registered, context)
    end,
    "Event.from_mutation (full payload)" => fn %{mutation: mutation} ->
      {:ok, %Event{type: :thing_updated}} = Event.from_mutation(mutation)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/registration.md",
     title: "# Registration, replacement, retrieval and lifecycle Events",
     description: """
     `Wotex.Directory.register/4`, `replace/5` and `get/3` over synthetic Thing
     Descriptions with one, 24 and 240 Properties, each with one Form, and
     `Wotex.Directory.Event.from_mutation/2` deriving the `thing_updated` Event
     data with the enriched Thing Description. The consumer ports are in-process:
     authorization always allows, the clock is fixed, and the repository answers
     from an immutable snapshot holding one entry, so the numbers cover the
     Directory mechanics (authorization order, Thing Description validation,
     registration information, entry and stored-entry validation) and no
     persistence.
     """}
  ]
)
