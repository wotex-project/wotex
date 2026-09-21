defmodule Wotex.Lab.Metrics.Catalogue do
  @moduledoc """
  The single checked-in, versioned metric catalogue of the Lab, as data.

  Every metric names its Prometheus series, type, unit, fixed versioned
  histogram buckets (seconds after the native conversion), the finite
  dimensions it may carry, its scope, the WLB.06 telemetry events that feed it
  and the measurement it reads (`nil` counts one per event). Dimensions are
  closed enums defined here: `component` and `operation` are the event
  segments, `outcome_class` is the finite class an outcome atom maps to
  through `outcome_class/1` (an arbitrary error code never passes through),
  `action` and `profile` are closed sets with an `:other` fallback,
  `backend_class` is configured on the collector, and `reason` and `kind`
  are derived the same way. Thing IDs, run IDs, topics, URLs, prompts,
  principals and free-form errors are not dimensions and cannot become one.

  `validate/1` refuses a catalogue with duplicate ids or names, a name that
  does not match its type and unit, unsorted or empty buckets, a dimension or
  event outside the closed vocabularies, a scope outside `:instance`/`:host`,
  a measurement that does not fit the unit or the source events, or a metric
  version newer than the catalogue. `to_definitions/0` emits plain maps a host
  can turn into `Telemetry.Metrics` or PromEx definitions; that generation is
  host work and is not part of the base library.
  """

  alias Wotex.Lab.{Error, Telemetry}

  @version "1.0.0"
  @prefix "wotex_lab_"
  @types [:counter, :gauge, :histogram]
  @units [:seconds, :bytes, :count, :rows, :ratio]
  @scopes [:instance, :host]
  @event_kinds [:start, :stop, :exception, :measurement]
  @max_buckets 16

  @duration_buckets [0.001, 0.005, 0.025, 0.1, 0.5, 2.5, 10.0]
  @long_duration_buckets [0.1, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0, 60.0]
  @points_buckets [10, 100, 1_000, 10_000]
  @tool_call_buckets [1, 2, 4, 8, 12, 16]
  @context_buckets [1_024, 4_096, 16_384, 32_768, 65_536]

  @outcome_classes ~w(ok error exception timeout unavailable rejected unsupported not_found conflict ignored)a
  @actions ~w(fetch list put delete create update readproperty writeproperty invokeaction observeproperty unobserveproperty subscribeevent unsubscribeevent get post patch head encode decode publish other)a
  @profiles ~w(thermal window_anomaly smart_room loopback http mqtt ets sqlite greptime test other)a
  @backend_classes ~w(binary exla torchx other)a
  @reasons ~w(none mismatch unsupported timeout malformed oversized crash changed_archive other)a
  @kinds ~w(error throw exit other)a

  @outcome_map %{
    ok: :ok,
    exception: :exception,
    ignored: :ignored,
    timeout: :timeout,
    deadline_exceeded: :timeout,
    not_found: :not_found,
    unknown_delivery: :not_found,
    unknown_decision: :not_found,
    unsupported: :unsupported,
    unsupported_query: :unsupported,
    unsupported_operation: :unsupported,
    unsupported_method: :unsupported,
    unsupported_credential: :unsupported,
    unavailable: :unavailable,
    transport_failed: :unavailable,
    capacity_exhausted: :unavailable,
    supervisor_unavailable: :unavailable,
    rate_limited: :unavailable,
    rejected: :rejected,
    refused: :rejected,
    unauthorized: :rejected,
    forbidden: :rejected,
    budget_exhausted: :rejected,
    query_too_large: :rejected,
    conflict: :conflict,
    revision_mismatch: :conflict,
    precondition_failed: :conflict,
    conflicting_decision: :conflict
  }

  @reason_map %{
    ok: :none,
    mismatch: :mismatch,
    fail: :mismatch,
    unsupported: :unsupported,
    unsupported_operation: :unsupported,
    timeout: :timeout,
    malformed: :malformed,
    invalid_document: :malformed,
    oversized: :oversized,
    response_too_large: :oversized,
    exception: :crash,
    crash: :crash,
    changed_archive: :changed_archive,
    archive_mismatch: :changed_archive
  }

  @type metric :: %{
          required(:id) => atom(),
          required(:group) => atom(),
          required(:name) => String.t(),
          required(:version) => String.t(),
          required(:type) => :counter | :gauge | :histogram,
          required(:unit) => :seconds | :bytes | :count | :rows | :ratio,
          required(:buckets) => [number()] | nil,
          required(:dimensions) => [atom()],
          required(:scope) => :instance | :host,
          required(:events) => [[atom()]],
          required(:measurement) => atom() | nil,
          required(:only) => %{atom() => [atom()]},
          required(:description) => String.t()
        }

  @doc "The catalogue version; names, buckets and dimensions change only with it."
  @spec version() :: String.t()
  def version, do: @version

  @doc "Closed dimension enums keyed by dimension name."
  @spec dimensions() :: %{atom() => [atom()]}
  def dimensions do
    %{
      component: Telemetry.components(),
      operation: Telemetry.operations(),
      outcome_class: @outcome_classes,
      action: @actions,
      profile: @profiles,
      backend_class: @backend_classes,
      reason: @reasons,
      kind: @kinds
    }
  end

  @doc "Maps a telemetry outcome atom to its finite class; unknown codes are `:error`."
  @spec outcome_class(term()) :: atom()
  def outcome_class(outcome) when is_atom(outcome), do: Map.get(@outcome_map, outcome, :error)
  def outcome_class(_), do: :error

  @doc "Derives one closed dimension value from an event, its metadata and the collector context."
  @spec dimension_value(atom(), [atom()], map(), map()) :: atom()
  def dimension_value(:component, [_, _, component, _, _], _, _),
    do: component

  def dimension_value(:operation, [_, _, _, operation, _], _, _),
    do: operation

  def dimension_value(:outcome_class, _, meta, _),
    do: outcome_class(Map.get(meta, :outcome))

  def dimension_value(:action, _, meta, _),
    do: closed(Map.get(meta, :operation), @actions)

  def dimension_value(:profile, _, meta, _),
    do: closed(Map.get(meta, :profile), @profiles)

  def dimension_value(:backend_class, _, _, context),
    do: closed(Map.get(context, :backend_class), @backend_classes)

  def dimension_value(:reason, _, meta, _) do
    outcome = Map.get(meta, :outcome)
    if is_atom(outcome), do: Map.get(@reason_map, outcome, :other), else: :other
  end

  def dimension_value(:kind, _, meta, _), do: closed(Map.get(meta, :kind), @kinds)

  @doc "Every metric of this catalogue version."
  @spec metrics() :: [metric()]
  def metrics do
    scenario() ++
      transport() ++
      directory() ++ continuum() ++ nx() ++ conformance() ++ formal() ++ exporter() ++ query()
  end

  @doc "Fetches a metric by id."
  @spec fetch(atom()) :: {:ok, metric()} | {:error, Error.t()}
  def fetch(id) when is_atom(id) do
    case Enum.find(metrics(), &(&1.id == id)) do
      nil -> {:error, Error.new(:unknown_metric, :catalogue, "metric is not in the catalogue")}
      metric -> {:ok, metric}
    end
  end

  def fetch(_), do: {:error, Error.new(:unknown_metric, :catalogue, "metric id must be an atom")}

  @doc "Validates the checked-in catalogue, or a supplied list of metrics."
  @spec validate([metric()]) :: :ok | {:error, Error.t()}
  def validate(metrics \\ metrics()) when is_list(metrics) do
    with :ok <- unique(metrics, :id, :duplicate_metric_id),
         :ok <- unique(metrics, :name, :duplicate_metric_name) do
      Enum.find_value(metrics, :ok, &invalid_metric/1)
    end
  end

  defp invalid_metric(metric) do
    case validate_metric(metric) do
      :ok -> nil
      error -> error
    end
  end

  @doc "Plain definition maps for a host's Telemetry.Metrics or PromEx generation."
  @spec to_definitions() :: [map()]
  def to_definitions do
    Enum.map(metrics(), fn metric ->
      %{
        id: metric.id,
        name: metric.name,
        catalogue_version: @version,
        version: metric.version,
        type: metric.type,
        unit: metric.unit,
        buckets: metric.buckets,
        tags: metric.dimensions,
        tag_values: Map.take(dimensions(), metric.dimensions),
        scope: metric.scope,
        event_names: metric.events,
        measurement: metric.measurement,
        only: metric.only,
        description: metric.description
      }
    end)
  end

  defp scenario do
    spans = spans([:scenario], [:parse, :cleanup])

    [
      counter(:scenario_operations_total, :scenario, [:operation, :outcome_class, :profile], spans,
        description: "Scenario parse and cleanup outcomes."
      ),
      histogram(
        :scenario_duration_seconds,
        :scenario,
        [:operation, :outcome_class, :profile],
        spans,
        description: "Scenario parse and cleanup latency."
      ),
      counter(
        :scenario_cleanup_total,
        :scenario,
        [:outcome_class, :profile],
        spans([:scenario], [:cleanup]),
        description: "Scenario cleanup results."
      )
    ]
  end

  defp transport do
    requests = spans([:runtime, :http, :mqtt], [:request])
    subscriptions = spans([:runtime, :http, :mqtt, :sse], [:subscription])

    [
      counter(
        :transport_requests_total,
        :transport,
        [:component, :action, :outcome_class, :profile],
        requests,
        description: "Runtime and binding requests by outcome."
      ),
      histogram(
        :transport_request_duration_seconds,
        :transport,
        [:component, :outcome_class, :profile],
        requests,
        description: "Request latency per transport."
      ),
      counter(
        :transport_subscriptions_total,
        :transport,
        [:component, :outcome_class, :profile],
        subscriptions,
        description: "Subscription opens (churn) by outcome."
      ),
      counter(
        :transport_subscription_drops_total,
        :transport,
        [:component, :profile],
        measurements([:http, :mqtt, :sse], [:subscription]),
        measurement: :dropped,
        description: "Subscription frames or deliveries dropped."
      ),
      counter(
        :transport_bytes_total,
        :transport,
        [:component, :profile],
        measurements([:sse, :mqtt], [:parse]),
        measurement: :bytes,
        unit: :bytes,
        description: "Bytes parsed from streams."
      )
    ]
  end

  defp directory do
    spans = spans([:directory], [:directory])

    [
      counter(:directory_operations_total, :directory, [:action, :outcome_class, :profile], spans,
        description: "Directory operations by store and outcome."
      ),
      histogram(
        :directory_duration_seconds,
        :directory,
        [:action, :outcome_class, :profile],
        spans,
        description: "Directory operation latency."
      ),
      counter(:directory_conflicts_total, :directory, [:action, :profile], spans,
        only: %{outcome_class: [:conflict]},
        description: "Directory conditional-write conflicts."
      )
    ]
  end

  defp continuum do
    codec = spans([:continuum], [:codec])

    [
      counter(:continuum_codec_total, :continuum, [:action, :outcome_class], codec,
        description: "Continuum encode and decode outcomes."
      ),
      histogram(:continuum_codec_duration_seconds, :continuum, [:action, :outcome_class], codec,
        description: "Continuum codec latency."
      ),
      counter(
        :continuum_bytes_total,
        :continuum,
        [:action],
        measurements([:continuum], [:codec]),
        measurement: :bytes,
        unit: :bytes,
        description: "Continuum wire bytes."
      ),
      counter(
        :continuum_deliveries_total,
        :continuum,
        [:outcome_class],
        measurements([:continuum], [:dispatch]),
        measurement: :deliveries,
        description: "Continuum channel deliveries, rejections and drops."
      ),
      counter(:policy_dispatches_total, :continuum, [:outcome_class], spans([:policy], [:dispatch]),
        description: "Policy Action dispatch outcomes."
      )
    ]
  end

  defp nx do
    spans = spans([:nx], [:encode, :inference, :decode])
    encode = measurements([:nx], [:encode])
    dims = [:operation, :outcome_class, :profile, :backend_class]

    [
      counter(:nx_operations_total, :nx, dims, spans,
        description: "Nx admission (encode), inference and decode outcomes."
      ),
      histogram(:nx_duration_seconds, :nx, dims, spans,
        description: "Nx encode, inference and decode latency."
      ),
      counter(:nx_rows_total, :nx, [:profile, :backend_class], encode,
        measurement: :rows,
        unit: :rows,
        description: "Rows admitted into batches."
      ),
      gauge(:nx_batch_rows, :nx, [:profile], encode,
        measurement: :rows,
        unit: :rows,
        description: "Rows in the last encoded batch."
      ),
      gauge(:nx_batch_width, :nx, [:profile], encode,
        measurement: :width,
        description: "Feature width of the last encoded batch."
      ),
      gauge(:nx_batch_fill_ratio, :nx, [:profile], encode,
        measurement: :fill,
        unit: :ratio,
        description: "Rows over schema capacity for the last batch."
      ),
      gauge(:nx_mask_observed_ratio, :nx, [:profile], encode,
        measurement: :mask_observed,
        unit: :ratio,
        description: "Observed (mask 1) share of the last batch."
      ),
      gauge(:nx_quality_mean_ratio, :nx, [:profile], encode,
        measurement: :quality,
        unit: :ratio,
        description: "Mean batch quality: good 1, uncertain 0.5, bad or missing 0."
      ),
      gauge(:nx_queue_depth, :nx, [:profile], measurements([:nx], [:inference]),
        measurement: :queue_depth,
        description: "Inference requests waiting; direct non-queued profiles report zero."
      )
    ]
  end

  defp conformance do
    spans = spans([:conformance], [:conformance])

    [
      counter(:conformance_outcomes_total, :conformance, [:outcome_class, :action], spans,
        description: "Conformance target outcomes."
      ),
      counter(:conformance_reasons_total, :conformance, [:reason], spans,
        only: %{reason: @reasons -- [:none]},
        description: "Conformance non-pass reasons."
      ),
      histogram(:conformance_duration_seconds, :conformance, [:outcome_class], spans,
        description: "Conformance vector latency."
      )
    ]
  end

  defp formal do
    spans = spans([:formal], [:verification])

    [
      counter(:formal_verification_total, :formal, [:outcome_class, :profile], spans,
        description: "Formal verification outcomes."
      ),
      histogram(:formal_verification_duration_seconds, :formal, [:outcome_class, :profile], spans,
        buckets: @long_duration_buckets,
        description: "Formal verification duration."
      ),
      gauge(
        :formal_verification_budget_ratio,
        :formal,
        [:profile],
        measurements([:formal], [:verification]),
        measurement: :budget_used,
        unit: :ratio,
        description: "Share of the verification budget used."
      )
    ]
  end

  defp exporter do
    spans = spans([:metrics], [:export])
    measurements = measurements([:metrics], [:export])

    [
      counter(:exporter_exports_total, :exporter, [:outcome_class, :profile], spans,
        description: "Snapshot exports by outcome."
      ),
      histogram(:exporter_export_duration_seconds, :exporter, [:outcome_class, :profile], spans,
        buckets: @long_duration_buckets,
        description: "Export round-trip latency."
      ),
      gauge(:exporter_backlog, :exporter, [:profile], measurements,
        measurement: :backlog,
        description: "Snapshots queued for export."
      ),
      counter(:exporter_dropped_snapshots_total, :exporter, [:profile], measurements,
        measurement: :dropped,
        description: "Snapshots dropped by the exporter."
      ),
      counter(:exporter_bytes_total, :exporter, [:profile], measurements,
        measurement: :bytes,
        unit: :bytes,
        description: "Remote-write bytes sent."
      )
    ]
  end

  defp query do
    queries = spans([:metrics], [:query])
    investigations = spans([:metrics], [:investigation])
    budget = measurements([:metrics], [:investigation])

    [
      counter(:query_total, :query, [:outcome_class, :profile], queries,
        description: "Metric queries by outcome."
      ),
      histogram(:query_duration_seconds, :query, [:outcome_class, :profile], queries,
        description: "Metric query latency."
      ),
      histogram(:query_points, :query, [:profile], measurements([:metrics], [:query]),
        measurement: :points,
        unit: :count,
        buckets: @points_buckets,
        description: "Points returned per query."
      ),
      counter(:investigation_total, :query, [:outcome_class, :profile], investigations,
        description: "AI investigations by outcome."
      ),
      histogram(:investigation_duration_seconds, :query, [:outcome_class, :profile], investigations,
        buckets: @long_duration_buckets,
        description: "Investigation duration."
      ),
      histogram(:investigation_tool_calls, :query, [:profile], budget,
        measurement: :tool_calls,
        unit: :count,
        buckets: @tool_call_buckets,
        description: "Tool calls per investigation."
      ),
      histogram(:investigation_context_bytes, :query, [:profile], budget,
        measurement: :context_bytes,
        unit: :bytes,
        buckets: @context_buckets,
        description: "Admitted context bytes per investigation."
      )
    ]
  end

  defp counter(id, group, dimensions, events, opts),
    do: metric(id, group, :counter, dimensions, events, opts)

  defp gauge(id, group, dimensions, events, opts),
    do: metric(id, group, :gauge, dimensions, events, opts)

  defp histogram(id, group, dimensions, events, opts) do
    opts =
      opts
      |> Keyword.put_new(:buckets, @duration_buckets)
      |> Keyword.put_new(:measurement, :duration)
      |> Keyword.put_new(:unit, :seconds)

    metric(id, group, :histogram, dimensions, events, opts)
  end

  defp metric(id, group, type, dimensions, events, opts) do
    %{
      id: id,
      group: group,
      name: @prefix <> Atom.to_string(id),
      version: Keyword.get(opts, :version, @version),
      type: type,
      unit: Keyword.get(opts, :unit, :count),
      buckets: Keyword.get(opts, :buckets),
      dimensions: dimensions,
      scope: Keyword.get(opts, :scope, :instance),
      events: events,
      measurement: Keyword.get(opts, :measurement),
      only: Keyword.get(opts, :only, %{}),
      description: Keyword.fetch!(opts, :description)
    }
  end

  defp spans(components, operations) do
    for component <- components,
        operation <- operations,
        kind <- [:stop, :exception],
        do: [:wotex, :lab, component, operation, kind]
  end

  defp measurements(components, operations) do
    for component <- components,
        operation <- operations,
        do: [:wotex, :lab, component, operation, :measurement]
  end

  defp unique(metrics, key, code) do
    values = Enum.map(metrics, &Map.get(&1, key))

    if values == Enum.uniq(values),
      do: :ok,
      else: {:error, Error.new(code, :catalogue, "catalogue #{key}s must be unique")}
  end

  defp validate_metric(%{id: id} = metric) when is_atom(id) do
    checks = [
      {metric.type in @types, :invalid_type, "type must be counter, gauge or histogram"},
      {metric.unit in @units, :invalid_unit, "unit is outside the closed unit set"},
      {name?(metric), :invalid_name, "name must carry the prefix, type and unit suffix"},
      {buckets?(metric), :invalid_buckets, "histogram buckets must be sorted positive numbers"},
      {dimensions?(metric.dimensions), :invalid_dimension, "dimension is not a closed enum"},
      {only?(metric), :invalid_filter, "filter must select closed dimension values"},
      {metric.scope in @scopes, :invalid_scope, "scope must be instance or host"},
      {events?(metric.events), :invalid_event, "source event is outside the Lab vocabulary"},
      {measurement?(metric), :invalid_measurement, "measurement does not fit unit or events"},
      {version?(metric.version), :invalid_version, "metric version is newer than the catalogue"},
      {is_binary(metric.description), :invalid_description, "description must be text"}
    ]

    Enum.find_value(checks, :ok, fn
      {true, _, _} -> nil
      {false, code, message} -> {:error, Error.new(code, :catalogue, message, details: %{id: id})}
    end)
  end

  defp validate_metric(_),
    do: {:error, Error.new(:invalid_metric, :catalogue, "metric must be a map with an atom id")}

  defp name?(%{name: name, type: type, unit: unit}) when is_binary(name) do
    Regex.match?(~r/\Awotex_lab_[a-z][a-z0-9_]*\z/, name) and
      String.ends_with?(name, "_total") == (type == :counter) and
      suffix?(name, unit)
  end

  defp name?(_), do: false

  defp suffix?(name, :seconds), do: String.contains?(name, "_seconds")
  defp suffix?(name, :bytes), do: String.contains?(name, "_bytes")
  defp suffix?(name, :ratio), do: String.ends_with?(name, "_ratio")
  defp suffix?(name, _), do: not String.contains?(name, ["_seconds", "_bytes", "_ratio"])

  defp buckets?(%{type: :histogram, buckets: buckets}) when is_list(buckets) do
    buckets != [] and length(buckets) <= @max_buckets and
      Enum.all?(buckets, &(is_number(&1) and &1 > 0)) and
      buckets == Enum.sort(buckets) and buckets == Enum.uniq(buckets)
  end

  defp buckets?(%{type: :histogram}), do: false
  defp buckets?(%{buckets: nil}), do: true
  defp buckets?(_), do: false

  defp dimensions?(dimensions) when is_list(dimensions) do
    known = Map.keys(dimensions())
    dimensions == Enum.uniq(dimensions) and Enum.all?(dimensions, &(&1 in known))
  end

  defp dimensions?(_), do: false

  defp only?(%{only: only}) when is_map(only) do
    enums = dimensions()

    Enum.all?(only, fn {dimension, values} ->
      Map.has_key?(enums, dimension) and is_list(values) and values != [] and
        Enum.all?(values, &(&1 in Map.get(enums, dimension, [])))
    end)
  end

  defp only?(_), do: false

  defp events?(events) when is_list(events) and events != [] do
    Enum.all?(events, fn
      [:wotex, :lab, component, operation, kind] ->
        component in Telemetry.components() and operation in Telemetry.operations() and
          kind in @event_kinds

      _ ->
        false
    end)
  end

  defp events?(_), do: false

  defp measurement?(%{measurement: nil, type: :counter, unit: :count}), do: true
  defp measurement?(%{measurement: nil}), do: false

  defp measurement?(%{measurement: :duration, unit: :seconds, events: events}),
    do: Enum.all?(events, &(List.last(&1) in [:stop, :exception]))

  defp measurement?(%{measurement: :duration}), do: false
  defp measurement?(%{unit: :seconds}), do: false

  defp measurement?(%{measurement: measurement, events: events}) when is_atom(measurement),
    do: Enum.all?(events, &(List.last(&1) == :measurement))

  defp measurement?(_), do: false

  defp version?(version) when is_binary(version) do
    match?({:ok, _}, Version.parse(version)) and Version.compare(version, @version) != :gt
  end

  defp version?(_), do: false

  defp closed(value, enum) when is_atom(value) do
    if value in enum, do: value, else: :other
  end

  defp closed(_, _), do: :other
end
