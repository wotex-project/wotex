defmodule WotexLabWorkbenchWeb.E2E.ThingInspectorTest do
  @moduledoc false

  use PhoenixTest.Playwright.Case, async: false

  alias Wotex.Lab.Reference.Thing
  alias WotexLabWorkbench.{Room, Sessions}
  alias WotexLabWorkbenchWeb.{Endpoint, Plugs.SessionToken}

  @moduletag :e2e
  @inspector "[aria-label='Thing inspector']"
  @statistics @inspector <> " details:has(> summary:text-is('Statistics'))"
  @sources @inspector <> " details:has(> summary:text-is('Sources'))"
  @label @inspector <> " section[aria-label='label']"
  @temperature @inspector <> " section[aria-label='temperature']"
  @target @inspector <> " section[aria-label='target']"

  setup %{conn: conn} do
    {:ok, session} = Sessions.open()
    on_exit(fn -> Sessions.revoke(session.token) end)

    conn =
      add_session_cookie(
        conn,
        [value: %{SessionToken.key() => session.token}],
        Endpoint.session_options()
      )

    %{conn: conn, token: session.token}
  end

  test "disclosure choices survive reads, errors, observation frames and pause", %{
    conn: conn,
    token: token
  } do
    conn =
      conn
      |> start_room()
      |> click_button("Actions for Actuator")
      |> click("[role='menuitem']", "Inspect")
      |> assert_has(@inspector)
      |> click(@statistics <> " > summary", "Statistics")
      |> click(@sources <> " > summary", "Sources")
      |> click_button("Read target")
      |> assert_has(@target <> " .wl-inspector-reading", text: "21.0°C")
      |> assert_has(@statistics <> "[open]")
      |> assert_has(@sources <> "[open] time")
      |> click_button("Read label")
      |> assert_has(@label <> " [role='alert']", text: "Invalid numeric reading")
      |> refute_has(".wl-flash-error")
      |> assert_has(@statistics <> "[open]")
      |> assert_has(@sources <> "[open]")
      |> click_button("Observe")
      |> assert_has(@temperature <> " header", text: "Waiting")
      |> assert_has(@statistics <> "[open]")
      |> assert_has(@sources <> "[open]")

    {:ok, %{room: room}} = Sessions.verify(token)
    host = :sys.get_state(room).things["actuator"].pid
    :ok = Thing.emit(host, "temperature", 23.2)

    conn
    |> assert_has(@temperature <> " header", text: "Live")
    |> assert_has(@temperature <> " .wl-inspector-reading", text: "23.2°C")
    |> assert_has(@statistics <> "[open]")
    |> assert_has(@sources <> "[open]")
    |> click_button("Pause")
    |> assert_has(@temperature <> " header", text: "Paused")
    |> assert_has(@target <> " .wl-inspector-reading", text: "21.0°C")
    |> assert_has(@statistics <> "[open]")
    |> assert_has(@sources <> "[open]")
    |> screenshot("thing-inspector-retained-disclosures.png", full_page: false)
    |> click(@statistics <> " > summary", "Statistics")
    |> click_button("Read temperature")
    |> assert_has(@temperature <> " header", text: "Read")
    |> assert_has(@statistics <> ":not([open])")
    |> assert_has(@sources <> "[open]")
    |> evaluate(
      """
      Array.from(document.querySelectorAll("section[aria-label='temperature'] .wl-inspector-reading > *"),
        element => {
          const style = getComputedStyle(element);
          return [style.fontSize, style.lineHeight, style.fontWeight];
        })
      """,
      &assert(&1 == [["24px", "28px", "500"], ["24px", "28px", "500"]])
    )

    assert Room.runs(room) == []
    assert Thing.stats(host).subscriptions == 0
  end

  test "an explicit context destination opens its section after a different disclosure choice", %{
    conn: conn
  } do
    conn
    |> start_room()
    |> click_button("Actions for Thermostat")
    |> click("[role='menuitem']", "Statistics")
    |> assert_has(@statistics <> "[open]")
    |> click(@statistics <> " > summary", "Statistics")
    |> click(@sources <> " > summary", "Sources")
    |> click_button("Read temperature")
    |> assert_has(@statistics <> ":not([open])")
    |> assert_has(@sources <> "[open]")
    |> click_button("Actions for Thermostat")
    |> click("[role='menuitem']", "Sources")
    |> assert_has(@sources <> "[open]")
    |> assert_has(@statistics <> ":not([open])")
    |> click_button("Actions for Thermostat")
    |> click("[role='menuitem']", "Statistics")
    |> assert_has(@statistics <> "[open]")
    |> assert_has(@sources <> ":not([open])")
  end

  test "a failed read stays with its Property and a successful retry clears only that error", %{
    conn: conn,
    token: token
  } do
    conn =
      conn
      |> start_room()
      |> click_button("Actions for Actuator")
      |> click("[role='menuitem']", "Inspect")
      |> click_button("Read temperature")
      |> assert_has(@temperature <> " .wl-inspector-reading", text: "20.0°C")
      |> click_button("Read label")
      |> assert_has(@label <> " [role='alert']", text: "Invalid numeric reading")

    {:ok, %{room: room}} = Sessions.verify(token)
    host = :sys.get_state(room).things["actuator"].pid
    :ok = Thing.emit(host, "temperature", "invalid")

    conn =
      conn
      |> click_button("Read temperature")
      |> assert_has(@temperature <> " .wl-inspector-reading", text: "20.0°C")
      |> assert_has(@temperature <> " [role='alert']", text: "Invalid numeric reading")
      |> assert_has(
        "#read-actuator-temperature button[aria-describedby='wl-property-error-actuator-temperature']"
      )
      |> refute_has(".wl-flash-error")
      |> click(@sources <> " > summary", "Sources")
      |> assert_has(@sources <> " .wl-property-errors dt", text: "temperature error")
      |> assert_has(@sources <> " .wl-property-errors code", text: "invalid_property_reading")

    :ok = Thing.emit(host, "temperature", 21.2)

    conn
    |> click_button("Read temperature")
    |> assert_has(@temperature <> " .wl-inspector-reading", text: "21.2°C")
    |> refute_has(@temperature <> " [role='alert']")
    |> refute_has("#read-actuator-temperature button[aria-describedby]")
    |> refute_has(@sources <> " .wl-property-errors dt", text: "temperature error")
    |> assert_has(@label <> " [role='alert']", text: "Invalid numeric reading")
    |> assert_has(@sources <> " .wl-property-errors dt", text: "label error")
    |> assert_has(@sources <> "[open]")
    |> assert_has("button[aria-label='Close inspector'].wl-panel-close img[src='/icons/x.svg']")
    |> refute_has(".wl-flash-error")
    |> screenshot("thing-inspector-property-errors.png", full_page: false)

    assert Room.runs(room) == []
    assert Thing.stats(host).subscriptions == 0
  end

  test "Property feedback and icon controls fit the narrow dark and contrast inspector", %{
    conn: conn
  } do
    resize(conn, 320)
    conn = start_room(conn)

    for {theme, filter} <- [{"dark", "invert(1)"}, {"contrast", "none"}] do
      conn
      |> click_button("Board menu")
      |> select("Appearance", option: theme)
      |> click_button("Search board")
      |> fill_in("Search board", with: "actuator")
      |> press("#wl-board-search-query", "ArrowDown")
      |> press(":focus", "Enter")
      |> assert_has(".wl-shell[data-wotex-theme='#{theme}']")
      |> click_button("Read label")
      |> assert_has(@label <> " [role='alert']", text: "Invalid numeric reading")
      |> refute_has(".wl-flash-error")
      |> evaluate(
        """
        (() => {
          const panel = document.querySelector('[aria-label="Thing inspector"]');
          const box = panel.getBoundingClientRect();
          const buttons = Array.from(panel.querySelectorAll('header > button'));
          return [box.left, box.top, innerWidth-box.right, innerHeight-box.bottom,
                  document.documentElement.scrollWidth <= innerWidth,
                  buttons.map(button => [button.getBoundingClientRect().width,
                                         button.getBoundingClientRect().height,
                                         getComputedStyle(button.querySelector('img')).filter])];
        })()
        """,
        &assert(&1 == [20, 76, 20, 20, true, [[28, 28, filter], [28, 28, filter]]])
      )
      |> screenshot("thing-inspector-#{theme}-narrow.png", full_page: false)
      |> press("button[aria-label='Close inspector']", "Enter")
      |> assert_has("#wl-board-toggle:focus")
    end
  end

  test "a failed canvas read opens its inspector without a false selection-change alert", %{
    conn: conn,
    token: token
  } do
    conn = start_room(conn)
    {:ok, %{room: room}} = Sessions.verify(token)
    host = :sys.get_state(room).things["thermostat"].pid
    :ok = Thing.emit(host, "temperature", "invalid")

    conn
    |> click_button("Actions for Thermostat")
    |> click("[role='menuitem']", "Read Property")
    |> assert_has(@temperature <> " [role='alert']", text: "Invalid numeric reading")
    |> click(@sources <> " > summary", "Sources")
    |> assert_has(@sources <> " .wl-property-errors code", text: "invalid_property_reading")
    |> refute_has(".wl-canvas-notice[role='alert']")
    |> refute_has(".wl-flash-error")
    |> screenshot("thing-inspector-canvas-error.png", full_page: false)
    |> press("button[aria-label='Close inspector']", "Enter")
    |> assert_has(".svelte-flow__node[data-id='thing-thermostat']:focus")

    assert Thing.stats(host).handler_calls == 1
    assert Thing.stats(host).subscriptions == 0
    assert Room.runs(room) == []
  end

  defp start_room(conn) do
    conn
    |> visit("/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("[data-wotex-island='canvas'][data-wotex-island-state='mounted']")
    |> click_button("Start room")
    |> assert_has(".svelte-flow__node[data-id='thing-actuator']")
  end

  defp resize(conn, width) do
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
