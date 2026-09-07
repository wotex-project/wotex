defmodule Wotex.Conformance.ContractsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Conformance.{Claim, Subject, Vector}

  test "claim requires an exact standards revision and HTTPS source" do
    input = %{
      id: "w3c.wot.td11.parse",
      revision: "1.0.0",
      operation: "thing_description.parse",
      evidence_profile: "value",
      standard: %{
        "identifier" => "w3c.wot.thing-description",
        "revision" => "2023-12-05",
        "source" => "https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/"
      }
    }

    assert {:ok, claim} = Claim.new(input)
    assert claim.standard["revision"] == "2023-12-05"

    assert {:error, %{code: :invalid_value}} =
             Claim.new(put_in(input, [:standard, "source"], "http://example.org/spec"))

    assert {:error, %{code: :unknown_field}} = Claim.new(Map.put(input, :support_level, "broad"))
  end

  test "subject identity excludes execution paths" do
    assert {:ok, subject} =
             Subject.new(%{
               id: "example.subject",
               version: "1.0.0",
               artifact_digest:
                 "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
               interface: %{"kind" => "archive_adapter", "revision" => "1"}
             })

    refute Map.has_key?(Subject.to_map(subject), "artifact_path")
  end

  test "target request omits expectation, expected digest, vector digest, and provenance" do
    vector = vector!()

    {:ok, subject} =
      Subject.new(%{
        id: "example.subject",
        version: "1",
        artifact_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        interface: %{"kind" => "archive_adapter", "revision" => "1"}
      })

    request = Vector.target_request(vector, subject, %{"environment" => %{}})
    encoded = Jason.encode!(request)

    refute Map.has_key?(request["vector"], "expectation")
    refute Map.has_key?(request["vector"], "digest")
    refute String.contains?(encoded, "expected_digest")
    refute String.contains?(encoded, "provenance")
  end

  defp vector! do
    {:ok, vector} =
      Vector.new(%{
        id: "example.vector",
        revision: "1",
        claim: %{
          id: "example.claim",
          revision: "1",
          operation: "thing_description.parse",
          evidence_profile: "value",
          standard: %{
            "identifier" => "w3c.wot.thing-description",
            "revision" => "2023-12-05",
            "source" => "https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/"
          }
        },
        input: %{
          "document" => %{"title" => "Synthetic Thing"},
          "projection" => ["/title"]
        },
        expectation: %{
          "operator" => "exact",
          "value" => %{"accepted" => true, "document" => %{"/title" => "Synthetic Thing"}}
        },
        provenance: %{
          "source" => "https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/",
          "observed" => "2026-09-02"
        }
      })

    vector
  end
end
