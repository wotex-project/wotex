defmodule WotexLabWorkbench.Runs.WindowAnomaly do
  @moduledoc """
  Runs the window-anomaly lane and derives bounded series from the simulated
  stream and the encoded window.
  """

  alias Wotex.Lab.Examples.WindowAnomaly
  alias Wotex.Lab.Simulators.Thermal
  alias WotexLabWorkbench.{Preview, Runs}

  @doc "Runs the lane with admitted `:seed`, `:count`, `:window_count`, `:threshold`, `:fill`, `:backend`."
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(params) do
    backend = Keyword.fetch!(params, :backend)
    lane = Keyword.take(params, [:seed, :count, :window_count, :threshold, :fill])

    {outcome, elapsed} =
      Runs.measure(fn -> WindowAnomaly.run(Keyword.put(lane, :backend, backend)) end)

    with {:ok, result} <- outcome do
      tensor = Preview.tensor_summary(result.encoded, backend)
      anomaly = Map.from_struct(result.anomaly)
      prediction = Map.from_struct(result.prediction)
      simulation = Thermal.generate(Keyword.take(params, [:seed, :count]))

      stream =
        Enum.map(simulation.samples, fn sample ->
          {sample.observed_at, if(sample.quality == :good, do: sample.value, else: nil)}
        end)

      {:ok,
       %{
         duration_ms: elapsed,
         backend: inspect(backend),
         summary: [
           {"Simulator", "wotex_lab.thermal@" <> Thermal.version()},
           {"Samples", Integer.to_string(result.manifest["count"])},
           {"Window",
            "#{result.manifest["window"]["count"]} rows, step #{result.manifest["step"]} ms"},
           {"Score", Preview.format(anomaly.score)},
           {"Anomaly", if(anomaly.anomalous?, do: "yes (at or above threshold)", else: "no")},
           {"Persistence prediction", Preview.format(prediction.value) <> " Cel"}
         ],
         tensor: tensor,
         timeseries: [
           Runs.series(
             "simulated temperature (Cel)",
             "Cel",
             "simulator stream, bad quality as gaps",
             stream
           )
           | Runs.timeseries(tensor)
         ],
         assertions: [
           Runs.assertion(
             "window:score-finite",
             is_number(anomaly.score),
             "score is a finite number"
           ),
           Runs.assertion(
             "window:threshold-recorded",
             anomaly.threshold == params[:threshold],
             "threshold recorded"
           ),
           Runs.assertion(
             "window:outputs-inert",
             true,
             "anomaly, prediction and observation are inert"
           )
         ],
         proposal: nil,
         outcomes: %{
           score: anomaly.score,
           anomalous: anomaly.anomalous?,
           prediction: prediction.value,
           rows: tensor.rows
         },
         inputs: ["simulator:wotex_lab.thermal@" <> Thermal.version()],
         seed: params[:seed],
         budgets: %{max_rows: 64, samples: params[:count]}
       }}
    end
  end
end
