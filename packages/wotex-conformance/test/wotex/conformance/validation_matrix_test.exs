defmodule Wotex.Conformance.ValidationMatrixTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Conformance

  alias Wotex.Conformance.{
    Artifact,
    Claim,
    Corpus,
    Environment,
    Error,
    Expectation,
    FailingTarget,
    Input,
    Report,
    Result,
    Subject,
    Target,
    TestFixtures,
    Value,
    Vector
  }

  alias Wotex.Conformance.Target.{External, Response}

  @digest "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  @generated_at ~U[2026-09-02 12:00:00Z]

  setup do
    {root, archive, digest} = TestFixtures.subject_archive!()
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, archive: archive, digest: digest}
  end

  test "input access normalizes supported key representations" do
    assert Input.required(%{id: 1}, :id) == {:ok, 1}
    assert Input.required(%{"id" => 2}, :id) == {:ok, 2}
    assert {:error, %{code: :missing_field}} = Input.required(%{}, :id)

    assert Input.optional(%{id: 1}, :id, 0) == 1
    assert Input.optional(%{"id" => 2}, :id, 0) == 2
    assert Input.optional(%{}, :id, 0) == 0

    assert :ok = Input.only_keys(%{id: 1}, ["id"])
    assert {:error, %{code: :invalid_field}} = Input.only_keys(%{1 => "value"}, ["id"])

    assert {:error, %{code: :unknown_field, path: ["extra"]}} =
             Input.only_keys(%{"extra" => true}, ["id"])

    assert {:error, %{code: :duplicate_field}} =
             Input.only_keys(%{:id => 1, "id" => 2}, ["id"])

    assert :ok = Input.options([limit: 1], [:limit])
    assert_error(Input.options([:malformed], [:limit]), :invalid_options)
    assert_error(Input.options([limit: 1, limit: 2], [:limit]), :invalid_options)
    assert_error(Input.options([unknown: true], [:limit]), :invalid_options)
  end

  test "bounded JSON validation accepts values and rejects every public limit class" do
    for value <- [nil, true, 1, 1.5, "value", [1, false], %{"nested" => [nil]}] do
      assert {:ok, ^value} = Value.validate(value)
    end

    assert {:error, %{code: :invalid_limit}} = Value.validate(nil, max_depth: 0)
    assert {:error, %{code: :invalid_encoding}} = Value.validate(<<255>>)
    assert {:error, %{code: :limit_exceeded}} = Value.validate("ab", max_string_bytes: 1)
    assert {:error, %{code: :limit_exceeded}} = Value.validate(%{"a" => %{"b" => 1}}, max_depth: 1)
    assert {:error, %{code: :limit_exceeded}} = Value.validate([1], max_entries: 1)
    assert {:error, %{code: :invalid_map_key}} = Value.validate(%{atom: "value"})
    assert {:error, %{code: :invalid_type}} = Value.validate({:unsupported, "term"})
    assert_error(Value.validate(%{}, [:malformed]), :invalid_options)
    assert_error(Value.validate(%{}, unknown: true), :invalid_options)

    assert Value.validate_identifier("thing:one", "id") == {:ok, "thing:one"}
    assert {:error, %{code: :invalid_type}} = Value.validate_identifier(1, "id")
    assert {:error, %{code: :invalid_value}} = Value.validate_identifier("", "id")
    assert {:error, %{code: :limit_exceeded}} = Value.validate_identifier("ab", "id", max_bytes: 1)
    assert {:error, %{code: :invalid_encoding}} = Value.validate_identifier(<<255>>, "id")
    assert {:error, %{code: :invalid_value}} = Value.validate_identifier("bad space", "id")
    assert_error(Value.validate_identifier("id", "id", :invalid), :invalid_options)
    assert_error(Value.validate_identifier("id", "id", pattern: :invalid), :invalid_limit)

    assert Value.string_key_map(%{"key" => "value"}, "object") ==
             {:ok, %{"key" => "value"}}

    assert {:error, %{code: :invalid_map_key}} = Value.string_key_map(%{key: "value"}, "object")
    assert {:error, %{code: :invalid_type}} = Value.string_key_map([], "object")
  end

  test "claim constructors retain only bounded, explicit standards evidence" do
    input = claim_input()
    assert {:ok, claim} = Claim.new(input)
    assert claim.assertions == ["assertion:a", "assertion:b"]
    assert claim.tags == ["core", "td"]
    assert Claim.to_map(claim)["standard"]["section"] == "5.3"

    assert_error(Claim.new(nil), :invalid_type)
    assert_error(Claim.new(Map.delete(input, :id)), :missing_field)
    assert_error(Claim.new(%{input | evidence_profile: "imaginary"}), :invalid_value)
    assert_error(Claim.new(%{input | standard: []}), :invalid_type)

    assert_error(
      Claim.new(%{input | standard: Map.put(input.standard, "extra", true)}),
      :unknown_field
    )

    assert_error(
      Claim.new(%{input | standard: Map.delete(input.standard, "identifier")}),
      :missing_field
    )

    assert_error(
      Claim.new(%{input | standard: Map.delete(input.standard, "revision")}),
      :missing_field
    )

    assert_error(
      Claim.new(%{input | standard: Map.delete(input.standard, "source")}),
      :missing_field
    )

    assert_error(
      Claim.new(%{input | standard: Map.put(input.standard, "source", "http://invalid")}),
      :invalid_value
    )

    assert_error(
      Claim.new(%{
        input
        | standard: Map.put(input.standard, "section", String.duplicate("x", 256))
      }),
      :invalid_value
    )

    assert_error(Claim.new(%{input | assertions: :invalid}), :invalid_value)
    assert_error(Claim.new(%{input | tags: ["bad tag"]}), :invalid_value)
  end

  test "expectations, subjects, and vectors enforce their portable contracts" do
    assert {:ok, expectation} = Expectation.new(%{operator: :exact, value: %{"ok" => true}})
    assert Expectation.to_map(expectation) == %{"operator" => "exact", "value" => %{"ok" => true}}
    assert_error(Expectation.new(nil), :invalid_type)
    assert_error(Expectation.new(%{operator: "subset", value: %{}}), :unsupported_operator)
    assert_error(Expectation.new(%{operator: "exact"}), :missing_field)
    assert_error(Expectation.new(%{operator: "exact", value: self()}), :invalid_type)

    assert {:ok, subject} = Subject.new(subject_input())
    assert Subject.to_map(subject)["artifact_digest"] == @digest
    assert_error(Subject.new(nil), :invalid_type)
    assert_error(Subject.new(%{subject_input() | artifact_digest: "bad"}), :invalid_digest)
    assert_error(Subject.new(%{subject_input() | interface: []}), :invalid_type)
    assert_error(Subject.new(%{subject_input() | interface: %{"revision" => "1"}}), :missing_field)

    assert_error(
      Subject.new(%{subject_input() | interface: %{"kind" => "archive"}}),
      :missing_field
    )

    input = vector_input()
    assert {:ok, vector} = Vector.new(input)
    refute Map.has_key?(Vector.to_map(vector, include_digest: false), "digest")
    assert Vector.to_map(vector)["digest"] == vector.digest
    assert_error(Vector.new(nil), :invalid_type)
    assert_error(Vector.new(%{input | provenance: []}), :invalid_type)
    assert_error(Vector.new(%{input | provenance: %{"observed" => "2026-09-02"}}), :missing_field)

    assert_error(
      Vector.new(%{
        input
        | provenance: %{"source" => "http://invalid", "observed" => "2026-09-02"}
      }),
      :invalid_value
    )

    assert_error(
      Vector.new(%{input | provenance: %{"source" => "https://example.org"}}),
      :missing_field
    )

    assert_error(
      Vector.new(%{
        input
        | provenance: %{"source" => "https://example.org", "observed" => "today"}
      }),
      :invalid_value
    )

    assert_error(Vector.new(%{input | tags: :invalid}), :invalid_value)
    assert_error(Vector.new(%{input | tags: ["bad tag"]}), :invalid_value)

    request = Vector.target_request(vector, subject, %{"mode" => "offline"})
    assert request["context"] == %{"mode" => "offline"}
  end

  test "target responses distinguish observations from unsupported operations" do
    observed = response_input("observed") |> Map.put("actual", %{"ok" => true})

    assert {:ok, %Response{outcome: :observed, actual: %{"ok" => true}}} =
             Response.new(observed, "example.vector")

    unsupported = response_input("unsupported") |> Map.put("codes", ["z", "a", "a"])

    assert {:ok, %Response{outcome: :unsupported, actual: nil, codes: ["a", "z"]}} =
             Response.new(unsupported, "example.vector")

    assert_error(Response.new(nil, "example.vector"), :invalid_target_response)

    assert_error(
      Response.new(Map.delete(observed, "protocol"), "example.vector"),
      :target_protocol_mismatch
    )

    assert_error(
      Response.new(%{observed | "vector_id" => "other"}, "example.vector"),
      :target_vector_mismatch
    )

    assert_error(
      Response.new(%{observed | "outcome" => "pass"}, "example.vector"),
      :invalid_target_outcome
    )

    assert_error(
      Response.new(Map.delete(observed, "actual"), "example.vector"),
      :missing_target_observation
    )

    assert_error(
      Response.new(Map.put(unsupported, "actual", nil), "example.vector"),
      :unexpected_target_observation
    )

    assert_error(
      Response.new(Map.put(observed, "codes", :invalid), "example.vector"),
      :invalid_target_codes
    )

    assert_error(
      Response.new(Map.put(observed, "codes", ["bad code"]), "example.vector"),
      :invalid_value
    )
  end

  test "result and report evidence is typed, ordered, and content addressed", %{digest: digest} do
    vector = vector!()

    for status <- [:pass, :fail, :unsupported, :not_run, :infrastructure_error] do
      assert {:ok, result} =
               Result.new(vector, status, actual: %{"status" => Atom.to_string(status)})

      assert result.status == status
      assert is_binary(result.evidence_digest)
    end

    assert {:ok, result} = Result.new(vector, :pass, actual: %{"ok" => true}, duration_us: 7)
    assert Result.to_map(result)["evidence_digest"] == result.evidence_digest
    refute Map.has_key?(Result.to_map(result, include_digest: false), "evidence_digest")
    assert_error(Result.new(vector, :unknown), :invalid_result_status)
    assert_error(Result.new(vector, :pass, code: "bad code"), :invalid_value)
    assert_error(Result.new(vector, :pass, duration_us: -1), :invalid_duration)
    assert_error(Result.new(vector, :pass, actual: self()), :invalid_type)
    assert_error(Result.new(vector, :pass, [:malformed]), :invalid_options)
    assert_error(Result.new(vector, :pass, unknown: true), :invalid_options)

    subject = TestFixtures.subject!(digest)

    assert {:ok, report} =
             Report.new(subject, vector.digest, @generated_at, %{"mode" => "offline"}, [result])

    assert report.summary["pass"] == 1
    assert {:ok, encoded} = Report.encode(report)
    assert Jason.decode!(encoded)["digest"] == report.digest
    refute Map.has_key?(Report.to_map(report, include_digest: false), "digest")

    assert_error(Report.new(subject, "bad", @generated_at, %{}, []), :invalid_digest)
    assert_error(Report.new(subject, vector.digest, @generated_at, [], []), :invalid_type)
    assert_error(Report.new(subject, vector.digest, @generated_at, %{}, [:invalid]), :invalid_type)

    assert_error(
      Report.new(subject, vector.digest, @generated_at, %{}, [result, result]),
      :duplicate_vector_result
    )

    assert_error(Report.new(subject, vector.digest, :invalid, %{}, []), :invalid_report_input)
  end

  test "environment evidence rejects secrets at arbitrary map and list depth" do
    assert Environment.validate(%{"runtime" => %{"version" => "28"}}) ==
             {:ok, %{"runtime" => %{"version" => "28"}}}

    assert_error(Environment.validate([]), :invalid_type)

    assert_error(
      Environment.validate(%{"nested" => [%{"private-key" => "redacted"}]}),
      :sensitive_environment_key
    )
  end

  test "artifact verification rejects invalid paths, limits, file types, and content", context do
    assert_error(Artifact.verify(nil, context.digest), :invalid_artifact_path)
    assert_error(Artifact.verify(context.archive, "bad"), :invalid_digest)
    assert_error(Artifact.verify(context.archive, context.digest, max_bytes: 0), :invalid_limit)

    assert_error(
      Artifact.verify(Path.join(context.root, "missing"), context.digest),
      :artifact_unreadable
    )

    assert_error(Artifact.verify(context.root, context.digest), :invalid_artifact_type)
    assert_error(Artifact.verify(context.archive, context.digest, max_bytes: 1), :limit_exceeded)
    assert_error(Artifact.verify(context.archive, context.digest, [:malformed]), :invalid_options)
    assert_error(Artifact.verify(context.archive, context.digest, unknown: true), :invalid_options)
    assert_error(Artifact.digest_file(nil), :invalid_artifact_path)
    assert_error(Artifact.digest_file(Path.join(context.root, "missing")), :artifact_unreadable)
  end

  test "callback targets normalize and contain malformed, raised, and thrown callbacks", context do
    assert_error(Target.normalize(:invalid), :invalid_target)
    assert_error(Target.normalize({String, %{}}), :invalid_target)

    assert {:ok, {FailingTarget, _state}} =
             Target.normalize({FailingTarget, %{artifact_path: context.archive}})

    assert Target.artifact_path({FailingTarget, %{artifact_path: context.archive}}) ==
             {:ok, context.archive}

    assert_error(
      Target.artifact_path({FailingTarget, %{artifact_result: :invalid}}),
      :invalid_target_callback
    )

    explicit = Error.new(:explicit_failure, "explicit")

    assert Target.artifact_path({FailingTarget, %{artifact_result: {:error, explicit}}}) ==
             {:error, explicit}

    assert_error(
      Target.artifact_path({FailingTarget, %{failure: :artifact}}),
      :target_artifact_callback_failed
    )

    assert_error(
      Target.artifact_path({FailingTarget, %{failure: :artifact_throw}}),
      :target_artifact_callback_failed
    )

    response = %Response{vector_id: "example.vector", outcome: :unsupported, codes: []}

    assert Target.invoke({FailingTarget, %{invoke_result: {:ok, response, 3}}}, %{}) ==
             {:ok, response, 3}

    assert Target.invoke({FailingTarget, %{invoke_result: {:error, explicit, 4}}}, %{}) ==
             {:error, explicit, 4}

    assert Target.invoke({FailingTarget, %{invoke_result: {:error, explicit}}}, %{}) ==
             {:error, explicit, 0}

    assert {:error, %{code: :invalid_target_callback}, 0} =
             Target.invoke({FailingTarget, %{invoke_result: :invalid}}, %{})

    assert {:error, %{code: :target_callback_failed}, 0} =
             Target.invoke({FailingTarget, %{failure: :invoke}}, %{})

    assert {:error, %{code: :target_callback_failed}, 0} =
             Target.invoke({FailingTarget, %{failure: :invoke_throw}}, %{})
  end

  test "external targets validate executable, arguments, environment, and limits", context do
    executable = System.find_executable("elixir")
    valid = external_input(executable, context.archive)

    assert {:ok, target} = External.new(valid)
    assert External.artifact_path(target) == {:ok, context.archive}
    assert_error(External.new(nil), :invalid_type)
    assert_error(External.new(%{valid | executable: "relative"}), :invalid_executable)
    assert_error(External.new(%{valid | executable: context.root}), :invalid_executable)
    assert_error(External.new(%{valid | executable: 1}), :invalid_executable)
    assert_error(External.new(%{valid | args: :invalid}), :invalid_argument)
    assert_error(External.new(%{valid | args: [1, "{subject_archive}"]}), :invalid_argument)
    assert_error(External.new(%{valid | args: ["prefix-{subject_archive}"]}), :invalid_argument)
    assert_error(External.new(%{valid | args: ["no-archive"]}), :invalid_argument)

    assert_error(
      External.new(%{valid | args: ["{subject_archive}", "{subject_archive}"]}),
      :invalid_argument
    )

    assert_error(External.new(%{valid | artifact_path: "relative"}), :invalid_artifact_path)
    assert_error(External.new(%{valid | artifact_path: nil}), :invalid_artifact_path)
    assert_error(External.new(%{valid | environment: []}), :invalid_environment)
    assert_error(External.new(%{valid | environment: %{1 => "value"}}), :invalid_environment)

    assert_error(
      External.new(%{valid | environment: %{"BAD-KEY" => "value"}}),
      :invalid_environment
    )

    assert_error(
      External.new(%{valid | environment: %{"API_TOKEN" => "value"}}),
      :invalid_environment
    )

    assert_error(External.new(%{valid | environment: %{"VALID" => <<0>>}}), :invalid_environment)
    assert_error(External.new(%{valid | timeout_ms: 0}), :invalid_limit)
    assert_error(External.new(%{valid | max_output_bytes: 0}), :invalid_limit)

    pass_target = TestFixtures.external_target!(context.archive, "pass")
    assert {:error, %{code: :invalid_target_request}, duration} = External.invoke(pass_target, %{})
    assert duration >= 0

    assert {:error, %{code: :invalid_type}, duration} =
             External.invoke(pass_target, %{"bad" => self()})

    assert duration >= 0
  end

  test "corpora construct from typed and map vectors and reject ambiguous collections" do
    vector = vector!()
    assert {:ok, corpus} = Corpus.new(%{id: "example.corpus", revision: "1", vectors: [vector]})
    assert Corpus.to_map(corpus)["digest"] == corpus.digest
    refute Map.has_key?(Corpus.to_map(corpus, include_digest: false), "digest")

    assert {:ok, map_corpus} =
             Corpus.new(%{id: "example.corpus", revision: "1", vectors: [vector_input()]})

    assert hd(map_corpus.vectors).id == vector.id
    assert_error(Corpus.new(nil), :invalid_type)
    assert_error(Corpus.new(%{id: "example", revision: "1", vectors: []}), :empty_corpus)
    assert_error(Corpus.new(%{id: "example", revision: "1", vectors: :invalid}), :invalid_value)
    assert_error(Corpus.new(%{id: "example", revision: "1", vectors: [:invalid]}), :invalid_type)

    assert_error(
      Corpus.new(%{id: "example", revision: "1", vectors: [vector, vector]}),
      :duplicate_vector
    )
  end

  test "corpus loading fails closed on invalid manifests and entries", context do
    assert_error(Conformance.load_corpus(nil), :invalid_corpus_path)
    assert_error(Conformance.load_corpus(Path.join(context.root, "missing")), :corpus_unreadable)

    assert_manifest_error(
      context.root,
      fn manifest ->
        Map.put(manifest, "schema_version", "2.0")
      end,
      :unsupported_schema_version
    )

    assert_manifest_error(
      context.root,
      fn manifest -> Map.put(manifest, "vectors", []) end,
      :invalid_manifest
    )

    assert_manifest_error(
      context.root,
      fn manifest ->
        [first | rest] = manifest["vectors"]
        Map.put(manifest, "vectors", [first, first | rest])
      end,
      :duplicate_vector_file
    )

    assert_manifest_error(
      context.root,
      fn manifest ->
        Map.put(manifest, "vectors", ["invalid"])
      end,
      :invalid_manifest_entry
    )

    assert_manifest_error(
      context.root,
      fn manifest ->
        [first | rest] = manifest["vectors"]
        Map.put(manifest, "vectors", [Map.put(first, "file", 1) | rest])
      end,
      :invalid_vector_filename
    )

    assert_manifest_error(
      context.root,
      fn manifest ->
        [first | rest] = manifest["vectors"]
        Map.put(manifest, "vectors", [Map.put(first, "digest", "bad") | rest])
      end,
      :invalid_digest
    )

    assert_manifest_error(
      context.root,
      fn manifest -> Map.put(manifest, "digest", "bad") end,
      :corpus_digest_mismatch
    )
  end

  test "the public facade loads and runs the verified corpus", context do
    assert {:ok, corpus} = Conformance.load_corpus(corpus_source())
    subject = TestFixtures.subject!(context.digest)
    target = TestFixtures.external_target!(context.archive, "pass")

    assert {:ok, report} =
             Conformance.run(corpus, subject, target,
               generated_at: @generated_at,
               environment: %{"mode" => "offline"},
               select: {:ids, [hd(corpus.vectors).id]}
             )

    assert report.summary["pass"] == 1
    assert_error(Conformance.run(corpus, subject, target, []), :missing_generated_at)

    assert_error(
      Conformance.run(corpus, subject, target, generated_at: :invalid),
      :invalid_generated_at
    )

    assert_error(Conformance.run(corpus, subject, target, :invalid), :invalid_options)
    assert_error(Conformance.run(corpus, subject, target, [:malformed]), :invalid_options)

    assert_error(
      Conformance.run(corpus, subject, target,
        generated_at: @generated_at,
        generated_at: @generated_at
      ),
      :invalid_options
    )

    assert_error(
      Conformance.run(corpus, subject, target, generated_at: @generated_at, unknown: true),
      :invalid_options
    )

    assert_error(
      Conformance.run(corpus, subject, target, generated_at: @generated_at, select: {:ids, [1]}),
      :invalid_selection
    )

    assert_error(
      Conformance.run(corpus, subject, target, generated_at: @generated_at, select: :invalid),
      :invalid_selection
    )
  end

  defp claim_input do
    %{
      id: "example.claim",
      revision: "1",
      operation: "thing_description.parse",
      evidence_profile: "value",
      standard: %{
        "identifier" => "w3c.wot.thing-description",
        "revision" => "2023-12-05",
        "source" => "https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/",
        "section" => "5.3"
      },
      assertions: ["assertion:b", "assertion:a", "assertion:a"],
      tags: ["td", "core", "td"]
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
      input: %{"document" => %{"title" => "Synthetic Thing"}},
      expectation: %{"operator" => "exact", "value" => %{"ok" => true}},
      provenance: %{
        "source" => "https://www.w3.org/TR/wot-thing-description11/",
        "observed" => "2026-09-02"
      },
      tags: ["core", "td", "core"]
    }
  end

  defp vector! do
    {:ok, vector} = Vector.new(vector_input())
    vector
  end

  defp response_input(outcome) do
    %{
      "protocol" => "wotex.conformance.target",
      "protocol_version" => "1.0",
      "vector_id" => "example.vector",
      "outcome" => outcome
    }
  end

  defp external_input(executable, archive) do
    %{
      executable: executable,
      args: ["{subject_archive}"],
      artifact_path: archive,
      environment: %{"MODE" => "offline"},
      timeout_ms: 5_000,
      max_output_bytes: 1_048_576
    }
  end

  defp corpus_source do
    Path.expand("../../../priv/vectors/thing-description-1.1", __DIR__)
  end

  defp assert_manifest_error(temp_root, transform, expected_code) do
    root = Path.join(temp_root, "corpus-#{System.unique_integer([:positive, :monotonic])}")
    File.cp_r!(corpus_source(), root)

    path = Path.join(root, "manifest.json")
    manifest = path |> File.read!() |> Jason.decode!() |> transform.()
    File.write!(path, Jason.encode!(manifest))

    assert_error(Corpus.load(root), expected_code)
  end

  defp assert_error({:error, %Error{code: actual}}, expected) do
    assert actual == expected
  end
end
