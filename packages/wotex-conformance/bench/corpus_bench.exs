Code.require_file("support/corpora.exs", __DIR__)

alias Wotex.Conformance.Bench.Corpora
alias Wotex.Conformance.{Canonical, Corpus}

Corpora.with_scratch(fn scratch ->
  inputs =
    Enum.map(Corpora.sizes(), fn {label, count} ->
      corpus = Corpora.corpus(count)

      {label,
       %{
         corpus: corpus,
         digest: corpus.digest,
         directory: Corpora.directory!(corpus, scratch),
         decoded: Corpus.to_map(corpus)
       }}
    end)

  Benchee.run(
    %{
      "load and verify directory" => fn %{directory: directory, digest: digest} ->
        {:ok, %Corpus{digest: ^digest}} = Corpus.load(directory)
      end,
      "construct from decoded vectors" => fn %{decoded: decoded, digest: digest} ->
        {:ok, %Corpus{digest: ^digest}} = Corpus.from_map(decoded)
      end,
      "recompute corpus digest" => fn %{corpus: corpus, digest: digest} ->
        {:ok, ^digest} = Canonical.digest(Corpus.to_map(corpus, include_digest: false))
      end
    },
    inputs: inputs,
    warmup: 1,
    time: 3,
    memory_time: 1,
    formatters: [
      Benchee.Formatters.Console,
      {Benchee.Formatters.Markdown,
       file: "bench/output/corpus.md",
       title: "# Corpus loading and digest verification",
       description: """
       `Wotex.Conformance.Corpus.load/1` reads a corpus directory, checks its
       declared files, decodes and constructs every vector and compares each
       vector digest and the aggregate digest with the manifest.
       `Wotex.Conformance.Corpus.from_map/1` constructs the same corpus from
       already decoded vectors, and the digest job recomputes the canonical
       corpus digest alone. The 16-vector input is the bundled Thing
       Description 1.1 corpus; the larger inputs repeat its vectors under new
       identifiers and are written to a temporary directory before measurement.
       """}
    ]
  )
end)
