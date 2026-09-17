defmodule Wotex.Lab.MetricsDurableQueryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{DurableQuery, Query}

  @t0 1_700_000_000_000
  @scope %{instance: "lab-1", session: "session-1"}

  defp at(offset_ms), do: DateTime.from_unix!(@t0 + offset_ms, :millisecond)

  defp query(metric, aggregation, opts \\ []) do
    {:ok, query} =
      Query.new(
        Keyword.merge(
          [
            scope: @scope,
            metric: metric,
            aggregation: aggregation,
            start_at: at(0),
            end_at: at(60_000),
            step_ms: 15_000
          ],
          opts
        )
      )

    query
  end

  defp matrix(series),
    do: %{"status" => "success", "data" => %{"resultType" => "matrix", "result" => series}}

  defp series(values, metric \\ %{}),
    do: %{"metric" => metric, "values" => Enum.map(values, fn {s, v} -> [s, v] end)}

  test "templates are fixed per type and aggregation with scoped exact matchers" do
    filters = %{operation: :encode, profile: :test}

    expectations = [
      {:nx_queue_depth, :last, [],
       ~S|last_over_time(wotex_lab_nx_queue_depth{instance="lab-1"}[15s])|, 15_000},
      {:nx_queue_depth, :sum, [],
       ~S|sum(last_over_time(wotex_lab_nx_queue_depth{instance="lab-1"}[15s]))|, 15_000},
      {:nx_queue_depth, :min, [],
       ~S|min(min_over_time(wotex_lab_nx_queue_depth{instance="lab-1"}[15s]))|, 15_000},
      {:nx_queue_depth, :max, [],
       ~S|max(max_over_time(wotex_lab_nx_queue_depth{instance="lab-1"}[15s]))|, 15_000},
      {:nx_operations_total, :increase, [filters: filters],
       ~S|sum(increase(wotex_lab_nx_operations_total{instance="lab-1",operation="encode",profile="test"}[15s]))|,
       15_000},
      {:nx_operations_total, :rate, [step_ms: 5_000],
       ~S|sum(rate(wotex_lab_nx_operations_total{instance="lab-1"}[15s]))|, 15_000},
      {:nx_duration_seconds, :increase, [],
       ~S|sum(increase(wotex_lab_nx_duration_seconds_count{instance="lab-1"}[15s]))|, 15_000},
      {:nx_duration_seconds, :histogram_quantile, [quantile: 0.95, step_ms: 30_000],
       ~S|histogram_quantile(0.95, sum by (le) (increase(wotex_lab_nx_duration_seconds_bucket{instance="lab-1"}[30s])))|,
       30_000}
    ]

    for {metric, aggregation, opts, expression, window} <- expectations do
      assert {:ok, template} = DurableQuery.template(query(metric, aggregation, opts))
      assert template.expression == expression
      assert template.window_ms == window
      assert template.path == "/v1/prometheus/api/v1/query_range"
      assert {"query", ^expression} = hd(template.params)
      assert {"start", "1700000000.000"} in template.params
      assert {"end", "1700000060.000"} in template.params
      assert String.starts_with?(template.digest, "sha256:")
    end

    assert {:ok, %{window_ms: 60_000}} =
             DurableQuery.template(query(:nx_operations_total, :rate, step_ms: 5_000),
               capture_interval_ms: 20_000
             )

    assert {:ok, %{window_ms: 5_000}} =
             DurableQuery.template(query(:nx_operations_total, :rate, step_ms: 5_000),
               capture_interval_ms: 1_500
             )

    for {metric, aggregation, opts} <- [
          {:nx_queue_depth, :avg, []},
          {:nx_queue_depth, :rate, []},
          {:nx_duration_seconds, :last, []},
          {:nx_operations_total, :last, [step_ms: 5_500]}
        ] do
      assert {:error, %Error{code: :unsupported_query}} =
               DurableQuery.template(query(metric, aggregation, opts))
    end

    assert {:error, %Error{code: :invalid_options}} =
             DurableQuery.template(query(:nx_queue_depth, :last), capture_interval_ms: 999)

    assert {:error, %Error{code: :invalid_options}} =
             DurableQuery.template(query(:nx_queue_depth, :last), endpoint: "http://other")

    assert {:error, %Error{code: :invalid_scope}} =
             DurableQuery.template(%{query(:nx_queue_depth, :last) | scope: %{instance: "x\"}"}})
  end

  test "matrix answers keep gaps, mark nonfinite values and carry both digests" do
    descriptor = query(:nx_duration_seconds, :histogram_quantile, quantile: 0.95)
    parent = self()

    executor = fn template ->
      send(parent, {:template, template})

      {:ok,
       matrix([
         series([
           {1_700_000_015.0, "0.0048"},
           {1_700_000_030.0, "NaN"},
           {1_700_000_060.0, "0.025"}
         ])
       ])}
    end

    assert {:ok, answer} = DurableQuery.query(descriptor, executor)
    assert_receive {:template, %{expression: "histogram_quantile(0.95" <> _}}
    assert answer.source == :durable_promql and answer.instance == "lab-1"
    assert answer.points == [%{t: @t0 + 15_000, value: 0.0048}, %{t: @t0 + 60_000, value: 0.025}]
    assert answer.markers == [%{t: @t0 + 30_000, kind: :nonfinite}]
    assert answer.freshness == %{latest_ms: @t0 + 60_000, age_ms: 0}

    assert answer.interval == %{
             start_ms: @t0,
             end_ms: @t0 + 60_000,
             step_ms: 15_000,
             window_ms: 15_000
           }

    assert answer.digest == Query.digest(descriptor)
    assert answer.series_matched == 1 and answer.unit == :seconds

    assert {:ok, %{points: [], freshness: nil, series_matched: 0}} =
             DurableQuery.query(descriptor, fn _ -> {:ok, matrix([])} end)

    assert {:ok, %{points: [%{value: 5}]}} =
             DurableQuery.query(query(:nx_queue_depth, :last), fn _ ->
               {:ok, matrix([series([{1_700_000_015.0, "5"}])])}
             end)
  end

  test "ambiguous, refused, malformed, oversized and unavailable answers are refused" do
    last = query(:nx_queue_depth, :last)
    two = matrix([series([{1_700_000_015.0, "1"}]), series([{1_700_000_015.0, "2"}])])

    for {body, code} <- [
          {{:ok, two}, :unsupported_query},
          {{:ok, %{"status" => "error", "error" => "secret receiver detail"}}, :durable_refused},
          {{:ok, %{"status" => "success", "data" => %{"resultType" => "vector"}}},
           :durable_invalid_response},
          {{:ok, matrix([%{"metric" => %{}, "values" => [["t", "1"]]}])},
           :durable_invalid_response},
          {{:ok, "not json"}, :durable_invalid_response},
          {{:error, :econnrefused}, :durable_unavailable},
          {:unexpected, :durable_unavailable}
        ] do
      assert {:error, %Error{code: ^code} = error} = DurableQuery.query(last, fn _ -> body end)
      refute inspect(error) =~ "secret receiver detail"
    end

    assert {:ok, %{series_matched: 2}} =
             DurableQuery.query(query(:nx_queue_depth, :sum), fn _ -> {:ok, two} end)

    small = query(:nx_queue_depth, :sum, limits: %{points: 13})
    many = matrix([series(for s <- 0..13, do: {1_700_000_000.0 + s, "1"})])

    assert {:error, %Error{code: :query_too_large}} =
             DurableQuery.query(small, fn _ -> {:ok, many} end)

    tiny = query(:nx_queue_depth, :sum, limits: %{output_bytes: 64})

    assert {:error, %Error{code: :output_too_large}} =
             DurableQuery.query(tiny, fn _ -> {:ok, matrix([series([{1_700_000_015.0, "1"}])])} end)

    assert {:ok, %{points: [], markers: [%{kind: :invalid}]}} =
             DurableQuery.query(query(:nx_queue_depth, :sum), fn _ ->
               {:ok, matrix([series([{1_700_000_015.0, "1x"}])])}
             end)
  end
end
