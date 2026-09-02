defmodule Wotex.Nx.WindowEncoderTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Nx.{Encoded, Encoder, Error, Window}
  alias Wotex.Nx.TestFactory
  alias Wotex.Nx.TestUnitConverter

  test "window constructors require caller-supplied bounded temporal policy" do
    assert {:ok, window} =
             Window.new(start: 0, step: 10, count: 3, strategy: :nearest, max_age: 5)

    assert window.start == 0
    assert window.step == 10
    assert window.count == 3
    assert window.strategy == :nearest
    assert window.max_age == 5

    for {options, code} <- [
          {[start: nil, step: 1, count: 1], :invalid_window_start},
          {[start: 0, step: 0, count: 1], :invalid_window_step},
          {[start: 0, step: 1, count: 0], :invalid_window_count},
          {[start: 0, step: 1, count: 1, strategy: :mean], :invalid_window_strategy},
          {[start: 0, step: 1, count: 1, max_age: -1], :invalid_max_age}
        ] do
      assert {:error, %Error{code: ^code}} = Window.new(options)
    end

    assert {:error, %Error{code: :invalid_window_options}} = Window.new(%{})
  end

  test "exact selection is deterministic by observation id" do
    schema = TestFactory.schema()
    {:ok, window} = Window.new(start: 100, step: 1, count: 1, strategy: :exact)
    later_id = TestFactory.observation(id: "z", value: 30)
    earlier_id = TestFactory.observation(id: "a", value: 20)

    assert {:ok, [row]} = Window.resample([later_id, earlier_id], schema, window)
    assert row.observations["temperature"].id == "a"
  end

  test "latest selection prefers newest timestamp then stable id and enforces max age" do
    schema = TestFactory.schema()
    older = TestFactory.observation(id: "a", observed_at: 90, value: 10)
    newest_z = TestFactory.observation(id: "z", observed_at: 99, value: 20)
    newest_a = TestFactory.observation(id: "a", observed_at: 99, value: 21)

    {:ok, window} = Window.new(start: 100, step: 5, count: 2, max_age: 2)
    assert {:ok, [first, second]} = Window.resample([older, newest_z, newest_a], schema, window)
    assert first.observations["temperature"].id == "a"
    assert second.observations["temperature"] == nil
  end

  test "nearest selection resolves equal distance by earlier timestamp then id" do
    schema = TestFactory.schema()
    before_z = TestFactory.observation(id: "z", observed_at: 95)
    before_a = TestFactory.observation(id: "a", observed_at: 95)
    later = TestFactory.observation(id: "b", observed_at: 105)
    {:ok, window} = Window.new(start: 100, step: 1, count: 1, strategy: :nearest)

    assert {:ok, [row]} = Window.resample([later, before_z, before_a], schema, window)
    assert row.observations["temperature"].id == "a"
  end

  test "window preserves schema feature order and leaves absent affordances missing" do
    temperature = TestFactory.feature()
    humidity = TestFactory.feature(name: "humidity", affordance_name: "humidity", unit: "%")
    schema = TestFactory.schema([temperature, humidity])
    {:ok, window} = Window.new(start: 100, step: 1, count: 1, strategy: :exact)

    assert {:ok, [row]} = Window.resample([TestFactory.observation()], schema, window)
    assert Map.keys(row.observations) |> Enum.sort() == ["humidity", "temperature"]
    assert row.observations["humidity"] == nil
  end

  test "window and encoder never mix identical affordance names across Things" do
    schema = TestFactory.schema()

    other_thing =
      TestFactory.observation(id: "other", thing_id: "urn:example:thing:2")

    {:ok, window} = Window.new(start: 100, step: 1, count: 1, strategy: :exact)
    assert {:ok, [row]} = Window.resample([other_thing], schema, window)
    assert row.observations["temperature"] == nil

    direct_row = TestFactory.row(100, %{"temperature" => other_thing})

    assert {:error, %Error{code: :observation_feature_mismatch}} =
             Encoder.encode([direct_row], schema)
  end

  test "window reports observation and work bounds plus invalid aggregate input" do
    schema = TestFactory.schema()
    observation = TestFactory.observation()
    {:ok, window} = Window.new(start: 0, step: 1, count: 2)

    assert {:error, %Error{code: :invalid_window_limit}} =
             Window.resample([], schema, window, max_work: 0)

    assert {:error, %Error{code: :observation_limit_exceeded}} =
             Window.resample([observation, observation], schema, window, max_observations: 1)

    assert {:error, %Error{code: :window_work_limit_exceeded}} =
             Window.resample([observation], schema, window, max_work: 1)

    assert {:error, %Error{code: :invalid_observations}} =
             Window.resample([:not_an_observation], schema, window)

    assert {:error, %Error{code: :invalid_window_input}} =
             Window.resample([], :not_a_schema, window)

    one_row_schema = TestFactory.schema([TestFactory.feature()], max_rows: 1)

    assert {:error, %Error{code: :row_limit_exceeded}} =
             Window.resample([observation], one_row_schema, window)
  end

  test "encoder creates a keyed batch with deterministic values, masks, quality, and provenance" do
    first = TestFactory.feature(name: "temperature", affordance_name: "temperature")

    second =
      TestFactory.feature(
        name: "enabled",
        affordance_name: "enabled",
        data_schema: TestFactory.data_schema(%{"type" => "boolean"}),
        unit: nil
      )

    schema = TestFactory.schema([first, second], batch_key: {:model, "v1"})

    enabled =
      TestFactory.observation(
        id: "enabled-1",
        affordance_name: "enabled",
        value: true,
        unit: nil,
        quality: :uncertain
      )

    row = TestFactory.row(100, %{"enabled" => enabled, "temperature" => TestFactory.observation()})

    assert {:ok, encoded} = Encoder.encode([row], schema)
    assert %Nx.Batch{key: {:model, "v1"}, size: 1} = Encoded.batch(encoded)
    assert Encoded.feature_order(encoded) == ["temperature", "enabled"]
    assert encoded.timestamps == [100]
    assert encoded.provenance == [%{"enabled" => "enabled-1", "temperature" => "observation-1"}]

    {{temperature, enabled_tensor}, {temperature_mask, enabled_mask}, quality} =
      Nx.Defn.jit_apply(&Function.identity/1, [Encoded.batch(encoded)])

    assert Nx.to_flat_list(temperature) == [21.5]
    assert Nx.to_flat_list(enabled_tensor) == [1]
    assert Nx.to_flat_list(temperature_mask) == [0]
    assert Nx.to_flat_list(enabled_mask) == [0]
    assert Nx.to_flat_list(quality) == [0, 1]
  end

  test "missing fill broadcasts over fixed arrays and marks mask and quality" do
    vector =
      TestFactory.feature(
        name: "vector",
        affordance_name: "vector",
        data_schema:
          TestFactory.data_schema(%{
            "type" => "array",
            "minItems" => 2,
            "maxItems" => 2,
            "items" => %{"type" => "number"}
          }),
        missing: {:fill, 3},
        unit: nil
      )

    schema = TestFactory.schema([vector])
    row = TestFactory.row(10, %{"vector" => nil})
    assert {:ok, encoded} = Encoder.encode([row], schema)
    {{values}, {masks}, quality} = Nx.Defn.jit_apply(&Function.identity/1, [encoded.batch])
    assert Nx.to_flat_list(values) == [3.0, 3.0]
    assert Nx.to_flat_list(masks) == [1, 1]
    assert Nx.to_flat_list(quality) == [3]
  end

  test "rejected quality follows declared missing policy" do
    strict = TestFactory.feature(accepted_quality: [:good])
    schema = TestFactory.schema([strict])
    bad = TestFactory.observation(quality: :bad)
    row = TestFactory.row(100, %{"temperature" => bad})

    assert {:error, %Error{code: :missing_feature_value, details: %{quality: :bad}}} =
             Encoder.encode([row], schema)

    fill = TestFactory.feature(accepted_quality: [:good], missing: {:fill, 0})
    assert {:ok, encoded} = Encoder.encode([row], TestFactory.schema([fill]))
    {{value}, {mask}, quality} = Nx.Defn.jit_apply(&Function.identity/1, [encoded.batch])
    assert Nx.to_flat_list(value) == [0.0]
    assert Nx.to_flat_list(mask) == [1]
    assert Nx.to_flat_list(quality) == [2]
  end

  test "unit conversion is explicit and converter failures are redacted" do
    feature = TestFactory.feature()
    schema = TestFactory.schema([feature])
    fahrenheit = TestFactory.observation(value: 68, unit: "degF")
    row = TestFactory.row(100, %{"temperature" => fahrenheit})

    assert {:error, %Error{code: :unit_conversion_required}} = Encoder.encode([row], schema)

    assert {:ok, encoded} =
             Encoder.encode([row], schema, unit_converter: {TestUnitConverter, :valid})

    {{value}, {_mask}, _quality} = Nx.Defn.jit_apply(&Function.identity/1, [encoded.batch])
    assert_in_delta hd(Nx.to_flat_list(value)), 20.0, 0.0001

    assert {:error, %Error{code: :unit_conversion_failed}} =
             Encoder.encode([row], schema, unit_converter: {TestUnitConverter, :error})

    assert {:error, %Error{code: :invalid_unit_converter_return}} =
             Encoder.encode([row], schema, unit_converter: {TestUnitConverter, :invalid})

    assert {:error, %Error{code: :invalid_unit_converter}} =
             Encoder.encode([row], schema, unit_converter: {String, :valid})
  end

  test "normalization is explicit for scalars and nested arrays" do
    scalar = TestFactory.feature(normalization: {:z_score, 10, 2})
    scalar_row = TestFactory.row(1, %{"temperature" => TestFactory.observation(value: 14)})
    assert {:ok, scalar_encoded} = Encoder.encode([scalar_row], TestFactory.schema([scalar]))
    {{scalar_value}, _, _} = Nx.Defn.jit_apply(&Function.identity/1, [scalar_encoded.batch])
    assert Nx.to_flat_list(scalar_value) == [2.0]

    vector =
      TestFactory.feature(
        name: "vector",
        affordance_name: "vector",
        data_schema:
          TestFactory.data_schema(%{
            "type" => "array",
            "minItems" => 2,
            "maxItems" => 2,
            "items" => %{"type" => "number"}
          }),
        normalization: {:min_max, 0, 10},
        unit: nil
      )

    vector_observation =
      TestFactory.observation(affordance_name: "vector", value: [0, 10], unit: nil)

    vector_row = TestFactory.row(1, %{"vector" => vector_observation})
    assert {:ok, vector_encoded} = Encoder.encode([vector_row], TestFactory.schema([vector]))
    {{vector_value}, _, _} = Nx.Defn.jit_apply(&Function.identity/1, [vector_encoded.batch])
    assert Nx.to_flat_list(vector_value) == [0.0, 1.0]
  end

  test "encoder enforces row and aggregate contracts" do
    schema = TestFactory.schema()
    row = TestFactory.row(100, %{"temperature" => TestFactory.observation()})

    assert {:error, %Error{code: :empty_rows}} = Encoder.encode([], schema)
    assert {:error, %Error{code: :invalid_rows}} = Encoder.encode([:invalid], schema)
    assert {:error, %Error{code: :invalid_encoder_input}} = Encoder.encode([row], :invalid)

    one_row_schema = TestFactory.schema([TestFactory.feature()], max_rows: 1)

    assert {:error, %Error{code: :row_limit_exceeded}} =
             Encoder.encode([row, row], one_row_schema)
  end

  test "encoder rejects feature mismatch and DataSchema violations before allocation" do
    feature = TestFactory.feature()
    schema = TestFactory.schema([feature])

    mismatched = TestFactory.observation(affordance_name: "humidity")
    assert_error(:observation_feature_mismatch, mismatched, schema)

    assert_error(:data_schema_type_mismatch, TestFactory.observation(value: "hot"), schema)

    bounded =
      TestFactory.feature(
        data_schema:
          TestFactory.data_schema(%{
            "type" => "number",
            "minimum" => 0,
            "maximum" => 10,
            "exclusiveMinimum" => -1,
            "exclusiveMaximum" => 11,
            "enum" => [1, 2]
          })
      )

    assert_error(
      :data_schema_enum_mismatch,
      TestFactory.observation(value: 3, unit: nil),
      TestFactory.schema([bounded])
    )

    constant =
      TestFactory.feature(
        data_schema: TestFactory.data_schema(%{"type" => "integer", "const" => 2}),
        unit: nil
      )

    assert_error(
      :data_schema_const_mismatch,
      TestFactory.observation(value: 1, unit: nil),
      TestFactory.schema([constant])
    )

    minimum =
      TestFactory.feature(
        data_schema: TestFactory.data_schema(%{"type" => "number", "minimum" => 0}),
        unit: nil
      )

    assert_error(
      :data_schema_bound_mismatch,
      TestFactory.observation(value: -1, unit: nil),
      TestFactory.schema([minimum])
    )
  end

  test "encoder rejects variable shape, nested item violations, and non-finite values" do
    vector =
      TestFactory.feature(
        data_schema:
          TestFactory.data_schema(%{
            "type" => "array",
            "minItems" => 2,
            "maxItems" => 2,
            "items" => %{"type" => "number", "minimum" => 0}
          }),
        unit: nil
      )

    vector_schema = TestFactory.schema([vector])

    assert_error(
      :data_schema_shape_mismatch,
      TestFactory.observation(value: [1], unit: nil),
      vector_schema
    )

    assert_error(
      :data_schema_bound_mismatch,
      TestFactory.observation(value: [1, -1], unit: nil),
      vector_schema
    )

    assert_error(
      :non_finite_value,
      TestFactory.observation(value: :nan),
      TestFactory.schema()
    )

    finite_optional = TestFactory.feature(allow_non_finite?: true)

    finite_row =
      TestFactory.row(100, %{"temperature" => TestFactory.observation(value: :nan)})

    assert {:ok, _encoded} = Encoder.encode([finite_row], TestFactory.schema([finite_optional]))
  end

  defp assert_error(code, observation, schema) do
    row = TestFactory.row(100, %{"temperature" => observation})
    assert {:error, %Error{code: ^code}} = Encoder.encode([row], schema)
  end
end
