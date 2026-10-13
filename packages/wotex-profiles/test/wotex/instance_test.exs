defmodule Wotex.Profiles.InstanceTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Profiles.{Error, Instance}
  alias Wotex.Profiles.Test.Fixtures, as: F

  test "independent logical-domain vectors freeze exact matching" do
    for vector <- F.json("instances")["cases"] do
      actual = Instance.c02(vector["value"], vector["schema"], F.limits(), "/value")

      if vector["valid"],
        do: assert(actual == :ok, vector["name"]),
        else: assert(match?({:error, %Error{code: :out_of_domain}}, actual), vector["name"])
    end
  end

  test "selectors use the same closed schema and safe parent error paths" do
    schema = F.json("installed-binding")["selector_schema"]
    assert :ok = Instance.json(%{"register" => 4}, schema, F.limits(), "/selector")

    for value <- [
          %{},
          %{"register" => -1},
          %{"register" => "4"},
          %{"credential-canary" => "secret"}
        ] do
      assert {:error, %Error{code: :out_of_domain, path: "/selector"}} =
               Instance.json(value, schema, F.limits(), "/selector")
    end

    assert {:error, %Error{code: :codec_required}} =
             Instance.c02(
               %{"type" => "bytes", "base64" => "AA=="},
               %{"type" => "string"},
               F.limits(),
               "/value"
             )

    assert {:error, %Error{code: :invalid_input}} =
             Instance.c02(1, %{"type" => "integer"}, F.limits(), "/value")
  end

  test "large exponents and cross-products refuse before approximate comparison" do
    schema = %{"type" => "number", "maximum" => 1}
    node = %{"type" => "decimal", "coefficient" => "1", "exponent" => 32_767}
    assert :ok = Instance.c02(node, %{"type" => "number"}, F.limits(), "/value")
    assert {:error, %Error{code: :numeric_limit}} = Instance.c02(node, schema, F.limits(), "/value")
    limits = Map.put(F.limits(), "max_numeric_digits", 2)

    assert {:error, %Error{code: :numeric_limit}} =
             Instance.c02(
               %{"type" => "sint", "value" => "99"},
               %{"type" => "number", "minimum" => 0.1},
               limits,
               "/value"
             )
  end

  test "nested const and enum use logical equality while keeping booleans and numbers distinct" do
    schema = %{
      "type" => "object",
      "properties" => %{"x" => %{"type" => "number"}},
      "additionalProperties" => false,
      "const" => %{"x" => 1}
    }

    node = %{
      "type" => "object",
      "entries" => [
        %{"key" => "x", "value" => %{"type" => "decimal", "coefficient" => "1", "exponent" => 0}}
      ]
    }

    assert :ok = Instance.c02(node, schema, F.limits(), "/value")

    assert {:error, %Error{code: :out_of_domain}} =
             Instance.c02(%{"type" => "object", "entries" => []}, schema, F.limits(), "/value")

    assert :ok = Instance.json(%{"x" => 1.0}, schema, F.limits(), "/value")

    assert {:error, %Error{code: :out_of_domain}} =
             Instance.json(%{"x" => 2}, schema, F.limits(), "/value")

    assert {:error, %Error{code: :out_of_domain}} =
             Instance.c02(
               %{"type" => "boolean", "value" => false},
               %{"type" => "boolean", "enum" => [true]},
               F.limits(),
               "/value"
             )

    assert {:error, %Error{code: :out_of_domain}} =
             Instance.c02(
               %{"type" => "text", "value" => "x"},
               %{"type" => "string", "const" => "y"},
               F.limits(),
               "/value"
             )

    assert {:error, %Error{code: :out_of_domain}} =
             Instance.json(
               [nil, false, "x"],
               %{"type" => "array", "items" => %{"type" => "null"}, "const" => [nil, false, "x"]},
               F.limits(),
               "/value"
             )
  end
end
