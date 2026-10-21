defmodule WotexLabWorkbench.BoardTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Island.Encoder
  alias WotexLabWorkbench.{Board, Canvas, Chart, Sessions}

  test "pins preserve the exact measured series, gaps, source and window" do
    history = history()
    assert {:ok, board} = Board.change(Board.empty(), {:pin, history})
    [pin] = board.pins
    assert pin.metric == "nx_batch_rows" and pin.range == "5m"
    assert pin.window.end_ms == history.end_ms
    assert pin.result.chart == hd(history.panels).chart
    assert {:ok, same} = Board.change(board, {:pin, history})
    assert length(same.pins) == 1

    props = Canvas.props([], [], %{}) |> Board.decorate(board, MapSet.new([pin.id]))
    assert {:ok, ^props} = Encoder.encode("canvas", props)
    [projected] = props["pins"]
    assert projected["source"] == "Room history" and projected["state"] == "Auto"
    assert [%{"points" => points}] = projected["series"]
    assert [-15, nil] in points
    assert [-20, 2] in points and [-10, 4] in points
    refute Enum.any?(points, &(List.last(&1) == 0))
    assert hd(Board.decorate(Canvas.props([], [], %{}), board)["pins"])["state"] == "Paused"
  end

  test "invalid source definitions, numerical envelopes and empty results cannot create a pin" do
    history = history()
    %{panels: [%{chart: %Chart{} = chart}]} = history

    for invalid <- [
          nil,
          %{},
          %{history | range: "30d"},
          put_in(history, [:panels, Access.at(0), :id], "caller_metric"),
          put_in(history, [:panels, Access.at(0), :display_unit], "W"),
          put_in(history, [:panels, Access.at(0), :digests], []),
          put_in(history, [:panels, Access.at(0), :chart], nil),
          put_in(history, [:panels, Access.at(0), :chart], %Chart{
            chart
            | series: [%{name: "invalid", points: [{0, 4}]}]
          })
        ] do
      assert {:error, _} = Board.change(Board.empty(), {:pin, invalid})
    end
  end

  test "a failed refresh keeps the original timestamped data instead of drawing zero" do
    history = history()
    {:ok, board} = Board.change(Board.empty(), {:pin, history})
    [pin] = board.pins

    unavailable = %{
      history
      | start_ms: history.start_ms + 5_000,
        end_ms: history.end_ms + 5_000,
        panels: [%{hd(history.panels) | status: :unavailable, chart: nil, digests: []}]
    }

    assert {:ok, refreshed} = Board.change(board, {:refresh, [unavailable]})
    assert [cached] = refreshed.pins
    assert cached.result == pin.result and cached.window == pin.window
    assert cached.checked_at == unavailable.end_ms
    assert cached.error == "Refresh unavailable"
    props = Board.decorate(Canvas.props([], [], %{}), refreshed, MapSet.new([pin.id]))
    assert hd(props["pins"])["auto_refresh"]
    {:ok, paused} = Board.change(refreshed, {:pause, pin.id, true})

    refute hd(Board.decorate(Canvas.props([], [], %{}), paused, MapSet.new([pin.id]))["pins"])[
             "auto_refresh"
           ]

    assert {:ok, failed} =
             Board.change(board, {:refresh, [{:unavailable, [pin.id], 1_799_000_400_000}]})

    assert hd(failed.pins).result == pin.result
    assert hd(failed.pins).checked_at == 1_799_000_400_000
    {:ok, removed} = Board.change(board, {:remove, pin.id})
    assert {:ok, %{pins: []}} = Board.change(removed, {:refresh, [history]})
  end

  test "layout admits geometry for current identities and restores viewport and pin size" do
    {:ok, board} = Board.change(Board.empty(), {:pin, history()})
    [pin] = board.pins

    layout = %{
      "positions" => [%{"id" => pin.id, "x" => 25, "y" => 30, "width" => 440, "height" => 310}],
      "viewport" => %{"x" => -12, "y" => 45, "zoom" => 0.75}
    }

    assert {:ok, saved} = Board.change(board, {:layout, layout, []})
    props = Board.decorate(Canvas.props([], [], %{}), saved)
    assert props["view"] == [layout["viewport"]] and props["layout_revision"] == "1"
    assert hd(props["pins"])["width"] == 440
    assert {:ok, ^props} = Encoder.encode("canvas", props)

    for bad <- [
          Map.put(layout, "query", "caller()"),
          put_in(layout, ["positions", Access.at(0), "id"], "another-session-pin"),
          put_in(layout, ["positions", Access.at(0), "x"], 20_001),
          put_in(layout, ["positions", Access.at(0), "width"], 299),
          put_in(layout, ["viewport", "zoom"], 0),
          %{layout | "positions" => layout["positions"] ++ layout["positions"]}
        ] do
      assert {:error, _} = Board.change(saved, {:layout, bad, []})
    end

    assert {:ok, removed} = Board.change(saved, {:remove, pin.id})
    assert removed.pins == []
    assert {:error, _} = Board.change(removed, {:rename, pin.id, "other"})
  end

  test "session board changes cannot substitute a room or survive revocation" do
    lab = start_supervised!({Wotex.Lab, id: "board-sessions"})

    registry =
      start_supervised!(
        {Sessions,
         lab: lab, ttl_ms: 60_000, sweep_ms: 1_000, max_sessions: 4, name: __MODULE__.Registry}
      )

    {:ok, one} = Sessions.open(registry)
    {:ok, two} = Sessions.open(registry)
    {:ok, one} = Sessions.admit(registry, one.token, :start_room)
    {:ok, two} = Sessions.admit(registry, two.token, :start_room)

    assert {:error, %{code: :room_changed}} =
             Sessions.change_board(registry, two.token, one.room, {:pin, history()})

    assert {:ok, %{pins: []}} = Sessions.board(registry, two.token)

    assert {:ok, %{pins: [_]}} =
             Sessions.change_board(registry, one.token, one.room, {:pin, history()})

    :ok = Sessions.revoke(registry, one.token)
    assert {:error, _} = Sessions.board(registry, one.token)
    assert {:ok, %{pins: []}} = Sessions.board(registry, two.token)
  end

  defp history do
    points =
      for offset <- -300..0//5,
          do: {offset, if(offset == -20, do: 2, else: if(offset == -10, do: 4))}

    {:ok, chart} =
      Chart.new(
        title: "Batch rows",
        x: %{field: "offset_s", title: "Seconds before range end"},
        y: %{field: "value", title: "rows"},
        series: [%{name: "profile=test", points: points}]
      )

    %{
      range: "5m",
      start_ms: 1_799_000_000_000,
      end_ms: 1_799_000_300_000,
      step_ms: 5_000,
      panels: [
        %{
          id: "nx_batch_rows",
          title: "Batch rows",
          status: :available,
          chart: chart,
          aggregation: "last value per step",
          display_unit: "rows",
          series_shown: 1,
          series_total: 1,
          freshness_ms: 10_000,
          markers: %{},
          error: nil,
          digests: ["sha256:" <> String.duplicate("a", 64)]
        }
      ]
    }
  end
end
