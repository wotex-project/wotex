defmodule Wotex.Lab.Examples.Thermal do
  @moduledoc """
  A deterministic observation-to-proposal example using public WoTEx and Nx APIs.

  Two Kelvin observations become Celsius tensors. An explicit Nx function takes
  their mean and adds one degree, then the decoder returns an inert `setTarget`
  Action proposal. No Action is invoked, network contacted or model downloaded.
  The example uses process-local BinaryBackend selection and restores the caller.
  """

  import Nx.Defn

  alias Wotex.{DataSchema, ThingDescription}
  alias Wotex.Lab.Adapters.Nx.UnitConverter
  alias Wotex.Nx.{Decoder, Encoded, Encoder, Feature, Observation, OutputSchema, Row, Schema}

  @doc "Runs the checked-in thermal fixture and returns the TD, encoded batch and inert proposal."
  @spec run() :: {:ok, map()} | {:error, term()}
  def run do
    Nx.with_default_backend(Nx.BinaryBackend, &run_example/0)
  end

  @doc "Computes a scalar target from a single-feature values/masks/quality batch."
  @spec target({{Nx.Tensor.t()}, {Nx.Tensor.t()}, Nx.Tensor.t()}) :: Nx.Tensor.t()
  defn target({{temperatures}, {_masks}, _quality}) do
    Nx.mean(temperatures) + 1.0
  end

  defp run_example do
    path = Application.app_dir(:wotex_lab, "priv/fixtures/thermal/thing-description.json")

    with {:ok, json} <- File.read(path),
         {:ok, td} <- ThingDescription.parse(json),
         map <- ThingDescription.to_map(td),
         {:ok, input_schema} <-
           DataSchema.new(Map.take(map["properties"]["temperature"], ["type", "unit"])),
         {:ok, feature} <- feature(ThingDescription.id(td), input_schema),
         {:ok, schema} <- Schema.new(features: [feature], max_rows: 2),
         {:ok, rows} <- rows(ThingDescription.id(td)),
         {:ok, encoded} <- Encoder.encode(rows, schema, unit_converter: {UnitConverter, []}),
         tensor <-
           Nx.Defn.jit_apply(&target/1, [Encoded.batch(encoded)], compiler: Nx.Defn.Evaluator),
         {:ok, output_schema} <- DataSchema.new(map["actions"]["setTarget"]["input"]),
         {:ok, output} <- output(ThingDescription.id(td), output_schema),
         {:ok, proposal} <-
           Decoder.decode(tensor, output, id: "thermal-proposal-1", proposed_at: 2_000) do
      {:ok, %{thing_description: td, encoded: encoded, proposal: proposal}}
    end
  end

  defp feature(thing_id, schema) do
    Feature.new(
      name: "temperature",
      thing_id: thing_id,
      affordance_type: :property,
      affordance_name: "temperature",
      data_schema: schema,
      accepted_quality: [:good],
      missing: :error
    )
  end

  defp rows(thing_id) do
    observations = [{"thermal-1", 0, 293.15}, {"thermal-2", 1_000, 295.15}]

    Enum.reduce_while(observations, {:ok, []}, fn {id, time, value}, {:ok, rows} ->
      with {:ok, observation} <- observation(thing_id, id, time, value),
           {:ok, row} <- Row.new(time, %{"temperature" => observation}) do
        {:cont, {:ok, rows ++ [row]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp observation(thing_id, id, time, value) do
    Observation.new(
      id: id,
      thing_id: thing_id,
      affordance_type: :property,
      affordance_name: "temperature",
      observed_at: time,
      value: value,
      unit: "K",
      quality: :good
    )
  end

  defp output(thing_id, schema) do
    OutputSchema.new(
      kind: :action_proposal,
      thing_id: thing_id,
      affordance_type: :action,
      affordance_name: "setTarget",
      data_schema: schema,
      dtype: :f32
    )
  end
end
