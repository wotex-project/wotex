defmodule WotexLabWorkbench.HistoryPanelsTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{Collector, History}
  alias WotexLabWorkbench.{Experiments, HistoryPanels, Room, Sessions}

  @now ~U[2026-09-17 12:00:00.000Z]
  @encode_stop [:wotex, :lab, :nx, :encode, :stop]
  @encode_measurement [:wotex, :lab, :nx, :encode, :measurement]
  @request_stop [:wotex, :lab, :runtime, :request, :stop]

  setup do
    lab = start_supervised!({Wotex.Lab, id: "history-panels", max_children: 128})

    registry =
      start_supervised!(
        {Sessions,
         lab: lab,
         ttl_ms: 60_000,
         sweep_ms: 1_000,
         max_sessions: 8,
         name: WotexLabWorkbench.HistoryPanelsTest.Registry}
      )

    %{registry: registry}
  end

  test "each room history holds only events from its own process tree", %{registry: registry} do
    thermal_room = room(registry)
    other_room = room(registry)

    run!(thermal_room, "thermal")
    run!(thermal_room, "thermal")
    run!(other_room, "window_anomaly")
    run!(other_room, "smart_room")

    assert {:ok, thermal} = Room.history(thermal_room)
    assert {:ok, other} = Room.history(other_room)
    assert thermal.interval_ms == 5_000
    refute thermal.scope.instance == other.scope.instance

    thermal_series = latest(thermal)
    other_series = latest(other)

    assert labels(thermal_series, "wotex_lab_nx_operations_total", "profile") == ["thermal"]
    assert labels(other_series, "wotex_lab_nx_operations_total", "profile") == ["window_anomaly"]

    assert %{sample: %{value: 2}} =
             Enum.find(
               thermal_series,
               &(&1.name == "wotex_lab_nx_operations_total" and
                   {"operation", "inference"} in &1.labels)
             )

    assert labels(thermal_series, "wotex_lab_scenario_operations_total", "operation") == ["parse"]
    assert labels(other_series, "wotex_lab_scenario_operations_total", "operation") == []

    # Continuum spans come from processes the room started; Things' server-side
    # processes belong to the host instance and are not attributed.
    assert labels(other_series, "wotex_lab_continuum_codec_total", "action") != []
    assert labels(thermal_series, "wotex_lab_continuum_codec_total", "action") == []
    assert labels(other_series, "wotex_lab_transport_requests_total", "component") == ["runtime"]

    assert {:ok, loaded} =
             HistoryPanels.load(thermal, ["nx_operations_total", "continuum_codec_total"], "5m")

    assert [%{status: :available} = operations, %{status: :unavailable} = codec] = loaded.panels
    assert operations.series_total == 3 and codec.series_total == 0

    crossed = %{thermal | scope: other.scope}
    assert {:ok, %{panels: [refused]}} = HistoryPanels.load(crossed, ["nx_operations_total"], "5m")
    assert refused.status == :refused and refused.error == "scope_denied"

    state = :sys.get_state(thermal_room)
    %{collector: collector, store: store} = state.history
    :ok = Sessions.revoke(registry, session_token(registry, thermal_room))
    eventually(fn -> not Process.alive?(collector) and not Process.alive?(store) end)
    refute Enum.any?(:telemetry.list_handlers(@encode_stop), &(&1.id == {Collector, collector}))
  end

  test "panels chart each label set with gaps, rates, last values and p95" do
    %{binding: binding, history: history, collector: collector} = fixture_history()
    now_ms = DateTime.to_unix(@now, :millisecond)

    emit_encode(2, 2, 3)
    put(history, collector, now_ms - 120_000)
    emit_encode(3, 2, 5)
    put(history, collector, now_ms - 60_000)
    put(history, collector, now_ms - 30_000)

    ids = ~w(nx_operations_total nx_batch_rows nx_duration_seconds directory_operations_total)
    assert {:ok, result} = HistoryPanels.load(binding, ids, "5m", now: @now)
    assert result.range == "5m" and result.step_ms == 5_000
    assert result.end_ms == now_ms and result.start_ms == now_ms - 300_000

    [operations, rows, duration, directory] = result.panels

    assert %{status: :available, series_total: 1, series_shown: 1, freshness_ms: 30_000} =
             operations

    assert operations.aggregation == "rate per step"
    assert [series] = operations.chart.series
    assert series.name == "backend_class=other operation=encode outcome_class=ok profile=test"
    assert length(series.points) == 61
    assert {-120, 0} in series.points and {-60, 0.6} in series.points and {-30, 0} in series.points
    assert Enum.count(series.points, &is_nil(elem(&1, 1))) == 58
    assert [digest] = operations.digests
    assert String.starts_with?(digest, "sha256:")
    assert operations.markers == %{gap: 0, reset: 0, stale: 0, evicted: 0, clock_rollback: 0}

    assert [%{points: points}] = rows.chart.series
    assert {-120, 3} in points and {-60, 5} in points and {-30, 5} in points
    assert rows.aggregation == "last value per step"

    assert [%{points: points}] = duration.chart.series
    p95 = for {offset, value} <- points, is_number(value), do: {offset, value}
    assert [{-120, first}, {-60, second}] = p95
    assert first > 0.001 and first <= 0.005 and second > 0.001 and second <= 0.005
    assert duration.chart.y.title == "seconds"

    assert %{status: :unavailable, chart: nil, series_total: 0} = directory

    assert {:ok, %{panels: [outside]}} =
             HistoryPanels.load(binding, ["nx_operations_total"], "5m",
               now: DateTime.add(@now, 3_600, :second)
             )

    assert outside.status == :unavailable
  end

  test "label sets beyond eight, budgets, rollbacks and refusals stay explicit" do
    %{binding: binding, history: history, collector: collector} = fixture_history()
    now_ms = DateTime.to_unix(@now, :millisecond)

    for action <- ~w(fetch list put delete create update readproperty writeproperty invokeaction)a do
      :telemetry.execute(@request_stop, %{duration: native(1)}, %{
        operation: action,
        outcome: :ok,
        profile: :test
      })
    end

    put(history, collector, now_ms - 10_000)

    assert {:ok, %{panels: [requests]}} =
             HistoryPanels.load(binding, ["transport_requests_total"], "15m", now: @now)

    assert %{status: :available, series_total: 9, series_shown: 8} = requests
    assert length(requests.chart.series) == 8 and length(requests.digests) == 8
    assert hd(requests.chart.series).points |> length() == 61

    assert {:ok, %{panels: [skipped]}} =
             HistoryPanels.load(binding, ["transport_requests_total"], "1h",
               now: @now,
               budget_ms: 0
             )

    assert %{status: :not_queried, error: "budget_exhausted", chart: nil} = skipped

    put(history, collector, now_ms - 20_000)

    assert {:ok, %{panels: [rolled_back]}} =
             HistoryPanels.load(binding, ["transport_requests_total"], "5m", now: @now)

    assert %{status: :refused, error: "clock_rollback"} = rolled_back

    for {range, ids, opts, code} <- [
          {"2h", ["nx_operations_total"], [], :invalid_range},
          {:caller, ["nx_operations_total"], [], :invalid_range},
          {"5m", ["caller"], [], :invalid_panels},
          {"5m", [], [], :invalid_panels},
          {"5m", ["nx_operations_total"], [budget_ms: 1_501], :invalid_budget},
          {"5m", ["nx_operations_total"], [now: ~N[2026-09-17 12:00:00]], :invalid_range}
        ] do
      assert {:error, %Error{code: ^code}} = HistoryPanels.load(binding, ids, range, opts)
    end

    assert {:error, %Error{code: :history_unavailable}} =
             HistoryPanels.load(%{scope: binding.scope}, ["nx_operations_total"], "5m")

    assert HistoryPanels.ranges() == ~w(5m 15m 1h)
    assert HistoryPanels.default_range() == "15m"

    GenServer.stop(history)

    assert {:error, %Error{code: :history_unavailable}} =
             HistoryPanels.load(binding, ["nx_operations_total"], "5m")
  end

  defp fixture_history do
    collector = start_supervised!({Collector, id: :panels, attribute_to: self()})
    history = start_supervised!({History, id: :panels, instance: "panels-test"})

    %{
      collector: collector,
      history: history,
      binding: %{
        history: history,
        scope: %{instance: "panels-test", session: "panels-test"},
        interval_ms: 5_000
      }
    }
  end

  defp put(history, collector, wall_time_ms) do
    {:ok, snapshot} = Collector.snapshot(collector)
    {:ok, _} = History.put(history, %{snapshot | wall_time_ms: wall_time_ms})
  end

  defp emit_encode(count, milliseconds, rows) do
    for _ <- 1..count do
      :telemetry.execute(@encode_stop, %{duration: native(milliseconds)}, %{
        outcome: :ok,
        profile: :test
      })
    end

    :telemetry.execute(@encode_measurement, %{rows: rows}, %{profile: :test})
  end

  defp native(ms), do: System.convert_time_unit(ms, :millisecond, :native)

  defp room(registry) do
    {:ok, session} = Sessions.open(registry)
    {:ok, live} = Sessions.admit(registry, session.token, :run)
    Process.put({:session_token, live.room}, session.token)
    live.room
  end

  defp session_token(_, room), do: Process.get({:session_token, room})

  defp run!(room, id) do
    {:ok, experiment} = Experiments.fetch(id)
    {:ok, params} = Experiments.admit(experiment, %{})
    assert {:ok, _} = Room.start_run(room, id, params)
  end

  defp latest(binding) do
    binding.history
    |> History.snapshots()
    |> List.last()
    |> Map.fetch!(:snapshot)
    |> Map.fetch!(:series)
  end

  defp labels(series, name, label) do
    series
    |> Enum.filter(&(&1.name == name))
    |> Enum.flat_map(fn one -> for {^label, value} <- one.labels, do: value end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp eventually(fun, attempts \\ 200) do
    cond do
      fun.() -> :ok
      attempts == 0 -> flunk("condition was not reached")
      true -> Process.sleep(10) && eventually(fun, attempts - 1)
    end
  end
end
