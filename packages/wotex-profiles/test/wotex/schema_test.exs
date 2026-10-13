defmodule Wotex.Profiles.SchemaTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Profiles.{Definition, Error}
  alias Wotex.Profiles.Test.Fixtures, as: F

  test "supported mechanical DataSchema shapes preserve inert metadata and closed structures" do
    for schema <- [
          %{"type" => "null"},
          %{"type" => "boolean", "const" => true},
          %{"type" => "number", "minimum" => -1.1, "exclusiveMaximum" => 10, "multipleOf" => 0.1},
          %{"type" => "integer", "exclusiveMinimum" => 0, "maximum" => 12, "enum" => [1, 2]},
          %{
            "type" => "string",
            "minLength" => 0,
            "maxLength" => 20,
            "title" => "",
            "description" => "inert",
            "readOnly" => true,
            "writeOnly" => false,
            "observable" => true
          },
          %{"type" => "array", "items" => %{"type" => "boolean"}, "minItems" => 1, "maxItems" => 5},
          %{
            "type" => "object",
            "properties" => %{"x" => %{"type" => "integer"}},
            "required" => ["x"],
            "additionalProperties" => false
          },
          %{"type" => "object", "properties" => %{}, "additionalProperties" => false}
        ] do
      assert {:ok, value} =
               Definition.new(Map.put(F.definition(), "value_schema", schema), F.limits())

      assert value.data["value_schema"] == schema
    end
  end

  test "unsupported and ill-formed operators refuse instead of weakening validation" do
    for schema <- [
          nil,
          %{},
          %{"type" => ["string", "null"]},
          %{"type" => "bytes"},
          %{"type" => "number", "pattern" => "secret"},
          %{"type" => "number", "multipleOf" => 0},
          %{"type" => "number", "minimum" => "0"},
          %{"type" => "string", "minLength" => -1},
          %{"type" => "string", "maxLength" => 1_048_577},
          %{"type" => "string", "minLength" => 2, "maxLength" => 1},
          %{"type" => "array"},
          %{"type" => "array", "items" => true},
          %{"type" => "object", "properties" => %{}, "additionalProperties" => true},
          %{
            "type" => "object",
            "properties" => %{},
            "additionalProperties" => false,
            "required" => ["missing"]
          },
          %{
            "type" => "object",
            "properties" => %{},
            "additionalProperties" => false,
            "required" => false
          },
          %{
            "type" => "object",
            "properties" => %{"" => %{"type" => "string"}},
            "additionalProperties" => false
          },
          %{"type" => "string", "title" => 1},
          %{"type" => "boolean", "readOnly" => 1},
          %{"type" => "number", "enum" => []},
          %{"type" => "number", "enum" => [1, 1]},
          %{"type" => "number", "enum" => false}
        ] do
      assert {:error, %Error{}} =
               Definition.new(Map.put(F.definition(), "value_schema", schema), F.limits())
    end
  end

  test "numeric thresholds survive decimal normalization exactly or refuse" do
    base = Map.put(F.definition(), "value_schema", %{"type" => "number", "minimum" => 1.1})
    bytes = F.encode(base)
    assert {:ok, value} = Definition.parse(bytes, F.limits())
    assert value.data["value_schema"]["minimum"] == 1.1
    assert {:ok, _} = Definition.parse(String.replace(bytes, "1.1", "1.10"), F.limits())
    assert {:ok, _} = Definition.parse(String.replace(bytes, "1.1", "11e-1"), F.limits())

    for spelling <- [
          "1.10000000000000001",
          "1e19",
          "1e-19",
          "1e999999",
          "1e-999999",
          "9.9999999999999999e18"
        ] do
      assert {:error, %Error{code: :numeric_limit}} =
               Definition.parse(String.replace(bytes, "1.1", spelling), F.limits())
    end

    for value <- [1.0e19, 1.0e-19] do
      assert {:error, %Error{code: :numeric_limit}} =
               Definition.new(put_in(base, ["value_schema", "minimum"], value), F.limits())
    end

    assert {:ok, _} = Definition.parse(String.replace(bytes, "1.1", "0e18"), F.limits())

    assert {:error, %Error{code: :numeric_limit}} =
             Definition.new(
               Map.put(base, "value_schema", %{"type" => "number", "const" => [1.0e19]}),
               F.limits()
             )
  end
end
