defmodule Wotex.Lab.MetricsCollectorTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab
  alias Wotex.Lab.Adapters.Runtime.{Loopback, StaticRef}
  alias Wotex.Lab.Error
  alias Wotex.Lab.Examples.Thermal
  alias Wotex.Lab.Metrics.{Collector, Snapshot}
  alias Wotex.Lab.Reference.Thing
  alias Wotex.Runtime.{BindingProfile, ConsumedThing, Context}
  alias Wotex.ThingDescription

  @credential "secret-credential-2b7c"
  @payload "payload-sentinel-91ee"
  @encode_stop [:wotex, :lab, :nx, :encode, :stop]
  @encode_measurement [:wotex, :lab, :nx, :encode, :measurement]

  defp native(ms), do: System.convert_time_unit(ms, :millisecond, :native)

  defp series(snapshot, name, labels) do
    Enum.find(snapshot.series, &(&1.name == name and Enum.all?(labels, fn l -> l in &1.labels end)))
  end

  test "aggregates real Lab telemetry from the thermal example and the loopback lane" do
    lab = start_supervised!({Lab, id: "metrics-collector", max_children: 8})

    {:ok, collector} =
      Lab.start_child(lab, :sessions, {Collector, id: :metrics, backend_class: :binary})

    assert {:ok, _result} = Thermal.run()
    assert {:ok, _result} = loopback_request(lab)
    assert {:ok, %Snapshot{} = snapshot} = Collector.snapshot(collector)

    assert snapshot.source == :collector and snapshot.sequence == 1 and snapshot.instance_slot == 0
    assert %{started_at: started, generation: 0} = snapshot.identity
    assert is_integer(started) and is_integer(snapshot.monotonic_ms)

    thermal = [{"operation", "inference"}, {"profile", "thermal"}, {"backend_class", "binary"}]
    assert %{sample: %{value: count}} = series(snapshot, "wotex_lab_nx_operations_total", thermal)
    assert count >= 1

    encode = series(snapshot, "wotex_lab_nx_duration_seconds", [{"operation", "encode"}])
    assert encode.sample.count >= 1 and is_number(encode.sample.sum)
    assert {:infinity, 1} = List.last(encode.sample.buckets)
    assert %{sample: %{value: 2}} = series(snapshot, "wotex_lab_nx_batch_rows", [])
    assert %{sample: %{value: 2}} = series(snapshot, "wotex_lab_nx_rows_total", [])
    assert %{sample: %{value: 1}} = series(snapshot, "wotex_lab_nx_batch_fill_ratio", [])

    runtime = [{"component", "runtime"}, {"action", "readproperty"}, {"outcome_class", "ok"}]

    assert %{sample: %{value: requests}} =
             series(snapshot, "wotex_lab_transport_requests_total", runtime)

    assert requests >= 1
    assert series(snapshot, "wotex_lab_scenario_operations_total", [{"operation", "parse"}])

    text = inspect(snapshot, limit: :infinity)
    refute text =~ @credential
    refute text =~ @payload
    refute text =~ "urn:wotex:lab"

    for %{labels: labels} <- snapshot.series, {name, value} <- labels do
      assert name in ~w(action backend_class component operation outcome_class profile reason kind)
      assert byte_size(value) < 32
    end

    stats = Collector.stats(collector)
    assert stats.series_used > 0 and stats.series_used <= stats.series_budget
    assert stats.dropped_series == 0

    handler_id = {Collector, collector}
    assert Enum.any?(:telemetry.list_handlers(@encode_stop), &(&1.id == handler_id))
    :ok = GenServer.stop(collector)
    refute Enum.any?(:telemetry.list_handlers(@encode_stop), &(&1.id == handler_id))
  end

  test "counters are cumulative with a reset identity and histograms use catalogue buckets" do
    collector = start_supervised!({Collector, id: :reset, series_budget: 64})
    meta = %{profile: :test, outcome: :ok}

    :telemetry.execute(@encode_stop, %{duration: native(2)}, meta)
    :telemetry.execute(@encode_stop, %{duration: native(30)}, meta)
    :telemetry.execute(@encode_stop, %{duration: native(30_000)}, meta)

    {:ok, first} = Collector.snapshot(collector)
    counter = series(first, "wotex_lab_nx_operations_total", [{"operation", "encode"}])
    assert counter.sample.value == 3

    histogram = series(first, "wotex_lab_nx_duration_seconds", [{"operation", "encode"}])
    assert histogram.sample.count == 3 and histogram.sample.sum == 30.032

    assert histogram.sample.buckets == [
             {0.001, 0},
             {0.005, 1},
             {0.025, 1},
             {0.1, 2},
             {0.5, 2},
             {2.5, 2},
             {10, 2},
             {:infinity, 3}
           ]

    :telemetry.execute(@encode_stop, %{duration: native(1)}, meta)
    {:ok, second} = Collector.snapshot(collector)

    assert series(second, "wotex_lab_nx_operations_total", [{"operation", "encode"}]).sample.value ==
             4

    assert second.sequence == 2 and second.identity == first.identity

    :ok = Collector.reset(collector)
    :telemetry.execute(@encode_stop, %{duration: native(1)}, meta)
    {:ok, third} = Collector.snapshot(collector)
    assert third.identity.generation == 1 and third.identity.started_at == first.identity.started_at

    assert series(third, "wotex_lab_nx_operations_total", [{"operation", "encode"}]).sample.value ==
             1

    assert third.counters.resets == 1
    assert Collector.stats(collector).generation == 1

    assert [%{sample: %{value: :stale}}] =
             Snapshot.stale_markers(first, %{third | series: []})
             |> Enum.filter(&(&1.name == "wotex_lab_nx_operations_total"))

    assert [%{sample: %{stale: true, sum: :stale, count: 0}}] =
             Snapshot.stale_markers(first, %{third | series: []})
             |> Enum.filter(&(&1.name == "wotex_lab_nx_duration_seconds"))

    assert Snapshot.stale_markers(first, first) == []
  end

  test "series beyond the budget are dropped and counted; histograms consume bucket capacity" do
    collector = start_supervised!({Collector, id: :budget, series_budget: 3})
    stop = [:wotex, :lab, :sse, :parse, :measurement]

    for profile <- [:http, :mqtt, :ets, :sqlite, :loopback] do
      :telemetry.execute(stop, %{bytes: 1}, %{profile: profile})
    end

    :telemetry.execute(stop, %{bytes: 1}, %{profile: :http})
    :telemetry.execute(@encode_stop, %{duration: native(1)}, %{profile: :test, outcome: :ok})

    {:ok, snapshot} = Collector.snapshot(collector)
    assert length(snapshot.series) == 3
    assert snapshot.counters.dropped_series >= 3
    assert snapshot.counters.dropped_samples >= 3

    assert series(snapshot, "wotex_lab_transport_bytes_total", [{"profile", "http"}]).sample.value ==
             2

    refute series(snapshot, "wotex_lab_nx_duration_seconds", [])

    assert Collector.stats(collector).series_used == 3
    assert Collector.default_series_budget() == 256 and Collector.max_series_budget() == 4_096
  end

  test "negative durations and invalid measurements are counted, never recorded" do
    collector = start_supervised!({Collector, id: :negative})
    meta = %{profile: :test, outcome: :ok}

    :telemetry.execute(@encode_stop, %{duration: -native(5)}, meta)
    :telemetry.execute(@encode_stop, %{duration: 1.5}, meta)
    :telemetry.execute(@encode_stop, %{}, meta)
    :telemetry.execute(@encode_measurement, %{rows: -1}, %{profile: :test})
    :telemetry.execute(@encode_measurement, %{rows: 2.5}, %{profile: :test})
    :telemetry.execute(@encode_measurement, %{fill: 0.25, queue_depth: 3}, %{profile: :test})

    {:ok, snapshot} = Collector.snapshot(collector)
    assert snapshot.counters.negative_durations == 1
    assert snapshot.counters.invalid_samples == 3
    refute series(snapshot, "wotex_lab_nx_duration_seconds", [])
    refute series(snapshot, "wotex_lab_nx_rows_total", [])
    assert series(snapshot, "wotex_lab_nx_operations_total", []).sample.value == 3
    assert series(snapshot, "wotex_lab_nx_batch_fill_ratio", []).sample.value == 0.25
    refute series(snapshot, "wotex_lab_nx_queue_depth", [])
  end

  test "gauges keep the last value, filters select outcome classes and unknown values map to other" do
    collector = start_supervised!({Collector, id: :gauge})
    directory = [:wotex, :lab, :directory, :directory, :stop]

    :telemetry.execute(@encode_measurement, %{width: 4}, %{profile: :test})
    :telemetry.execute(@encode_measurement, %{width: 9}, %{profile: :test})

    :telemetry.execute(directory, %{duration: native(1)}, %{
      operation: :put,
      profile: :ets,
      outcome: :ok
    })

    :telemetry.execute(directory, %{duration: native(1)}, %{
      operation: :put,
      profile: :sqlite,
      outcome: :revision_mismatch
    })

    :telemetry.execute(directory, %{duration: native(1)}, %{
      operation: "urn:wotex:lab:thing:1",
      profile: :secret_tenant,
      outcome: :private_failure
    })

    {:ok, snapshot} = Collector.snapshot(collector)
    assert series(snapshot, "wotex_lab_nx_batch_width", []).sample.value == 9

    conflicts = Enum.filter(snapshot.series, &(&1.name == "wotex_lab_directory_conflicts_total"))
    assert [%{labels: [{"action", "put"}, {"profile", "sqlite"}], sample: %{value: 1}}] = conflicts

    other = series(snapshot, "wotex_lab_directory_operations_total", [{"profile", "other"}])
    assert other.labels == [{"action", "other"}, {"outcome_class", "error"}, {"profile", "other"}]
    refute inspect(snapshot) =~ "urn:wotex"
  end

  test "a raising handler path is contained and two collectors keep separate budgets" do
    left = start_supervised!({Collector, id: :left, series_budget: 2, instance_slot: 1}, id: :left)

    right =
      start_supervised!({Collector, id: :right, series_budget: 64, instance_slot: 2}, id: :right)

    :telemetry.execute(@encode_stop, %{duration: native(1)}, %{profile: :test, outcome: :ok})
    {:ok, left_snapshot} = Collector.snapshot(left)
    {:ok, right_snapshot} = Collector.snapshot(right)

    assert left_snapshot.instance_slot == 1 and right_snapshot.instance_slot == 2

    assert left_snapshot.counters.dropped_series == 1 and
             right_snapshot.counters.dropped_series == 0

    assert length(right_snapshot.series) == 2

    :ok = GenServer.stop(left)
    :telemetry.execute(@encode_stop, %{duration: native(1)}, %{profile: :test, outcome: :ok})
    {:ok, after_stop} = Collector.snapshot(right)
    assert series(after_stop, "wotex_lab_nx_operations_total", []).sample.value == 2

    table = :ets.new(:dead_config, [:public])
    :ets.delete(table)
    config = %{table: table, index: %{@encode_stop => [%{id: :x}]}, context: %{}}
    assert :ok = Collector.handle_event(@encode_stop, %{duration: 1}, %{}, config)
  end

  test "options are validated and handler ids can be explicit" do
    assert {:error, %Error{code: :invalid_options}} = Collector.start_link(id: :x, secret: "no")
    assert {:error, %Error{code: :invalid_collector}} = Collector.start_link(series_budget: 0)
    assert {:error, %Error{code: :invalid_collector}} = Collector.start_link(series_budget: 5_000)
    assert {:error, %Error{code: :invalid_collector}} = Collector.start_link(instance_slot: -1)
    assert {:error, %Error{code: :invalid_collector}} = Collector.start_link(backend_class: "exla")

    handler = {:explicit, System.unique_integer([:positive])}
    {:ok, first} = Collector.start_link(handler_id: handler)
    assert Enum.any?(:telemetry.list_handlers(@encode_stop), &(&1.id == {Collector, handler}))

    Process.flag(:trap_exit, true)
    assert {:error, %Error{code: :handler_exists}} = Collector.start_link(handler_id: handler)
    :ok = GenServer.stop(first)

    assert %{id: {Collector, :named}, restart: :transient} = Collector.child_spec(id: :named)
    {:ok, named} = Collector.start_link(name: :"collector-#{System.unique_integer([:positive])}")
    :ok = GenServer.stop(named)
  end

  test "snapshot admission refuses malformed values with a pointer path" do
    base = %{
      source: :collector,
      instance_slot: 0,
      sequence: 1,
      monotonic_ms: 0,
      wall_time_ms: 1,
      series: []
    }

    counter = %{name: "a_total", type: :counter, labels: [{"k", "v"}], sample: %{value: 1}}
    assert {:ok, %Snapshot{}} = Snapshot.new(base)
    assert {:ok, %Snapshot{}} = Snapshot.new(%{base | series: [counter]})

    cases = [
      {%{base | source: :promex}, :invalid_source, "/source"},
      {%{base | instance_slot: 70_000}, :invalid_instance_slot, "/instance_slot"},
      {%{base | sequence: -1}, :invalid_sequence, "/sequence"},
      {%{base | monotonic_ms: nil}, :invalid_time, "/monotonic_ms"},
      {%{base | wall_time_ms: -1}, :invalid_time, "/wall_time_ms"},
      {Map.put(base, :identity, %{started_at: 1}), :invalid_identity, "/identity"},
      {Map.put(base, :counters, %{"x" => 1}), :invalid_counters, "/counters"},
      {Map.put(base, :counters, []), :invalid_counters, "/counters"},
      {Map.put(base, :schema_version, "2.0.0"), :unsupported_schema_version, ""},
      {%{base | series: :none}, :invalid_series, "/series"},
      {%{base | series: [%{name: "a"}]}, :invalid_series, "/series/0"},
      {%{base | series: [%{counter | name: "1bad"}]}, :invalid_name, "/series/0/name"},
      {%{base | series: [%{counter | type: :summary}]}, :invalid_type, "/series/0/type"},
      {%{base | series: [%{counter | labels: [{"b", "1"}, {"a", "1"}]}]}, :unsorted_labels,
       "/series/0/labels"},
      {%{base | series: [%{counter | labels: [{"a", "1"}, {"a", "2"}]}]}, :duplicate_label,
       "/series/0/labels"},
      {%{base | series: [%{counter | labels: [{"a", 1}]}]}, :invalid_label, "/series/0/labels"},
      {%{base | series: [%{counter | labels: %{}}]}, :invalid_label, "/series/0/labels"},
      {%{base | series: [%{counter | sample: %{value: -1}}]}, :invalid_sample, "/series/0/sample"},
      {%{base | series: [%{counter | sample: %{value: "1"}}]}, :invalid_sample, "/series/0/sample"},
      {%{base | series: [%{counter | sample: %{buckets: []}}]}, :invalid_sample,
       "/series/0/sample"},
      {%{base | series: [counter, counter]}, :duplicate_series, "/series"}
    ]

    for {fields, code, path} <- cases do
      assert {:error, %Error{code: ^code, path: ^path}} = Snapshot.new(fields), "expected #{code}"
    end

    histogram = %{
      name: "h",
      type: :histogram,
      labels: [],
      sample: %{buckets: [{1, 1}, {:infinity, 2}], sum: 1.5, count: 2}
    }

    assert {:ok, _snapshot} = Snapshot.new(%{base | series: [histogram]})

    for sample <- [
          %{buckets: [{1, 1}], sum: 1, count: 1},
          %{buckets: [{1, 3}, {:infinity, 2}], sum: 1, count: 2},
          %{buckets: [{2, 1}, {1, 1}, {:infinity, 2}], sum: 1, count: 2},
          %{buckets: [{1, 1}, {:infinity, 2}], sum: 1, count: 3},
          %{buckets: [{1, 1}, {:infinity, 2}], sum: "1", count: 2},
          %{buckets: [{"1", 1}, {:infinity, 2}], sum: 1, count: 2},
          %{buckets: [{1, 1}, {:infinity, 2}], sum: 1, count: 2, extra: true}
        ] do
      assert {:error, %Error{code: :invalid_sample}} =
               Snapshot.new(%{base | series: [%{histogram | sample: sample}]})
    end

    assert {:error, %Error{code: :invalid_snapshot}} = Snapshot.new([])

    assert Snapshot.number(2.0) == 2 and Snapshot.number(2.5) == 2.5 and
             Snapshot.number(:nan) == :nan

    assert Snapshot.value?(:stale) and not Snapshot.value?("1")
    assert Snapshot.schema_version() == "1.0.0"
  end

  defp loopback_request(lab) do
    {:ok, json} =
      File.read(Application.app_dir(:wotex_lab, "priv/fixtures/loopback/thing-description.json"))

    {:ok, td} = ThingDescription.parse(json)

    {:ok, host} =
      Lab.start_child(
        lab,
        :things,
        {Thing,
         td: td,
         state: %{"temperature" => 20.0, "target" => @payload},
         tokens: %{"bearer_sc" => @credential}}
      )

    {:ok, profile} =
      BindingProfile.new(
        id: :loopback,
        schemes: ["loopback"],
        operations: Wotex.Runtime.operations()
      )

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{loopback: {Loopback, %{host: host}}},
        credentials:
          {StaticRef,
           %{references: %{"bearer_sc" => "ref"}, lookup: fn "ref" -> {:ok, @credential} end}}
      )

    ConsumedThing.read_property(consumed, "target", Context.new!(request_id: "metrics-read"))
  end
end
