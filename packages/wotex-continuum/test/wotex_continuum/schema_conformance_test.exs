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

      case vector["schema"] do
        "reject" -> assert {:error, [_ | _]} = result, path
        "semantic" -> assert :ok = result, path
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

  test "the agreement checker evaluates every schema keyword used by WCT" do
    registry = registry()

    assertion_keywords =
      @documents
      |> Enum.flat_map(fn {_, file} -> schema_keywords(Map.fetch!(registry, file)) end)
      |> Enum.uniq()
      |> Enum.reject(&(&1 in ~w($schema $id $defs title)))
      |> Enum.sort()

    assert assertion_keywords == Enum.sort(JSONSchemaSubset.supported_keywords())

    format_and_property_name_errors =
      valid_evidence()
      |> Map.put("uri", "relative-evidence")
      |> Map.put("extensions", %{"not-an-iri" => true})

    assert JSONSchemaSubset.unsupported_keywords() == []

    assert {:error, [_ | _]} =
             JSONSchemaSubset.validate(
               format_and_property_name_errors,
               "wct-02.schema.json",
               registry
             )

    assert {:error, %WotexContinuum.Error{code: :invalid_iri, path: "/uri"}} =
             WotexContinuum.from_map(format_and_property_name_errors)

    semantic_only =
      read_vector(Path.join(@vectors, "valid/wct-01-compatibility.json"))
      |> Map.put("schema_requirement", "not a version requirement")

    assert :ok = JSONSchemaSubset.validate(semantic_only, "wct-01.schema.json", registry)

    assert {:error,
            %WotexContinuum.Error{
              code: :invalid_version_requirement,
              path: "/schema_requirement"
            }} = WotexContinuum.from_map(semantic_only)
  end

  test "cross-document references resolve through exact embedded schema IDs" do
    registry = registry()

    ids =
      @documents
      |> Map.values()
      |> Map.new(fn file ->
        schema = Map.fetch!(registry, file)
        {schema["$id"], true}
      end)

    for {_, file} <- @documents,
        reference <- schema_references(Map.fetch!(registry, file)),
        not String.starts_with?(reference, "#") do
      [target, _] = String.split(reference, "#", parts: 2)
      assert Map.has_key?(ids, target), "#{file} has unresolved reference #{reference}"
    end
  end

  defp registry do
    Enum.reduce(@documents, %{}, fn {id, file}, registry ->
      assert {:ok, source} = Schema.fetch(id)
      schema = Jason.decode!(source)

      registry
      |> Map.put(file, schema)
      |> Map.put(schema["$id"], schema)
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

  defp schema_keywords(schema) when is_map(schema) do
    Map.keys(schema) ++ Enum.flat_map(schema_children(schema), &schema_keywords/1)
  end

  defp schema_keywords(_), do: []

  defp schema_references(schema) when is_map(schema) do
    references = if is_binary(schema["$ref"]), do: [schema["$ref"]], else: []
    references ++ Enum.flat_map(schema_children(schema), &schema_references/1)
  end

  defp schema_references(_), do: []

  defp schema_children(schema) do
    singular = Enum.map(~w(if then items propertyNames), &Map.get(schema, &1))
    plural = Enum.flat_map(~w(oneOf allOf), &Map.get(schema, &1, []))
    named = Enum.flat_map(~w($defs properties), &Map.values(Map.get(schema, &1, %{})))

    Enum.reject(singular ++ plural ++ named, &is_nil/1)
  end
end
