defmodule WotexLabWorkbenchWeb.E2E.ConnectionsTest do
  @moduledoc false

  use PhoenixTest.Playwright.Case, async: false

  alias PhoenixTest.Playwright.{Case, Config}
  alias PlaywrightEx.Frame
  alias WotexLabWorkbench.{Room, Sessions}
  alias WotexLabWorkbenchWeb.{Endpoint, Plugs.SessionToken}

  @moduletag :e2e
  @temperature ".svelte-flow__edge[data-id='temperature']"
  @power ".svelte-flow__edge[data-id='power']"
  @source "#wl-connection-thing"
  @connections ".wl-canvas-tools button[aria-label='Connections']"

  setup %{conn: conn} do
    {:ok, session} = Sessions.open()
    on_exit(fn -> Sessions.revoke(session.token) end)
    %{conn: attach_session(conn, session.token), token: session.token}
  end

  test "keyboard editing retains a draft and returns to its edge without moving the board", %{
    conn: conn,
    token: token
  } do
    conn = start_room(conn)
    before = viewport(conn)

    conn
    |> press("#wl-board-toggle", "Tab")
    |> assert_has(@temperature <> ":focus")
    |> press(":focus", "Enter")
    |> assert_has(@source <> ":focus")
    |> select("Source", option: "Actuator")
    |> select("Property", option: "target · °C")
    |> press(@source, "Escape")
    |> assert_path("/")
    |> refute_has("#wl-connections-panel")
    |> assert_has(@temperature <> ":focus")
    |> press(":focus", "Space")
    |> assert_has(@source <> ":focus")
    |> evaluate("document.querySelector('#wl-connection-thing').value", &assert(&1 == "actuator"))
    |> evaluate(
      "document.querySelector('#wl-connection-affordance').value",
      &assert(&1 == "target")
    )

    room = room(token)
    assert Room.connections(room).revision == 0

    conn
    |> press("button[type='submit']", "Enter")
    |> assert_has("#wl-connection-temperature:focus")
    |> press(":focus", "Escape")
    |> assert_path("/")
    |> refute_has("#wl-connections-panel")
    |> assert_has(@temperature <> ":focus[aria-label='Configure target · °C connection']")

    assert viewport(conn) == before
    assert Room.connections(room).revision == 1
    assert_inert(room)
  end

  test "Back, Cancel, Apply and native Remove focus the edited row and recover a removed origin", %{
    conn: conn,
    token: token
  } do
    conn = start_room(conn)

    conn
    |> press("#wl-board-toggle", "Tab")
    |> press(":focus", "Tab")
    |> assert_has(@power <> ":focus")
    |> press(":focus", "Enter")
    |> assert_has(@source <> ":focus")
    |> press("button[aria-label='Back to connections']", "Enter")
    |> assert_has("#wl-connection-power:focus")
    |> press(":focus", "Enter")
    |> press("button[phx-click='cancel_connection']", "Enter")
    |> assert_has("#wl-connection-power:focus")
    |> press(":focus", "Enter")
    |> press("button[type='submit']", "Enter")
    |> assert_has("#wl-connection-power:focus")
    |> press(":focus", "Enter")
    |> press("button[phx-click='remove_connection']", "Enter")
    |> assert_has("#wl-connection-power:focus[aria-label='Connect Power']")
    |> refute_has(@power)
    |> press(":focus", "Escape")
    |> assert_path("/")
    |> refute_has("#wl-connections-panel")
    |> assert_has(@connections <> ":focus")
    |> press(":focus", "Enter")
    |> assert_has("#wl-connections-list")
    |> click_button("Connect Power")
    |> select("Source", option: "Energy meter")
    |> select("Property", option: "power · W")
    |> press("button[type='submit']", "Enter")
    |> assert_has("#wl-connection-power:focus[aria-label='Change Power']")
    |> assert_has(@power)

    room = room(token)
    assert Room.connections(room).revision == 2
    assert_inert(room)
  end

  test "edge and Thing context menus support keyboard navigation and restore their origin", %{
    conn: conn,
    token: token
  } do
    conn = start_room(conn)

    conn
    |> press(@temperature, "Shift+F10")
    |> assert_has("[role='menu'][aria-label='Connection actions']")
    |> press("[role='menuitem']:focus", "Escape")
    |> assert_has(@temperature <> ":focus")
    |> press(
      ".svelte-flow__node[data-id='thing-thermostat'] button[aria-label='Actions for Thermostat']",
      "Shift+F10"
    )
    |> assert_has("[role='menu'][aria-label='Thing actions']")
    |> press("[role='menuitem']:focus", "End")
    |> assert_has("[role='menuitem']:focus", text: "Room metrics")
    |> press(":focus", "ArrowUp")
    |> assert_has("[role='menuitem']:focus", text: "Sources")
    |> press(":focus", "Home")
    |> assert_has("[role='menuitem']:focus", text: "Inspect")
    |> press(":focus", "Tab")
    |> refute_has("[role='menu']")
    |> refute_has("body:focus")

    assert_inert(room(token))
  end

  test "profile changes preserve the focused editor and use a visible fallback at 320 pixels", %{
    conn: conn,
    token: token
  } do
    conn = start_room(conn)

    conn
    |> press(@power, "Enter")
    |> assert_has(@source <> ":focus")

    before = viewport(conn)

    for {width, profile, top} <- [
          {599, "compact", 76},
          {600, "medium", 20},
          {839, "medium", 20},
          {840, "expanded", 20},
          {320, "compact", 76}
        ] do
      resize(conn, width)

      conn
      |> assert_has(".wl-main[data-layout-profile='#{profile}']")
      |> assert_has(@source <> ":focus")
      |> evaluate(
        """
        (() => {
          const box = document.querySelector('#wl-connections-panel').getBoundingClientRect();
          return [innerWidth, document.documentElement.scrollWidth <= innerWidth,
                  innerWidth - box.right, innerHeight - box.bottom, box.top];
        })()
        """,
        &assert(&1 == [width, true, 20, 20, top])
      )
    end

    conn
    |> press(@source, "Escape")
    |> assert_path("/")
    |> refute_has("#wl-connections-panel")
    |> assert_has(@connections <> ":focus")

    assert viewport(conn) == before
    assert_inert(room(token))
  end

  test "a second browser changes wiring; stale Reload and a replaced edge recover focus", context do
    %{conn: conn, token: token} = context
    conn = start_room(conn)

    peer =
      Config.global()
      |> Case.new_session(context)
      |> attach_session(token)
      |> visit("/")

    conn
    |> press(@power, "Enter")
    |> assert_has(@source <> ":focus")

    peer
    |> assert_has(@power)
    |> press(@power, "Enter")
    |> click_button("Remove")
    |> assert_has("#wl-connection-power[aria-label='Connect Power']")

    conn
    |> refute_has(@power, timeout: 8_000)
    |> assert_has(@source <> ":focus")

    peer
    |> click_button("Connect Power")
    |> select("Source", option: "Energy meter")
    |> select("Property", option: "power · W")
    |> click_button("Apply")
    |> assert_has(@power)

    conn
    |> assert_has(@power, timeout: 8_000)
    |> press(@source, "Escape")
    |> assert_path("/")
    |> refute_has("#wl-connections-panel")
    |> assert_has(@power <> ":focus")
    |> press(":focus", "Enter")
    |> click_button("Apply")
    |> assert_has("#wl-connection-editor [role='alert']", text: "Connections changed")
    |> assert_has("button:has-text('Reload draft'):not(:disabled)")
    |> press("button:has-text('Reload draft')", "Enter")
    |> refute_has("#wl-connection-editor [role='alert']")
    |> assert_has(@source <> ":focus")

    room = room(token)
    assert Room.connections(room).revision == 2
    assert_inert(room)
  end

  defp attach_session(conn, token) do
    add_session_cookie(conn, [value: %{SessionToken.key() => token}], Endpoint.session_options())
  end

  defp start_room(conn) do
    conn
    |> visit("/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("[data-wotex-island='canvas'][data-wotex-island-state='mounted']")
    |> click_button("Start room")
    |> assert_has(@temperature)
    |> assert_has(@power)
  end

  defp room(token) do
    {:ok, %{room: room}} = Sessions.verify(token)
    room
  end

  defp assert_inert(room) do
    assert Room.runs(room) == []
    assert Enum.all?(Room.things(room), &(&1.stats.handler_calls == 0))
  end

  defp viewport(conn) do
    {:ok, transform} =
      Frame.evaluate(conn.frame_id,
        expression: "getComputedStyle(document.querySelector('.svelte-flow__viewport')).transform",
        timeout: 5_000
      )

    transform
  end

  defp resize(conn, width) do
    # The Elixir driver has no Page.set_viewport_size wrapper in this pinned cohort.
    response =
      PlaywrightEx.send(
        %{
          guid: conn.page_id,
          method: :set_viewport_size,
          params: %{viewport_size: %{width: width, height: 900}}
        },
        timeout: 5_000
      )

    refute Map.has_key?(response, :error)
  end
end
