defmodule Wotex.Nx.ObservationFeatureSchemaTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Nx.{Error, Feature, Observation, Row, Schema}
  alias Wotex.Nx.TestFactory

  test "observation retains caller identity, time, quality, source, and metadata" do
    assert {:ok, observation} =
             Observation.new(
               id: "o-1",
               thing_id: "urn:thing:1",
               affordance_type: :event,
               affordance_name: "alarm",
               observed_at: 42,
               value: true,
               unit: nil,
               quality: :uncertain,
               source: "sensor-a",
               metadata: %{"trace" => "t-1"}
             )

    assert observation.id == "o-1"
    assert observation.affordance_type == :event
    assert observation.value
    assert observation.quality == :uncertain
    assert Observation.qualities() == [:good, :uncertain, :bad, :missing]
  end

  test "observation validates every governed field" do
    valid = [
      id: "o",
      thing_id: "t",
      affordance_type: :property,
      affordance_name: "p",
      observed_at: 1,
      value: 1
    ]

    for {field, value, code} <- [
          {:id, "", :invalid_observation_field},
          {:thing_id, nil, :invalid_observation_field},
          {:affordance_type, :action, :invalid_affordance_type},
          {:affordance_name, 1, :invalid_observation_field},
          {:observed_at, 1.5, :invalid_observed_at},
          {:unit, "", :invalid_observation_field},
          {:quality, :unknown, :invalid_quality},
          {:source, 12, :invalid_observation_field},
          {:metadata, [], :invalid_metadata}
        ] do
      assert {:error, %Error{code: ^code}} = Observation.new(Keyword.put(valid, field, value))
    end

    assert {:error, %Error{code: :invalid_observation_options}} = Observation.new(%{})
  end

  test "feature infers scalar number, integer, boolean, and nested fixed-array contracts" do
    assert {:ok, number} = Feature.new(feature_options(TestFactory.data_schema()))
    assert number.dtype == {:f, 32}
    assert number.shape == {}
    assert number.unit == "Cel"
    assert Feature.width(number) == 1

    integer_schema = TestFactory.data_schema(%{"type" => "integer"})
    assert {:ok, integer} = Feature.new(feature_options(integer_schema))
    assert integer.dtype == {:s, 64}

    boolean_schema = TestFactory.data_schema(%{"type" => "boolean"})
    assert {:ok, boolean} = Feature.new(feature_options(boolean_schema))
    assert boolean.dtype == {:u, 8}

    matrix_schema =
      TestFactory.data_schema(%{
        "type" => "array",
        "minItems" => 2,
        "maxItems" => 2,
        "items" => %{
          "type" => "array",
          "minItems" => 3,
          "maxItems" => 3,
          "items" => %{"type" => "number"}
        }
      })

    assert {:ok, matrix} = Feature.new(feature_options(matrix_schema))
    assert matrix.shape == {2, 3}
    assert Feature.width(matrix) == 6
  end

  test "feature accepts explicit quality, missing, normalization, finite, dtype, and unit policy" do
    assert {:ok, feature} =
             Feature.new(
               Keyword.merge(
                 feature_options(TestFactory.data_schema(%{"type" => "number"})),
                 accepted_quality: [:good],
                 missing: {:fill, 0},
                 normalization: {:z_score, 10, 2},
                 allow_non_finite?: true,
                 dtype: :f64,
                 unit: "m"
               )
             )

    assert feature.accepted_quality == MapSet.new([:good])
    assert feature.missing == {:fill, 0}
    assert feature.normalization == {:z_score, 10, 2}
    assert feature.allow_non_finite?
    assert feature.dtype == {:f, 64}
    assert feature.unit == "m"

    assert {:ok, min_max} =
             Feature.new(
               Keyword.merge(
                 feature_options(TestFactory.data_schema()),
                 normalization: {:min_max, -10, 30}
               )
             )

    assert min_max.normalization == {:min_max, -10, 30}
  end

  test "feature rejects unsupported schemas and invalid identity or numerical policy" do
    unsupported = TestFactory.data_schema(%{"type" => "string"})
    variable = TestFactory.data_schema(%{"type" => "array", "items" => %{"type" => "number"}})

    assert {:error, %Error{code: :unsupported_data_schema}} =
             Feature.new(feature_options(unsupported))

    assert {:error, %Error{code: :unsupported_data_schema}} =
             Feature.new(feature_options(variable))

    assert {:error, %Error{code: :data_schema_required}} =
             Feature.new(feature_options(nil))

    assert {:error, %Error{code: :data_schema_required}} =
             Feature.new(feature_options(%{}))

    valid = feature_options(TestFactory.data_schema())

    for {change, code} <- [
          {[name: ""], :invalid_feature_identity},
          {[thing_id: ""], :invalid_feature_identity},
          {[affordance_type: :action], :invalid_feature_identity},
          {[affordance_name: nil], :invalid_feature_identity},
          {[shape: {2}], :shape_schema_mismatch},
          {[dtype: :not_a_dtype], :invalid_dtype},
          {[dtype: :s64], :dtype_schema_mismatch},
          {[accepted_quality: []], :invalid_accepted_quality},
          {[accepted_quality: [:invented]], :invalid_accepted_quality},
          {[missing: :drop], :invalid_missing_policy},
          {[normalization: {:z_score, 0, 0}], :invalid_normalization},
          {[normalization: {:min_max, 1, 1}], :invalid_normalization},
          {[unit: ""], :invalid_unit},
          {[allow_non_finite?: :yes], :invalid_finite_policy}
        ] do
      assert {:error, %Error{code: ^code}} = Feature.new(Keyword.merge(valid, change))
    end

    assert {:error, %Error{code: :invalid_feature_options}} = Feature.new(:invalid)

    integer = TestFactory.data_schema(%{"type" => "integer"})

    assert {:error, %Error{code: :normalization_dtype_mismatch}} =
             Feature.new(
               feature_options(integer)
               |> Keyword.put(:unit, nil)
               |> Keyword.put(:normalization, {:z_score, 0, 1})
             )
  end

  test "row captures exact observation provenance and permits explicit missing values" do
    observation = TestFactory.observation(id: "source-1")
    assert {:ok, row} = Row.new(100, %{"temperature" => observation, "humidity" => nil})
    assert row.timestamp == 100
    assert row.provenance == %{"temperature" => "source-1", "humidity" => nil}

    assert {:error, %Error{code: :invalid_row_observations}} = Row.new(100, %{1 => observation})
    assert {:error, %Error{code: :invalid_row}} = Row.new("100", %{})
  end

  test "schema preserves order, key, and explicit allocation limits" do
    first = TestFactory.feature(name: "first", affordance_name: "first")
    second = TestFactory.feature(name: "second", affordance_name: "second")

    assert {:ok, schema} =
             Schema.new(
               features: [first, second],
               max_rows: 4,
               max_features: 2,
               max_width: 2,
               batch_key: {:model, "a"}
             )

    assert Schema.features(schema) == [first, second]
    assert schema.batch_key == {:model, "a"}
  end

  test "schema rejects invalid limits, features, duplicates, counts, and width" do
    feature = TestFactory.feature()

    wide =
      TestFactory.feature(
        name: "wide",
        data_schema:
          TestFactory.data_schema(%{
            "type" => "array",
            "minItems" => 3,
            "maxItems" => 3,
            "items" => %{"type" => "number"}
          })
      )

    for {options, code} <- [
          {[features: [feature], max_rows: 0], :invalid_limit},
          {[features: [feature], max_features: -1], :invalid_limit},
          {[features: [feature], max_width: :infinite], :invalid_limit},
          {[features: []], :invalid_features},
          {[features: [:invalid]], :invalid_features},
          {[features: [feature], max_features: 0], :invalid_limit},
          {[features: [feature, feature]], :duplicate_feature_name},
          {[features: [wide], max_width: 2], :width_limit_exceeded}
        ] do
      assert {:error, %Error{code: ^code}} = Schema.new(options)
    end

    second = TestFactory.feature(name: "second", affordance_name: "second")

    assert {:error, %Error{code: :feature_limit_exceeded}} =
             Schema.new(features: [feature, second], max_features: 1)

    assert {:error, %Error{code: :invalid_schema_options}} = Schema.new(%{})
  end

  defp feature_options(data_schema) do
    [
      name: "temperature",
      thing_id: "urn:example:thing:1",
      affordance_type: :property,
      affordance_name: "temperature",
      data_schema: data_schema
    ]
  end
end
