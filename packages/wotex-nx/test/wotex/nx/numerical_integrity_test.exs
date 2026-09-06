defmodule Wotex.Nx.NumericalIntegrityTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Nx.{Decoder, Encoder, Error, OutputSchema, TestFactory}

  test "every supported integer width preserves its endpoints and rejects wrapping" do
    for class <- [:s, :u], bits <- [2, 4, 8, 16, 32, 64] do
      minimum = if class == :s, do: -Bitwise.bsl(1, bits - 1), else: 0
      maximum = Bitwise.bsl(1, if(class == :s, do: bits - 1, else: bits)) - 1
      feature = feature(%{"type" => "integer"}, dtype: {class, bits})

      for value <- [minimum, maximum] do
        assert {:ok, encoded} = encode(value, feature)
        assert values(encoded) == [value]
      end

      for value <- [minimum - 1, maximum + 1] do
        assert {:error, %Error{code: :dtype_value_out_of_range}} = encode(value, feature)
      end
    end
  end

  test "integer range checks cover nested arrays and missing fills" do
    schema = array_schema(array_schema(%{"type" => "integer"}))
    feature = feature(schema, dtype: :u8)

    assert {:error, %Error{code: :dtype_value_out_of_range}} =
             encode([[1, 2], [3, 256]], feature)

    assert {:ok, encoded} = encode([[0, 1], [254, 255]], feature)
    assert values(encoded) == [0, 1, 254, 255]

    fill_feature = feature(schema, dtype: :u8, missing: {:fill, 256})
    row = TestFactory.row(100, %{})

    assert {:error, %Error{code: :dtype_value_out_of_range}} =
             Encoder.encode([row], TestFactory.schema([fill_feature]))
  end

  test "finite inputs cannot silently become infinity in a narrower floating dtype" do
    for dtype <- [:bf16, :f16, :f32], value <- [1.0e100, -1.0e100] do
      feature = feature(%{"type" => "number"}, dtype: dtype)
      assert {:error, %Error{code: :non_finite_value}} = encode(value, feature)
    end

    feature = feature(array_schema(%{"type" => "number"}), dtype: :f32)

    assert {:error, %Error{code: :non_finite_value}} = encode([1.0, 1.0e100], feature)

    assert {:ok, encoded} = encode([0.1, 2.0], feature)
    assert_in_delta hd(values(encoded)), 0.1, 1.0e-7

    allowed = feature(%{"type" => "number"}, dtype: :f32, allow_non_finite?: true)
    assert {:ok, encoded} = encode(1.0e100, allowed)
    assert values(encoded) == [:infinity]
  end

  test "finite policy covers missing fills and values returned by a unit converter" do
    feature = feature(%{"type" => "number"}, dtype: :f32, missing: {:fill, 1.0e100})
    row = TestFactory.row(100, %{})

    assert {:error, %Error{code: :non_finite_value}} =
             Encoder.encode([row], TestFactory.schema([feature]))

    converted_feature = feature(%{"type" => "number"}, dtype: :f32, unit: "Cel")
    observation = TestFactory.observation(value: 1.0e100, unit: "degF")
    row = TestFactory.row(100, %{"temperature" => observation})

    assert {:error, %Error{code: :non_finite_value}} =
             Encoder.encode([row], TestFactory.schema([converted_feature]),
               unit_converter: {Wotex.Nx.TestUnitConverter, :valid}
             )
  end

  test "normalization checks both resulting dtype overflow and arithmetic overflow" do
    feature =
      feature(%{"type" => "number"}, dtype: :f32, normalization: {:z_score, 0, 1.0e-30})

    assert {:error, %Error{code: :non_finite_value}} = encode(1.0e30, feature)

    feature =
      feature(%{"type" => "number"}, dtype: :f64, normalization: {:z_score, 0, 1.0e-100})

    assert {:error, %Error{code: :normalization_overflow}} = encode(1.0e300, feature)

    feature =
      feature(%{"type" => "number"},
        normalization: {:min_max, 0, 1},
        allow_non_finite?: true
      )

    assert {:ok, encoded} = encode(:nan, feature)
    assert values(encoded) == [:nan]
  end

  test "enum and const are both enforced on scalar and array items" do
    constrained = %{"type" => "integer", "enum" => [1, 2], "const" => 2}
    feature = feature(constrained)

    assert {:error, %Error{code: :data_schema_const_mismatch}} = encode(1, feature)
    assert {:error, %Error{code: :data_schema_enum_mismatch}} = encode(3, feature)
    assert {:ok, encoded} = encode(2, feature)
    assert values(encoded) == [2]

    feature = feature(array_schema(constrained))
    assert {:error, %Error{code: :data_schema_const_mismatch}} = encode([2, 1], feature)
    assert {:ok, encoded} = encode([2, 2], feature)
    assert values(encoded) == [2, 2]
  end

  test "decoded output also enforces enum and const together" do
    assert {:ok, schema} =
             OutputSchema.new(
               kind: :prediction,
               thing_id: "urn:example:thing:1",
               affordance_type: :property,
               affordance_name: "temperature",
               data_schema:
                 TestFactory.data_schema(%{"type" => "integer", "enum" => [1, 2], "const" => 2})
             )

    opts = [id: "prediction-1", produced_at: 100, target_at: 200]

    assert {:error, %Error{code: :data_schema_const_mismatch}} =
             Decoder.decode(Nx.tensor(1, type: :s64), schema, opts)

    assert {:ok, prediction} = Decoder.decode(Nx.tensor(2, type: :s64), schema, opts)
    assert prediction.value == 2
  end

  defp feature(schema, options \\ []) do
    TestFactory.feature(
      Keyword.merge([data_schema: TestFactory.data_schema(schema), unit: nil], options)
    )
  end

  defp encode(value, feature) do
    observation = TestFactory.observation(value: value, unit: feature.unit)
    row = TestFactory.row(100, %{"temperature" => observation})
    Encoder.encode([row], TestFactory.schema([feature]))
  end

  defp values(encoded) do
    {{tensor}, _, _} = Nx.Defn.jit_apply(&Function.identity/1, [encoded.batch])
    Nx.to_flat_list(tensor)
  end

  defp array_schema(items),
    do: %{"type" => "array", "minItems" => 2, "maxItems" => 2, "items" => items}
end
