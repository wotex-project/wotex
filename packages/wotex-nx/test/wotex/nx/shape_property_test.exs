defmodule Wotex.Nx.ShapePropertyTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.DataSchema
  alias Wotex.Nx.{Encoded, Encoder, Error, Feature, Observation, Row, Schema}

  property "fixed DataSchema arrays preserve their declared shape through encoding" do
    check all(
            count <- integer(1..16),
            values <- list_of(integer(-1_000..1_000), length: count)
          ) do
      {:ok, data_schema} =
        DataSchema.new(%{
          "type" => "array",
          "items" => %{"type" => "integer"},
          "minItems" => count,
          "maxItems" => count
        })

      {:ok, feature} =
        Feature.new(
          name: "samples",
          thing_id: "urn:example:thing:shape",
          affordance_type: :property,
          affordance_name: "samples",
          data_schema: data_schema
        )

      {:ok, schema} = Schema.new(features: [feature], max_width: 16)

      {:ok, observation} =
        Observation.new(
          id: "observation-shape",
          thing_id: "urn:example:thing:shape",
          affordance_type: :property,
          affordance_name: "samples",
          observed_at: 1,
          value: values
        )

      {:ok, row} = Row.new(1, %{"samples" => observation})
      assert {:ok, encoded} = Encoder.encode([row], schema)
      assert feature.shape == {count}
      assert %Nx.Batch{size: 1} = Encoded.batch(encoded)
    end
  end

  property "a value with the wrong fixed width is rejected before batch allocation" do
    check all(
            count <- integer(1..16),
            values <- list_of(integer(), length: count + 1)
          ) do
      {:ok, data_schema} =
        DataSchema.new(%{
          "type" => "array",
          "items" => %{"type" => "integer"},
          "minItems" => count,
          "maxItems" => count
        })

      {:ok, feature} =
        Feature.new(
          name: "samples",
          thing_id: "urn:example:thing:shape",
          affordance_type: :property,
          affordance_name: "samples",
          data_schema: data_schema
        )

      {:ok, schema} = Schema.new(features: [feature])

      {:ok, observation} =
        Observation.new(
          id: "observation-invalid-shape",
          thing_id: "urn:example:thing:shape",
          affordance_type: :property,
          affordance_name: "samples",
          observed_at: 1,
          value: values
        )

      {:ok, row} = Row.new(1, %{"samples" => observation})

      assert {:error, %Error{code: :data_schema_shape_mismatch}} =
               Encoder.encode([row], schema)
    end
  end

  test "structured errors reject malformed constructor arguments" do
    assert_raise FunctionClauseError, fn ->
      Error.new("invalid-code", :encoding, "message")
    end

    assert_raise FunctionClauseError, fn ->
      Error.new(:invalid, :encoding, :not_a_message)
    end
  end
end
