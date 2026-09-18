defmodule Wotex.Lab.Examples.Thermal do
  @moduledoc """
  A deterministic observation-to-proposal example using public WoTEx and Nx APIs.

  Two Kelvin observations become Celsius tensors. An explicit Nx function takes
  their mask-weighted mean and adds one degree, then the decoder returns an
  inert `setTarget` Action proposal. No Action is invoked, network contacted or
  model downloaded.

  `run/0` selects `Nx.BinaryBackend` and `Nx.Defn.Evaluator` for the calling
  process only and restores the caller's default afterwards, so the example
  works without a native backend. `run/1` accepts explicit `:backend` and
  `:compiler` options for a profile the caller already started.
  """

  import Nx.Defn

  alias Wotex.{DataSchema, ThingDescription}
  alias Wotex.Lab.Adapters.Nx.UnitConverter
  alias Wotex.Lab.{Error, Options, Telemetry}
  alias Wotex.Nx.{Decoder, Encoded, Encoder, Feature, Observation, OutputSchema, Row, Schema}

  @max_rows 2

  @doc "Runs the checked-in thermal fixture and returns the TD, encoded batch and inert proposal."
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    with :ok <- Options.validate(opts, [:backend, :compiler]),
         {:ok, backend, compiler} <- profile(opts) do
      safe_run(backend, compiler)
    end
  end

  @doc """
  Computes a scalar target from a single-feature values/masks/quality batch.

  Only observed rows (mask `1`) contribute: the target is the mask-weighted
  mean plus one degree. Filled rows carry mask `0` and are excluded.
  """
  @spec target({{Nx.Tensor.t()}, {Nx.Tensor.t()}, Nx.Tensor.t()}) :: Nx.Tensor.t()
  defn target({{temperatures}, {masks}, _quality}) do
    weights = Nx.as_type(masks, Nx.type(temperatures))
    Nx.sum(temperatures * weights) / Nx.max(Nx.sum(weights), 1.0) + 1.0
  end

  defp profile(opts) do
    backend = Keyword.get(opts, :backend, Nx.BinaryBackend)
    compiler = Keyword.get(opts, :compiler, Nx.Defn.Evaluator)

    if valid_backend?(backend) and Code.ensure_loaded?(backend_module(backend)) and
         is_atom(compiler) and not is_nil(compiler) and Code.ensure_loaded?(compiler) do
      {:ok, backend, compiler}
    else
      {:error, Error.new(:invalid_nx_profile, :construction, "Nx profile is invalid")}
    end
  end

  defp valid_backend?(backend) when is_atom(backend), do: not is_nil(backend)
  defp valid_backend?({backend, opts}), do: is_atom(backend) and is_list(opts)
  defp valid_backend?(_), do: false

  defp backend_module({backend, _}), do: backend
  defp backend_module(backend), do: backend

  defp safe_run(backend, compiler) do
    Nx.with_default_backend(backend, fn -> run_example(compiler) end)
  rescue
    _ -> {:error, Error.new(:nx_profile_failed, :inference, "Nx profile failed")}
  catch
    _, _ -> {:error, Error.new(:nx_profile_failed, :inference, "Nx profile failed")}
  end

  defp run_example(compiler) do
    path = Application.app_dir(:wotex_lab, "priv/fixtures/thermal/thing-description.json")

    with {:ok, json} <- File.read(path),
         {:ok, td} <-
           Telemetry.span(:scenario, :parse, %{profile: :thermal}, fn ->
             ThingDescription.parse(json)
           end),
         map <- ThingDescription.to_map(td),
         {:ok, input_schema} <-
           DataSchema.new(Map.take(map["properties"]["temperature"], ["type", "unit"])),
         {:ok, feature} <- feature(ThingDescription.id(td), input_schema),
         {:ok, schema} <- Schema.new(features: [feature], max_rows: @max_rows),
         {:ok, rows} <- rows(ThingDescription.id(td)),
         {:ok, encoded} <-
           Telemetry.span(:nx, :encode, %{profile: :thermal}, fn ->
             Encoder.encode(rows, schema, unit_converter: {UnitConverter, []})
           end),
         :ok <- batch_measurements(encoded),
         tensor <-
           Telemetry.span(:nx, :inference, %{profile: :thermal}, fn ->
             Nx.Defn.jit_apply(&target/1, [Encoded.batch(encoded)], compiler: compiler)
           end),
         {:ok, output_schema} <- DataSchema.new(map["actions"]["setTarget"]["input"]),
         {:ok, output} <- output(ThingDescription.id(td), output_schema),
         {:ok, proposal} <-
           Telemetry.span(:nx, :decode, %{profile: :thermal}, fn ->
             Decoder.decode(tensor, output, id: "thermal-proposal-1", proposed_at: 2_000)
           end) do
      {:ok, %{thing_description: td, encoded: encoded, proposal: proposal}}
    end
  end

  defp batch_measurements(encoded) do
    rows = Encoded.row_count(encoded)
    width = length(Encoded.feature_order(encoded))

    Telemetry.event(
      :nx,
      :encode,
      %{rows: rows, width: width, fill: rows / @max_rows},
      %{profile: :thermal}
    )
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

    reduced =
      Enum.reduce_while(observations, {:ok, []}, fn {id, time, value}, {:ok, rows} ->
        with {:ok, observation} <- observation(thing_id, id, time, value),
             {:ok, row} <- Row.new(time, %{"temperature" => observation}) do
          {:cont, {:ok, [row | rows]}}
        else
          error -> {:halt, error}
        end
      end)

    case reduced do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
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
