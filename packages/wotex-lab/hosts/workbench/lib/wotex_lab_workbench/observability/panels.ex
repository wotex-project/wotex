defmodule WotexLabWorkbench.Observability.Panels do
  @moduledoc """
  Read-only panel descriptors and portable Grafana JSON from the metric catalogue.

  Select at most 16 distinct catalogue IDs. No expressions, module names, URLs,
  EEx, JavaScript or caller labels are accepted. PromQL preserves each label set
  (including a receiver's job/instance labels): counters use a five-minute rate,
  gauges their measured value, and classic histograms a bucket-derived p95.
  Missing data is not filled with zero. These are templates, not query execution
  or evidence that a Grafana server imported them.
  """

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.Catalogue

  @default ~w(nx_operations_total nx_duration_seconds nx_batch_rows nx_batch_fill_ratio)
  @datasource %{type: "prometheus", uid: "${DS_PROMETHEUS}"}

  @doc "One descriptor per metric, with exact source semantics and the fixed display query."
  @spec all() :: [map()]
  def all do
    :ok = Catalogue.validate()
    Enum.map(Catalogue.metrics(), &descriptor/1)
  end

  @doc "The small default numerical dashboard selection."
  @spec defaults() :: [String.t()]
  def defaults, do: @default

  @doc "Admits only a bounded, nonempty list of distinct known string IDs."
  @spec select(term()) :: {:ok, [map()]} | {:error, Error.t()}
  def select(ids) when is_list(ids) and length(ids) in 1..16 do
    index = Map.new(all(), &{&1.id, &1})

    if Enum.all?(ids, &(is_binary(&1) and byte_size(&1) <= 128 and Map.has_key?(index, &1))) and
         length(Enum.uniq(ids)) == length(ids) do
      {:ok, Enum.map(ids, &Map.fetch!(index, &1))}
    else
      invalid()
    end
  end

  def select(_ids), do: invalid()

  @doc "Generates inert Grafana classic dashboard JSON data, never uploading it."
  @spec dashboard(term()) :: {:ok, map()} | {:error, Error.t()}
  def dashboard(ids \\ @default) do
    with {:ok, selected} <- select(ids) do
      {:ok,
       %{
         "__inputs" => [
           %{
             name: "DS_PROMETHEUS",
             label: "Prometheus-compatible source",
             type: "datasource",
             pluginId: "prometheus",
             pluginName: "Prometheus"
           }
         ],
         "id" => nil,
         "uid" => nil,
         "title" => "WoTEx Lab catalogue #{Catalogue.version()}",
         "description" =>
           "Operator-selected source. Host instance metrics are not browser-session metrics.",
         "schemaVersion" => 39,
         "version" => 1,
         "timezone" => "utc",
         "editable" => false,
         "refresh" => "",
         "time" => %{from: "now-1h", to: "now"},
         "panels" => Enum.with_index(selected, &grafana_panel/2),
         "annotations" => %{list: []},
         "templating" => %{list: []},
         "links" => [],
         "tags" => ["wotex-lab", "catalogue-#{Catalogue.version()}"]
       }}
    end
  end

  defp descriptor(metric) do
    {aggregation, query, display_unit} = query(metric)

    %{
      id: Atom.to_string(metric.id),
      catalogue_version: Catalogue.version(),
      name: metric.name,
      title: metric.description,
      type: metric.type,
      unit: metric.unit,
      dimensions: metric.dimensions,
      buckets: metric.buckets,
      scope: metric.scope,
      aggregation: aggregation,
      query: query,
      display_unit: display_unit
    }
  end

  defp query(%{type: :counter} = metric),
    do: {:rate, "rate(#{metric.name}[5m])", "#{metric.unit}/second"}

  defp query(%{type: :histogram} = metric),
    do:
      {:p95, "histogram_quantile(0.95, rate(#{metric.name}_bucket[5m]))",
       Atom.to_string(metric.unit)}

  defp query(%{type: :gauge} = metric),
    do: {:last, metric.name, Atom.to_string(metric.unit)}

  defp grafana_panel(panel, index) do
    %{
      id: index + 1,
      type: "timeseries",
      title: "#{panel.title} (#{panel.aggregation})",
      description:
        "#{panel.name}; catalogue #{panel.catalogue_version}; #{panel.scope} scope. Missing is unavailable.",
      datasource: @datasource,
      gridPos: %{h: 8, w: 12, x: rem(index, 2) * 12, y: div(index, 2) * 8},
      targets: [
        %{
          refId: "A",
          expr: panel.query,
          datasource: @datasource,
          range: true,
          legendFormat: "__auto",
          editorMode: "code"
        }
      ],
      fieldConfig: %{
        defaults: %{unit: grafana_unit(panel), noValue: "unavailable", custom: %{spanNulls: false}},
        overrides: []
      },
      options: %{tooltip: %{mode: "multi"}, legend: %{displayMode: "list", placement: "bottom"}}
    }
  end

  defp grafana_unit(%{aggregation: :rate, unit: :bytes}), do: "Bps"
  defp grafana_unit(%{aggregation: :rate} = panel), do: "suffix:#{panel.display_unit}"
  defp grafana_unit(%{unit: :seconds}), do: "s"
  defp grafana_unit(%{unit: :bytes}), do: "bytes"
  defp grafana_unit(%{unit: :ratio}), do: "percentunit"
  defp grafana_unit(panel), do: "suffix:#{panel.display_unit}"

  defp invalid,
    do: {:error, Error.new(:invalid_panels, :metrics, "select 1–16 distinct catalogue IDs")}
end
