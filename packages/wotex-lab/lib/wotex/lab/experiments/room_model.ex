# Compiled only when the optional Axon profile is present; the base package
# remains usable without model-training dependencies.
if Code.ensure_loaded?(Axon) do
  defmodule Wotex.Lab.Experiments.RoomModel do
    @moduledoc """
    Bounded Axon training and held-out evaluation over the synthetic room stream.

    The experiment splits by time before making three-sample windows, derives
    normalization only from the training split, trains a small Axon model, and
    compares it with persistence on the same held-out targets. Its output is an
    inert `Wotex.Nx.Prediction`, a serialized parameter artifact, and a manifest;
    it never dispatches an Action or changes global Nx defaults.

    Experiment contract `2.0.0` predicts the next step from the two latest
    observations, independently of held-out scoring. Parameters use
    `Nx.serialize/2`, not raw external terms containing backend resources.
    Restore trusted artifacts with `Nx.deserialize/2` on an explicitly selected
    backend; this module does not accept arbitrary uploaded parameter bytes.

    Axon and a compiled backend are optional integration-profile dependencies.
    The default uses `Nx.BinaryBackend` with `Nx.Defn.Evaluator`. A caller may
    explicitly select `EXLA.Backend` and `EXLA` after starting that dependency.
    """

    alias Wotex.DataSchema
    alias Wotex.Lab.{Error, Options}
    alias Wotex.Lab.Evidence.Digest
    alias Wotex.Lab.Simulators.Thermal
    alias Wotex.Nx.{Decoder, OutputSchema}

    @thing_id "urn:wotex:lab:room:simulated"
    @options [:backend, :compiler, :count, :epochs, :seed, :split_at, :timeout_ms]
    @max_rows 512
    @max_epochs 200
    @max_timeout_ms 60_000

    @typedoc "Result of one explicit model experiment."
    @type result :: %{
            manifest: map(),
            metrics: %{model_mae: float(), persistence_mae: float()},
            model: Axon.t(),
            parameters: binary(),
            prediction: Wotex.Nx.Prediction.t(),
            split: %{boundary: integer(), test_windows: pos_integer(), train_windows: pos_integer()}
          }

    @doc """
    Runs one bounded experiment.

    Options are `:seed` (11), `:count` (64, maximum 512), `:split_at`
    (three quarters of the rows), `:epochs` (20, maximum 200), `:timeout_ms`
    (10 seconds, maximum 60 seconds), `:backend` (`Nx.BinaryBackend`) and
    `:compiler` (`Nx.Defn.Evaluator`). Options are closed and unique.
    """
    @spec run(keyword()) :: {:ok, result()} | {:error, Error.t()}
    def run(opts \\ []) do
      with :ok <- Options.validate(opts, @options),
           {:ok, config} <- validate(opts),
           :ok <- dependencies_available(config) do
        bounded_run(config)
      end
    end

    defp validate(opts) do
      count = Keyword.get(opts, :count, 64)
      split_at = Keyword.get_lazy(opts, :split_at, fn -> default_split(count) end)

      config = %{
        backend: Keyword.get(opts, :backend, Nx.BinaryBackend),
        compiler: Keyword.get(opts, :compiler, Nx.Defn.Evaluator),
        count: count,
        epochs: Keyword.get(opts, :epochs, 20),
        seed: Keyword.get(opts, :seed, 11),
        split_at: split_at,
        timeout_ms: Keyword.get(opts, :timeout_ms, 10_000)
      }

      if valid_config?(config) do
        {:ok, config}
      else
        {:error,
         Error.new(:invalid_experiment, :construction, "room-model configuration is invalid")}
      end
    end

    defp default_split(count) when is_integer(count) and count in 12..@max_rows,
      do: div(count * 3, 4)

    defp default_split(_), do: nil

    defp valid_config?(config) do
      Enum.all?([
        integer_in?(config.seed, 0..4_294_967_295),
        integer_in?(config.count, 12..@max_rows),
        valid_split?(config.split_at, config.count),
        integer_in?(config.epochs, 1..@max_epochs),
        integer_in?(config.timeout_ms, 1..@max_timeout_ms),
        backend?(config.backend),
        compiler?(config.compiler)
      ])
    end

    defp integer_in?(value, range) when is_integer(value), do: value in range
    defp integer_in?(_, _), do: false

    defp valid_split?(split_at, count) when is_integer(split_at) and is_integer(count),
      do: split_at >= 6 and split_at <= count - 3

    defp valid_split?(_, _), do: false

    defp backend?(backend) when is_atom(backend), do: not is_nil(backend)
    defp backend?({backend, opts}), do: is_atom(backend) and not is_nil(backend) and is_list(opts)
    defp backend?(_), do: false

    defp compiler?(compiler), do: is_atom(compiler) and not is_nil(compiler)

    defp dependencies_available(config) do
      backend = backend_module(config.backend)

      if Code.ensure_loaded?(Axon) and Code.ensure_loaded?(backend) and
           Code.ensure_loaded?(config.compiler) do
        :ok
      else
        {:error,
         Error.new(
           :experiment_profile_unavailable,
           :admission,
           "selected model experiment profile is unavailable"
         )}
      end
    end

    defp backend_module({backend, _}), do: backend
    defp backend_module(backend), do: backend

    defp bounded_run(config) do
      parent = self()
      tag = make_ref()

      {pid, monitor} =
        spawn_monitor(fn -> send(parent, {tag, safe_execute(config)}) end)

      receive do
        {^tag, result} ->
          Process.demonitor(monitor, [:flush])
          result

        {:DOWN, ^monitor, :process, ^pid, _} ->
          execution_failure()
      after
        config.timeout_ms ->
          Process.exit(pid, :kill)
          receive do: ({:DOWN, ^monitor, :process, ^pid, _} -> :ok)

          {:error,
           Error.new(:experiment_timeout, :inference, "model experiment exceeded its deadline",
             details: %{timeout_ms: config.timeout_ms}
           )}
      end
    end

    defp safe_execute(config) do
      Nx.with_default_backend(config.backend, fn -> execute(config) end)
    rescue
      _ -> execution_failure()
    catch
      _, _ -> execution_failure()
    end

    defp execution_failure do
      {:error, Error.new(:experiment_failed, :inference, "model experiment failed")}
    end

    defp execute(config) do
      simulation =
        Thermal.generate(
          seed: config.seed,
          count: config.count,
          heater: heater_schedule(config.count)
        )

      {training, held_out} = Enum.split(simulation.samples, config.split_at)
      boundary = hd(held_out).observed_at
      training_windows = Enum.chunk_every(training, 3, 1, :discard)
      held_out_windows = Enum.chunk_every(held_out, 3, 1, :discard)
      {mean, deviation} = training_statistics(training)
      {train_inputs, train_targets} = tensors(training_windows, mean, deviation)
      {test_inputs, test_targets} = tensors(held_out_windows, mean, deviation)
      model = model()
      model_state = train(model, train_inputs, train_targets, config)

      normalized_predictions =
        Axon.predict(model, model_state, test_inputs, compiler: config.compiler)

      predictions = normalized_predictions |> Nx.multiply(deviation) |> Nx.add(mean)
      truth = test_targets |> Nx.multiply(deviation) |> Nx.add(mean)
      persistence = persistence_tensor(held_out_windows)
      metrics = metrics(predictions, truth, persistence)
      parameters = model_state |> Nx.serialize() |> IO.iodata_to_binary()
      latest = Enum.take(held_out, -2)

      prediction_value =
        model
        |> Axon.predict(
          model_state,
          Nx.tensor([input_pair(latest, mean, deviation)], type: :f32),
          compiler: config.compiler
        )
        |> Nx.multiply(deviation)
        |> Nx.add(mean)
        |> Nx.to_flat_list()
        |> hd()

      last_at = held_out |> List.last() |> Map.fetch!(:observed_at)
      {:ok, prediction} = decode_prediction(prediction_value, last_at, simulation.manifest["step"])

      split = %{
        boundary: boundary,
        train_windows: length(training_windows),
        test_windows: length(held_out_windows)
      }

      manifest =
        manifest(
          simulation,
          config,
          split,
          mean,
          deviation,
          metrics,
          parameters
        )
        |> Map.put("prediction", %{
          "input_times" => Enum.map(latest, & &1.observed_at),
          "produced_at" => last_at,
          "target_at" => last_at + simulation.manifest["step"]
        })

      {:ok,
       %{
         manifest: manifest,
         metrics: metrics,
         model: model,
         parameters: parameters,
         prediction: prediction,
         split: split
       }}
    end

    defp heater_schedule(count) do
      [{20, 3.0}, {44, 2.0}]
      |> Enum.filter(fn {index, _} -> index < count end)
      |> Map.new()
    end

    defp training_statistics(samples) do
      values = Nx.tensor(Enum.map(samples, & &1.value), type: :f32)
      mean = Nx.to_number(Nx.mean(values))
      deviation = Nx.to_number(Nx.standard_deviation(values))
      {mean, max(deviation, 1.0e-6)}
    end

    defp tensors(windows, mean, deviation) do
      inputs =
        Enum.map(windows, fn [first, second, _] ->
          input_pair([first, second], mean, deviation)
        end)

      targets =
        Enum.map(windows, fn [_, _, target] ->
          [normalize(target.value, mean, deviation)]
        end)

      {Nx.tensor(inputs, type: :f32), Nx.tensor(targets, type: :f32)}
    end

    defp input_pair([first, second], mean, deviation) do
      [
        normalize(first.value, mean, deviation),
        normalize(second.value, mean, deviation),
        1.0,
        1.0,
        quality_code(first.quality),
        quality_code(second.quality)
      ]
    end

    defp normalize(value, mean, deviation), do: (value - mean) / deviation
    defp quality_code(:good), do: 0.0
    defp quality_code(_), do: 1.0

    defp model do
      Axon.input("window", shape: {nil, 6})
      |> Axon.dense(4, activation: :tanh)
      |> Axon.dense(1)
    end

    defp train(model, inputs, targets, config) do
      model
      |> Axon.Loop.trainer(:mean_squared_error, :sgd, log: 0, seed: config.seed)
      |> Axon.Loop.run(
        [{inputs, targets}],
        Axon.ModelState.new(%{}),
        epochs: config.epochs,
        compiler: config.compiler
      )
    end

    defp persistence_tensor(windows) do
      windows
      |> Enum.map(fn [_, second, _] -> [second.value] end)
      |> Nx.tensor(type: :f32)
    end

    defp metrics(predictions, truth, persistence) do
      %{
        model_mae: mae(predictions, truth),
        persistence_mae: mae(persistence, truth)
      }
    end

    defp mae(predictions, truth) do
      predictions
      |> Nx.subtract(truth)
      |> Nx.abs()
      |> Nx.mean()
      |> Nx.to_number()
    end

    defp decode_prediction(value, produced_at, step) do
      with {:ok, schema} <- DataSchema.new(%{"type" => "number", "unit" => "Cel"}),
           {:ok, output} <-
             OutputSchema.new(
               kind: :prediction,
               thing_id: @thing_id,
               affordance_type: :property,
               affordance_name: "temperature",
               data_schema: schema,
               dtype: :f32,
               metadata: %{
                 "model" => "axon-room-v1",
                 "baseline" => "persistence",
                 "experiment_version" => "2.0.0"
               }
             ) do
        Decoder.decode(Nx.tensor(value, type: :f32), output,
          id: "axon-room-#{produced_at}",
          produced_at: produced_at,
          target_at: produced_at + step
        )
      end
    end

    defp manifest(simulation, config, split, mean, deviation, metrics, parameters) do
      dataset = %{
        "times" => Enum.map(simulation.samples, & &1.observed_at),
        "values" => Enum.map(simulation.samples, & &1.value)
      }

      {:ok, dataset_json} = Wotex.JSON.encode(dataset)

      architecture = %{
        "input" => 6,
        "hidden" => 4,
        "output" => 1,
        "activations" => ["tanh", "linear"]
      }

      {:ok, architecture_json} = Wotex.JSON.encode(architecture)

      Map.merge(simulation.manifest, %{
        "dataset_digest" => Digest.bytes(dataset_json),
        "schema_digest" => Digest.bytes("temperature:Cel:f32:values,masks,quality"),
        "model_digest" => Digest.bytes(architecture_json),
        "parameters_digest" => Digest.bytes(parameters),
        "parameters_encoding" => "nx-serialize",
        "experiment_version" => "2.0.0",
        "feature_order" => ["temperature"],
        "window" => %{"width" => 3, "built_after_split" => true},
        "input_layout" => ["value[0]", "value[1]", "mask[0]", "mask[1]", "quality[0]", "quality[1]"],
        "accepted_quality" => ["good"],
        "missing_policy" => "reject",
        "normalization" => %{"mean" => mean, "std" => deviation, "from" => "train"},
        "dtype" => "f32",
        "backend" => inspect(config.backend),
        "compiler" => inspect(config.compiler),
        "model" => "axon-room-v1",
        "split" => %{
          "train_rows" => config.split_at,
          "test_rows" => config.count - config.split_at,
          "boundary" => split.boundary
        },
        "training" => %{
          "epochs" => config.epochs,
          "optimizer" => "sgd",
          "loss" => "mean_squared_error",
          "seed" => config.seed
        },
        "limits" => %{
          "max_rows" => @max_rows,
          "max_epochs" => @max_epochs,
          "timeout_ms" => config.timeout_ms
        },
        "metrics" => %{
          "model_mae" => metrics.model_mae,
          "persistence_mae" => metrics.persistence_mae
        },
        "cohort" => cohort()
      })
    end

    defp cohort do
      for app <- [:wotex_lab, :wotex_nx, :nx, :axon], into: %{} do
        {Atom.to_string(app), app |> Application.spec(:vsn) |> List.to_string()}
      end
    end
  end
end
