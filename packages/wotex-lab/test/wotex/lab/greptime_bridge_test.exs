defmodule Wotex.Lab.GreptimeBridgeTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab
  alias Wotex.Lab.Examples.Thermal

  alias Wotex.Lab.Metrics.{
    Collector,
    Exposition,
    GreptimeBridge,
    History,
    RemoteWrite,
    ReqSink,
    Retention
  }

  alias Wotex.Lab.Test.Greptime

  @moduletag :greptime

  @labels [
    {"backend_class", "binary"},
    {"operation", "inference"},
    {"outcome_class", "ok"},
    {"profile", "thermal"}
  ]

  test "real collector values with distinct fixture timestamps round trip through GreptimeDB" do
    greptime = Greptime.start()
    lab = start_supervised!({Lab, id: "greptime-lab", max_children: 8})
    {:ok, collector} = Lab.start_child(lab, :sessions, {Collector, id: :c, backend_class: :binary})
    {:ok, history} = Lab.start_child(lab, :sessions, {History, id: :h})

    sink = fn request, credential ->
      ReqSink.write(request, credential, %{url: greptime.write_url, receive_timeout: 5_000})
    end

    {:ok, bridge} =
      Lab.start_child(
        lab,
        :sessions,
        {GreptimeBridge,
         id: :b,
         scrape: fn ->
           {:ok, snapshot} = Collector.snapshot(collector)
           # Explicit fixture clock: execution speed is not a sampling interval.
           {:ok, %{snapshot | wall_time_ms: 1_700_000_000_000 + snapshot.sequence * 5_000}}
         end,
         sink: sink,
         history: history,
         labels: [{"instance", "greptime-lab"}]}
      )

    assert {:ok, _} = Thermal.run()
    assert {:ok, %{sequence: 1}} = GreptimeBridge.scrape_now(bridge)
    [%{snapshot: first}] = History.snapshots(history)
    assert {:ok, _} = Thermal.run()
    assert {:ok, %{sequence: 2}} = GreptimeBridge.scrape_now(bridge)

    stats = await_exported(bridge, 2, 100)
    assert stats.rejected_permanent == 0 and stats.failed == 0 and stats.last_error == nil

    counter =
      Enum.find(
        first.series,
        &(&1.name == "wotex_lab_nx_operations_total" and &1.labels == @labels)
      )

    assert counter.sample.value >= 1

    rows =
      Greptime.await_rows(
        greptime,
        "wotex_lab_nx_operations_total",
        [{"instance", "greptime-lab"} | @labels],
        2
      )

    assert Enum.map(rows, & &1.value) == [
             counter.sample.value * 1.0,
             (counter.sample.value + 1) * 1.0
           ]

    assert Enum.map(rows, & &1.timestamp) == [first.wall_time_ms, first.wall_time_ms + 5_000]

    [bucket | _] =
      Greptime.await_rows(
        greptime,
        "wotex_lab_nx_duration_seconds_bucket",
        [{"le", "+Inf"} | @labels],
        2
      )

    assert bucket.value >= 1.0

    assert [%{snapshot: ^first}, %{snapshot: second}] = History.snapshots(history)
    assert second.sequence == 2 and second.wall_time_ms > first.wall_time_ms

    assert Greptime.read(greptime, "wotex_lab_nx_operations_total", [{"profile", "nonexistent"}]) ==
             []
  end

  test "separate successful same-timestamp writes deduplicate at the pinned receiver" do
    greptime = Greptime.start()
    timestamp = 1_700_000_000_000
    metric = "wotex_lab_fixture_deduplication"

    for value <- [1, 2] do
      {:ok, snapshot} =
        Exposition.parse("# TYPE #{metric} gauge\n#{metric} #{value}\n",
          sequence: value,
          wall_time_ms: timestamp
        )

      {:ok, request} = RemoteWrite.encode(snapshot)
      assert {:ok, %{status: status}} = ReqSink.write(request, nil, %{url: greptime.write_url})
      assert status in 200..299

      assert [%{timestamp: ^timestamp, value: stored}] =
               Greptime.await_rows(greptime, metric, [], 1)

      assert stored == value * 1.0
    end
  end

  test "provisioned retention removes a flushed capture older than the database TTL" do
    greptime = Greptime.start()
    executor = &Greptime.sql(greptime, &1)
    {:ok, plan} = Retention.plan(database: "wotex_lab_retention", ttl: "1h")

    assert {:ok, %{database: "wotex_lab_retention", seconds: 3_600}} =
             Retention.provision(plan, executor)

    metric = "wotex_lab_fixture_retention"
    now = System.system_time(:millisecond)
    expired = now - 2 * 3_600_000

    write = fn value, wall_time_ms ->
      {:ok, snapshot} =
        Exposition.parse("# TYPE #{metric} gauge\n#{metric} #{value}\n",
          sequence: value,
          wall_time_ms: wall_time_ms
        )

      {:ok, request} = RemoteWrite.encode(snapshot)
      request = %{request | headers: [{"x-greptime-db-name", plan.database} | request.headers]}
      url = greptime.base_url <> "/v1/prometheus/write"
      assert {:ok, %{status: status}} = ReqSink.write(request, nil, %{url: url})
      assert status in 200..299
    end

    write.(1, expired)
    assert [%{timestamp: ^expired}] = Greptime.read(greptime, metric, [], plan.database)
    :ok = Greptime.flush(greptime, plan.database)
    assert await_empty(greptime, metric, plan.database, 50)

    write.(2, now)
    :ok = Greptime.flush(greptime, plan.database)
    assert [%{timestamp: ^now, value: 2.0}] = Greptime.read(greptime, metric, [], plan.database)

    {:ok, longer} = Retention.plan(database: plan.database, ttl: "3h")
    assert {:ok, %{seconds: 10_800}} = Retention.provision(longer, executor)
    assert [%{timestamp: ^now}] = Greptime.read(greptime, metric, [], plan.database)

    assert {:error, %Wotex.Lab.Error{code: :retention_refused}} =
             Retention.provision(plan, fn statement ->
               executor.(String.replace(statement, "'1h'", "'x1'"))
             end)
  end

  defp await_empty(greptime, metric, database, attempts) do
    cond do
      Greptime.read(greptime, metric, [], database) == [] -> true
      attempts == 0 -> false
      true -> Process.sleep(100) && await_empty(greptime, metric, database, attempts - 1)
    end
  end

  defp await_exported(bridge, count, attempts) do
    stats = GreptimeBridge.stats(bridge)

    cond do
      stats.exported == count -> stats
      attempts == 0 -> flunk("exports never completed: #{inspect(stats)}")
      true -> Process.sleep(100) && await_exported(bridge, count, attempts - 1)
    end
  end
end
