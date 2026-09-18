Code.require_file("support/datasets.exs", __DIR__)

alias Wotex.Thread.Bench.Datasets
alias Wotex.Thread.Dataset

Benchee.run(
  %{
    "decode TLVs" => fn %{bytes: bytes} -> {:ok, %Dataset{}} = Dataset.decode(bytes) end,
    "encode TLVs" => fn %{dataset: dataset} -> {:ok, _} = Dataset.encode(dataset) end,
    "check required TLVs" => fn %{dataset: dataset, context: context} ->
      true = Dataset.complete?(dataset, context)
    end
  },
  inputs: Datasets.inputs(),
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/dataset.md",
     title: "# Thread Operational Dataset TLVs",
     description: """
     `Wotex.Thread.Dataset.decode/1`, `encode/1` (which revalidates the
     complete value by decoding it again) and `complete?/2` over a complete
     Active Dataset of 10 TLVs (102 bytes), a complete Pending Dataset of 12
     TLVs (118 bytes) and that Active Dataset padded with eight unknown TLVs to
     the 254-byte limit.
     """}
  ]
)
