defmodule WotexContinuum.SchemaConformanceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias WotexContinuum.{Codec, JSONSchemaSubset, Schema}

  @vectors Path.expand("../vectors", __DIR__)

  @documents %{
    "WCT.01" => "wct-01.schema.json",
    "WCT.02" => "wct-02.schema.json",
    "WCT.03" => "wct-03.schema.json"
  }

  @document_for_kind %{
    "capability" => "wct-01.schema.json",
    "compatibility" => "wct-01.schema.json",
    "continuum_manifest" => "wct-01.schema.json",
    "execution_scope" => "wct-01.schema.json",
    "action_intent" => "wct-02.schema.json",
    "action_result" => "wct-02.schema.json",
    "delivery" => "wct-02.schema.json",
    "evidence_reference" => "wct-02.schema.json",
    "observation_proposal" => "wct-02.schema.json",
    "degradation" => "wct-03.schema.json",
    "exit_receipt" => "wct-03.schema.json",
    "lifecycle" => "wct-03.schema.json",
    "mode" => "wct-03.schema.json"
  }

  @schema_rejects_invalid_vector %{
    "wct-01-unknown-field.json" => true,
    "wct-01-unsupported-schema.json" => true,
    "wct-02-failed-result-without-error.json" => false,
    "wct-02-invalid-thing-id.json" => false,
    "wct-03-air-gap-connectivity.json" => true,
    "wct-03-empty-degradation.json" => false,
    "wct-03-remove-residuals.json" => false
  }

  test "every registered kind has a canonical vector" do
    covered =
      [@vectors, "canonical", "*.json"]
      |> Path.join()
      |> Path.wildcard()
      |> Enum.map(&get_in(read_vector(&1), ["input", "kind"]))
      |> Enum.uniq()
      |> Enum.sort()

    assert covered == WotexContinuum.kinds()
  end

  test "every canonical vector validates against its embedded normative schema" do
    registry = registry()

    for path <- Path.wildcard(Path.join([@vectors, "canonical", "*.json"])) do
      vector = read_vector(path)
      input = vector["input"]

      assert :ok = JSONSchemaSubset.validate(input, document_for(input), registry), path

      assert :ok =
               JSONSchemaSubset.validate(
                 Jason.decode!(vector["canonical"]),
                 document_for(input),
                 registry
               ),
             path
    end
  end

  test "every valid vector validates against its embedded normative schema" do
    registry = registry()

    for path <- Path.wildcard(Path.join([@vectors, "valid", "*.json"])) do
      input = read_vector(path)

      assert :ok = JSONSchemaSubset.validate(input, document_for(input), registry), path
      assert {:ok, _} = Codec.decode(File.read!(path)), path
    end
  end

  test "invalid vectors separate schema-expressible rules from semantic rules" do
    registry = registry()

    for path <- Path.wildcard(Path.join([@vectors, "invalid", "*.json"])) do
      vector = read_vector(path)
      input = vector["input"]
      result = JSONSchemaSubset.validate(input, document_for(input), registry)

      if Map.fetch!(@schema_rejects_invalid_vector, Path.basename(path)) do
        assert {:error, [_ | _]} = result, path
      else
        assert :ok = result, path
      end

      assert {:error, _} = Codec.decode(Jason.encode!(input)), path
    end
  end

  test "the subset checker enforces the keywords it claims to support" do
    registry = registry()
    valid = valid_capability()

    assert :ok = JSONSchemaSubset.validate(valid, "wct-01.schema.json", registry)

    for change <- [
          Map.delete(valid, "id"),
          Map.put(valid, "network", "satellite"),
          Map.put(valid, "kind", "capability_v2"),
          Map.put(valid, "version", "one"),
          Map.put(valid, "modes", []),
          Map.put(valid, "operations", ["forward", "forward"]),
          Map.put(valid, "id", ""),
          Map.put(valid, "ambient_policy", true)
        ] do
      assert {:error, [_ | _]} =
               JSONSchemaSubset.validate(change, "wct-01.schema.json", registry),
             inspect(change)
    end

    lifecycle = valid_lifecycle()
    assert :ok = JSONSchemaSubset.validate(lifecycle, "wct-03.schema.json", registry)

    assert {:error, [_ | _]} =
             JSONSchemaSubset.validate(
               Map.put(lifecycle, "generation", -1),
               "wct-03.schema.json",
               registry
             )
  end

  test "the subset checker does not evaluate format or property names" do
    registry = registry()

    unevaluated =
      valid_evidence()
      |> Map.put("uri", "relative-evidence")
      |> Map.put("extensions", %{"not-an-iri" => true})

    assert JSONSchemaSubset.unsupported_keywords() == ["format", "propertyNames"]
    assert :ok = JSONSchemaSubset.validate(unevaluated, "wct-02.schema.json", registry)

    assert {:error, %WotexContinuum.Error{code: :invalid_iri}} =
             WotexContinuum.from_map(unevaluated)
  end

  defp registry do
    Map.new(@documents, fn {id, file} ->
      assert {:ok, source} = Schema.fetch(id)

      {file, Jason.decode!(source)}
    end)
  end

  defp document_for(%{"kind" => kind}), do: Map.fetch!(@document_for_kind, kind)

  defp read_vector(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp valid_capability, do: read_vector(Path.join(@vectors, "valid/wct-01-capability.json"))

  defp valid_lifecycle, do: read_vector(Path.join(@vectors, "valid/wct-03-lifecycle.json"))

  defp valid_evidence, do: read_vector(Path.join(@vectors, "valid/wct-02-evidence.json"))
end
