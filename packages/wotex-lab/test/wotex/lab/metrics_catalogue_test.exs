defmodule Wotex.Lab.MetricsCatalogueTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.{Error, Telemetry}
  alias Wotex.Lab.Metrics.Catalogue

  @groups ~w(scenario transport directory continuum nx conformance formal exporter query)a
  @forbidden ~w(thing_id run_id topic url prompt principal error reason_text scenario_id)a

  test "the checked-in catalogue validates and covers every required group" do
    assert :ok = Catalogue.validate()
    assert {:ok, _} = Version.parse(Catalogue.version())
    metrics = Catalogue.metrics()
    assert Enum.sort(Enum.uniq(Enum.map(metrics, & &1.group))) == Enum.sort(@groups)
    assert length(metrics) > 30

    ids = ~w(scenario_cleanup_total transport_subscription_drops_total directory_conflicts_total
      continuum_deliveries_total nx_duration_seconds nx_batch_fill_ratio nx_mask_observed_ratio
      nx_quality_mean_ratio nx_queue_depth conformance_reasons_total
      formal_verification_duration_seconds exporter_backlog exporter_dropped_snapshots_total
      query_total investigation_tool_calls)a

    for id <- ids, do: assert({:ok, %{id: ^id}} = Catalogue.fetch(id))
    assert {:error, %Error{code: :unknown_metric}} = Catalogue.fetch(:nope)
    assert {:error, %Error{code: :unknown_metric}} = Catalogue.fetch("nx_duration_seconds")
  end

  test "dimensions are closed enums and never identifiers, topics, URLs or free text" do
    dimensions = Catalogue.dimensions()
    assert dimensions.component == Telemetry.components()
    assert dimensions.operation == Telemetry.operations()
    assert :other in dimensions.profile and :other in dimensions.action

    for metric <- Catalogue.metrics(), dimension <- metric.dimensions do
      assert Map.has_key?(dimensions, dimension)
      refute dimension in @forbidden
    end

    for {_, values} <- dimensions, value <- values, do: assert(is_atom(value))
  end

  test "outcome atoms map to a finite class and never pass through" do
    assert Catalogue.outcome_class(:ok) == :ok
    assert Catalogue.outcome_class(:capacity_exhausted) == :unavailable
    assert Catalogue.outcome_class(:revision_mismatch) == :conflict
    assert Catalogue.outcome_class(:deadline_exceeded) == :timeout
    assert Catalogue.outcome_class(:some_private_error_code) == :error
    assert Catalogue.outcome_class("urn:wotex:lab:thing:1") == :error
    assert Catalogue.outcome_class(nil) == :error

    event = [:wotex, :lab, :nx, :encode, :stop]
    meta = %{outcome: :dtype_mismatch, operation: :readproperty, profile: :thermal, kind: :throw}
    assert Catalogue.dimension_value(:component, event, meta, %{}) == :nx
    assert Catalogue.dimension_value(:operation, event, meta, %{}) == :encode
    assert Catalogue.dimension_value(:outcome_class, event, meta, %{}) == :error
    assert Catalogue.dimension_value(:action, event, meta, %{}) == :readproperty
    assert Catalogue.dimension_value(:action, event, %{operation: "setTarget"}, %{}) == :other
    assert Catalogue.dimension_value(:profile, event, meta, %{}) == :thermal
    assert Catalogue.dimension_value(:profile, event, %{profile: :private}, %{}) == :other
    assert Catalogue.dimension_value(:backend_class, event, meta, %{backend_class: :exla}) == :exla
    assert Catalogue.dimension_value(:backend_class, event, meta, %{backend_class: :cuda}) == :other
    assert Catalogue.dimension_value(:reason, event, %{outcome: :timeout}, %{}) == :timeout
    assert Catalogue.dimension_value(:reason, event, %{outcome: :weird}, %{}) == :other
    assert Catalogue.dimension_value(:reason, event, %{outcome: "text"}, %{}) == :other
    assert Catalogue.dimension_value(:kind, event, meta, %{}) == :throw
    assert Catalogue.dimension_value(:kind, event, %{}, %{}) == :other
  end

  test "definitions are plain maps with versioned names, units, buckets and tag values" do
    definitions = Catalogue.to_definitions()
    assert length(definitions) == length(Catalogue.metrics())

    definition = Enum.find(definitions, &(&1.id == :nx_duration_seconds))
    assert definition.name == "wotex_lab_nx_duration_seconds"
    assert definition.catalogue_version == Catalogue.version()
    assert definition.type == :histogram and definition.unit == :seconds
    assert definition.buckets == Enum.sort(definition.buckets)
    assert definition.tag_values.operation == Telemetry.operations()
    assert [:wotex, :lab, :nx, :encode, :stop] in definition.event_names
    assert definition.measurement == :duration and definition.scope == :instance

    counter = Enum.find(definitions, &(&1.id == :directory_conflicts_total))
    assert counter.only == %{outcome_class: [:conflict]}
    assert counter.buckets == nil and counter.measurement == nil
  end

  test "validation fails on duplicate ids or names" do
    [first | rest] = Catalogue.metrics()
    assert {:error, %Error{code: :duplicate_metric_id}} = Catalogue.validate([first, first | rest])

    renamed = %{first | id: :another_id}
    assert {:error, %Error{code: :duplicate_metric_name}} = Catalogue.validate([first, renamed])
  end

  test "validation fails on name, unit, bucket, dimension, scope, event and measurement mismatch" do
    {:ok, histogram} = Catalogue.fetch(:nx_duration_seconds)
    {:ok, counter} = Catalogue.fetch(:nx_operations_total)
    {:ok, gauge} = Catalogue.fetch(:nx_queue_depth)

    cases = [
      {%{counter | name: "wotex_lab_nx_operations"}, :invalid_name},
      {%{counter | name: "nx_operations_total"}, :invalid_name},
      {%{histogram | name: "wotex_lab_nx_duration"}, :invalid_name},
      {%{histogram | name: "wotex_lab_nx_duration_seconds_total"}, :invalid_name},
      {%{counter | name: 12}, :invalid_name},
      {%{counter | type: :summary}, :invalid_type},
      {%{gauge | unit: :celsius}, :invalid_unit},
      {%{histogram | buckets: [1.0, 0.5]}, :invalid_buckets},
      {%{histogram | buckets: []}, :invalid_buckets},
      {%{histogram | buckets: [0.1, 0.1]}, :invalid_buckets},
      {%{histogram | buckets: [-1.0, 1.0]}, :invalid_buckets},
      {%{histogram | buckets: nil}, :invalid_buckets},
      {%{counter | buckets: [1.0]}, :invalid_buckets},
      {%{counter | dimensions: [:thing_id]}, :invalid_dimension},
      {%{counter | dimensions: [:profile, :profile]}, :invalid_dimension},
      {%{counter | dimensions: :profile}, :invalid_dimension},
      {%{counter | only: %{outcome_class: [:whatever]}}, :invalid_filter},
      {%{counter | only: %{thing_id: [:x]}}, :invalid_filter},
      {%{counter | only: %{outcome_class: []}}, :invalid_filter},
      {%{counter | only: [:conflict]}, :invalid_filter},
      {%{counter | scope: :tenant}, :invalid_scope},
      {%{counter | events: [[:wotex, :lab, :nx, :encode, :begin]]}, :invalid_event},
      {%{counter | events: [[:wotex, :lab, :private, :encode, :stop]]}, :invalid_event},
      {%{counter | events: [[:other, :app, :nx, :encode, :stop]]}, :invalid_event},
      {%{counter | events: []}, :invalid_event},
      {%{counter | events: [:wotex]}, :invalid_event},
      {%{gauge | measurement: nil}, :invalid_measurement},
      {%{histogram | measurement: :duration, events: gauge.events}, :invalid_measurement},
      {%{histogram | measurement: :rows}, :invalid_measurement},
      {%{gauge | unit: :seconds, name: "wotex_lab_nx_queue_seconds"}, :invalid_measurement},
      {%{gauge | measurement: "queue"}, :invalid_measurement},
      {%{counter | version: "9.0.0"}, :invalid_version},
      {%{counter | version: "latest"}, :invalid_version},
      {%{counter | description: nil}, :invalid_description}
    ]

    for {metric, code} <- cases do
      assert {:error, %Error{code: ^code, phase: :catalogue}} = Catalogue.validate([metric]),
             "expected #{code} for #{inspect(metric, limit: 5)}"
    end

    assert {:error, %Error{code: :invalid_metric}} = Catalogue.validate([%{name: "x"}])
    assert :ok = Catalogue.validate([histogram, counter, gauge])
  end
end
