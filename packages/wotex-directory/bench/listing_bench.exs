Code.require_file("support/things.exs", __DIR__)
Code.require_file("support/snapshot_ports.exs", __DIR__)

alias Wotex.Directory
alias Wotex.Directory.Bench.{SnapshotPorts, Things}
alias Wotex.Directory.{Context, Page}

context = Context.new!("urn:example:principal:operator")

entries =
  Enum.map(1..400, fn index ->
    index
    |> Things.identifier()
    |> Things.thing_description(4)
    |> SnapshotPorts.entry()
  end)

service = SnapshotPorts.service(entries, Things.introduction())

inputs =
  Map.new(
    %{
      "1 entry per page" => 1,
      "50 entries per page (default)" => 50,
      "200 entries per page (maximum)" => 200
    },
    fn {label, limit} ->
      {:ok, %Page{next_cursor: cursor}} = Directory.list(service, context, limit: limit)
      {label, %{limit: limit, cursor: cursor}}
    end
  )

Benchee.run(
  %{
    "first page" => fn %{limit: limit} ->
      {:ok, %Page{entries: [_ | _]}} = Directory.list(service, context, limit: limit)
    end,
    "continuation page (cursor)" => fn %{limit: limit, cursor: cursor} ->
      {:ok, %Page{entries: [_ | _]}} =
        Directory.list(service, context, limit: limit, cursor: cursor)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/listing.md",
     title: "# Keyset listing",
     description: """
     `Wotex.Directory.list/3` over 400 registered Thing Descriptions with four
     Properties each, for page limits of one, 50 (the default) and 200 (the
     maximum). The continuation page decodes the opaque cursor issued by the
     first page. The in-process repository builds each page from an immutable
     sorted snapshot with `Wotex.Directory.Page.new/1`; page construction and
     the Directory's own page validation both check every entry, including its
     Thing Description, before the shared retrieval time is assigned.
     """}
  ]
)
