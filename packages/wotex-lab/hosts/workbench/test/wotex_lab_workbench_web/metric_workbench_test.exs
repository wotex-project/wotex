defmodule WotexLabWorkbenchWeb.MetricWorkbenchTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias WotexLabWorkbench.{Room, Sessions}
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  test "an executed room query pins actual data and a saved layout restores paused", %{conn: conn} do
    conn = get(conn, "/") |> track_session()
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/experiments")
    render_submit(element(view, "#run-thermal"))
    assert_patch(view, "/runs/run-1")
    render_patch(view, "/metrics")
    refute has_element?(view, "#metric-compose-result")

    render_submit(element(view, "#metric-compose-query"), %{
      "metric" => "nx_duration_seconds",
      "range" => "5m"
    })

    assert has_element?(view, "#metric-compose-result")
    assert has_element?(view, "button[phx-click='pin_metric']:not([disabled])")
    render_click(element(view, "button[phx-click='pin_metric']"))
    assert_patch(view, "/")
    [pin] = snapshot(view)["payload"]["pins"]
    assert pin["metric"] == "nx_duration_seconds"
    assert pin["source"] == "Room history" and pin["state"] == "Auto"

    assert Enum.any?(pin["series"], fn series ->
             Enum.any?(series["points"], &is_number(List.last(&1)))
           end)

    layout = %{
      "positions" => [%{"id" => pin["id"], "x" => 30, "y" => 80, "width" => 420, "height" => 300}],
      "viewport" => %{"x" => 12, "y" => -40, "zoom" => 0.8}
    }

    event(view, "save_layout", %{"layout" => layout})
    assert snapshot(view)["payload"]["view"] == [layout["viewport"]]
    {:ok, restored, _} = live(recycle(conn), "/")
    [again] = snapshot(restored)["payload"]["pins"]
    assert again["id"] == pin["id"] and again["width"] == 420 and again["x"] == 30
    assert again["state"] == "Paused"
    assert snapshot(restored)["payload"]["view"] == [layout["viewport"]]
    assert {:ok, session} = Sessions.verify(token)
    assert [%{id: "run-1"}] = Room.runs(session.room)

    send(restored.pid, :refresh_pins)
    render(restored)
    assert hd(snapshot(restored)["payload"]["pins"])["state"] == "Paused"
    event(restored, "pin_resume", %{"id" => pin["id"]})
    render_async(restored)
    assert hd(snapshot(restored)["payload"]["pins"])["auto_refresh"]
    send(restored.pid, :refresh_pins)
    render_async(restored)
    event(restored, "pin_pause", %{"id" => pin["id"]})
    refute hd(snapshot(restored)["payload"]["pins"])["auto_refresh"]
    event(restored, "pin_refresh", %{"id" => pin["id"]})
    render_async(restored)
    refute hd(snapshot(restored)["payload"]["pins"])["auto_refresh"]

    event(restored, "inspect", %{"id" => pin["id"]})
    assert_patch(restored, "/metrics?pin=#{pin["id"]}")
    assert has_element?(restored, "#rename-pin")

    render_submit(element(restored, "#rename-pin"), %{"pin_id" => pin["id"], "title" => "Execution"})

    assert hd(snapshot(restored)["payload"]["pins"])["title"] == "Execution"
    event(restored, "pin_remove", %{"id" => pin["id"]})
    assert snapshot(restored)["payload"]["pins"] == []
  end

  test "tool opening, invalid query/layout and foreign pin references remain inert", %{conn: conn} do
    conn = get(conn, "/") |> track_session()
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/metrics")
    assert {:ok, %{room: nil}} = Sessions.verify(token)
    render_change(element(view, "#metric-compose-query"), %{"metric" => "other", "range" => "5m"})
    assert {:ok, %{room: nil}} = Sessions.verify(token)
    assert snapshot(view)["payload"]["pins"] == []

    event(view, "save_layout", %{
      "layout" => %{
        "positions" => [%{"id" => "foreign-pin", "x" => 0, "y" => 0}],
        "viewport" => %{"x" => 0, "y" => 0, "zoom" => 1}
      }
    })

    assert {:ok, %{layout: nil, pins: []}} = Sessions.board(token)
    event(view, "pin_resume", %{"id" => "foreign-pin"})
    assert {:ok, %{room: nil}} = Sessions.verify(token)
    html = render_patch(view, "/metrics?pin=foreign-pin")
    assert html =~ "Pin unavailable"
    refute has_element?(view, "#rename-pin")
    :ok = Sessions.revoke(token)

    event(view, "save_layout", %{
      "layout" => %{"positions" => [], "viewport" => %{"x" => 0, "y" => 0, "zoom" => 1}}
    })

    refute has_element?(view, "[data-wotex-island='canvas']")
  end

  defp event(view, event, payload) do
    current = snapshot(view)

    render_hook(view, "wotex:island:#{current["instance_id"]}:event", %{
      "schema" => "wotex-lab-island-event/v1",
      "component" => "canvas",
      "instance_id" => current["instance_id"],
      "client_revision" => current["revision"],
      "event" => event,
      "payload" => payload
    })
  end

  defp snapshot(view) do
    [encoded] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-wotex-island-component='canvas']")
      |> LazyHTML.attribute("data-wotex-island-snapshot")

    encoded
    |> Base.url_decode64!(padding: false)
    |> Jason.decode!()
  end
end
