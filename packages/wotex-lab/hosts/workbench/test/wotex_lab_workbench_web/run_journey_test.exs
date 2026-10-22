defmodule WotexLabWorkbenchWeb.RunJourneyTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias WotexLabWorkbench.{Room, Sessions}
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  setup %{conn: conn} do
    conn = get(conn, "/")
    token = get_session(conn, SessionToken.key())
    on_exit(fn -> Sessions.revoke(token) end)
    %{conn: recycle(conn), token: token}
  end

  test "result, data, details and Sources preserve the same Run and canvas", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/experiments")
    room = start_room(view, token)
    run(view, "thermal")
    assert_patch(view, "/runs/run-1")
    before = Room.runs(room)
    [run] = before
    assert has_element?(view, "#wl-run-result", "22.000")
    assert has_element?(view, "#run-chart-0 svg")
    refute has_element?(view, "#tensor-summary-title")
    refute has_element?(view, "#run-analysis")
    refute has_element?(view, "#investigation")
    refute has_element?(view, "form[phx-submit='approve']")

    render_click(element(view, "a[href='/runs/run-1?view=data']"))
    assert_patch(view, "/runs/run-1?view=data")
    assert has_element?(view, "#tensor-summary-title")
    assert has_element?(view, "table", "f32")
    refute has_element?(view, "#wl-run-result")
    render_click(element(view, "a[aria-label='Back to result']"))
    assert_patch(view, "/runs/run-1")

    render_click(element(view, "a[href='/runs/run-1?view=details']"))
    assert_patch(view, "/runs/run-1?view=details")
    assert has_element?(view, "#run-assertions", "thermal:proposal-inert")
    render_click(element(view, "a[href='/evidence?run=run-1']"))
    assert_patch(view, "/evidence?run=run-1")
    assert has_element?(view, "#wl-run-sources", run.record_digest)
    assert has_element?(view, "a[href='/evidence/report.json?run=run-1']")
    refute has_element?(view, "#formal-verify")
    assert Room.runs(room) == before
  end

  test "opening Action review performs no dispatch and exposes the same exact decision", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/experiments?experiment=smart_room")
    room = start_room(view, token)
    run(view, "smart_room")
    assert_patch(view, "/runs/run-1")
    [before] = Room.runs(room)
    refute has_element?(view, "form[phx-submit='approve']")
    render_click(element(view, "a[href='/runs/run-1?view=review']"))
    assert_patch(view, "/runs/run-1?view=review")
    assert has_element?(view, "input[name='decision_id'][value='#{before.decision["id"]}']")

    assert has_element?(
             view,
             "input[name='proposal_digest'][value='#{before.decision["proposal_digest"]}']"
           )

    assert render(view) =~ "s remaining"
    assert Room.runs(room) == [before]

    render_submit(element(view, "form[phx-submit='approve']"))
    [after_run] = Room.runs(room)
    assert after_run.status == :dispatched
    assert has_element?(view, "a", "Return to result")
    refute has_element?(view, "form[phx-submit='approve']")
  end

  test "the review clock expires without granting, dispatching or cancelling", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/experiments?experiment=smart_room")
    room = start_room(view, token)
    render_hook(view, "run", %{"experiment_id" => "smart_room", "params" => %{"ttl_ms" => "100"}})
    assert_patch(view, "/runs/run-1")
    render_click(element(view, "a[href='/runs/run-1?view=review']"))
    [before] = Room.runs(room)
    Process.sleep(125)
    send(view.pid, :refresh_pins)
    assert render(view) =~ "Expired · cancel this run"
    assert has_element?(view, "form[phx-submit='approve'] button[type='submit'][disabled]")
    assert Room.runs(room) == [before]
    render_click(element(view, "button[phx-click='cancel']"))
    assert [%{status: :cancelled}] = Room.runs(room)
  end

  test "passive refresh resolves another view's cancellation without replay", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/experiments?experiment=smart_room")
    room = start_room(view, token)
    run(view, "smart_room")
    render_click(element(view, "a[href='/runs/run-1?view=review']"))
    {:ok, peer, _} = live(recycle(conn), "/runs/run-1?view=review")
    render_click(element(peer, "button[phx-click='cancel']"))
    before = Room.runs(room)
    send(view.pid, :refresh_pins)
    assert render(view) =~ "No pending Action"
    refute has_element?(view, "form[phx-submit='approve']")
    assert Room.runs(room) == before
  end

  test "Run downloads contain only the selected owned record and never another decision", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/experiments")
    room = start_room(view, token)
    run(view, "thermal")
    run(view, "smart_room")
    before = Room.runs(room)

    response = get(recycle(conn), "/evidence/report.json?run=run-1")
    report = json_response(response, 200)
    assert report["scope"] == %{"kind" => "run", "run_id" => "run-1"}
    assert Enum.map(report["runs"], & &1["id"]) == ["run-1"]
    assert report["datasets"] == [] and report["formal"] == [] and report["policy"] == []

    assert get_resp_header(response, "content-disposition") == [
             ~s(attachment; filename="wotex-lab-run-evidence.json")
           ]

    assert response(get(recycle(conn), "/evidence/report.json?run=other"), 404)
    assert response(get(recycle(conn), "/evidence/report.json?run=run-1&room=other"), 400)
    assert response(get(recycle(conn), "/evidence/report.json?run[]=run-1"), 400)
    assert Room.runs(room) == before

    other = get(build_conn(), "/")
    other_token = get_session(other, SessionToken.key())
    on_exit(fn -> Sessions.revoke(other_token) end)
    assert response(get(recycle(other), "/evidence/report.json?run=run-1"), 404)
    refute json_response(get(recycle(conn), "/evidence/report.json"), 200)["scope"]
  end

  test "unknown views and unavailable Run ids cannot select or operate another Run", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/experiments")
    room = start_room(view, token)
    run(view, "thermal")
    before = Room.runs(room)

    assert {:ok, invalid, html} = live(recycle(conn), "/runs/run-1?view=approve")
    assert html =~ "invalid_run_view"
    refute has_element?(invalid, "form[phx-submit='approve']")
    assert {:ok, missing, html} = live(recycle(conn), "/runs/run-999?view=review")
    assert html =~ "unknown_run"
    refute has_element?(missing, "form[phx-submit='approve']")
    assert Room.runs(room) == before
  end

  defp start_room(view, token) do
    render_click(element(view, "button[phx-click='start_room']"))
    {:ok, %{room: room}} = Sessions.verify(token)
    room
  end

  defp run(view, id),
    do: render_hook(view, "run", %{"experiment_id" => id, "params" => %{}})
end
