defmodule Wotex.Routines.DecisionSchemaTest do
  @moduledoc false

  use ExUnit.Case, async: true

  setup_all do
    schema = read("schemas/wro-02-verified-decision.schema.json")
    corpus = read("vectors/wro-02-verified-decision.json")

    selected =
      Map.new(Map.keys(corpus["shapes"]), fn name ->
        {name, select(schema, name)}
      end)

    %{raw: schema, schema: ExJsonSchema.Schema.resolve(schema), corpus: corpus, selected: selected}
  end

  test "closed entry shapes and all six elapsed/UTC alternatives resolve offline", c do
    for {name, shape} <- c.corpus["shapes"] do
      assert :ok == ExJsonSchema.Validator.validate(c.schema, shape), name
      assert :ok == ExJsonSchema.Validator.validate(c.selected[name], shape), name
    end

    assert length(c.corpus["cell_variants"]) == 6

    for cell <- c.corpus["cell_variants"] do
      assert :ok == ExJsonSchema.Validator.validate(c.selected["time_cell"], cell)

      for key <- Map.keys(cell) do
        assert {:error, _} =
                 ExJsonSchema.Validator.validate(c.selected["time_cell"], Map.delete(cell, key))
      end

      assert {:error, _} =
               ExJsonSchema.Validator.validate(
                 c.selected["time_cell"],
                 Map.put(cell, "authority", true)
               )
    end
  end

  test "frozen malformed and missing-field vectors refuse their selected shape", c do
    assert length(c.corpus["invalid_shapes"]) == 52

    for vector <- c.corpus["invalid_shapes"] do
      name = vector["shape"]
      shape = change(c.corpus["shapes"][name], vector["path"], vector)

      assert {:error, _} = ExJsonSchema.Validator.validate(c.selected[name], shape),
             inspect({name, vector["path"]})
    end
  end

  test "copied producer definitions and both retained grammars cannot drift", c do
    inherited = read("schemas/wro-02-continuation.schema.json")["definitions"]

    for {name, definition} <- inherited do
      assert c.raw["definitions"][name] == definition, name
    end

    names = %{
      "time1" => "time_v1",
      "time2" => "time_v2",
      "time2_without_utc" => "time_v2",
      "run1" => "run_v1",
      "run2" => "run_v2",
      "edge1" => "edge_v1",
      "edge2" => "edge_v2"
    }

    for {name, shape} <- c.corpus["inherited_shapes"] do
      schema = select(c.raw, names[name])
      assert :ok == ExJsonSchema.Validator.validate(schema, shape), name
      assert {:error, _} = ExJsonSchema.Validator.validate(schema, Map.put(shape, "extra", nil))
    end
  end

  test "cell mode and selected time grammar cannot silently switch", c do
    [ignored, absent1, present1, _, absent2, present2] = c.corpus["cell_variants"]

    invalid = [
      Map.put(ignored, "utc_generation", "utc:unexpected"),
      Map.put(absent1, "utc_generation", nil),
      Map.put(absent2, "utc_generation", "utc:unexpected"),
      Map.put(present1, "utc_generation", nil),
      Map.put(present2, "utc_high", nil),
      put_in(present2, ["utc_low", "min"], -9_223_372_036_854_775_808),
      put_in(present1, ["utc_high", "max"], 9_223_372_036_854_775_808)
    ]

    for cell <- invalid do
      assert {:error, _} = ExJsonSchema.Validator.validate(c.selected["time_cell"], cell)
    end
  end

  test "representation explicitly leaves correspondence and authority to semantic checks", c do
    shape = c.corpus["shapes"]["decision"]
    inverted = put_in(shape, ["cell", "elapsed"], %{"min" => 100, "max" => 20})
    assert :ok == ExJsonSchema.Validator.validate(c.schema, inverted)

    # A schema cannot compare an interval's endpoints, rederive a canonical
    # cell, authenticate membership or verify the synthetic fixture digests.
    assert String.contains?(c.raw["$comment"], "cannot prove")

    for refusal <- c.corpus["semantic_refusals"] do
      assert refusal["status"] == "planned"

      assert :ok ==
               ExJsonSchema.Validator.validate(
                 c.selected["decision_refusal"],
                 Map.take(refusal, ~w(code path))
               )
    end
  end

  defp select(schema, name) do
    schema
    |> Map.put("oneOf", [%{"$ref" => "#/definitions/" <> name}])
    |> ExJsonSchema.Schema.resolve()
  end

  defp read(path) do
    :wotex_routines
    |> :code.priv_dir()
    |> List.to_string()
    |> Path.join(path)
    |> File.read!()
    |> JSON.decode!()
  end

  defp change(data, [key], %{"operation" => "delete"}), do: Map.delete(data, key)
  defp change(data, [key], vector), do: Map.put(data, key, vector["value"])

  defp change(data, [key | rest], vector),
    do: Map.update!(data, key, &change(&1, rest, vector))
end
