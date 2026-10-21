defmodule WotexLabWorkbench.InvestigationMetricsTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias WotexLabWorkbench.{Experiments, Room, Sessions}
  alias WotexLabWorkbench.Investigation.{ContextStore, MetricQuery, Skill}

  setup do
    lab = start_supervised!({Wotex.Lab, id: "investigation-metrics"})

    registry =
      start_supervised!(
        {Sessions,
         lab: lab, name: __MODULE__.Registry, ttl_ms: 60_000, sweep_ms: 1_000, max_sessions: 4}
      )

    start_supervised!(ContextStore)
    %{registry: registry}
  end

  test "a browser callback queries only its bound room and records the same chart", %{
    registry: registry
  } do
    one = room(registry)
    two = room(registry)
    run(one, "thermal")
    run(two, "window_anomaly")
    :ok = ContextStore.put(nil, nil, one)
    query = Skill.callbacks()["lab_metric_query"]
    summary = query.("nx_operations_total", "rate")
    assert summary.available and summary.source == "Room history"
    assert Enum.all?(summary.series, &String.contains?(&1.name, "thermal"))
    refute Enum.any?(summary.series, &String.contains?(&1.name, "window_anomaly"))
    [history] = ContextStore.metric_results()
    [panel] = history.panels
    assert summary.queries == Enum.map(panel.digests, &%{digest: &1})
    assert Enum.all?(panel.digests, &(&1 in ContextStore.evidence()))
    assert hd(panel.chart.series).points |> Enum.any?(&is_nil(elem(&1, 1)))
    assert query.("nx_operations_total", "sum") == %{available: false, error: "invalid_request"}
    assert {:error, :invalid_request} = MetricQuery.load(one, "caller()", "rate")

    GenServer.stop(one)

    assert query.("nx_operations_total", "rate") == %{
             available: false,
             error: "history_unavailable"
           }

    assert ContextStore.metric_results() == [history]
  end

  test "receipt admission rejects foreign and expired context and obeys callback and chart limits",
       %{registry: registry} do
    one = room(registry)
    run(one, "thermal")
    :ok = ContextStore.put(nil, nil, one)
    {:room, ^one, old} = ContextStore.metric_source()
    {:ok, summary, history} = MetricQuery.load(one, "nx_batch_rows", "last")
    :ok = ContextStore.clear()
    assert ContextStore.metric_source() == :unavailable
    :ok = ContextStore.put(nil, nil, one)
    {:room, ^one, current} = ContextStore.metric_source()
    assert old != current
    assert ContextStore.charge_metric({one, old}, summary, history).error == "context_unavailable"

    assert ContextStore.charge_metric({self(), current}, summary, history).error ==
             "context_unavailable"

    assert ContextStore.usage().tool_calls == 0
    assert ContextStore.metric_results() == []

    assert ContextStore.charge_metric(
             {one, current},
             %{text: String.duplicate("x", 8_193)},
             history
           ).error == "callback_output_budget_exhausted"

    assert ContextStore.metric_results() == []

    for _ <- 1..8,
        do:
          assert(
            ContextStore.charge_metric({one, current}, %{small: true}, history) == %{small: true}
          )

    assert length(ContextStore.metric_results()) == 8

    assert ContextStore.charge_metric({one, current}, summary, history).error ==
             "metric_result_unavailable"

    :ok = ContextStore.clear()
    assert ContextStore.metric_results() == [] and ContextStore.evidence() == []
  end

  test "an empty room reports no measurements and yields no pinnable chart", %{registry: registry} do
    one = room(registry)
    :ok = ContextStore.put(nil, nil, one)
    summary = Skill.callbacks()["lab_metric_query"].("nx_batch_rows", "last")
    assert summary.available == false and summary.series == []
    assert ContextStore.metric_results() == []
  end

  defp room(registry) do
    {:ok, session} = Sessions.open(registry)
    {:ok, session} = Sessions.admit(registry, session.token, :start_room)
    session.room
  end

  defp run(room, id) do
    {:ok, experiment} = Experiments.fetch(id)
    {:ok, params} = Experiments.admit(experiment, %{})
    {:ok, _} = Room.start_run(room, id, params)
  end
end
