defmodule Wotex.Nx.ContractMatrixTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Nx.{Decoder, Encoder, Error, Feature, Observation, OutputSchema, Row, Schema}
  alias Wotex.Nx.{TestFactory, Window}

  test "every keyword-list admission boundary rejects duplicate and unknown options" do
    feature_options = feature_options()
    schema = TestFactory.schema()
    observation = TestFactory.observation()
    row = TestFactory.row(100, %{"temperature" => observation})
    {:ok, window} = Window.new(start: 100, step: 1, count: 1)
    output_options = output_options()
    {:ok, output_schema} = OutputSchema.new(output_options)

    cases = [
      {:observation, fn -> Observation.new([id: "duplicate"] ++ observation_options()) end,
       fn -> Observation.new([{:unknown, true} | observation_options()]) end,
       :invalid_observation_options, :construction},
      {:feature, fn -> Feature.new([name: "duplicate"] ++ feature_options) end,
       fn -> Feature.new([{:unknown, true} | feature_options]) end, :invalid_feature_options,
       :construction},
      {:schema, fn -> Schema.new(features: [TestFactory.feature()], features: []) end,
       fn -> Schema.new(features: [TestFactory.feature()], unknown: true) end,
       :invalid_schema_options, :construction},
      {:window, fn -> Window.new(start: 0, start: 1, step: 1, count: 1) end,
       fn -> Window.new(start: 0, step: 1, count: 1, unknown: true) end, :invalid_window_options,
       :construction},
      {:resample,
       fn -> Window.resample([observation], schema, window, max_work: 100, max_work: 100) end,
       fn -> Window.resample([observation], schema, window, unknown: true) end,
       :invalid_window_input, :window},
      {:encode, fn -> Encoder.encode([row], schema, unit_converter: nil, unit_converter: nil) end,
       fn -> Encoder.encode([row], schema, unknown: true) end, :invalid_encoder_input, :encoding},
      {:output_schema, fn -> OutputSchema.new([kind: :prediction] ++ output_options) end,
       fn -> OutputSchema.new([{:unknown, true} | output_options]) end,
       :invalid_output_schema_options, :construction},
      {:decode,
       fn ->
         Decoder.decode(Nx.tensor(1.0), output_schema,
           id: "first",
           id: "second",
           produced_at: 1,
           target_at: 2
         )
       end,
       fn ->
         Decoder.decode(Nx.tensor(1.0), output_schema,
           id: "prediction",
           produced_at: 1,
           target_at: 2,
           unknown: true
         )
       end, :invalid_output_options, :output}
    ]

    for {operation, duplicate, unknown, code, phase} <- cases do
      assert_error(duplicate.(), code, phase, operation)
      assert_error(unknown.(), code, phase, operation)
    end
  end

  test "every opaque input is reconstructed before an operation admits it" do
    forged_data_schema = %{
      TestFactory.data_schema()
      | value: %{"type" => "number", "invalidExtension" => self()}
    }

    assert_error(
      Feature.new(Keyword.put(feature_options(), :data_schema, forged_data_schema)),
      :data_schema_required,
      :construction,
      :feature
    )

    assert_error(
      OutputSchema.new(Keyword.put(output_options(), :data_schema, forged_data_schema)),
      :data_schema_required,
      :construction,
      :output_schema
    )

    observation = TestFactory.observation()
    forged_observation = %{observation | metadata: []}

    assert_error(
      Row.new(100, %{"temperature" => forged_observation}),
      :invalid_row_observations,
      :construction,
      :row
    )

    feature = TestFactory.feature()
    forged_feature = %{feature | thing_id: ""}
    assert_error(Schema.new(features: [forged_feature]), :invalid_features, :construction, :schema)

    schema = TestFactory.schema()
    row = TestFactory.row(100, %{"temperature" => observation})
    {:ok, window} = Window.new(start: 100, step: 1, count: 1)

    assert_error(
      Window.resample([forged_observation], schema, window),
      :invalid_observations,
      :window,
      :resample_observation
    )

    assert_error(
      Window.resample([observation], %{schema | max_rows: 0}, window),
      :invalid_window_input,
      :window,
      :resample_schema
    )

    assert_error(
      Window.resample([observation], schema, %{window | step: 0}),
      :invalid_window_input,
      :window,
      :resample_window
    )

    assert_error(
      Encoder.encode([row], %{schema | max_rows: 0}),
      :invalid_encoder_input,
      :encoding,
      :encode_schema
    )

    assert_error(
      Encoder.encode([%{row | provenance: %{}}], schema),
      :invalid_rows,
      :encoding,
      :encode_row
    )

    {:ok, output_schema} = OutputSchema.new(output_options())

    assert_error(
      Decoder.decode(Nx.tensor(1.0), %{output_schema | shape: {1}},
        id: "prediction",
        produced_at: 1,
        target_at: 2
      ),
      :invalid_decoder_input,
      :output,
      :decode_schema
    )
  end

  test "Thing identity and affordance category are exact at selection and encoding" do
    schema = TestFactory.schema()
    {:ok, window} = Window.new(start: 100, step: 1, count: 1, strategy: :exact)

    for overrides <- [
          [thing_id: "urn:example:thing:other"],
          [affordance_type: :event],
          [affordance_name: "humidity"]
        ] do
      observation = TestFactory.observation(overrides)
      assert {:ok, [selected]} = Window.resample([observation], schema, window)
      assert selected.observations["temperature"] == nil

      row = TestFactory.row(100, %{"temperature" => observation})

      assert_error(
        Encoder.encode([row], schema),
        :observation_feature_mismatch,
        :encoding,
        overrides
      )
    end
  end

  test "all public error phases have executable boundary examples" do
    observation = TestFactory.observation(unit: "degF")
    schema = TestFactory.schema()
    row = TestFactory.row(100, %{"temperature" => observation})
    second = TestFactory.feature(name: "humidity", affordance_name: "humidity")

    cases = [
      {:construction, Observation.new([]), :invalid_observation_field},
      {:window, Window.resample([], schema, :invalid), :invalid_window_input},
      {:encoding, Encoder.encode([], schema), :empty_rows},
      {:unit, Encoder.encode([row], schema), :unit_conversion_required},
      {:output, Decoder.decode(:invalid, :invalid), :invalid_decoder_input},
      {:limit, Schema.new(features: [TestFactory.feature(), second], max_features: 1),
       :feature_limit_exceeded}
    ]

    for {phase, result, code} <- cases do
      assert {:error, %Error{phase: ^phase, code: ^code}} = result
    end
  end

  defp observation_options do
    [
      id: "observation",
      thing_id: "urn:example:thing:1",
      affordance_type: :property,
      affordance_name: "temperature",
      observed_at: 100,
      value: 21.5,
      unit: "Cel"
    ]
  end

  defp feature_options do
    [
      name: "temperature",
      thing_id: "urn:example:thing:1",
      affordance_type: :property,
      affordance_name: "temperature",
      data_schema: TestFactory.data_schema()
    ]
  end

  defp output_options do
    [
      kind: :prediction,
      thing_id: "urn:example:thing:1",
      affordance_type: :property,
      affordance_name: "temperature",
      data_schema: TestFactory.data_schema()
    ]
  end

  defp assert_error(result, code, phase, operation) do
    assert {:error, %Error{code: ^code, phase: ^phase}} = result,
           "#{inspect(operation)} unexpectedly admitted input: #{inspect(result)}"
  end
end
