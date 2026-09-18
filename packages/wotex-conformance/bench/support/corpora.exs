defmodule Wotex.Conformance.Bench.Corpora do
  @moduledoc false

  # The bundled Thing Description 1.1 corpus and synthetic scale-ups of it. A
  # synthetic corpus repeats the bundled vectors under new identifiers, so
  # every vector keeps a realistic document, projection and expectation.
  # Files are written only below a scratch directory that `with_scratch/1`
  # removes again.

  alias Wotex.Conformance.{Canonical, Corpus, Subject, Vector}

  @bundled Path.expand("../../priv/vectors/thing-description-1.1", __DIR__)

  @spec sizes() :: [{String.t(), pos_integer()}]
  def sizes, do: [{"16 vectors", 16}, {"64 vectors", 64}, {"128 vectors", 128}]

  @spec bundled() :: Corpus.t()
  def bundled do
    {:ok, corpus} = Corpus.load(@bundled)
    corpus
  end

  @spec corpus(pos_integer()) :: Corpus.t()
  def corpus(count) do
    bundled = bundled()

    if count == length(bundled.vectors) do
      bundled
    else
      vectors =
        bundled.vectors
        |> Stream.cycle()
        |> Stream.with_index()
        |> Enum.take(count)
        |> Enum.map(fn {vector, index} ->
          vector
          |> Vector.to_map(include_digest: false)
          |> Map.put("id", "#{vector.id}.r#{index}")
        end)

      {:ok, corpus} =
        Corpus.from_map(%{
          "id" => "example.bench.synthetic",
          "revision" => "1.0.0",
          "vectors" => vectors
        })

      corpus
    end
  end

  @spec directory!(Corpus.t(), Path.t()) :: Path.t()
  def directory!(%Corpus{} = corpus, scratch) do
    if corpus.digest == bundled().digest do
      @bundled
    else
      directory = Path.join(scratch, "corpus-#{length(corpus.vectors)}")
      File.mkdir_p!(directory)

      entries =
        corpus.vectors
        |> Enum.with_index(1)
        |> Enum.map(fn {vector, index} ->
          file = "vector-#{String.pad_leading(Integer.to_string(index), 4, "0")}.json"
          File.write!(Path.join(directory, file), Jason.encode!(Vector.to_map(vector)))
          %{"id" => vector.id, "file" => file, "digest" => vector.digest}
        end)

      manifest = %{
        "schema_version" => corpus.schema_version,
        "id" => corpus.id,
        "revision" => corpus.revision,
        "vectors" => entries,
        "digest" => corpus.digest
      }

      File.write!(Path.join(directory, "manifest.json"), Jason.encode!(manifest))
      directory
    end
  end

  @spec subject(String.t()) :: Subject.t()
  def subject(artifact_digest) do
    {:ok, subject} =
      Subject.from_map(%{
        id: "example.bench-subject",
        version: "1.0.0",
        artifact_digest: artifact_digest,
        interface: %{"kind" => "archive_adapter", "revision" => "1"}
      })

    subject
  end

  @spec archive!(Path.t()) :: {Path.t(), String.t()}
  def archive!(scratch) do
    path = Path.join(scratch, "subject-archive.bin")
    bytes = :binary.copy("synthetic subject archive\n", 2_521)
    File.write!(path, bytes)
    {path, Canonical.digest_bytes(bytes)}
  end

  @spec with_scratch((Path.t() -> result)) :: result when result: term()
  def with_scratch(fun) do
    scratch =
      Path.join(
        System.tmp_dir!(),
        "wotex-conformance-bench-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(scratch)

    try do
      fun.(scratch)
    after
      File.rm_rf!(scratch)
    end
  end
end
