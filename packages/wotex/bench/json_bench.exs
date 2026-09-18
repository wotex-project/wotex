Code.require_file("support/documents.exs", __DIR__)

alias Wotex.Bench.Documents

inputs =
  Map.new(Documents.sizes(), fn {label, count} ->
    document = Documents.thing_description(count)
    {label, %{json: Documents.json(document), document: document}}
  end)

Benchee.run(
  %{
    "decode with default limits" => fn %{json: json} -> {:ok, _} = Wotex.JSON.decode(json) end,
    "encode with sorted keys" => fn %{document: document} ->
      {:ok, _} = Wotex.JSON.encode(document)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/json.md",
     title: "# Bounded JSON admission and canonical encoding",
     description: """
     `Wotex.JSON.decode/2` with the default `Wotex.JSON.Limits` and
     `Wotex.JSON.encode/2` over the Thing Description documents of the
     Thing Description benchmark.
     """}
  ]
)
