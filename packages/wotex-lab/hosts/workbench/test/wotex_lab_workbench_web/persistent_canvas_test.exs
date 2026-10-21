defmodule WotexLabWorkbenchWeb.PersistentCanvasTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias WotexLabWorkbench.{Room, Sessions}
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  test "opening tools and restoring drafts performs no room or experiment command", %{conn: conn} do
    conn = get(conn, "/") |> track_session()
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/")
    original = canvas(view)
    refute has_element?(view, "#run-thermal")

    open_tool(view, "experiments")
    assert_patch(view, "/experiments?experiment=thermal")
    assert has_element?(view, "#wl-experiments-panel")
    assert canvas(view)["instance_id"] == original["instance_id"]

    render_click(element(view, "button[phx-value-id='window_anomaly']"))
    assert_patch(view, "/experiments?experiment=window_anomaly")

    render_change(element(view, "#run-window_anomaly"), %{
      "experiment_id" => "window_anomaly",
      "params" => %{"seed" => "42", "count" => "513"}
    })

    render_click(element(view, "a[aria-label='Close panel']"))
    assert_patch(view, "/")
    refute has_element?(view, "#wl-experiments-panel")
    open_tool(view, "metrics")
    assert_patch(view, "/metrics")
    refute has_element?(view, "#history-results")
    render_click(element(view, "a[aria-label='Close panel']"))
    assert_patch(view, "/")

    open_tool(view, "experiments")
    assert_patch(view, "/experiments?experiment=window_anomaly")
    assert has_element?(view, "#experiment-window_anomaly:not([hidden])")
    assert has_element?(view, "#parameter-window_anomaly-seed[value='42']")
    assert has_element?(view, "#parameter-window_anomaly-count[value='513'][aria-invalid='true']")
    assert has_element?(view, "#run-window_anomaly button[disabled]")
    assert {:ok, %{room: nil}} = Sessions.verify(token)
  end

  test "inspection, execution and selected evidence retain the board and explicit readings", %{
    conn: conn
  } do
    conn = get(conn, "/") |> track_session()
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/")
    render_click(element(view, "button[phx-click='start_room']"))
    original = canvas(view)

    inspect_node(view, "thing-thermostat")
    assert_patch(view, "/things")
    render_submit(element(view, "#read-thermostat-temperature"))
    render_click(element(view, "button[aria-label='Close inspector']"))
    assert_patch(view, "/")
    assert temperature(view) == "21.5"

    inspect_node(view, "process-smart-room")
    assert_patch(view, "/experiments?experiment=smart_room")
    assert has_element?(view, "#experiment-smart_room:not([hidden])")
    render_click(element(view, "button[phx-value-id='thermal']"))
    assert_patch(view, "/experiments?experiment=thermal")
    render_submit(element(view, "#run-thermal"))
    assert_patch(view, "/runs/run-1")
    assert has_element?(view, "#wl-run-panel-run-1")
    assert temperature(view) == "21.5"

    render_click(element(view, "a[href='/evidence?run=run-1']"))
    assert_patch(view, "/evidence?run=run-1")
    assert has_element?(view, "#wl-evidence-panel", "Run evidence")
    refute has_element?(view, "#formal-verify")
    render_click(element(view, "a[aria-label='Back to run']"))
    assert_patch(view, "/runs/run-1")
    render_click(element(view, "a[aria-label='Close panel']"))
    assert_patch(view, "/")
    assert canvas(view)["instance_id"] == original["instance_id"]
    assert temperature(view) == "21.5"
    assert {:ok, %{room: room}} = Sessions.verify(token)
    assert [%{id: "run-1"}] = Room.runs(room)
  end

  test "tool envelopes reject unknown and stale requests and revoked navigation removes the graph",
       %{conn: conn} do
    conn = get(conn, "/") |> track_session()
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/")
    snapshot = canvas(view)
    event = "wotex:island:#{snapshot["instance_id"]}:event"
    envelope = envelope(snapshot, "open", "metrics")

    for invalid <- [
          put_in(envelope, ["payload", "id"], "execute"),
          put_in(envelope, ["payload", "id"], %{"path" => "/runs/run-1"}),
          Map.put(envelope, "instance_id", "other-session--connected-things")
        ] do
      render_hook(view, event, invalid)
      refute has_element?(view, "#wl-metrics-panel")
    end

    render_patch(view, "/experiments")
    render_hook(view, event, envelope)
    refute has_element?(view, "#wl-metrics-panel")
    assert {:ok, %{room: nil}} = Sessions.verify(token)
    :ok = Sessions.revoke(token)
    assert render_patch(view, "/metrics") =~ "Session denied"
    refute has_element?(view, "[data-wotex-island='canvas']")
  end

  test "a missing selected run cannot fall back to a different run or a session report", %{
    conn: conn
  } do
    conn = get(conn, "/") |> track_session()
    {:ok, view, _} = live(recycle(conn), "/experiments")
    render_submit(element(view, "#run-thermal"))
    assert_patch(view, "/runs/run-1")
    html = render_patch(view, "/evidence?run=run-2")
    assert html =~ "unknown_run"
    refute has_element?(view, "#evidence-runs")
    refute has_element?(view, "a[download]")
    refute has_element?(view, "#investigation")
  end

  test "a revoked theme event removes the previous room from the workbench", %{conn: conn} do
    conn = get(conn, "/") |> track_session()
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/")
    render_click(view, "start_room")
    assert length(canvas(view)["payload"]["nodes"]) == 4

    :ok = Sessions.revoke(token)
    assert render_change(view, "set_theme", %{"theme" => "dark"}) =~ "Session denied"
    refute has_element?(view, "[data-wotex-island='canvas']")
  end

  test "selected evidence lists only its run and returns to that exact result", %{conn: conn} do
    conn = get(conn, "/") |> track_session()
    {:ok, view, _} = live(recycle(conn), "/experiments")
    render_submit(element(view, "#run-thermal"))
    assert_patch(view, "/runs/run-1")
    render_patch(view, "/experiments")
    render_submit(element(view, "#run-thermal"))
    assert_patch(view, "/runs/run-2")

    render_patch(view, "/evidence?run=run-1")

    table =
      view
      |> element("#evidence-runs")
      |> render()

    assert table =~ "run-1"
    refute table =~ "run-2"
    assert has_element?(view, "a[aria-label='Back to run'][href='/runs/run-1']")
    render_click(element(view, "a[aria-label='Back to run']"))
    assert_patch(view, "/runs/run-1")
    assert has_element?(view, "#wl-run-panel-run-1")
  end

  defp open_tool(view, id) do
    snapshot = canvas(view)

    render_hook(
      view,
      "wotex:island:#{snapshot["instance_id"]}:event",
      envelope(snapshot, "open", id)
    )
  end

  defp inspect_node(view, id) do
    snapshot = canvas(view)

    render_hook(
      view,
      "wotex:island:#{snapshot["instance_id"]}:event",
      envelope(snapshot, "inspect", id)
    )
  end

  defp envelope(snapshot, event, id) do
    %{
      "schema" => "wotex-lab-island-event/v1",
      "component" => "canvas",
      "instance_id" => snapshot["instance_id"],
      "client_revision" => snapshot["revision"],
      "event" => event,
      "payload" => %{"id" => id}
    }
  end

  defp temperature(view) do
    snapshot = canvas(view)
    node = Enum.find(snapshot["payload"]["nodes"], &(&1["id"] == "thing-thermostat"))
    node["value"]
  end

  defp canvas(view) do
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
