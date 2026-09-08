defmodule Wotex.Lab.MetricsQueryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{History, Query, Snapshot}

  @t0 1_700_000_000_000
  @step 5_000
  @scope %{instance: "lab-1", session: "session-1"}
  @labels [
    {"backend_class", "binary"},
    {"operation", "encode"},
    {"outcome_class", "ok"},
    {"profile", "test"}
  ]

  defp at(offset_ms), do: DateTime.from_unix!(@t0 + offset_ms, :millisecond)

  defp gauge(value),
    do: %{
      name: "wotex_lab_nx_queue_depth",
      type: :gauge,
      labels: [{"profile", "test"}],
      sample: %{value: value}
    }

  defp counter(value, labels \\ @labels),
    do: %{
      name: "wotex_lab_nx_operations_total",
      type: :counter,
      labels: labels,
      sample: %{value: value}
    }

  defp histogram(counts, sum) do
    buckets = Enum.zip([0.001, 0.005, 0.025, 0.1, 0.5, 2.5, 10, :infinity], counts)

    %{
      name: "wotex_lab_nx_duration_seconds",
      type: :histogram,
      labels: @labels,
      sample: %{buckets: buckets, sum: sum, count: List.last(counts)}
    }
  end

  defp store(history, index, series, generation) do
    {:ok, snapshot} =
      Snapshot.new(%{
        source: :collector,
        instance_slot: 0,
        sequence: index + 1,
        monotonic_ms: index * @step,
        wall_time_ms: @t0 + index * @step,
        identity: %{started_at: 1, generation: generation},
        series: series
      })

    {:ok, _admission} = History.put(history, snapshot)
  end

  defp seed(history) do
    other = List.keyreplace(@labels, "operation", 0, {"operation", "decode"})

    for index <- 0..9 do
      generation = if index >= 5, do: 1, else: 0
      counter_value = if index >= 5, do: 5 + (index - 5) * 10, else: 10 + index * 10
      gauge_value = if index == 7, do: :stale, else: index + 1

      hist =
        histogram(
          [index, index * 2, index * 3, index * 4, index * 4, index * 4, index * 4, index * 4 + 1],
          index * 0.5
        )

      store(
        history,
        index,
        [gauge(gauge_value), counter(counter_value), counter(index, other), hist],
        generation
      )
    end

    history
  end

  defp query!(opts) do
    {:ok, query} =
      Query.new(
        Keyword.merge([scope: @scope, start_at: at(0), end_at: at(45_000), step_ms: @step], opts)
      )

    query
  end

  test "an empty histogram query reports no data instead of crashing" do
    history = start_supervised!({History, id: :empty_histogram, instance: "lab-1"})

    assert {:ok, %{points: [], freshness: nil, series_matched: 0}} =
             History.query(
               history,
               query!(metric: :nx_duration_seconds, aggregation: :histogram_quantile, quantile: 0.5)
             )
  end

  test "counter increases retain resets and multiple samples inside the same query bucket" do
    history = start_supervised!({History, id: :within_bucket, instance: "lab-1"})
    store(history, 0, [counter(10)], 0)
    store(history, 1, [counter(50)], 0)
    store(history, 2, [counter(5)], 1)
    store(history, 3, [counter(15)], 1)

    assert {:ok, response} =
             History.query(
               history,
               query!(metric: :nx_operations_total, aggregation: :increase, step_ms: 15_000)
             )

    assert Enum.map(response.points, & &1.value) == [0, 55]
  end

  test "query text cannot substitute another history instance" do
    history = start_supervised!({History, id: :bound, instance: "lab-1"})
    store(history, 0, [gauge(91)], 0)

    assert {:error, %Error{code: :scope_denied}} =
             History.query(
               history,
               query!(
                 metric: :nx_queue_depth,
                 aggregation: :last,
                 scope: %{instance: "lab-2", session: "session-1"}
               )
             )
  end

  test "unbound storage cannot claim a query scope and forged descriptors never execute" do
    unbound = start_supervised!({History, id: :unbound})
    descriptor = query!(metric: :nx_queue_depth, aggregation: :last)
    assert {:error, %Error{code: :scope_unbound}} = History.query(unbound, descriptor)
    bound = start_supervised!({History, id: :forge, instance: "lab-1"})

    for forged <- [
          nil,
          %{},
          %{descriptor | step_ms: 0},
          %{descriptor | schema_version: "99"},
          %{descriptor | limits: %{points: -1}},
          %{descriptor | start_at: nil}
        ] do
      assert {:error, %Error{}} = History.query(bound, forged)
      assert {:error, %Error{}} = Query.estimate(forged)
    end

    assert History.stats(bound).active_queries == 0
    :ok = stop_supervised({History, :forge})
    assert {:error, %Error{code: :history_unavailable}} = History.query(bound, descriptor)
  end

  test "query leases have a global ceiling, expire on caller death and leave no session keys" do
    history = start_supervised!({History, id: :leases, instance: "lab-1", max_queries: 1})
    owner = self()

    {holder, monitor} =
      spawn_monitor(fn ->
        {:ok, _table, token} = GenServer.call(history, {:acquire, @scope, 2})
        send(owner, {:leased, token})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:leased, token}
    assert History.stats(history).active_queries == 1
    assert {:error, %Error{code: :scope_denied}} = GenServer.call(history, {:release, token})

    descriptor =
      query!(
        metric: :nx_queue_depth,
        aggregation: :last,
        scope: %{instance: "lab-1", session: "other-session"}
      )

    assert {:error, %Error{code: :too_many_queries}} = History.query(history, descriptor)
    Process.exit(holder, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^holder, :killed}
    await_idle(history)

    for index <- 1..100 do
      assert {:ok, _result} =
               History.query(
                 history,
                 %{descriptor | scope: %{instance: "lab-1", session: "session-#{index}"}}
               )
    end

    assert History.stats(history).active_queries == 0
  end

  test "histogram deltas include every reset within a bucket and stale is not a new zero" do
    history = start_supervised!({History, id: :histogram_resets, instance: "lab-1"})
    low = fn count -> histogram(List.duplicate(count, 8), count * 0.001) end
    high = fn count -> histogram([0, 0, 0, count, count, count, count, count], count * 0.1) end
    store(history, 0, [low.(10)], 0)
    store(history, 1, [low.(50)], 0)
    store(history, 2, [high.(5)], 1)
    store(history, 3, [high.(15)], 1)
    stale = %{high.(0) | sample: Map.merge(high.(0).sample, %{sum: :stale, stale: true})}
    store(history, 4, [stale], 1)

    descriptor =
      query!(
        metric: :nx_duration_seconds,
        aggregation: :histogram_quantile,
        quantile: 0.5,
        step_ms: 15_000
      )

    assert {:ok, response} = History.query(history, descriptor)
    assert [%{value: 0.0005}, %{value: second}] = response.points
    assert_in_delta second, 0.0006875, 0.00000001
    assert %{kind: :stale, t: @t0 + 30_000} in response.markers
    refute %{kind: :reset, t: @t0 + 30_000} in response.markers
  end

  test "wall-clock rollback is visible and affected queries are refused" do
    history = start_supervised!({History, id: :clock, instance: "lab-1"})
    store(history, 0, [gauge(1)], 0)
    store(history, 2, [gauge(2)], 0)
    store(history, 1, [gauge(3)], 0)
    assert History.stats(history).clock_rollbacks == 1
    assert List.last(History.snapshots(history)).clock_rollback

    assert {:error, %Error{code: :clock_rollback}} =
             History.query(history, query!(metric: :nx_queue_depth, aggregation: :last))
  end

  test "changed types and histogram buckets cannot borrow a catalogue metric's meaning" do
    for {id, series, metric, aggregation, extra} <- [
          {:type, %{counter(3) | type: :gauge}, :nx_operations_total, :increase, []},
          {:buckets,
           %{
             histogram(List.duplicate(3, 8), 1)
             | sample: %{buckets: [{1, 3}, {:infinity, 3}], count: 3, sum: 1}
           }, :nx_duration_seconds, :histogram_quantile, [quantile: 0.5]},
          {:labels, %{gauge(3) | labels: [{"profile", "user-controlled"}]}, :nx_queue_depth, :last,
           []}
        ] do
      history = start_supervised!({History, id: id, instance: "lab-1"})
      store(history, 0, [series], 0)

      assert {:error, %Error{code: :invalid_metric_cohort}} =
               History.query(history, query!([metric: metric, aggregation: aggregation] ++ extra))
    end
  end

  test "deadline checks interrupt bounded query work and release its lease" do
    history = start_supervised!({History, id: :deadline, instance: "lab-1"})
    store(history, 0, [gauge(1)], 0)

    query =
      query!(
        metric: :nx_queue_depth,
        aggregation: :last,
        end_at: at(99_999_000),
        step_ms: 1_000,
        limits: %{range_ms: 100_000_000, min_step_ms: 1_000, points: 100_000, deadline_ms: 1}
      )

    assert {:error, %Error{code: :deadline_exceeded}} = History.query(history, query)
    assert History.stats(history).active_queries == 0
  end

  defp await_idle(history, attempts \\ 100) do
    cond do
      History.stats(history).active_queries == 0 -> :ok
      attempts == 0 -> flunk("query lease survived caller death")
      true -> Process.sleep(1) && await_idle(history, attempts - 1)
    end
  end

  test "the descriptor validates scope, metric, aggregation, filters, range, step and limits" do
    now = at(0)
    {:ok, query} = Query.new(scope: @scope, metric: :nx_queue_depth, aggregation: :last, now: now)
    assert query.schema_version == Query.schema_version()

    assert DateTime.diff(query.end_at, query.start_at, :millisecond) ==
             Query.default_limits().range_ms

    assert query.step_ms == 9_000 and query.limits.points == 10_000
    assert query.limits.output_bytes == 1_048_576 and query.limits.deadline_ms == 2_000
    assert query.limits.concurrent == 2 and query.quantile == nil
    assert {:ok, %{points: 9_601}} = Query.estimate(query)

    {:ok, short} =
      Query.new(
        scope: @scope,
        metric: :nx_queue_depth,
        aggregation: :last,
        now: now,
        start_at: at(-60_000)
      )

    assert short.step_ms == 5_000
    assert Query.digest(query) == Query.digest(query)
    assert String.starts_with?(Query.digest(query), "sha256:")

    assert Query.aggregations() == [
             :last,
             :sum,
             :min,
             :max,
             :avg,
             :increase,
             :rate,
             :histogram_quantile
           ]

    {:ok, other} = Query.new(scope: @scope, metric: :nx_queue_depth, aggregation: :max, now: now)
    refute Query.digest(other) == Query.digest(query)

    base = [scope: @scope, metric: :nx_queue_depth, aggregation: :last, now: now]

    cases = [
      {[scope: %{instance: "lab-1"}], :invalid_scope},
      {[scope: %{instance: "Lab One", session: "s"}], :invalid_scope},
      {[metric: :not_a_metric], :unknown_metric},
      {[aggregation: :percentile], :invalid_aggregation},
      {[filters: %{thing_id: :x}], :invalid_filter},
      {[filters: %{profile: :secret}], :invalid_filter},
      {[filters: [profile: :test]], :invalid_filter},
      {[quantile: 0.5], :invalid_quantile},
      {[aggregation: :histogram_quantile], :invalid_quantile},
      {[aggregation: :histogram_quantile, quantile: 1.5], :invalid_quantile},
      {[limits: %{points: 0}], :invalid_limits},
      {[limits: %{min_step_ms: 500}], :invalid_limits},
      {[limits: %{points: 1_000_000}], :invalid_limits},
      {[limits: %{sql: true}], :invalid_limits},
      {[limits: [points: 1]], :invalid_limits},
      {[start_at: at(10), end_at: at(0)], :invalid_range},
      {[start_at: ~N[2024-01-01 00:00:00]], :invalid_range},
      {[start_at: at(0), end_at: at(25 * 60 * 60 * 1_000)], :invalid_range},
      {[step_ms: 1_000], :invalid_step},
      {[unknown: 1], :invalid_options}
    ]

    for {overrides, code} <- cases do
      assert {:error, %Error{code: ^code}} = Query.new(Keyword.merge(base, overrides)),
             "expected #{code}"
    end

    assert {:error, %Error{code: :invalid_query}} = Query.new(%{})

    {:ok, fitted} = Query.new(Keyword.merge(base, limits: %{points: 10}))
    assert {:ok, %{points: fitted_points}} = Query.estimate(fitted)
    assert fitted_points in 1..10
    {:ok, large} = Query.new(Keyword.merge(base, limits: %{points: 10}, step_ms: 5_000))
    assert {:error, %Error{code: :query_too_large}} = Query.estimate(large)
  end

  test "gauges answer last, min, max, avg and sum; stale samples are markers, zero is a value" do
    history = seed(start_supervised!({History, id: :gauges, instance: "lab-1"}))
    {:ok, last} = History.query(history, query!(metric: :nx_queue_depth, aggregation: :last))

    assert last.source == :ets_history and last.instance == "lab-1"
    assert last.metric == :nx_queue_depth and last.unit == :count and last.aggregation == :last
    assert last.interval == %{start_ms: @t0, end_ms: @t0 + 45_000, step_ms: @step}
    assert last.freshness == %{latest_ms: @t0 + 45_000, age_ms: 0}
    assert Enum.map(last.points, & &1.value) == [1, 2, 3, 4, 5, 6, 7, 9, 10]

    assert Enum.map(last.points, & &1.t) ==
             for(i <- [0, 1, 2, 3, 4, 5, 6, 8, 9], do: @t0 + i * @step)

    assert %{t: t, kind: :stale} = Enum.find(last.markers, &(&1.kind == :stale))
    assert t == @t0 + 7 * @step
    assert Enum.any?(last.markers, &(&1.kind == :reset and &1.t == @t0 + 5 * @step))
    assert last.loss == %{evicted: 0, dropped_oversized: 0, gaps: 0, resets: 1, clock_rollbacks: 0}
    assert last.evidence == [] and last.series_matched == 1
    assert String.starts_with?(last.digest, "sha256:")

    {:ok, max} = History.query(history, query!(metric: :nx_queue_depth, aggregation: :max))
    assert Enum.map(max.points, & &1.value) == [1, 2, 3, 4, 5, 6, 7, 9, 10]

    {:ok, avg} =
      History.query(history, query!(metric: :nx_queue_depth, aggregation: :avg, step_ms: 10_000))

    assert Enum.map(avg.points, & &1.value) == [1, 2.5, 4.5, 6.5, 9]

    {:ok, min} =
      History.query(history, query!(metric: :nx_queue_depth, aggregation: :min, step_ms: 10_000))

    assert Enum.map(min.points, & &1.value) == [1, 2, 4, 6, 9]

    {:ok, empty} =
      History.query(
        history,
        query!(
          metric: :nx_queue_depth,
          aggregation: :last,
          start_at: at(100_000),
          end_at: at(200_000)
        )
      )

    assert empty.points == [] and empty.freshness == nil

    store(history, 20, [gauge(0)], 1)

    {:ok, zero} =
      History.query(
        history,
        query!(
          metric: :nx_queue_depth,
          aggregation: :last,
          start_at: at(100_000),
          end_at: at(200_000)
        )
      )

    assert [%{value: 0}] = zero.points
  end

  test "counters answer increase and rate with reset awareness and sum across series" do
    history = seed(start_supervised!({History, id: :counters, instance: "lab-1"}))
    filters = %{operation: :encode, profile: :test}

    {:ok, increase} =
      History.query(
        history,
        query!(metric: :nx_operations_total, aggregation: :increase, filters: filters)
      )

    assert Enum.map(increase.points, & &1.value) == [0, 10, 10, 10, 10, 5, 10, 10, 10, 10]
    assert [%{kind: :reset, t: reset_at}] = Enum.filter(increase.markers, &(&1.kind == :reset))
    assert reset_at == @t0 + 5 * @step

    {:ok, rate} =
      History.query(
        history,
        query!(metric: :nx_operations_total, aggregation: :rate, filters: filters)
      )

    assert Enum.map(rate.points, & &1.value) == [0, 2, 2, 2, 2, 1, 2, 2, 2, 2]

    {:ok, sum} =
      History.query(
        history,
        query!(metric: :nx_operations_total, aggregation: :sum, filters: %{profile: :test})
      )

    assert sum.series_matched == 2
    assert Enum.map(sum.points, & &1.value) == [10, 21, 32, 43, 54, 10, 21, 32, 43, 54]

    {:ok, both} =
      History.query(
        history,
        query!(metric: :nx_operations_total, aggregation: :increase, filters: %{profile: :test})
      )

    assert Enum.map(both.points, & &1.value) == [0, 11, 11, 11, 11, 10, 11, 11, 11, 11]

    {:ok, last} =
      History.query(
        history,
        query!(metric: :nx_operations_total, aggregation: :last, filters: filters)
      )

    assert List.last(last.points).value == 45
  end

  test "histogram quantiles derive from bucket counts, never from averages" do
    history = seed(start_supervised!({History, id: :histograms, instance: "lab-1"}))
    filters = %{operation: :encode}

    {:ok, median} =
      History.query(
        history,
        query!(
          metric: :nx_duration_seconds,
          aggregation: :histogram_quantile,
          quantile: 0.5,
          filters: filters
        )
      )

    assert median.unit == :seconds
    [first | rest] = median.points
    assert first.t == @t0

    assert Enum.all?(rest, fn %{value: value} ->
             is_number(value) and value > 0.001 and value <= 0.1
           end)

    assert Enum.any?(median.markers, &(&1.kind == :reset))

    {:ok, tail} =
      History.query(
        history,
        query!(
          metric: :nx_duration_seconds,
          aggregation: :histogram_quantile,
          quantile: 0.99,
          filters: filters
        )
      )

    assert Enum.all?(tail.points, fn %{value: value} -> value <= 10 end)

    {:ok, increase} =
      History.query(
        history,
        query!(metric: :nx_duration_seconds, aggregation: :increase, filters: filters)
      )

    assert Enum.map(increase.points, & &1.value) == [0, 4, 4, 4, 4, 21, 4, 4, 4, 4]
  end

  test "unsupported or ambiguous questions are refused instead of answered fluently" do
    history = seed(start_supervised!({History, id: :unsupported, instance: "lab-1"}))

    unsupported = [
      [metric: :nx_queue_depth, aggregation: :rate],
      [metric: :nx_queue_depth, aggregation: :increase],
      [metric: :nx_operations_total, aggregation: :avg],
      [metric: :nx_operations_total, aggregation: :max],
      [metric: :nx_duration_seconds, aggregation: :last],
      [metric: :nx_duration_seconds, aggregation: :sum]
    ]

    for opts <- unsupported do
      assert {:error, %Error{code: :unsupported_query, phase: :history}} =
               History.query(history, query!(opts))
    end

    assert {:error, %Error{code: :unsupported_query, details: %{series_matched: 2}}} =
             History.query(
               history,
               query!(metric: :nx_operations_total, aggregation: :last, filters: %{profile: :test})
             )

    assert {:error, %Error{code: :query_too_large}} =
             History.query(
               history,
               query!(metric: :nx_queue_depth, aggregation: :last, limits: %{points: 4})
             )

    assert {:error, %Error{code: :query_too_large}} =
             History.query(
               history,
               query!(
                 metric: :nx_operations_total,
                 aggregation: :sum,
                 filters: %{profile: :test},
                 limits: %{points: 15}
               )
             )

    assert {:error, %Error{code: :output_too_large}} =
             History.query(
               history,
               query!(metric: :nx_queue_depth, aggregation: :last, limits: %{output_bytes: 64})
             )

    {:ok, _table, first} = GenServer.call(history, {:acquire, @scope, 2})
    {:ok, _table, second} = GenServer.call(history, {:acquire, @scope, 2})

    assert {:error, %Error{code: :too_many_queries, class: :rate_limited}} =
             History.query(history, query!(metric: :nx_queue_depth, aggregation: :last))

    :ok = GenServer.call(history, {:release, first})
    :ok = GenServer.call(history, {:release, second})

    assert {:ok, _response} =
             History.query(history, query!(metric: :nx_queue_depth, aggregation: :last))

    assert History.stats(history).active_queries == 0
  end

  test "evicted history is reported as loss rather than as missing data" do
    history = start_supervised!({History, id: :evicted, max_snapshots: 3, instance: "lab-1"})
    for index <- 0..9, do: store(history, index, [gauge(index)], 0)

    {:ok, response} = History.query(history, query!(metric: :nx_queue_depth, aggregation: :last))
    assert Enum.map(response.points, & &1.value) == [7, 8, 9]
    assert %{kind: :evicted, t: @t0} = Enum.find(response.markers, &(&1.kind == :evicted))
    assert response.loss.evicted == 7

    {:ok, before} =
      History.query(
        history,
        query!(
          metric: :nx_queue_depth,
          aggregation: :last,
          start_at: at(-20_000),
          end_at: at(-10_000)
        )
      )

    assert before.points == []
    assert [%{kind: :evicted}] = before.markers
  end
end
