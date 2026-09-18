Code.require_file("support/documents.exs", __DIR__)

alias Wotex.Bench.Documents
alias Wotex.ThingDescription

inputs =
  Map.new(Documents.sizes(), fn {label, count} ->
    json = Documents.json(Documents.thing_description(count))
    {:ok, td} = ThingDescription.parse(json)
    {label, %{json: json, td: td}}
  end)

Benchee.run(
  %{
    "parse and validate" => fn %{json: json} -> {:ok, _} = ThingDescription.parse(json) end,
    "parse without validation" => fn %{json: json} ->
      {:ok, _} = ThingDescription.parse(json, validate: false)
    end,
    "validate" => fn %{td: td} -> {:ok, _} = ThingDescription.validate(td) end,
    "encode canonical" => fn %{td: td} -> {:ok, _} = ThingDescription.encode(td, :canonical) end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/thing_description.md",
     title: "# Thing Description parsing, validation and encoding",
     description: """
     `Wotex.ThingDescription` over synthetic Thing Descriptions with one, 24 and
     240 Properties plus a third as many Actions and Events, each with one Form.
     Parsing includes bounded JSON admission with the default limits.
     """}
  ]
)
