defmodule Wotex.Conformance.SchemaTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Conformance.{JSONSchema, Report, Runner, TestFixtures, Vector}

  alias Wotex.Conformance.StaticTarget

  @generated_at ~U[2026-09-02 12:00:00Z]

  setup_all do
    schemas =
      "../../../priv/schemas/*.schema.json"
      |> Path.expand(__DIR__)
      |> Path.wildcard()
      |> Enum.map(&(&1 |> File.read!() |> Jason.decode!()))

    %{schemas: schemas, registry: JSONSchema.registry(schemas)}
  end

  test "all portable schemas are identified JSON Schema 2020-12 documents", context do
    assert length(context.schemas) == 10

    for schema <- context.schemas do
      assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
      assert String.starts_with?(schema["$id"], "https://wotex.io/schemas/conformance/")
      assert is_binary(schema["title"])
    end
  end

  test "every bundled vector, claim, and observation matches its schema mirror", context do
    for path <- vector_files() do
      vector = path |> File.read!() |> Jason.decode!()

      assert :ok = validate(context, "vector-1.0", vector), "invalid vector: #{path}"
      assert :ok = validate(context, "claim-1.0", vector["claim"]), "invalid claim: #{path}"

      assert :ok = validate(context, "document-input-1.0", vector["input"]),
             "invalid input: #{path}"

      assert :ok = validate(context, "observation-1.0", vector["expectation"]["value"]),
             "invalid observation: #{path}"
    end
  end

  test "both corpus manifests match the corpus schema mirror", context do
    for directory <- ~w(thing-description-1.1 thing-model-1.1) do
      manifest =
        "../../../priv/vectors/#{directory}/manifest.json"
        |> Path.expand(__DIR__)
        |> File.read!()
        |> Jason.decode!()

      assert :ok = validate(context, "corpus-1.0", manifest), "invalid manifest: #{directory}"
    end
  end

  test "a produced report, its results, and its subject match their schema mirrors", context do
    report = report!()
    encoded = report |> Report.to_map() |> Jason.encode!() |> Jason.decode!()

    assert :ok = validate(context, "report-1.0", encoded)
    assert :ok = validate(context, "subject-1.0", encoded["subject"])

    for result <- encoded["results"] do
      assert :ok = validate(context, "result-1.0", result)
    end
  end

  test "a produced target request and both response outcomes match their mirrors", context do
    corpus = TestFixtures.corpus!()
    vector = hd(corpus.vectors)
    subject = TestFixtures.subject!(zero_digest())

    request =
      Vector.target_request(vector, subject, %{
        "corpus" => %{"id" => corpus.id, "revision" => corpus.revision, "digest" => corpus.digest},
        "generated_at" => "2026-09-02T12:00:00Z",
        "environment" => %{"runtime" => "otp-28"}
      })

    encoded = request |> Jason.encode!() |> Jason.decode!()
    assert :ok = validate(context, "target-request-1.0", encoded)
    refute Map.has_key?(encoded["vector"], "expectation")
    assert encoded["vector"]["input"]["projection"] == vector.input["projection"]

    observed = %{
      "protocol" => "wotex.conformance.target",
      "protocol_version" => "1.0",
      "vector_id" => vector.id,
      "outcome" => "observed",
      "actual" => vector.expectation.value
    }

    unsupported =
      observed
      |> Map.drop(["actual"])
      |> Map.merge(%{"outcome" => "unsupported", "codes" => ["operation_not_implemented"]})

    assert :ok = validate(context, "target-response-1.0", observed)
    assert :ok = validate(context, "target-response-1.0", unsupported)

    assert {:error, _messages} =
             validate(context, "target-response-1.0", Map.put(unsupported, "actual", %{}))
  end

  test "the schema mirrors reject the values their constructors reject", context do
    vector = vector_files() |> hd() |> File.read!() |> Jason.decode!()

    invalid = [
      {"vector-1.0", Map.put(vector, "unexpected", true)},
      {"vector-1.0", Map.put(vector, "digest", "sha256:not-a-digest")},
      {"vector-1.0", put_in(vector, ["input", "projection"], ["title"])},
      {"vector-1.0", put_in(vector, ["input"], %{"document" => %{}})},
      {"vector-1.0", put_in(vector, ["expectation", "value"], %{"accepted" => true})},
      {"claim-1.0", put_in(vector, ["claim", "evidence_profile"], "imaginary")["claim"]},
      {"observation-1.0", %{"accepted" => true, "document" => "not-an-object"}},
      {"observation-1.0", %{"accepted" => false, "errors" => []}},
      {"observation-1.0",
       %{"accepted" => false, "errors" => [%{"code" => "Bad Code", "phase" => "s", "path" => "/"}]}},
      {"observation-1.0",
       %{"accepted" => false, "errors" => [%{"code" => "ok", "phase" => "s", "path" => "title"}]}},
      {"document-input-1.0", %{"document" => %{}, "projection" => [""]}}
    ]

    for {schema, value} <- invalid do
      assert {:error, [_first | _rest]} = validate(context, schema, value),
             "schema #{schema} accepted an invalid value: #{inspect(value)}"
    end
  end

  test "a rejected vector expectation is also rejected by its constructor" do
    vector = vector_files() |> hd() |> File.read!() |> Jason.decode!()

    assert {:error, %{code: :invalid_observation}} =
             Vector.from_map(put_in(vector, ["expectation", "value"], %{"accepted" => true}))

    assert {:error, %{code: :invalid_projection}} =
             Vector.from_map(put_in(vector, ["input", "projection"], ["title"]))

    assert {:error, %{code: :invalid_vector_input}} =
             Vector.from_map(put_in(vector, ["input"], %{"document" => %{}}))
  end

  defp validate(context, schema, value) do
    schema = Map.fetch!(context.registry, "https://wotex.io/schemas/conformance/#{schema}.json")
    JSONSchema.validate(schema, value, context.registry)
  end

  defp vector_files do
    "../../../priv/vectors/*/*.json"
    |> Path.expand(__DIR__)
    |> Path.wildcard()
    |> Enum.reject(&(Path.basename(&1) == "manifest.json"))
    |> Enum.sort()
  end

  defp report! do
    {root, archive, digest} = TestFixtures.subject_archive!()
    on_exit(fn -> File.rm_rf!(root) end)

    corpus = TestFixtures.corpus!()
    subject = TestFixtures.subject!(digest)
    vector = hd(corpus.vectors)

    target =
      {StaticTarget, %{artifact_path: archive, actual: vector.expectation.value, owner: self()}}

    {:ok, report} =
      Runner.run(corpus, subject, target,
        generated_at: @generated_at,
        environment: %{"runtime" => "otp-28"}
      )

    assert Enum.any?(report.results, &(&1.status == :pass))
    report
  end

  defp zero_digest, do: "sha256:" <> String.duplicate("0", 64)
end
