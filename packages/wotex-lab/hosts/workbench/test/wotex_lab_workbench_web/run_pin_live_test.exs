defmodule WotexLabWorkbenchWeb.RunPinLiveTest do
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

  test "pin, arrange, reload, inspect, rename and remove retain the same recorded Run", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/experiments")
    render_hook(view, "run", %{"experiment_id" => "thermal", "params" => %{}})
    assert_patch(view, "/runs/run-1")
    {:ok, %{room: room}} = Sessions.verify(token)
    before = Room.runs(room)
    render_click(element(view, "button[phx-click='pin_run_chart']"), %{"value" => ""})
    assert_patch(view, "/")
    {:ok, %{pins: [pin]}} = Sessions.board(token)
    assert pin.kind == :run and pin.outcome.value == "22.000"
    assert hd(canvas(view)["payload"]["pins"])["kind"] == "run"

    layout = %{
      "positions" => [%{"id" => pin.id, "x" => 12, "y" => 34, "width" => 440, "height" => 320}],
      "viewport" => %{"x" => -100, "y" => 50, "zoom" => 0.75}
    }

    island(view, "save_layout", %{"layout" => layout})
    render_hook(view, "inspect_thing", %{"id" => pin.id})
    assert_patch(view, "/metrics?pin=#{pin.id}")
    assert has_element?(view, "#wl-run-pin", pin.record_digest)
    refute has_element?(view, "#metric-query-builder")

    render_submit(element(view, "#rename-run-pin"), %{
      "pin_id" => pin.id,
      "title" => "Thermal comparison"
    })

    {:ok, restored, _} = live(recycle(conn), "/")
    [capture] = canvas(restored)["payload"]["pins"]
    assert capture["title"] == "Thermal comparison"
    assert capture["x"] == 12 and capture["width"] == 440
    assert canvas(restored)["payload"]["view"] == [layout["viewport"]]
    send(restored.pid, :refresh_pins)
    render(restored)
    island(restored, "pin_open_run", %{"id" => pin.id})
    assert_patch(restored, "/runs/run-1")
    assert Room.runs(room) == before
    render_hook(restored, "inspect_thing", %{"id" => pin.id})
    render_click(element(restored, "button[phx-click='remove_pin']"), %{"value" => ""})
    assert_patch(restored, "/")
    assert {:ok, %{pins: []}} = Sessions.board(token)
  end

  test "capturing an admitted comparison preserves its query and never starts another Run", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/experiments")
    render_hook(view, "run", %{"experiment_id" => "thermal", "params" => %{}})
    {:ok, %{room: room}} = Sessions.verify(token)
    render_patch(view, "/runs/run-1?analysis[from]=1000&analysis[to]=1000&analysis[mark]=point")
    before = Room.runs(room)
    render_click(element(view, "button[phx-click='pin_run_chart']"))
    assert_patch(view, "/")
    {:ok, %{pins: [pin]}} = Sessions.board(token)
    assert pin.mark == "point"
    assert hd(pin.result.chart.series).points == [{1.0, 22.0}]
    assert pin.path =~ "analysis[mark]=point"
    assert Room.runs(room) == before
    island(view, "pin_refresh", %{"id" => pin.id})
    assert render(view) =~ "Captured Run pins cannot refresh"
    assert {:ok, %{pins: [^pin]}} = Sessions.board(token)
  end

  test "stale and foreign captures are refused while pending Action authority is unchanged", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/experiments")
    render_hook(view, "run", %{"experiment_id" => "smart_room", "params" => %{}})
    {:ok, %{room: room}} = Sessions.verify(token)
    [run] = before = Room.runs(room)

    params = %{
      "run_id" => run.id,
      "index" => "0",
      "record_digest" => "sha256:" <> String.duplicate("0", 64),
      "query" => "null"
    }

    assert render_hook(view, "pin_run_chart", params) =~ "stale_run_pin"
    assert {:ok, %{pins: []}} = Sessions.board(token)
    render_hook(view, "pin_run_chart", Map.put(params, "record_digest", run.record_digest))
    assert_patch(view, "/")
    assert Room.runs(room) == before
    assert hd(Room.runs(room)).status == :awaiting_approval
    other = get(build_conn(), "/")
    other_token = get_session(other, SessionToken.key())
    on_exit(fn -> Sessions.revoke(other_token) end)

    assert {:error, %{code: :room_changed}} =
             Sessions.change_board(other_token, room, {:pin_run, run.id, run.record_digest, 0, nil})

    assert {:ok, %{pins: []}} = Sessions.board(other_token)
    assert {:error, _} = Sessions.change_board(token, room, {:pin_run, run, 0, nil})
  end

  defp island(view, event, payload) do
    s = canvas(view)

    render_hook(view, "wotex:island:#{s["instance_id"]}:event", %{
      "schema" => "wotex-lab-island-event/v1",
      "component" => "canvas",
      "instance_id" => s["instance_id"],
      "client_revision" => s["revision"],
      "event" => event,
      "payload" => payload
    })
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
