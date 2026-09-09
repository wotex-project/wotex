defmodule Wotex.Lab.BackendCohortTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Examples.Thermal
  alias Wotex.Lab.Experiments.RoomModel
  alias Wotex.Lab.Simulators.Thermal, as: Simulator
  alias Wotex.Lab.Test.RoomModelReplay
  alias Wotex.Nx.{Encoded, Prediction}

  @moduletag timeout: 60_000

  test "Binary/Evaluator and EXLA CPU preserve the declared numerical contract" do
    assert {:ok, _} = Application.ensure_all_started(:exla)
    caller_backend = Nx.default_backend()

    assert {:ok, binary} =
             Thermal.run(backend: Nx.BinaryBackend, compiler: Nx.Defn.Evaluator)

    assert {:ok, exla} = Thermal.run(backend: EXLA.Backend, compiler: EXLA)
    assert Nx.default_backend() == caller_backend
    assert Encoded.feature_order(binary.encoded) == Encoded.feature_order(exla.encoded)
    assert Encoded.timestamps(binary.encoded) == Encoded.timestamps(exla.encoded)
    assert Encoded.provenance(binary.encoded) == Encoded.provenance(exla.encoded)
    assert_in_delta binary.proposal.input, exla.proposal.input, 1.0e-5

    assert {:ok, compiled_model} =
             RoomModel.run(
               backend: EXLA.Backend,
               compiler: EXLA,
               count: 32,
               split_at: 24,
               epochs: 2,
               timeout_ms: 30_000
             )

    assert compiled_model.manifest["backend"] == "EXLA.Backend"
    assert compiled_model.manifest["compiler"] == "EXLA"
    prediction = Prediction.to_map(compiled_model.prediction)
    assert is_float(prediction.value)
    assert byte_size(compiled_model.parameters) > 0

    simulation = Simulator.generate(seed: 11, count: 32, heater: %{20 => 3.0})
    replayed = RoomModelReplay.predict(compiled_model, Enum.take(simulation.samples, -2))
    assert_in_delta prediction.value, replayed, 1.0e-4
    assert Nx.default_backend() == caller_backend

    device = Nx.backend_transfer(Nx.tensor([1.0, 2.0]), EXLA.Backend)
    host = Nx.backend_transfer(device, Nx.BinaryBackend)
    assert Nx.to_flat_list(host) == [1.0, 2.0]
    assert Nx.backend_deallocate(device) == :already_deallocated
  end

  test "invalid or unavailable profiles return inert errors" do
    assert {:error, %Wotex.Lab.Error{code: :invalid_options}} =
             Thermal.run(backend: Nx.BinaryBackend, backend: EXLA.Backend)

    assert {:error, %Wotex.Lab.Error{code: :invalid_nx_profile}} =
             Thermal.run(backend: :not_a_backend)
  end
end
