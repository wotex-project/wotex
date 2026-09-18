Code.require_file("support/corpora.exs", __DIR__)

alias Wotex.Conformance.Bench.Corpora
alias Wotex.Conformance.{Canonical, Report, Result}

subject = Corpora.subject(Canonical.digest_bytes("synthetic subject archive"))
generated_at = ~U[2026-09-02 12:00:00Z]
environment = %{"runtime" => "benchmark", "mode" => "in_memory"}

classify = fn vectors ->
  vectors
  |> Enum.with_index()
  |> Enum.map(fn {vector, index} ->
    {:ok, result} =
      Result.new(vector, :pass,
        actual: vector.expectation.value,
        code: "exact_match",
        duration_us: 1_000 + index
      )

    result
  end)
end

inputs =
  Enum.map(Corpora.sizes(), fn {label, count} ->
    corpus = Corpora.corpus(count)
    results = classify.(corpus.vectors)
    {:ok, report} = Report.new(subject, corpus.digest, generated_at, environment, results)
    {label, %{corpus: corpus, results: results, report: report}}
  end)

Benchee.run(
  %{
    "classify results" => fn %{corpus: corpus} -> [_ | _] = classify.(corpus.vectors) end,
    "build report" => fn %{corpus: corpus, results: results} ->
      {:ok, _} = Report.new(subject, corpus.digest, generated_at, environment, results)
    end,
    "encode canonical report" => fn %{report: report} -> {:ok, _} = Report.encode(report) end,
    "verify report digest" => fn %{report: %Report{digest: digest} = report} ->
      {:ok, ^digest} = Canonical.digest(Report.to_map(report, include_digest: false))
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     file: "bench/output/report.md",
     title: "# Result classification and canonical report digests",
     description: """
     Evidence construction for 16, 64 and 128 passing vectors of the corpus
     benchmark. Classification builds one `Wotex.Conformance.Result` per vector,
     digesting its observation and its evidence. `Wotex.Conformance.Report.new/5`
     validates the environment, sorts the results and derives the run
     identifier and report digest; encoding emits the canonical JSON form, and
     verification recomputes the report digest from its canonical map.
     """}
  ]
)
