defmodule Wotex.Lab.ThermalTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.DataSchema
  alias Wotex.Lab.Adapters.Nx.UnitConverter
  alias Wotex.Lab.Examples.Thermal
  alias Wotex.Lab.Test.CallerBackend

  alias Wotex.Nx.{
    ActionProposal,
    Decoder,
    Encoded,
    Encoder,
    Feature,
    Observation,
    OutputSchema,
    Row,
    Schema
  }

  test "public APIs produce an inspectable batch and inert proposal with provenance" do
    backend = Nx.default_backend()
    assert {:ok, result} = Thermal.run()
    assert Nx.default_backend() == backend
    assert Encoded.feature_order(result.encoded) == ["temperature"]
    assert Encoded.timestamps(result.encoded) == [0, 1_000]
    assert Encoded.row_count(result.encoded) == 2

    assert [%{"temperature" => "thermal-1"}, %{"temperature" => "thermal-2"}] =
             Encoded.provenance(result.encoded)

    assert Encoded.layout(result.encoded) == :feature_tuple_values_masks_quality_vector

    {{values}, {masks}, quality} =
      Nx.Defn.jit_apply(&Function.identity/1, [Encoded.batch(result.encoded)],
        compiler: Nx.Defn.Evaluator
      )

    assert Nx.to_flat_list(values) == [20.0, 22.0]
    assert Nx.to_flat_list(masks) == [1, 1]
    assert Nx.to_flat_list(quality) == [0, 0]

    assert %ActionProposal{
             thing_id: "urn:wotex:lab:thermostat:1",
             action_name: "setTarget",
             proposed_at: 2_000,
             input: input
           } = result.proposal

    assert_in_delta input, 22.0, 0.00001
    assert {:ok, repeated} = Thermal.run()
    assert repeated.proposal == result.proposal

    assert {:ok, explicit} = Thermal.run(backend: Nx.BinaryBackend)
    assert explicit.proposal == result.proposal
    refute_received _unexpected
  end

  test "the target function weights rows by the observed mask" do
    values = Nx.tensor([20.0, 40.0], type: :f32)
    observed = Nx.tensor([1, 0], type: :u8)
    quality = Nx.tensor([[0], [3]], type: :u8)

    target =
      Nx.Defn.jit_apply(&Thermal.target/1, [{{values}, {observed}, quality}],
        compiler: Nx.Defn.Evaluator
      )

    assert_in_delta Nx.to_number(target), 21.0, 0.00001
  end

  test "the fixture manifest is executable and caller backend selection is restored" do
    path = Application.app_dir(:wotex_lab, "priv/fixtures/thermal/manifest.json")
    manifest = :json.decode(File.read!(path))
    expected = manifest["expected_proposal"]

    Nx.with_default_backend(CallerBackend, fn ->
      assert {:ok, %{proposal: proposal}} = Thermal.run()
      assert Nx.default_backend() == {CallerBackend, []}
      assert proposal.thing_id == expected["thing_id"]
      assert proposal.action_name == expected["action_name"]
      assert proposal.proposed_at == expected["proposed_at"]
      assert_in_delta proposal.input, expected["input"], manifest["absolute_tolerance"]
    end)
  end

  test "the converter has a closed policy and never guesses unknown units" do
    assert {:ok, schema} = DataSchema.new(%{"type" => "number", "unit" => "Cel"})
    assert {:ok, celsius} = UnitConverter.convert(293.15, "K", "Cel", schema, [])
    assert_in_delta celsius, 20.0, 0.00001
    assert {:ok, kelvin} = UnitConverter.convert(20, "Cel", "K", schema, [])
    assert_in_delta kelvin, 293.15, 0.00001

    for {value, source, target, config} <- [
          {20, "F", "Cel", []},
          {"20", "K", "Cel", []},
          {20, "K", "Cel", [implicit: true]}
        ] do
      assert {:error, :unsupported_conversion} =
               UnitConverter.convert(value, source, target, schema, config)
    end
  end

  test "unit refusal, wrong identity and invalid model output do not become proposals" do
    assert {:ok, data_schema} = DataSchema.new(%{"type" => "number", "unit" => "Cel"})

    assert {:ok, feature} =
             Feature.new(
               name: "temperature",
               thing_id: "urn:test:1",
               affordance_type: :property,
               affordance_name: "temperature",
               data_schema: data_schema
             )

    assert {:ok, schema} = Schema.new(features: [feature])

    assert {:ok, sample} =
             Observation.new(
               id: "sample",
               thing_id: "urn:test:1",
               affordance_type: :property,
               affordance_name: "temperature",
               observed_at: 0,
               value: 68,
               unit: "F"
             )

    assert {:ok, row} = Row.new(0, %{"temperature" => sample})

    assert {:error, %Wotex.Nx.Error{phase: :unit}} =
             Encoder.encode([row], schema, unit_converter: {UnitConverter, []})

    wrong = %{sample | thing_id: "urn:test:2", unit: "Cel"}
    assert {:ok, wrong_row} = Row.new(0, %{"temperature" => wrong})
    assert {:error, %Wotex.Nx.Error{}} = Encoder.encode([wrong_row], schema)

    assert {:ok, output_schema} = DataSchema.new(%{"type" => "number", "maximum" => 35})

    assert {:ok, output} =
             OutputSchema.new(
               kind: :action_proposal,
               thing_id: "urn:test:1",
               affordance_type: :action,
               affordance_name: "setTarget",
               data_schema: output_schema
             )

    assert {:error, %Wotex.Nx.Error{}} =
             Decoder.decode(Nx.tensor(40.0), output, id: "invalid", proposed_at: 0)

    refute_received _unexpected
  end
end
