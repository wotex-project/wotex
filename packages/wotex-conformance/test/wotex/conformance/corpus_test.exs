defmodule Wotex.Conformance.CorpusTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Conformance.{Corpus, TestFixtures}

  test "loads the canonical corpus and fixes deterministic vector order" do
    corpus = TestFixtures.corpus!()

    assert corpus.revision == "1.1.0"

    assert corpus.digest ==
             "sha256:b1f9c259c24c7edf9faf8979204bf3105efcdf49e9b3dc69330c9475c4903154"

    assert Enum.map(corpus.vectors, & &1.id) == Enum.sort(Enum.map(corpus.vectors, & &1.id))
    assert length(corpus.vectors) == 16
  end

  test "loads the independent Thing Model corpus with stable identity" do
    corpus = TestFixtures.thing_model_corpus!()

    assert corpus.id == "w3c.wot.thing-model.1.1.baseline"
    assert corpus.revision == "1.1.0"

    assert corpus.digest ==
             "sha256:800bfc2ea61f6c14167898e64bcdb8c8aff0a1fe9857505ed65f2837d6bd10a5"

    assert Enum.map(corpus.vectors, & &1.id) == Enum.sort(Enum.map(corpus.vectors, & &1.id))
    assert length(corpus.vectors) == 8
  end

  test "rejects a modified vector before target execution" do
    source = Path.expand("../../../priv/vectors/thing-description-1.1", __DIR__)
    root = Path.join(System.tmp_dir!(), "wotex-corpus-#{System.unique_integer([:positive])}")
    File.cp_r!(source, root)
    on_exit(fn -> File.rm_rf!(root) end)

    path = Path.join(root, "minimal-thing-description.json")

    modified =
      path
      |> File.read!()
      |> String.replace("Minimal Thing", "Changed Thing", global: false)

    File.write!(path, modified)

    assert {:error, %{code: :vector_digest_mismatch}} = Corpus.load(root)
  end

  test "rejects vector path traversal in the manifest" do
    source = Path.expand("../../../priv/vectors/thing-description-1.1", __DIR__)
    root = Path.join(System.tmp_dir!(), "wotex-corpus-#{System.unique_integer([:positive])}")
    File.cp_r!(source, root)
    on_exit(fn -> File.rm_rf!(root) end)

    path = Path.join(root, "manifest.json")
    manifest = Jason.decode!(File.read!(path))
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
