defmodule Wotex.Lab.Examples.WindowAnomaly do
  @moduledoc """
  Windowed anomaly, persistence prediction and observation decoding over a
  synthetic thermal stream, using only public `Wotex.Nx` APIs.

  The lane resamples simulator samples into a caller-defined window, encodes
  them with an explicit fill policy, scores the last observed row against the
  mask-weighted mean of the window with a small `defn`, and decodes the score
  as an inert anomaly, the last value as a persistence prediction for the next
  step, and the same value as an observation. Nothing here is a trained model;
  the numbers are inspectable baselines with recorded provenance.
  """

  import Nx.Defn

  alias Wotex.DataSchema
  alias Wotex.Lab.Error, as: LabError
  alias Wotex.Lab.{Options, Telemetry}
  alias Wotex.Lab.Simulators.Thermal

  alias Wotex.Nx.{
    Decoder,
    Encoded,
    Encoder,
    Feature,
    Observation,
    OutputSchema,
    Row,
    Schema,
    Window
  }

  @thing_id "urn:wotex:lab:room:simulated"
  @max_rows 64
  @quality_scores %{good: 1.0, uncertain: 0.5, bad: 0.0, missing: 0.0}
  @options [
    :backend,
    :count,
    :fill,
    :glitches,
    :heater,
    :max_age,
    :seed,
    :step,
    :strategy,
    :threshold,
    :window_count,
    :window_start
  ]

  @doc """
  Runs the lane and returns rows, the encoded batch, decoded outputs and the
  experiment manifest.

  Options: `:seed`, `:count`, `:step`, `:heater`, `:glitches` (simulator
  inputs), `:window_count` (8), `:window_start` (defaults to the last window
  ending at the final sample), `:strategy` (`:latest`), `:max_age`,
  `:threshold` (1.5), `:fill` (18.0), and `:backend` (`Nx.BinaryBackend`).
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    with :ok <- Options.validate(opts, @options),
         :ok <- validate_options(opts) do
      backend = Keyword.get(opts, :backend, Nx.BinaryBackend)
      safe_run(backend, opts)
    end
  end

  @doc "Scores the last observed row against the mask-weighted mean of the window."
  @spec score({{Nx.Tensor.t()}, {Nx.Tensor.t()}, Nx.Tensor.t()}) :: Nx.Tensor.t()
  defn score({{values}, {masks}, _quality}) do
    weights = Nx.as_type(masks, Nx.type(values))
    observed = Nx.max(Nx.sum(weights), 1.0)
    mean = Nx.sum(values * weights) / observed
    last_index = Nx.argmax(Nx.iota(Nx.shape(values)) * weights)
    Nx.abs(values[last_index] - mean)
  end

  @doc "Builds observations from simulator samples for the lane's Thing and affordance."
  @spec observations([Thermal.sample()]) :: {:ok, [Observation.t()]} | {:error, term()}
  def observations(samples) do
    reduced =
      Enum.reduce_while(samples, {:ok, []}, fn sample, {:ok, acc} ->
        case observation(sample) do
          {:ok, observation} -> {:cont, {:ok, [observation | acc]}}
          error -> {:halt, error}
        end
      end)

    case reduced do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp safe_run(backend, opts) do
    Nx.with_default_backend(backend, fn -> run_lane(opts) end)
  rescue
    _ -> {:error, LabError.new(:nx_profile_failed, :inference, "Nx profile failed")}
  catch
    _, _ -> {:error, LabError.new(:nx_profile_failed, :inference, "Nx profile failed")}
  end

  defp validate_options(opts) do
    backend = Keyword.get(opts, :backend, Nx.BinaryBackend)
    window_count = Keyword.get(opts, :window_count, 8)
    strategy = Keyword.get(opts, :strategy, :latest)
    max_age = Keyword.get(opts, :max_age)
    threshold = Keyword.get(opts, :threshold, 1.5)
    fill = Keyword.get(opts, :fill, 18.0)
    window_start = Keyword.get(opts, :window_start)

    admitted? =
      Enum.all?([
        available_backend?(backend),
        integer_in?(window_count, 2..64),
        strategy in [:exact, :latest, :nearest],
        optional_nonnegative_integer?(max_age),
        finite_nonnegative?(threshold),
        finite?(fill),
        is_nil(window_start) or is_integer(window_start)
      ])

    if admitted? do
      :ok
    else
      {:error, LabError.new(:invalid_experiment, :construction, "window experiment is invalid")}
    end
  end

  defp valid_backend?(backend) when is_atom(backend), do: not is_nil(backend)
  defp valid_backend?({backend, opts}), do: is_atom(backend) and is_list(opts)
  defp valid_backend?(_), do: false

  defp available_backend?(backend),
    do: valid_backend?(backend) and Code.ensure_loaded?(backend_module(backend))

  defp backend_module({backend, _}), do: backend
  defp backend_module(backend), do: backend

  defp integer_in?(value, range) when is_integer(value), do: value in range
  defp integer_in?(_, _), do: false

  defp optional_nonnegative_integer?(nil), do: true
  defp optional_nonnegative_integer?(value), do: is_integer(value) and value >= 0

  defp finite_nonnegative?(value), do: finite?(value) and value >= 0
  defp finite?(value) when is_integer(value), do: abs(value) <= 1_000_000_000_000

  defp finite?(value) when is_float(value), do: abs(value) <= 1_000_000_000_000

  defp finite?(_), do: false

  defp run_lane(opts) do
    simulation = Thermal.generate(Keyword.take(opts, [:seed, :count, :step, :heater, :glitches]))
    step = simulation.manifest["step"]
    count = Keyword.get(opts, :window_count, 8)
    final_sample_at = simulation.manifest["start"] + (simulation.manifest["count"] - 1) * step
    start = Keyword.get(opts, :window_start, final_sample_at - (count - 1) * step)
    last_at = start + (count - 1) * step

    with {:ok, observations} <- observations(simulation.samples),
         {:ok, schema} <- schema(Keyword.get(opts, :fill, 18.0)),
         {:ok, window} <-
           Window.new(
             start: start,
             step: step,
             count: count,
             strategy: Keyword.get(opts, :strategy, :latest),
             max_age: Keyword.get(opts, :max_age)
           ),
         {:ok, rows} <- Window.resample(observations, schema, window),
         {:ok, encoded} <-
           Telemetry.span(:nx, :encode, %{profile: :window_anomaly}, fn ->
             Encoder.encode(rows, schema)
           end),
         :ok <- batch_measurements(encoded),
         score <-
           Telemetry.span(:nx, :inference, %{profile: :window_anomaly}, fn ->
             Telemetry.event(
               :nx,
               :inference,
               %{queue_depth: 0},
               %{profile: :window_anomaly}
             )

             Nx.Defn.jit_apply(&score/1, [encoded], compiler: Nx.Defn.Evaluator)
           end),
         {:ok, anomaly} <- decode_anomaly(score, Keyword.get(opts, :threshold, 1.5), last_at),
         {:ok, last_value} <- last_observed(rows),
         {:ok, prediction} <- decode_prediction(last_value, last_at, step),
         {:ok, observation} <- decode_observation(last_value, last_at) do
      {:ok,
       %{
         rows: rows,
         encoded: encoded,
         score: score,
         anomaly: anomaly,
         prediction: prediction,
         observation: observation,
         manifest:
           Map.merge(simulation.manifest, %{
             "window" => %{"start" => start, "step" => step, "count" => count},
             "feature_order" => Encoded.feature_order(encoded),
             "fill" => Keyword.get(opts, :fill, 18.0),
             "threshold" => Keyword.get(opts, :threshold, 1.5),
             "dtype" => "f32"
           })
       }}
    end
  end

  defp batch_measurements(encoded) do
    {_, masks, quality} =
      Nx.Defn.jit_apply(&Function.identity/1, [Encoded.batch(encoded)], compiler: Nx.Defn.Evaluator)

    mask_values =
      masks
      |> Tuple.to_list()
      |> Enum.flat_map(&Nx.to_flat_list/1)

    Telemetry.event(
      :nx,
      :encode,
      %{
        rows: Encoded.row_count(encoded),
        width: length(Encoded.feature_order(encoded)),
        fill: Encoded.row_count(encoded) / @max_rows,
        mask_observed: ratio(mask_values, &(&1 == 1)),
        quality: quality_ratio(Nx.to_flat_list(quality))
      },
      %{profile: :window_anomaly}
    )
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp ratio(values, predicate),
    do: Enum.count(values, predicate) / max(length(values), 1)

  defp quality_ratio(values) do
    codes =
      Map.new(Wotex.Nx.quality_codes(), fn {quality, code} ->
        {code, Map.fetch!(@quality_scores, quality)}
      end)

    Enum.reduce(values, 0.0, &(Map.get(codes, &1, 0.0) + &2)) / max(length(values), 1)
  end

  defp schema(fill) do
    with {:ok, data_schema} <- DataSchema.new(%{"type" => "number", "unit" => "Cel"}),
         {:ok, feature} <-
           Feature.new(
             name: "temperature",
             thing_id: @thing_id,
             affordance_type: :property,
             affordance_name: "temperature",
             data_schema: data_schema,
             accepted_quality: [:good, :uncertain],
             missing: {:fill, fill}
           ) do
      Schema.new(features: [feature], max_rows: @max_rows)
    end
  end

  defp observation(sample) do
    Observation.new(
      id: "sim-#{sample.index}",
      thing_id: @thing_id,
      affordance_type: :property,
      affordance_name: "temperature",
      observed_at: sample.observed_at,
      value: sample.value,
      unit: "Cel",
      quality: sample.quality,
      source: "wotex_lab.thermal@" <> Thermal.version()
    )
  end

  defp last_observed(rows) do
    rows
    |> Enum.reverse()
    |> Enum.find_value({:error, :no_observed_row}, fn %Row{observations: observations} ->
      case observations["temperature"] do
        %Observation{value: value, quality: quality} when quality in [:good, :uncertain] ->
          {:ok, value}

        _ ->
          nil
      end
    end)
  end

  defp decode_anomaly(score, threshold, produced_at) do
    with {:ok, data_schema} <- DataSchema.new(%{"type" => "number", "minimum" => 0}),
         {:ok, output} <-
           OutputSchema.new(
             kind: :anomaly,
             thing_id: @thing_id,
             affordance_type: :property,
             affordance_name: "temperature",
             data_schema: data_schema,
             dtype: :f32,
             threshold: threshold,
             anomaly_rule: :at_or_above
           ) do
      Telemetry.span(:nx, :decode, %{profile: :window_anomaly}, fn ->
        Decoder.decode(score, output, id: "anomaly-#{produced_at}", produced_at: produced_at)
      end)
    end
  end

  defp decode_prediction(value, produced_at, step) do
    with {:ok, data_schema} <- DataSchema.new(%{"type" => "number", "unit" => "Cel"}),
         {:ok, output} <-
           OutputSchema.new(
             kind: :prediction,
             thing_id: @thing_id,
             affordance_type: :property,
             affordance_name: "temperature",
             data_schema: data_schema,
             dtype: :f32,
             metadata: %{"baseline" => "persistence"}
           ) do
      Decoder.decode(Nx.tensor(value, type: :f32), output,
        id: "prediction-#{produced_at}",
        produced_at: produced_at,
        target_at: produced_at + step
      )
    end
  end

  defp decode_observation(value, observed_at) do
    with {:ok, data_schema} <- DataSchema.new(%{"type" => "number", "unit" => "Cel"}),
         {:ok, output} <-
           OutputSchema.new(
             kind: :observation,
             thing_id: @thing_id,
             affordance_type: :property,
             affordance_name: "temperature",
             data_schema: data_schema,
             dtype: :f32
           ) do
      Decoder.decode(Nx.tensor(value, type: :f32), output,
        id: "decoded-#{observed_at}",
        observed_at: observed_at,
        source: "lane:window-anomaly"
      )
    end
  end
end
