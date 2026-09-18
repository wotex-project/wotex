Code.require_file("support/documents.exs", __DIR__)

alias Wotex.Bench.Documents
alias Wotex.ThingModel

inputs =
  Map.new(Documents.sizes(), fn {label, count} ->
    {label, Documents.json(Documents.thing_model(count))}
  end)

Benchee.run(
  %{
    "parse and validate" => fn json -> {:ok, _} = ThingModel.parse(json) end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/thing_model.md",
     title: "# Thing Model parsing",
     description: """
     `Wotex.ThingModel.parse/2` over synthetic Thing Models whose Properties are
     all listed in `tm:optional`.
     """}
  ]
)
