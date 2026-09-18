Code.require_file("support/corpora.exs", __DIR__)
Code.require_file("support/replay_target.exs", __DIR__)

alias Wotex.Conformance.Bench.{Corpora, ReplayTarget}
alias Wotex.Conformance.{Report, Runner}

generated_at = ~U[2026-09-02 12:00:00Z]
environment = %{"runtime" => "benchmark", "mode" => "in_memory_target"}

Corpora.with_scratch(fn scratch ->
  {archive, digest} = Corpora.archive!(scratch)
  subject = Corpora.subject(digest)

  inputs =
    Enum.map(Corpora.sizes(), fn {label, count} ->
      corpus = Corpora.corpus(count)

      {label,
       %{
         corpus: corpus,
         target: ReplayTarget.new(corpus, archive),
         count: count,
         first: hd(corpus.vectors).id
       }}
    end)

  Benchee.run(
    %{
      "run every vector" => fn %{corpus: corpus, target: target, count: count} ->
        {:ok, %Report{summary: %{"pass" => ^count}}} =
          Runner.run(corpus, subject, target,
            generated_at: generated_at,
            environment: environment
          )
      end,
      "run one selected vector" => fn %{corpus: corpus, target: target, first: id} ->
        {:ok, %Report{summary: %{"pass" => 1}}} =
          Runner.run(corpus, subject, target,
            generated_at: generated_at,
            environment: environment,
            select: {:ids, [id]}
          )
      end
    },
    inputs: inputs,
    warmup: 1,
    time: 3,
    memory_time: 1,
    formatters: [
      Benchee.Formatters.Console,
      {Benchee.Formatters.Markdown,
       file: "bench/output/runner.md",
       title: "# Runner evaluation with an in-memory target",
       description: """
       `Wotex.Conformance.Runner.run/4` over the corpora of the corpus benchmark
       with a `{module, state}` target that replays each vector's expected
       observation through `Wotex.Conformance.Target.Response.from_map/2`. A run
       verifies a 64 KiB subject archive, builds each expectation-free target
       request, validates and digests every observation, classifies it and
       builds the report. Selecting one vector records the others as
       `not_run`. No external target process is started, so the figures
       exclude process start-up and the target protocol's JSON transfer.
       """}
    ]
  )
end)
