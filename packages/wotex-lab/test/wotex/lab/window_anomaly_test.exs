defmodule Wotex.Lab.WindowAnomalyTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.DataSchema
  alias Wotex.Lab.Examples.WindowAnomaly
  alias Wotex.Lab.Simulators.Thermal

  alias Wotex.Nx.{
    Anomaly,
    Decoder,
    Encoder,
    Error,
    Feature,
    Observation,
    OutputSchema,
    Prediction,
    Row,
    Schema,
    Window
  }

  test "the simulator is versioned, deterministic and records its inputs" do
    first = Thermal.generate(seed: 11, count: 16, heater: %{4 => 2.0}, glitches: [9])
    second = Thermal.generate(seed: 11, count: 16, heater: %{4 => 2.0}, glitches: [9])
    other = Thermal.generate(seed: 12, count: 16, heater: %{4 => 2.0}, glitches: [9])

    assert first == second
    refute Enum.map(first.samples, & &1.value) == Enum.map(other.samples, & &1.value)
    assert first.manifest["version"] == Thermal.version()
    assert first.manifest["source_mode"] == "synthetic"
    assert first.manifest["equation"] =~ "T[n+1]"
    assert Enum.at(first.samples, 9).quality == :bad
    assert Enum.at(first.samples, 5).value > Enum.at(first.samples, 4).value
    assert Enum.map(first.samples, & &1.observed_at) == Enum.map(0..15, &(&1 * 1_000))
  end

  test "simulator and window work are admitted by fixed ceilings" do
    for opts <- [
          [count: 1],
          [count: 4_097],
          [step: 0],
          [heater: %{32 => 1.0}],
          [glitches: [1, 1]],
          [seed: -1],
          [unknown: true]
        ] do
      assert {:error, %Wotex.Lab.Error{}} = Thermal.generate(opts)
    end

    for opts <- [
          [window_count: 1],
          [window_count: 65],
          [strategy: :guess],
          [max_age: -1],
          [threshold: -1],
          [backend: :missing_backend]
        ] do
      assert {:error, %Wotex.Lab.Error{code: :invalid_experiment}} =
               WindowAnomaly.run(opts)
    end

    assert {:error, %Wotex.Lab.Error{code: :invalid_options}} =
             WindowAnomaly.run(window_count: 8, window_count: 9)
  end

  test "a heater step is scored anomalous while a quiet room is not, deterministically" do
    assert {:ok, heated} = WindowAnomaly.run(seed: 7, heater: %{28 => 4.0}, glitches: [30])
    assert {:ok, repeated} = WindowAnomaly.run(seed: 7, heater: %{28 => 4.0}, glitches: [30])
    assert {:ok, quiet} = WindowAnomaly.run(seed: 7)

    assert %Anomaly{anomalous?: true, threshold: 1.5, rule: :at_or_above} = heated.anomaly
    assert Nx.to_number(heated.score) == Nx.to_number(repeated.score)
    assert heated.anomaly == repeated.anomaly
    assert %Anomaly{anomalous?: false} = quiet.anomaly
    assert Nx.to_number(quiet.score) < 0.5

    assert %Prediction{value: value, target_at: 32_000, produced_at: 31_000} = heated.prediction
    assert heated.prediction.metadata == %{"baseline" => "persistence"}
    assert %Observation{value: ^value, observed_at: 31_000} = heated.observation
    assert heated.manifest["window"] == %{"start" => 24_000, "step" => 1_000, "count" => 8}
    assert heated.manifest["feature_order"] == ["temperature"]
  end

  test "rejected quality rows are filled with mask zero and their quality code" do
    attach_from_caller([
      [:wotex, :lab, :nx, :encode, :measurement],
      [:wotex, :lab, :nx, :inference, :measurement]
    ])

    assert {:ok, result} = WindowAnomaly.run(seed: 7, glitches: [30])

    {{_}, {masks}, quality} =
      Nx.Defn.jit_apply(&Function.identity/1, [result.encoded], compiler: Nx.Defn.Evaluator)

    assert Nx.to_flat_list(masks) == [1, 1, 1, 1, 1, 1, 0, 1]
    assert Nx.to_flat_list(quality) == [0, 0, 0, 0, 0, 0, 2, 0]
    assert Enum.at(result.rows, 6).provenance["temperature"] == "sim-30"
    assert Enum.at(result.rows, 6).observations["temperature"].quality == :bad

    assert_receive {:lab_event, [:wotex, :lab, :nx, :encode, :measurement],
                    %{
                      fill: 0.125,
                      mask_observed: 0.875,
                      quality: 0.875,
                      rows: 8,
                      width: 1
                    }, %{profile: :window_anomaly}}

    assert_receive {:lab_event, [:wotex, :lab, :nx, :inference, :measurement], %{queue_depth: 0},
                    %{profile: :window_anomaly}}
  end

  test "permuted input, exact and nearest strategies agree on aligned samples" do
    assert {:ok, latest} = WindowAnomaly.run(seed: 3, strategy: :latest)
    assert {:ok, exact} = WindowAnomaly.run(seed: 3, strategy: :exact)
    assert {:ok, nearest} = WindowAnomaly.run(seed: 3, strategy: :nearest)
    assert latest.rows == exact.rows and exact.rows == nearest.rows

    %{samples: samples} = Thermal.generate(seed: 3)
    {:ok, ordered} = WindowAnomaly.observations(samples)
    {:ok, shuffled} = WindowAnomaly.observations(Enum.reverse(samples))
    {:ok, schema} = schema(missing: {:fill, 18.0})
    {:ok, window} = Window.new(start: 24_000, step: 1_000, count: 8)
    assert Window.resample(ordered, schema, window) == Window.resample(shuffled, schema, window)
  end

  test "stale windows, wrong Things and unit mismatches never become values" do
    assert {:error, :no_observed_row} =
             WindowAnomaly.run(seed: 3, window_start: 1_000_000, max_age: 0)

    {:ok, schema} = schema(missing: {:fill, 18.0})
    {:ok, window} = Window.new(start: 0, step: 1_000, count: 2)

    {:ok, stranger} =
      Observation.new(
        id: "stranger",
        thing_id: "urn:wotex:lab:room:other",
        affordance_type: :property,
        affordance_name: "temperature",
        observed_at: 0,
        value: 20.0,
        unit: "Cel"
      )

    assert {:ok, [row, _]} = Window.resample([stranger], schema, window)
    assert row.observations["temperature"] == nil

    {:ok, kelvin} =
      Observation.new(
        id: "kelvin",
        thing_id: "urn:wotex:lab:room:simulated",
        affordance_type: :property,
        affordance_name: "temperature",
        observed_at: 0,
        value: 293.15,
        unit: "K"
      )

    {:ok, kelvin_row} = Row.new(0, %{"temperature" => kelvin})
    assert {:error, %Error{code: :unit_conversion_required}} = Encoder.encode([kelvin_row], schema)

    wrong_row = %{
      kelvin_row
      | observations: %{"temperature" => %{kelvin | unit: "Cel", thing_id: "urn:other"}}
    }

    assert {:error, %Error{code: :observation_feature_mismatch}} =
             Encoder.encode([wrong_row], schema)
  end

  test "integer limits and dtype-rounded thresholds are explicit" do
    {:ok, integer_schema} = DataSchema.new(%{"type" => "integer"})

    {:ok, feature} =
      Feature.new(
        name: "count",
        thing_id: "urn:wotex:lab:room:simulated",
        affordance_type: :property,
        affordance_name: "count",
        data_schema: integer_schema,
        dtype: :s8
      )

    {:ok, schema} = Schema.new(features: [feature])

    {:ok, big} =
      Observation.new(
        id: "big",
        thing_id: "urn:wotex:lab:room:simulated",
        affordance_type: :property,
        affordance_name: "count",
        observed_at: 0,
        value: 200
      )

    {:ok, row} = Row.new(0, %{"count" => big})
    assert {:error, %Error{code: :dtype_value_out_of_range}} = Encoder.encode([row], schema)

    assert {:ok, rounded} = WindowAnomaly.run(seed: 3, threshold: 0.1)
    assert rounded.anomaly.threshold == 0.10000000149011612

    {:ok, score_schema} = DataSchema.new(%{"type" => "number", "minimum" => 0})

    {:ok, output} =
      OutputSchema.new(
        kind: :anomaly,
        thing_id: "urn:wotex:lab:room:simulated",
        affordance_type: :property,
        affordance_name: "temperature",
        data_schema: score_schema,
        dtype: :f32,
        threshold: 1.0
      )

    assert {:error, %Error{code: :output_shape_mismatch}} =
             Decoder.decode(Nx.tensor([1.0, 2.0], type: :f32), output, id: "bad", produced_at: 0)

    assert {:error, %Error{code: :output_dtype_mismatch}} =
             Decoder.decode(Nx.tensor(1.0, type: :f64), output, id: "bad", produced_at: 0)
  end

  defp schema(feature_opts) do
    {:ok, data_schema} = DataSchema.new(%{"type" => "number", "unit" => "Cel"})

    {:ok, feature} =
      Feature.new(
        Keyword.merge(
          [
            name: "temperature",
            thing_id: "urn:wotex:lab:room:simulated",
            affordance_type: :property,
            affordance_name: "temperature",
            data_schema: data_schema,
            accepted_quality: [:good, :uncertain]
          ],
          feature_opts
        )
      )

    Schema.new(features: [feature], max_rows: 64)
  end

  @doc false
  @spec forward_from_caller(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          {pid(), pid()}
        ) :: :ok
  def forward_from_caller(event, measurements, metadata, {receiver, emitter}) do
    if self() == emitter, do: send(receiver, {:lab_event, event, measurements, metadata})
    :ok
  end

  defp attach_from_caller(events) do
    handler = {__MODULE__, make_ref()}
    caller = self()

    :ok =
      :telemetry.attach_many(
        handler,
        events,
        &__MODULE__.forward_from_caller/4,
        {caller, caller}
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end
end
