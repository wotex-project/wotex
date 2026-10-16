defmodule Wotex.Routines.ContinuationSchemaTest do
  @moduledoc false

  use ExUnit.Case, async: true

  setup_all do
    priv = priv()
    schema = read(priv, "schemas/wro-02-continuation.schema.json")
    corpus = read(priv, "vectors/wro-02-continuation.json")

    definitions = %{
      "resume" => "event",
      "satisfied" => "event",
      "time1" => "time_v1",
      "time2" => "time_v2",
      "time2_without_utc" => "time_v2",
      "run1" => "run_v1",
      "run2" => "run_v2",
      "edge1" => "edge_v1",
      "edge2" => "edge_v2",
      "scalar_occurrence1" => "scalar_occurrence_v1",
      "scalar_occurrence2" => "scalar_occurrence_v2",
      "wide_limits" => "limits",
      "collection_input1" => "collection_input_v1",
      "collection_input2" => "collection_input_v2",
      "collection1" => "collection_v1",
      "collection2" => "collection_v2",
      "arbitration" => "arbitration"
    }

    selected =
      Map.new(definitions, fn {name, definition} ->
        selected = Map.put(schema, "oneOf", [%{"$ref" => "#/definitions/" <> definition}])
        {name, ExJsonSchema.Schema.resolve(selected)}
      end)

    %{schema: ExJsonSchema.Schema.resolve(schema), selected: selected, shapes: corpus["shapes"]}
  end

  test "independent legacy and successor shapes have closed required fields", c do
    for {name, value} <- c.shapes do
      assert :ok == validate(c, value), name

      for key <- Map.keys(value) do
        assert {:error, _} =
                 ExJsonSchema.Validator.validate(c.selected[name], Map.delete(value, key)),
               "#{name}: #{key}"
      end

      assert {:error, _} = validate(c, Map.put(value, "undeclared", true)), name
    end
  end

  test "clock presence, run receipt slots and collection formats cannot be mixed", c do
    shapes = c.shapes

    invalid = [
      %{shapes["time2"] | "utc_generation" => nil},
      %{shapes["time2_without_utc"] | "utc_generation" => "utc:1"},
      %{shapes["time2"] | "utc_low_ms" => nil},
      Map.put(shapes["time1"], "utc_generation", nil),
      Map.put(shapes["edge1"], "time_format", "wotex.routines.time@2"),
      Map.delete(shapes["edge2"], "time_format"),
      %{shapes["edge2"] | "time_format" => "wotex.routines.time@1"},
      Map.put(shapes["run1"], "time_format", "wotex.routines.time@1"),
      put_in(shapes["run1"], ["steps", Access.at(0), "receipts", "satisfied"], nil),
      update_in(shapes["run2"], ["steps", Access.at(0), "receipts"], &Map.delete(&1, "satisfied")),
      put_in(shapes["run2"], ["time_format"], "wotex.routines.time@3"),
      %{shapes["collection1"] | "input" => shapes["collection_input2"]},
      %{shapes["collection2"] | "input" => shapes["collection_input1"]},
      Map.delete(shapes["collection2"], "proposal_states"),
      put_in(shapes["satisfied"], ["report_contract", "authority"], true),
      Map.put(shapes["resume"], "fact_id", "fact:1")
    ]

    for value <- invalid, do: assert({:error, _} = validate(c, value))
  end

  test "explicit limit ceilings and every embedded schema remain offline-resolvable", c do
    for key <- Map.keys(c.shapes["wide_limits"]) do
      value = c.shapes["wide_limits"][key]
      assert {:error, _} = validate(c, put_in(c.shapes["wide_limits"], [key], value + 1))
      assert {:error, _} = validate(c, put_in(c.shapes["wide_limits"], [key], 0))
    end

    priv = priv()

    for path <- Path.wildcard(Path.join(priv, "schemas/wro-*.json")) do
      assert %ExJsonSchema.Schema.Root{} =
               path
               |> File.read!()
               |> JSON.decode!()
               |> ExJsonSchema.Schema.resolve()
    end
  end

  defp priv do
    :wotex_routines
    |> :code.priv_dir()
    |> List.to_string()
  end

  defp read(priv, path) do
    priv
    |> Path.join(path)
    |> File.read!()
    |> JSON.decode!()
  end

  defp validate(c, value), do: ExJsonSchema.Validator.validate(c.schema, value)
end
