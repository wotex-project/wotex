defmodule Wotex.Lab.Metrics.Dataset do
  @moduledoc """
  Immutable, content-addressed export of one bounded diagnostic-history query.

  `freeze/3` is deliberately separate from ordinary history reads. The history
  owner serializes the query with snapshot writes and supplies the exact
  watermark captured. Every query step becomes one ordered row with an
  observed/missing mask; reset, gap, stale, eviction and rollback markers stay
  explicit. The only admitted split state is `unsplit`: a later experiment may
  split or normalize these rows only while recording a new provenance step.

  A dataset is inert data. Constructing one does not start an experiment,
  convert it to a tensor, select a training split or mutate the live history.
  """

  alias Wotex.Lab.Error
  alias Wotex.Lab.Evidence.Digest
  alias Wotex.Lab.Metrics.{History, Query}
  alias Wotex.Lab.Options

  @schema_version "1.0.0"
  @options [:experiment]

  @type row :: %{
          timestamp_ms: integer(),
          value: number() | nil,
          mask: 0 | 1,
          quality: [String.t()]
        }

  @type t :: %__MODULE__{
          schema_version: String.t(),
          id: String.t(),
          digest: String.t(),
          experiment: String.t(),
          source: map(),
          query: map(),
          interval: map(),
          watermark: map(),
          ordering: String.t(),
          unit: String.t(),
          rows: [row()],
          row_count: non_neg_integer(),
          markers: [map()],
          loss: map(),
          missing_policy: String.t(),
          split: map(),
          transforms: [map()]
        }

  @enforce_keys [
    :id,
    :digest,
    :experiment,
    :source,
    :query,
    :interval,
    :watermark,
    :ordering,
    :unit,
    :rows,
    :row_count,
    :markers,
    :loss,
    :missing_policy,
    :split,
    :transforms
  ]
  defstruct [{:schema_version, @schema_version} | @enforce_keys]

  @doc "The immutable diagnostic dataset schema version."
  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @doc "Freezes one admitted history query for the named experiment."
  @spec freeze(GenServer.server(), Query.t(), keyword()) ::
          {:ok, t()} | {:error, Error.t()}
  def freeze(history, descriptor, opts) do
    with :ok <- Options.validate(opts, @options),
         {:ok, experiment} <- experiment(Keyword.get(opts, :experiment)),
         {:ok, query} <- Query.validate(descriptor),
         {:ok, frozen} <- History.freeze(history, query) do
      build(experiment, query, frozen)
    end
  end

  @doc "Returns the stable string-keyed representation used by reports and JSON exporters."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = dataset) do
    dataset
    |> Map.from_struct()
    |> stringify()
  end

  defp build(experiment, query, %{response: response, watermark: watermark}) do
    rows = rows(response)
    markers = Enum.map(response.markers, &marker/1)
    query_map = query_map(query)

    fields = %{
      experiment: experiment,
      source: %{
        kind: "diagnostic_history",
        engine: Atom.to_string(response.source),
        instance: response.instance,
        metric: Atom.to_string(response.metric),
        name: response.name
      },
      query: query_map,
      interval: response.interval,
      watermark: watermark,
      ordering: "timestamp_ms ascending; one row per admitted query step",
      unit: to_string(response.unit),
      rows: rows,
      row_count: length(rows),
      markers: markers,
      loss: response.loss,
      missing_policy: "preserve null with mask zero; never fill with zero",
      split: %{status: "unsplit", strategy: "none"},
      transforms: [
        %{
          operation: Atom.to_string(response.aggregation),
          step_ms: response.interval.step_ms,
          window_alignment: "ceil source timestamp to query step",
          downsampling: "none beyond the admitted query aggregation"
        }
      ]
    }

    digest = Digest.bytes(canonical(fields))
    dataset = struct!(__MODULE__, Map.merge(fields, %{id: digest, digest: digest}))

    if :erlang.external_size(dataset) <= query.limits.output_bytes,
      do: {:ok, dataset},
      else: {:error, error(:dataset_too_large, "frozen dataset exceeds the query output limit")}
  end

  defp rows(response) do
    values = Map.new(response.points, &{&1.t, &1.value})

    quality =
      response.markers
      |> Enum.group_by(& &1.t, &Atom.to_string(&1.kind))
      |> Map.new(fn {time, kinds} -> {time, Enum.sort(Enum.uniq(kinds))} end)

    response.interval.start_ms
    |> Stream.iterate(&(&1 + response.interval.step_ms))
    |> Stream.take_while(&(&1 <= response.interval.end_ms))
    |> Enum.map(fn timestamp ->
      case Map.fetch(values, timestamp) do
        {:ok, value} ->
          %{
            timestamp_ms: timestamp,
            value: value,
            mask: 1,
            quality: ["observed" | Map.get(quality, timestamp, [])]
          }

        :error ->
          %{
            timestamp_ms: timestamp,
            value: nil,
            mask: 0,
            quality: ["missing" | Map.get(quality, timestamp, [])]
          }
      end
    end)
  end

  defp marker(marker), do: %{timestamp_ms: marker.t, kind: Atom.to_string(marker.kind)}

  defp query_map(query) do
    %{
      schema_version: query.schema_version,
      digest: Query.digest(query),
      scope: query.scope,
      metric: Atom.to_string(query.metric),
      aggregation: Atom.to_string(query.aggregation),
      filters:
        Map.new(query.filters, fn {key, value} -> {Atom.to_string(key), Atom.to_string(value)} end),
      quantile: query.quantile,
      start_at: DateTime.to_iso8601(query.start_at),
      end_at: DateTime.to_iso8601(query.end_at),
      step_ms: query.step_ms,
      limits: query.limits
    }
  end

  # Fixed arrays keep the content identity independent of map enumeration.
  defp canonical(fields) do
    rows =
      Enum.map(fields.rows, fn row ->
        [row.timestamp_ms, row.value, row.mask, row.quality]
      end)

    markers = Enum.map(fields.markers, &[&1.timestamp_ms, &1.kind])
    query = fields.query
    source = fields.source
    interval = fields.interval
    watermark = fields.watermark
    transform = hd(fields.transforms)

    JSON.encode!([
      "wotex-diagnostic-dataset-1",
      fields.experiment,
      [source.kind, source.engine, source.instance, source.metric, source.name],
      [
        query.schema_version,
        query.digest,
        query.scope.instance,
        query.scope.session,
        query.metric,
        query.aggregation,
        pairs(query.filters),
        query.quantile,
        query.start_at,
        query.end_at,
        query.step_ms,
        pairs(query.limits)
      ],
      [interval.start_ms, interval.end_ms, interval.step_ms],
      [
        watermark.history_sequence,
        watermark.count,
        watermark.bytes,
        watermark.oldest_wall_time_ms,
        watermark.newest_wall_time_ms
      ],
      fields.ordering,
      fields.unit,
      rows,
      markers,
      pairs(fields.loss),
      fields.missing_policy,
      [fields.split.status, fields.split.strategy],
      [
        transform.operation,
        transform.step_ms,
        transform.window_alignment,
        transform.downsampling
      ]
    ])
  end

  defp experiment(value) do
    if Options.identifier?(value),
      do: {:ok, value},
      else: {:error, error(:invalid_experiment, "experiment must be a bounded identifier")}
  end

  defp pairs(map),
    do: map |> Enum.sort() |> Enum.map(fn {key, value} -> [to_string(key), value] end)

  defp stringify(%{} = map),
    do: Map.new(map, fn {key, value} -> {to_string(key), stringify(value)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(value) when value in [nil, true, false], do: value
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: value

  defp error(code, message), do: Error.new(code, :dataset, message)
end
