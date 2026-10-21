defmodule WotexLabWorkbench.BoardHistoryTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias WotexLabWorkbench.{BoardHistory, Experiments, Room, Sessions}

  test "refresh rotates bounded range groups and retains their room source" do
    lab = start_supervised!({Wotex.Lab, id: "board-history"})

    registry =
      start_supervised!(
        {Sessions,
         lab: lab, ttl_ms: 60_000, sweep_ms: 1_000, max_sessions: 4, name: __MODULE__.Registry}
      )

    {:ok, session} = Sessions.open(registry)
    {:ok, session} = Sessions.admit(registry, session.token, :run)
    {:ok, experiment} = Experiments.fetch("thermal")
    {:ok, params} = Experiments.admit(experiment, %{})
    {:ok, _} = Room.start_run(session.room, "thermal", params)
    {:ok, binding} = Room.history(session.room)

    pins =
      for range <- ~w(15m 1h 5m), do: %{id: "pin-#{range}", metric: "nx_batch_rows", range: range}

    result = BoardHistory.load(binding, pins, 1)
    assert Enum.map(result, & &1.range) == ~w(1h 5m 15m)
    assert Enum.all?(result, &is_integer(&1.queried_at))

    assert Enum.all?(result, fn history ->
             [%{id: "nx_batch_rows", status: :available, chart: chart}] = history.panels

             Enum.any?(chart.series, fn series ->
               Enum.any?(series.points, &is_number(elem(&1, 1)))
             end)
           end)

    assert BoardHistory.load(binding, []) == []
  end

  test "unavailable history returns only the existing pin identities and check time" do
    pins = [%{id: "pin-rows", metric: "nx_batch_rows", range: "5m"}]
    assert [{:unavailable, ["pin-rows"], checked_at}] = BoardHistory.load(%{}, pins)
    assert is_integer(checked_at)
  end
end
