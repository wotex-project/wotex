defmodule Wotex.Conformance.CorpusTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Conformance.{Corpus, TestFixtures}

  test "loads the canonical corpus and fixes deterministic vector order" do
    corpus = TestFixtures.corpus!()

    assert corpus.digest ==
             "sha256:b5dc71665ea4d8183d8f52e3908e06ac5126d2ecbed7403114be11968a0c5332"

    assert Enum.map(corpus.vectors, & &1.id) == Enum.sort(Enum.map(corpus.vectors, & &1.id))
    assert length(corpus.vectors) == 14
  end

  test "rejects a modified vector before target execution" do
    source = Path.expand("../../../priv/vectors/thing-description-1.1", __DIR__)
    root = Path.join(System.tmp_dir!(), "wotex-corpus-#{System.unique_integer([:positive])}")
    File.cp_r!(source, root)
    on_exit(fn -> File.rm_rf!(root) end)

    path = Path.join(root, "minimal-thing-description.json")

    modified =
      path |> File.read!() |> String.replace("Minimal Thing", "Changed Thing", global: false)

    File.write!(path, modified)

    assert {:error, %{code: :vector_digest_mismatch}} = Corpus.load(root)
  end

  test "rejects vector path traversal in the manifest" do
    source = Path.expand("../../../priv/vectors/thing-description-1.1", __DIR__)
    root = Path.join(System.tmp_dir!(), "wotex-corpus-#{System.unique_integer([:positive])}")
    File.cp_r!(source, root)
    on_exit(fn -> File.rm_rf!(root) end)

    path = Path.join(root, "manifest.json")
    manifest = path |> File.read!() |> Jason.decode!()
    [first | rest] = manifest["vectors"]
    changed = Map.put(first, "file", "../outside.json")
    File.write!(path, Jason.encode!(Map.put(manifest, "vectors", [changed | rest])))

    assert {:error, %{code: :invalid_vector_filename}} = Corpus.load(root)
  end

  test "rejects files that are not declared by the corpus manifest" do
    source = Path.expand("../../../priv/vectors/thing-description-1.1", __DIR__)
    root = Path.join(System.tmp_dir!(), "wotex-corpus-#{System.unique_integer([:positive])}")
    File.cp_r!(source, root)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(Path.join(root, "undeclared.json"), Jason.encode!(%{"unexpected" => true}))

    assert {:error, %{code: :undeclared_corpus_file}} = Corpus.load(root)
  end
end
