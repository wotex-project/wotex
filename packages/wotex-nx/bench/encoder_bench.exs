Code.require_file("support/series.exs", __DIR__)

alias Wotex.Nx.Bench.Series
alias Wotex.Nx.{Encoded, Encoder}

inputs =
  Map.new(Series.sizes(), fn {label, {feature_count, row_count}} ->
    observations =
      feature_count
      |> Series.readings(row_count)
      |> Series.observations()

    {label,
     %{
       schema: Series.schema(feature_count, row_count),
       observed: Series.rows(observations, feature_count),
       sparse: Series.rows(observations, feature_count, missing_every: 4)
     }}
  end)

Benchee.run(
  %{
    "encode (every cell observed)" => fn %{observed: rows, schema: schema} ->
      {:ok, %Encoded{}} = Encoder.encode(rows, schema)
    end,
    "encode (every fourth cell filled)" => fn %{sparse: rows, schema: schema} ->
      {:ok, %Encoded{}} = Encoder.encode(rows, schema)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/encoder.md",
     title: "# Row encoding into a lazy Nx batch",
     description: """
     `Wotex.Nx.Encoder.encode/3` over 32 rows of 4 features, 128 rows of 16
     features and 512 rows of 64 features, each a scalar `number` Property in
     degrees Celsius with a `{:fill, 0.0}` missing-value policy and matching
     units, so no unit converter runs. Encoding validates every row and value,
     then builds the per-row value and mask tuples and quality vectors on the
     default `Nx.BinaryBackend`; the lazy `Nx.Batch` stack is not materialized.
     The second job leaves every fourth cell empty so the fill path supplies it.
     """}
  ]
)
