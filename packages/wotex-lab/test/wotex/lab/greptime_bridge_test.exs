defmodule Wotex.Lab.GreptimeBridgeTest do
  @moduledoc false

  use ExUnit.Case, async: false

  @moduletag :greptime

  alias Wotex.Lab
  alias Wotex.Lab.Examples.Thermal
  alias Wotex.Lab.Metrics.{Collector, GreptimeBridge, History, ReqSink}
  alias Wotex.Lab.Test.Greptime

  @labels [
    {"backend_class", "binary"},
    {"operation", "inference"},
    {"outcome_class", "ok"},
    {"profile", "thermal"}
  ]

  test "real snapshots reach GreptimeDB through remote write and read back through the SQL API" do
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
         scrape: fn -> Collector.snapshot(collector) end,
         sink: sink,
         history: history,
         labels: [{"instance", "greptime-lab"}]}
      )

    assert {:ok, _result} = Thermal.run()
    assert {:ok, %{sequence: 1}} = GreptimeBridge.scrape_now(bridge)
    {:ok, first} = Collector.snapshot(collector)
    assert {:ok, _result} = Thermal.run()
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

    assert Enum.map(rows, & &1.timestamp) == Enum.sort(Enum.map(rows, & &1.timestamp))

    [bucket | _rest] =
      Greptime.await_rows(
        greptime,
        "wotex_lab_nx_duration_seconds_bucket",
        [{"le", "+Inf"} | @labels],
        2
      )

    assert bucket.value >= 1.0

    assert length(History.snapshots(history)) == 2

    assert Greptime.read(greptime, "wotex_lab_nx_operations_total", [{"profile", "nonexistent"}]) ==
             []
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
