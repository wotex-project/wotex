defmodule Wotex.Nx.DecoderTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Nx.{
    ActionProposal,
    Anomaly,
    Decoder,
    Error,
    Observation,
    OutputSchema,
    Prediction
  }

  alias Wotex.Nx.TestFactory

  test "output schema binds exact Thing affordance, DataSchema, shape, dtype, and metadata" do
    assert {:ok, schema} =
             OutputSchema.new(
               kind: :prediction,
               thing_id: "urn:thing:1",
               affordance_type: :property,
               affordance_name: "temperature",
               data_schema: TestFactory.data_schema(),
               dtype: :f64,
               metadata: %{"model" => "v1"}
             )

    assert schema.kind == :prediction
    assert schema.shape == {}
    assert schema.dtype == {:f, 64}
    assert schema.unit == "Cel"
    assert schema.metadata == %{"model" => "v1"}
    assert OutputSchema.kinds() == [:observation, :prediction, :anomaly, :action_proposal]
  end

  test "output schema validates identities and kind-specific contracts" do
    base = [
      kind: :prediction,
      thing_id: "urn:thing:1",
      affordance_type: :property,
      affordance_name: "temperature",
      data_schema: TestFactory.data_schema()
    ]

    for {changes, code} <- [
          {[kind: :unknown], :invalid_output_identity},
          {[thing_id: ""], :invalid_output_identity},
          {[affordance_type: :action], :invalid_output_identity},
          {[affordance_name: nil], :invalid_output_identity},
          {[shape: {1}], :shape_schema_mismatch},
          {[max_width: 0], :invalid_limit},
          {[dtype: :invalid], :invalid_dtype},
          {[dtype: :s64], :dtype_schema_mismatch},
          {[unit: ""], :invalid_unit},
          {[metadata: []], :invalid_metadata},
          {[allow_non_finite?: :yes], :invalid_finite_policy},
          {[threshold: 1], :unexpected_threshold},
          {[anomaly_rule: :above], :unexpected_anomaly_rule}
        ] do
      assert {:error, %Error{code: ^code}} = OutputSchema.new(Keyword.merge(base, changes))
    end

    assert {:error, %Error{code: :data_schema_required}} =
             OutputSchema.new(Keyword.put(base, :data_schema, nil))

    assert {:error, %Error{code: :data_schema_required}} =
             OutputSchema.new(Keyword.put(base, :data_schema, %{}))

    assert {:error, %Error{code: :unsupported_data_schema}} =
             OutputSchema.new(
               Keyword.put(base, :data_schema, TestFactory.data_schema(%{"type" => "string"}))
             )

    wide =
      TestFactory.data_schema(%{
        "type" => "array",
        "minItems" => 2,
        "maxItems" => 2,
        "items" => %{"type" => "number"}
      })

    assert {:error, %Error{code: :width_limit_exceeded}} =
             OutputSchema.new(
               base
               |> Keyword.put(:data_schema, wide)
               |> Keyword.put(:max_width, 1)
             )

    assert {:error, %Error{code: :invalid_output_schema_options}} = OutputSchema.new(%{})
  end

  test "anomaly schema requires a scalar score, threshold, and explicit comparison rule" do
    base = [
      kind: :anomaly,
      thing_id: "urn:thing:1",
      affordance_type: :event,
      affordance_name: "vibration",
      data_schema: TestFactory.data_schema(%{"type" => "number"}),
      threshold: 0.8
    ]

    assert {:ok, default} = OutputSchema.new(base)
    assert default.anomaly_rule == :at_or_above

    assert {:ok, below} = OutputSchema.new(Keyword.put(base, :anomaly_rule, :below))
    assert below.anomaly_rule == :below

    assert {:error, %Error{code: :threshold_required}} =
             OutputSchema.new(Keyword.delete(base, :threshold))

    assert {:error, %Error{code: :invalid_anomaly_rule}} =
             OutputSchema.new(Keyword.put(base, :anomaly_rule, :equal))

    assert {:error, %Error{code: :invalid_threshold}} =
             OutputSchema.new(Keyword.put(base, :threshold, 1.0e300))

    assert {:error, %Error{code: :non_finite_anomaly_unsupported}} =
             OutputSchema.new(Keyword.put(base, :allow_non_finite?, true))

    array =
      TestFactory.data_schema(%{
        "type" => "array",
        "minItems" => 1,
        "maxItems" => 1,
        "items" => %{"type" => "number"}
      })

    assert {:error, %Error{code: :invalid_anomaly_schema}} =
             OutputSchema.new(Keyword.put(base, :data_schema, array))
  end

  test "decoder produces an observation without asserting canonical state" do
    schema = output_schema(:observation)

    assert {:ok, %Observation{} = observation} =
             Decoder.decode(Nx.tensor(22.5), schema,
               id: "decoded-1",
               observed_at: 500,
               quality: :uncertain,
               source: "model-a",
               metadata: %{"trace" => "t-1"}
             )

    assert observation.thing_id == "urn:thing:1"
    assert observation.value == 22.5
    assert observation.observed_at == 500
    assert observation.unit == "Cel"
    assert observation.quality == :uncertain
    assert observation.metadata == %{"schema" => "v1", "trace" => "t-1"}
  end

  test "decoder produces a prediction with caller-supplied production and target times" do
    schema = output_schema(:prediction)

    assert {:ok, %Prediction{} = prediction} =
             Decoder.decode(Nx.tensor(23.0), schema,
               id: "prediction-1",
               produced_at: 500,
               target_at: 600
             )

    assert prediction.value == 23.0
    assert prediction.produced_at == 500
    assert prediction.target_at == 600
  end

  test "decoder produces anomaly decisions using all four explicit comparison rules" do
    for {rule, score, expected} <- [
          {:above, 0.8, false},
          {:at_or_above, 0.8, true},
          {:below, 0.7, true},
          {:at_or_below, 0.8, true}
        ] do
      schema = anomaly_schema(rule)

      assert {:ok, %Anomaly{} = anomaly} =
               Decoder.decode(Nx.tensor(score), schema,
                 id: "anomaly-#{rule}",
                 produced_at: 500
               )

      assert anomaly.anomalous? == expected
      assert anomaly.rule == rule
      assert_in_delta anomaly.threshold, 0.8, 0.000_001
    end
  end

  test "decoder produces an inert Action proposal and never dispatches it" do
    schema =
      output_schema(:action_proposal,
        affordance_type: :action,
        affordance_name: "setLevel",
        data_schema: TestFactory.data_schema(%{"type" => "integer"}),
        dtype: :s64,
        unit: nil
      )

    assert {:ok, %ActionProposal{} = proposal} =
             Decoder.decode(Nx.tensor(4, type: :s64), schema,
               id: "proposal-1",
               proposed_at: 500
             )

    assert proposal.action_name == "setLevel"
    assert proposal.input == 4
    assert proposal.proposed_at == 500
  end

  test "decoder restores fixed boolean arrays from exact zero and one encodings" do
    boolean_vector =
      TestFactory.data_schema(%{
        "type" => "array",
        "minItems" => 2,
        "maxItems" => 2,
        "items" => %{"type" => "boolean"}
      })

    schema =
      output_schema(:prediction,
        data_schema: boolean_vector,
        dtype: :u8,
        unit: nil
      )

    assert {:ok, %Prediction{value: [false, true]}} =
             Decoder.decode(Nx.tensor([0, 1], type: :u8), schema,
               id: "p-bool",
               produced_at: 1,
               target_at: 2
             )

    assert {:error, %Error{code: :invalid_boolean_encoding}} =
             Decoder.decode(Nx.tensor([0, 2], type: :u8), schema,
               id: "p-invalid",
               produced_at: 1,
               target_at: 2
             )
  end

  test "decoder refuses shape, dtype, DataSchema, and non-finite mismatches" do
    schema = output_schema(:prediction)

    assert {:error, %Error{code: :output_shape_mismatch}} =
             Decoder.decode(Nx.tensor([1.0]), schema,
               id: "p",
               produced_at: 1,
               target_at: 2
             )

    assert {:error, %Error{code: :output_dtype_mismatch}} =
             Decoder.decode(Nx.tensor(1, type: :s64), schema,
               id: "p",
               produced_at: 1,
               target_at: 2
             )

    vectorized = Nx.vectorize(Nx.tensor([1.0]), :sample)

    assert {:error, %Error{code: :vectorized_output_unsupported}} =
             Decoder.decode(vectorized, schema,
               id: "p",
               produced_at: 1,
               target_at: 2
             )

    bounded =
      output_schema(:prediction,
        data_schema: TestFactory.data_schema(%{"type" => "number", "maximum" => 1}),
        unit: nil
      )

    assert {:error, %Error{code: :data_schema_bound_mismatch, phase: :output}} =
             Decoder.decode(Nx.tensor(2.0), bounded,
               id: "p",
               produced_at: 1,
               target_at: 2
             )

    assert {:error, %Error{code: :non_finite_value, phase: :output}} =
             Decoder.decode(Nx.Constants.infinity(), schema,
               id: "p",
               produced_at: 1,
               target_at: 2
             )

    permissive = output_schema(:prediction, allow_non_finite?: true)

    assert {:ok, %Prediction{value: :infinity}} =
             Decoder.decode(Nx.Constants.infinity(), permissive,
               id: "p-infinity",
               produced_at: 1,
               target_at: 2
             )
  end

  test "decoder requires caller identity, metadata, and kind-specific timestamps" do
    tensor = Nx.tensor(1.0)

    assert {:error, %Error{code: :invalid_output_options}} =
             Decoder.decode(tensor, output_schema(:prediction), produced_at: 1, target_at: 2)

    assert {:error, %Error{code: :invalid_output_options}} =
             Decoder.decode(tensor, output_schema(:prediction),
               id: "p",
               metadata: [],
               produced_at: 1,
               target_at: 2
             )

    assert {:error, %Error{code: :invalid_prediction_time}} =
             Decoder.decode(tensor, output_schema(:prediction), id: "p", produced_at: 1)

    assert {:error, %Error{code: :invalid_anomaly_time}} =
             Decoder.decode(tensor, anomaly_schema(:above), id: "a")

    assert {:error, %Error{code: :invalid_action_proposal_time}} =
             Decoder.decode(
               tensor,
               output_schema(:action_proposal,
                 affordance_type: :action,
                 affordance_name: "setLevel"
               ),
               id: "action"
             )

    assert {:error, %Error{code: :invalid_observed_at, phase: :output}} =
             Decoder.decode(tensor, output_schema(:observation), id: "o")

    assert {:error, %Error{code: :invalid_decoder_input}} =
             Decoder.decode(1.0, output_schema(:prediction), [])
  end

  defp output_schema(kind, overrides \\ []) do
    defaults = [
      kind: kind,
      thing_id: "urn:thing:1",
      affordance_type: :property,
      affordance_name: "temperature",
      data_schema: TestFactory.data_schema(),
      metadata: %{"schema" => "v1"}
    ]

    {:ok, schema} = OutputSchema.new(Keyword.merge(defaults, overrides))
    schema
  end

  defp anomaly_schema(rule) do
    output_schema(:anomaly,
      data_schema: TestFactory.data_schema(%{"type" => "number"}),
      unit: nil,
      threshold: 0.8,
      anomaly_rule: rule
    )
  end
end
