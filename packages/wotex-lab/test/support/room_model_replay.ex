defmodule Wotex.Lab.Test.RoomModelReplay do
  @moduledoc false

  # Restore only artifacts produced by these tests, never caller-supplied bytes.
  # Rebuild the declared six-column input via public Nx/Axon APIs, independently
  # of RoomModel's private training and prediction helpers.
  def predict(result, [first, second]) do
    Nx.with_default_backend(Nx.BinaryBackend, fn ->
      %Axon.ModelState{} = state = Nx.deserialize(result.parameters, [:safe])
      %{"mean" => mean, "std" => deviation} = result.manifest["normalization"]

      inputs =
        Nx.tensor(
          [[(first.value - mean) / deviation, (second.value - mean) / deviation, 1, 1, 0, 0]],
          type: :f32
        )

      result.model
      |> Axon.predict(state, inputs, compiler: Nx.Defn.Evaluator)
      |> Nx.multiply(deviation)
      |> Nx.add(mean)
      |> Nx.to_flat_list()
      |> hd()
    end)
  end
end
