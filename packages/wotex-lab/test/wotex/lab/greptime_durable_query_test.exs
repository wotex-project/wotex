defmodule Wotex.Lab.GreptimeDurableQueryTest do
  @moduledoc false

  use ExUnit.Case, async: false

  @moduletag :greptime

  alias Wotex.Lab.Metrics.{Collector, DurableQuery, History, Query, RemoteWrite, ReqSink}
  alias Wotex.Lab.Test.Greptime

  @t0 1_700_000_000_000
  @instance "durable-lab"
  @stop [:wotex, :lab, :nx, :encode, :stop]
  @measurement [:wotex, :lab, :nx, :encode, :measurement]

  test "fixed durable templates answer from real remote-written captures" do
    greptime = Greptime.start()
    collector = start_supervised!({Collector, id: :durable, attribute_to: self()})
    history = start_supervised!({History, id: :durable, instance: @instance})

    # Captures every five seconds; the capture at +20 s is deliberately absent.
    for index <- 0..7 do
      for _ <- 1..2 do
        :telemetry.execute(@stop, %{duration: native(2)}, %{outcome: :ok, profile: :test})
      end

      :telemetry.execute(@measurement, %{rows: 10 + index}, %{profile: :test})
      {:ok, snapshot} = Collector.snapshot(collector)
      snapshot = %{snapshot | wall_time_ms: @t0 + index * 5_000}

      unless index == 4 do
        {:ok, _} = History.put(history, snapshot)
        {:ok, request} = RemoteWrite.encode(snapshot, labels: [{"instance", @instance}])
        assert {:ok, %{status: status}} = ReqSink.write(request, nil, %{url: greptime.write_url})
        assert status in 200..299
      end
    end

    Greptime.await_rows(greptime, "wotex_lab_nx_batch_rows", [{"instance", @instance}], 7)
    executor = &execute(greptime, &1)

    rows = descriptor(:nx_batch_rows, :last, filters: %{profile: :test})
    assert {:ok, durable} = DurableQuery.query(rows, executor)
    assert {:ok, local} = History.query(history, rows)
    assert durable.points == local.points
    refute Enum.any?(durable.points, &(&1.t == @t0 + 20_000))
    assert length(durable.points) == 7 and durable.source == :durable_promql

    operations = descriptor(:nx_operations_total, :sum)
    assert {:ok, durable_sum} = DurableQuery.query(operations, executor)
    assert {:ok, local_sum} = History.query(history, operations)
    assert durable_sum.points == local_sum.points

    increase = descriptor(:nx_operations_total, :increase)

    assert {:ok, %{interval: %{window_ms: 15_000}} = durable_increase} =
             DurableQuery.query(increase, executor)

    assert durable_increase.points != []
    assert Enum.all?(durable_increase.points, &(&1.value >= 0))
    assert Enum.any?(durable_increase.points, &(&1.value > 0))

    quantile = descriptor(:nx_duration_seconds, :histogram_quantile, quantile: 0.95)
    assert {:ok, durable_quantile} = DurableQuery.query(quantile, executor)
    assert durable_quantile.points != []
    assert Enum.all?(durable_quantile.points, &(&1.value > 0.001 and &1.value <= 0.005))

    other = %{rows | scope: %{instance: "other-lab", session: "session-1"}}
    assert {:ok, %{points: [], series_matched: 0}} = DurableQuery.query(other, executor)
  end

  defp descriptor(metric, aggregation, opts \\ []) do
    {:ok, query} =
      Query.new(
        [
          scope: %{instance: @instance, session: "session-1"},
          metric: metric,
          aggregation: aggregation,
          start_at: DateTime.from_unix!(@t0, :millisecond),
          end_at: DateTime.from_unix!(@t0 + 35_000, :millisecond),
          step_ms: 5_000
        ] ++ opts
      )

    query
  end

  defp execute(greptime, template) do
    case Req.post(greptime.base_url <> template.path <> "?db=public",
           form: template.params,
           retry: false,
           receive_timeout: 10_000
         ) do
      {:ok, %{body: body}} when is_map(body) -> {:ok, body}
      other -> {:error, other}
    end
  end

  defp native(ms), do: System.convert_time_unit(ms, :millisecond, :native)
end
