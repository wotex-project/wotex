defmodule WotexLabWorkbench.Observability.Definitions do
  @moduledoc """
  Catalogue-generated Telemetry.Metrics definitions with one normalized event
  per metric. Relay admission retains the original event's finite dimensions
  and performs the native-duration conversion before these events are emitted.
  No metric name, bucket, unit or dimension is accepted from a browser.
  """

  alias Telemetry.Metrics
  alias Wotex.Lab.Metrics.Catalogue

  @doc "Generates the entire accepted custom metric definition cohort."
  @spec metrics() :: [Metrics.t()]
  def metrics do
    :ok = Catalogue.validate()
    Enum.map(Catalogue.metrics(), &metric/1)
  end

  @doc "The one normalized telemetry event for a catalogue metric."
  @spec event(atom()) :: [atom()]
  def event(id), do: [:wotex, :lab, :promex, id]

  defp metric(metric) do
    opts = [
      event_name: event(metric.id),
      measurement: :value,
      tags: metric.dimensions,
      description: metric.description,
      unit: unit(metric.unit),
      reporter_options: [
        buckets: metric.buckets,
        catalogue_id: metric.id,
        catalogue_version: Catalogue.version(),
        scope: metric.scope
      ]
    ]

    case {metric.type, metric.measurement} do
      {:counter, nil} -> Metrics.counter(metric.name, opts)
      {:counter, _} -> Metrics.sum(metric.name, opts)
      {:gauge, _} -> Metrics.last_value(metric.name, opts)
      {:histogram, _} -> Metrics.distribution(metric.name, opts)
    end
  end

  defp unit(:seconds), do: :second
  defp unit(:bytes), do: :byte
  defp unit(other), do: other
end
