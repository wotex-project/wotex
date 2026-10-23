defmodule WotexLabWorkbenchWeb.E2E.LayoutProfilesTest do
  @moduledoc false

  use PhoenixTest.Playwright.Case, async: false

  alias PlaywrightEx.Frame
  alias WotexLabWorkbench.{Room, Sessions}
  alias WotexLabWorkbenchWeb.{Endpoint, Plugs.SessionToken}

  @moduletag :e2e
  @source "#wl-connection-thing"
  @pairs [{599, "compact", 76}, {600, "medium", 20}, {839, "medium", 20}, {840, "expanded", 20}]

  setup %{conn: conn} do
    {:ok, session} = Sessions.open()
    on_exit(fn -> Sessions.revoke(session.token) end)

    response =
      PlaywrightEx.send(
        %{
          guid: conn.page_id,
          method: :set_viewport_size,
          params: %{viewport_size: %{width: 1440, height: 900}}
        },
        timeout: 5_000
      )

    refute Map.has_key?(response, :error)

    conn =
      add_session_cookie(
        conn,
        [value: %{SessionToken.key() => session.token}],
        Endpoint.session_options()
      )

    %{conn: conn, token: session.token}
  end

  test "a narrower parent changes composition without allocating a room or replacing its island", %{
    conn: conn,
    token: token
  } do
    conn =
      conn
      |> visit("/")
      |> assert_has("[data-wotex-island='canvas'][data-wotex-island-state='mounted']")

    before = canvas_snapshot(conn)

    for {width, profile, _} <- @pairs do
      resize_parent(conn, width, profile)
      assert canvas_snapshot(conn) == before
      assert {:ok, %{room: nil}} = Sessions.verify(token)
      refute_has(conn, ".svelte-flow__node")
    end
  end

  test "parent boundary pairs preserve an uncommitted connection, focus and graph revision", %{
    conn: conn,
    token: token
  } do
    conn =
      conn
      |> visit("/")
      |> click_button("Start room")
      |> assert_has(".svelte-flow__edge[data-id='temperature']")
      |> press(".svelte-flow__edge[data-id='temperature']", "Enter")
      |> select("Source", option: "Actuator")
      |> select("Property", option: "target · °C")
      |> evaluate("document.querySelector('#wl-connection-thing').focus()", fn _ -> :ok end)
      |> assert_has(@source <> ":focus")

    before = canvas_snapshot(conn)
    {:ok, %{room: room}} = Sessions.verify(token)
    model = Room.connections(room)

    for {width, profile, top} <- @pairs do
      resize_parent(conn, width, profile)
      assert_has(conn, @source <> ":focus")
      assert value(conn, "document.querySelector('#wl-connection-thing').value") == "actuator"
      assert value(conn, "document.querySelector('#wl-connection-affordance').value") == "target"
      assert canvas_snapshot(conn) == before
      assert_panel_bounds(conn, "#wl-connections-panel", width, top)
      assert Room.connections(room) == model
      assert Room.runs(room) == []
      assert Enum.all?(Room.things(room), &(&1.stats.handler_calls == 0))
    end

    conn
    |> press(@source, "Escape")
    |> refute_has("#wl-connections-panel")
    |> assert_has(".svelte-flow__edge[data-id='temperature']:focus")
  end

  test "parent boundary pairs preserve pending approval identity and visible exact Action scope", %{
    conn: conn,
    token: token
  } do
    conn =
      conn
      |> visit("/experiments?experiment=smart_room")
      |> click_button("#run-smart_room", "Run")
      |> assert_path("/runs/run-1")
      |> click_link("Review Action")
      |> assert_has("#approve-run-1")
      |> evaluate("document.querySelector('#approve-run-1 button[type=submit]').focus()", fn _ ->
        :ok
      end)
      |> assert_has("#approve-run-1 button[type=submit]:focus")

    {:ok, %{room: room}} = Sessions.verify(token)
    [pending] = Room.runs(room)
    calls = handler_calls(room)

    decision =
      value(conn, "Object.fromEntries(new FormData(document.querySelector('#approve-run-1')))")

    for {width, profile, top} <- @pairs do
      resize_parent(conn, width, profile)
      assert_has(conn, "#approve-run-1 button[type=submit]:focus:not(:disabled)")
      assert_has(conn, ".wl-approval", text: pending.decision["thing_id"])
      assert_has(conn, ".wl-approval", text: pending.decision["action_name"])
      assert_has(conn, ".wl-approval", text: pending.decision["proposal_digest"])

      assert value(
               conn,
               "Object.fromEntries(new FormData(document.querySelector('#approve-run-1')))"
             ) == decision

      assert_panel_bounds(conn, "#wl-run-panel-run-1", width, top)
      assert [%{status: :awaiting_approval, dispatch: nil, decision: current}] = Room.runs(room)
      assert current == pending.decision
      assert handler_calls(room) == calls
    end

    conn
    |> click_button("Cancel run")
    |> refute_has("#approve-run-1")

    assert [%{status: :cancelled, dispatch: nil}] = Room.runs(room)
    assert handler_calls(room) == calls
  end

  defp resize_parent(conn, width, profile) do
    evaluate(conn, "document.querySelector('.wl-shell').style.width = '#{width}px'", fn _ ->
      :ok
    end)

    assert_has(conn, ".wl-main[data-layout-profile='#{profile}']")
    assert value(conn, "innerWidth") == 1440
    assert value(conn, "document.querySelector('.wl-main').getBoundingClientRect().width") == width
  end

  defp assert_panel_bounds(conn, selector, width, top) do
    assert value(conn, """
           (() => {
             const shell = document.querySelector('.wl-shell').getBoundingClientRect()
             const panel = document.querySelector(#{JSON.encode!(selector)}).getBoundingClientRect()
             return [shell.width, shell.right - panel.right, innerHeight - panel.bottom, panel.top]
           })()
           """) == [width, 20, 20, top]

    assert value(conn, """
           (() => {
             const body = document.querySelector(#{JSON.encode!(selector <> " .wl-workbench-panel-body")})
             return body.scrollWidth <= body.clientWidth
           })()
           """)
  end

  defp canvas_snapshot(conn),
    do:
      value(
        conn,
        "document.querySelector('[data-wotex-island=canvas] [data-wotex-island-mount]').dataset.wotexIslandSnapshot"
      )

  defp value(conn, expression) do
    assert {:ok, result} = Frame.evaluate(conn.frame_id, expression: expression, timeout: 5_000)
    result
  end

  defp handler_calls(room), do: Enum.map(Room.things(room), &{&1.id, &1.stats.handler_calls})
end
