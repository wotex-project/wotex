defmodule Wotex.Conformance.ReportTest do
  use ExUnit.Case, async: true

  alias Wotex.Conformance.{Corpus, Report, Runner, TestFixtures, Vector}
  alias Wotex.Conformance.StaticTarget

  setup do
    {root, archive, digest} = TestFixtures.subject_archive!()
    on_exit(fn -> File.rm_rf!(root) end)

    %{archive: archive, digest: digest}
  end

  test "the same typed evidence has identical canonical bytes and report digest", context do
    corpus = corpus!()
    subject = TestFixtures.subject!(context.digest)

    target =
      {StaticTarget, %{artifact_path: context.archive, actual: %{"ok" => true}, owner: self()}}

    options = [generated_at: ~U[2026-09-02 12:00:00Z], environment: %{"runtime" => "otp-28"}]

    assert {:ok, first} = Runner.run(corpus, subject, target, options)
    assert_receive {:target_request, request}
    refute Map.has_key?(request["vector"], "expectation")

    assert {:ok, second} = Runner.run(corpus, subject, target, options)
    assert_receive {:target_request, _request}

    assert first.digest == second.digest
    assert first.run_id == second.run_id
    assert Report.encode(first) == Report.encode(second)
    assert first.summary["pass"] == 1
  end

  test "rejects sensitive environment keys recursively", context do
    corpus = corpus!()
    subject = TestFixtures.subject!(context.digest)

    target =
      {StaticTarget, %{artifact_path: context.archive, actual: %{"ok" => true}, owner: self()}}

    assert {:error, error} =
             Runner.run(corpus, subject, target,
               generated_at: ~U[2026-09-02 12:00:00Z],
               environment: %{"nested" => %{"api_key" => "must-not-enter-report"}}
             )

    assert error.code == :sensitive_environment_key
    refute String.contains?(inspect(error), "must-not-enter-report")
    refute_receive {:target_request, _request}
  end

  defp corpus! do
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
        input: %{"document" => %{"title" => "Synthetic Thing"}},
        expectation: %{"operator" => "exact", "value" => %{"ok" => true}},
        provenance: %{
          "source" => "https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/",
          "observed" => "2026-09-02"
        }
      })

    {:ok, corpus} = Corpus.new(%{id: "example.corpus", revision: "1", vectors: [vector]})
    corpus
  end
end
