defmodule Wotex.Lab.RoomModelTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias Wotex.Lab.Experiments.RoomModel
  alias Wotex.Nx.Prediction

  test "Axon training is reproducible, split before windows, and scored against persistence" do
    assert {:ok, first} = RoomModel.run(epochs: 8)
    assert {:ok, second} = RoomModel.run(epochs: 8)

    assert first.manifest["source_mode"] == "synthetic"
    assert first.manifest["window"] == %{"width" => 3, "built_after_split" => true}
    assert first.manifest["normalization"]["from"] == "train"

    assert first.manifest["input_layout"] == [
             "value[0]",
             "value[1]",
             "mask[0]",
             "mask[1]",
             "quality[0]",
             "quality[1]"
           ]

    assert first.split.boundary == 48_000
    assert first.split.train_windows == 46
    assert first.split.test_windows == 14
    assert is_float(first.metrics.model_mae)
    assert is_float(first.metrics.persistence_mae)
    assert first.manifest["parameters_digest"] == second.manifest["parameters_digest"]
    assert first.metrics == second.metrics

    assert %Prediction{thing_id: "urn:wotex:lab:room:simulated", target_at: 64_000} =
             first.prediction

    for key <- ["dataset_digest", "schema_digest", "model_digest", "parameters_digest"] do
      assert String.starts_with?(first.manifest[key], "sha256:")
    end
  end

  test "configuration and work ceilings fail before training" do
    for opts <- [
          [count: 11],
          [count: 513],
          [epochs: 0],
          [epochs: 201],
          [timeout_ms: 0],
          [split_at: 63],
          [seed: -1]
        ] do
      assert {:error, %Error{code: :invalid_experiment}} = RoomModel.run(opts)
    end

    assert {:error, %Error{code: :invalid_options}} = RoomModel.run(seed: 1, seed: 2)
    assert {:error, %Error{code: :invalid_options}} = RoomModel.run(secret: "not-admitted")
  end

  test "the wall deadline cancels training without producing a prediction" do
    assert {:error, %Error{code: :experiment_timeout, details: %{timeout_ms: 1}}} =
             RoomModel.run(count: 512, split_at: 400, epochs: 200, timeout_ms: 1)
  end
end
