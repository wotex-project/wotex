defmodule Wotex.Conformance.ConventionsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Conformance.{Claim, Corpus, Error, Expectation, Pointer, Subject, Value, Vector}
  alias Wotex.Conformance.Target.{External, Response}

  doctest Wotex.Conformance.Pointer

  @digest "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  setup do
    archive =
      Path.join(System.tmp_dir!(), "wotex-conventions-#{System.unique_integer([:positive])}")

    File.write!(archive, "synthetic")
    on_exit(fn -> File.rm_rf!(archive) end)
    %{archive: archive}
  end

  test "errors carry a phase and an escaped JSON Pointer path" do
    error = Error.new(:invalid_value, :vector, "message", path: ["properties", "a/b~c", 3])

    assert error.phase == :vector
    assert error.path == "/properties/a~1b~0c/3"
    assert error.details == %{}
    assert Error.new(:invalid_value, :vector, "message").path == nil
    assert Error.new(:invalid_value, :vector, "message", path: []).path == nil
    assert Error.phases() == Enum.uniq(Error.phases())
    assert :protocol in Error.phases()
  end

  test "pointer encoding and validation follow RFC 6901" do
    assert Pointer.encode([]) == ""
    assert Pointer.encode(["a", 0, "~"]) == "/a/0/~0"
    assert Pointer.valid?("")
    assert Pointer.valid?("/a~0b/0")
    refute Pointer.valid?("a")
    refute Pointer.valid?("/a~2b")
    refute Pointer.valid?(:atom)
  end

  test "every constructor failure reports a phase from the closed vocabulary" do
    failures = [
      Claim.from_map(%{}),
      Expectation.from_map(%{}),
      Subject.from_map(%{}),
      Vector.from_map(%{}),
      Corpus.from_map(%{}),
      External.from_map(%{}),
      Response.from_map(%{}, "example.vector"),
      Value.validate({:unsupported, "term"}),
      Value.validate(%{}, max_depth: 0)
    ]

    for {:error, %Error{} = error} <- failures do
      assert error.phase in Error.phases()
      assert is_binary(error.message)
      assert is_nil(error.path) or String.starts_with?(error.path, "/")
    end

    assert length(failures) == 9
  end

  test "JSON limits use the project vocabulary and reject invalid values" do
    assert {:ok, "value"} = Value.validate("value", max_string_bytes: 5)

    assert {:ok, %{"a" => [1, 2]}} = Value.validate(%{"a" => [1, 2]}, max_collection_size: 2)

    assert {:error, %Error{code: :limit_exceeded, phase: :limits} = error} =
             Value.validate(%{"a" => [1, 2, 3]}, max_collection_size: 2)

    assert error.details == %{"max_collection_size" => 2}
    assert error.path == "/a"

    for limit <- [:max_depth, :max_nodes, :max_string_bytes, :max_collection_size] do
      assert {:error, %Error{code: :invalid_limit, phase: :limits} = error} =
               Value.validate(%{"a" => 1}, [{limit, 0}])

      assert error.details == %{"option" => Atom.to_string(limit)}
    end
  end

  test "map constructors expose from_map with new as its alias", context do
    assert Claim.new(claim_input()) == Claim.from_map(claim_input())
    assert Subject.new(subject_input()) == Subject.from_map(subject_input())
    assert Vector.new(vector_input()) == Vector.from_map(vector_input())

    assert Expectation.new(%{operator: "exact", value: %{}}) ==
             Expectation.from_map(%{operator: "exact", value: %{}})

    {:ok, vector} = Vector.from_map(vector_input())
    corpus_input = %{id: "example.corpus", revision: "1", vectors: [vector]}
    assert Corpus.new(corpus_input) == Corpus.from_map(corpus_input)

    external_input = %{
      executable: System.find_executable("elixir"),
      args: ["{subject_archive}"],
      artifact_path: context.archive
    }

    assert External.new(external_input) == External.from_map(external_input)

    response_input = %{
      "protocol" => "wotex.conformance.target",
      "protocol_version" => "1.0",
      "vector_id" => "example.vector",
      "outcome" => "unsupported"
    }

    assert Response.new(response_input, "example.vector") ==
             Response.from_map(response_input, "example.vector")
  end

  defp claim_input do
    %{
      id: "example.claim",
      revision: "1",
      operation: "example.operation",
      evidence_profile: "value",
      standard: %{
        "identifier" => "w3c.wot.thing-description",
        "revision" => "2023-12-05",
        "source" => "https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/"
      }
    }
  end

  defp subject_input do
    %{
      id: "example.subject",
      version: "1.0.0",
      artifact_digest: @digest,
      interface: %{"kind" => "archive_adapter", "revision" => "1"}
    }
  end

  defp vector_input do
    %{
      id: "example.vector",
      revision: "1",
      claim: claim_input(),
      input: %{"value" => 1},
      expectation: %{"operator" => "exact", "value" => %{"ok" => true}},
      provenance: %{
        "source" => "https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/",
        "observed" => "2026-09-02"
      }
    }
  end
end
