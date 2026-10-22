defmodule WotexLabWorkbenchWeb.E2E.BoardSearchTest do
  @moduledoc false

  use PhoenixTest.Playwright.Case, async: false

  alias PhoenixTest.Playwright.{Case, Config}
  alias PlaywrightEx.Frame
  alias WotexLabWorkbench.{Canvas, Room, Sessions}
  alias WotexLabWorkbenchWeb.{Endpoint, Plugs.SessionToken}

  @moduletag :e2e
  @input "#wl-board-search-query"
  @results "#wl-board-search-results"

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

  test "menu and shortcut open inert lookup; keyboard inspection and Back preserve context", %{
    conn: conn,
    token: token
  } do
    conn
    |> visit("/")
    |> assert_has("[data-phx-main].phx-connected")
    |> click_button("Board menu")
    |> click_button("Search board")
    |> assert_has(@input <> ":focus")
    |> assert_has("#wl-board-search-content", text: "Your board is empty")

    assert {:ok, %{room: nil}} = Sessions.verify(token)

    conn
    |> press(@input, "Escape")
    |> assert_path("/")
    |> assert_has("#wl-board-toggle:focus")
    |> click_button("Start room")
    |> assert_has(".svelte-flow__node[data-id='thing-thermostat']")

    before = viewport(conn)

    conn
    |> press("#wl-board-toggle", "ControlOrMeta+k")
    |> assert_has(@input <> ":focus")
    |> assert_has(@results <> " button", count: 4)
    |> capture("desktop")
    |> fill_in("Search board", with: "THERMOstat 01")
    |> assert_has(@results <> " button", count: 1)
    |> press(@input, "ArrowDown")
    |> assert_has("#wl-search-result-thing-thermostat:focus")
    |> press(":focus", "Enter")
    |> assert_has("#wl-thing-inspector-thing-thermostat")
    |> press("button[aria-label='Back to search']", "Enter")
    |> assert_has("#wl-search-result-thing-thermostat:focus")
    |> evaluate(
      "document.querySelector('#wl-board-search-query').value",
      &assert(&1 == "THERMOstat 01")
    )
    |> press(":focus", "Escape")
    |> assert_path("/")
    |> assert_has("#wl-board-toggle:focus")

    assert viewport(conn) == before
    assert_inert(token)
  end

  test "narrow search has clean edge insets, keyboard bounds, empty reset and an inert process", %{
    conn: conn,
    token: token
  } do
    resize(conn, 320)

    conn
    |> visit("/")
    |> assert_has("[data-phx-main].phx-connected")
    |> click_button("Start room")
    |> assert_has(".svelte-flow__node[data-id='thing-thermostat']")
    |> press("#wl-board-toggle", "ControlOrMeta+k")
    |> assert_has(@input <> ":focus")
    |> assert_has(".wl-main[data-layout-profile='compact']")
    |> evaluate(
      """
      (() => {
        const panel = document.querySelector('#wl-board-search-panel').getBoundingClientRect();
        return [panel.left, panel.top, innerWidth-panel.right, innerHeight-panel.bottom,
                document.documentElement.scrollWidth <= innerWidth];
      })()
      """,
      &assert(&1 == [20, 76, 20, 20, true])
    )
    |> press(@input, "ArrowUp")
    |> assert_has("#wl-search-result-thing-thermostat:focus")
    |> press(":focus", "Home")
    |> assert_has("#wl-search-result-thing-actuator:focus")
    |> press(":focus", "End")
    |> assert_has("#wl-search-result-thing-thermostat:focus")
    |> press(":focus", "ArrowDown")
    |> assert_has("#wl-search-result-thing-actuator:focus")
    |> press(":focus", "ControlOrMeta+k")
    |> assert_has(@input <> ":focus")
    |> fill_in("Search board", with: "no such object")
    |> assert_has("#wl-board-search-content", text: "No matches")
    |> click_button("Clear search")
    |> assert_has(@input <> ":focus")
    |> evaluate("document.querySelector('#wl-board-search-query').value", &assert(&1 == ""))
    |> assert_has(@results <> " button", count: 4)
    |> capture("mobile")
    |> fill_in("Search board", with: "process")
    |> assert_has(@results <> " button", count: 1)
    |> press(@input, "ArrowDown")
    |> assert_has(@results <> " button:focus")
    |> press(":focus", "Enter")
    |> assert_has("#experiment-smart_room:not([hidden])")
    |> press("button[aria-label='Back to search']", "Enter")
    |> assert_has("#wl-search-result-process-smart-room:focus")

    assert_inert(token)
  end

  test "a saved Run pin opens, returns to search and recovers when another view removes it",
       context do
    %{conn: conn, token: token} = context

    conn
    |> visit("/experiments")
    |> assert_has("[data-phx-main].phx-connected")
    |> click_button("#run-thermal", "Run")
    |> assert_has("#wl-run-panel-run-1")
    |> click_button("Pin result")
    |> assert_path("/")

    {:ok, %{room: room}} = Sessions.verify(token)
    before = Room.runs(room)

    conn
    |> press("#wl-board-toggle", "ControlOrMeta+k")
    |> assert_has(@input <> ":focus")
    |> fill_in("Search board", with: "run-1")
    |> assert_has(@results <> " button", count: 1)
    |> press(@input, "ArrowDown")
    |> assert_has(@results <> " button:focus")
    |> press(":focus", "Enter")
    |> assert_has("#wl-run-pin")
    |> fill_in("Title", with: "Thermal comparison")
    |> click_button("Rename")
    |> press("button[aria-label='Back to search']", "Enter")
    |> assert_has(@results <> " strong", text: "Thermal comparison")
    |> assert_has(@results <> " button:focus")

    {:ok, %{pins: [pin]}} = Sessions.board(token)

    peer =
      Config.global()
      |> Case.new_session(context)
      |> add_session_cookie([value: %{SessionToken.key() => token}], Endpoint.session_options())
      |> visit("/metrics?pin=#{pin.id}")
      |> assert_has("#wl-run-pin")

    peer
    |> click_button("#wl-run-pin", "Remove")
    |> assert_path("/")

    conn
    |> refute_has(@results <> " button", timeout: 8_000)
    |> assert_has(@input <> ":focus")
    |> assert_has("#wl-board-search-content", text: "No matches")

    assert Room.runs(room) == before
  end

  test "dark and contrast lookup use compact shared surfaces", %{conn: conn, token: token} do
    conn
    |> visit("/")
    |> assert_has("[data-phx-main].phx-connected")
    |> click_button("Start room")
    |> assert_has(".svelte-flow__node[data-id='thing-thermostat']")

    for theme <- ~w(dark contrast) do
      conn
      |> click_button("Board menu")
      |> select("Appearance", option: theme)
      |> click_button("Search board")
      |> assert_has(".wl-shell[data-wotex-theme='#{theme}']")
      |> assert_has(@input <> ":focus")
      |> assert_has(@results <> " button", count: 4)
      |> evaluate(
        """
        (() => {
          const panel = document.querySelector('#wl-board-search-panel');
          const field = document.querySelector('#wl-board-search-query');
          const row = document.querySelector('#wl-board-search-results button');
          return [getComputedStyle(panel).borderRadius, field.getBoundingClientRect().height,
                  getComputedStyle(row).boxShadow];
        })()
        """,
        &assert(&1 == ["4px", 28, "none"])
      )
      |> capture(theme)
      |> press(@input, "Escape")
      |> assert_path("/")
      |> refute_has("#wl-board-search-panel")
    end

    assert_inert(token)
  end

  test "an offscreen Directory entry can be inspected at 320 pixels without moving the board", %{
    conn: conn,
    token: token
  } do
    resize(conn, 320)

    conn
    |> visit("/")
    |> assert_has("[data-phx-main].phx-connected")
    |> click_button("Start room")
    |> assert_has(".svelte-flow__node[data-id='thing-thermostat']")

    {:ok, %{room: room}} = Sessions.verify(token)

    source =
      Jason.encode!(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:test:search-offscreen",
        "title" => "Offscreen sensor",
        "security" => ["nosec_sc"],
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}}
      })

    assert {:ok, _} = Room.register_td(room, source)

    # Start this journey from an owned layout with the entry outside the viewport.
    things = Room.things(room)
    entry = Enum.find(things, &(&1.id == "urn:test:search-offscreen"))

    layout = %{
      "positions" => [%{"id" => Canvas.id(entry), "x" => 5000, "y" => 300}],
      "viewport" => %{"x" => 0, "y" => 0, "zoom" => 1}
    }

    ids = ["process-smart-room" | Enum.map(things, &Canvas.id/1)]
    assert {:ok, _} = Sessions.change_board(token, room, {:layout, layout, ids})

    conn
    |> visit("/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has(".svelte-flow__node[data-id^='entry-']")

    before = viewport(conn)

    conn
    |> press("#wl-board-toggle", "ControlOrMeta+k")
    |> assert_has(@input <> ":focus")
    |> fill_in("Search board", with: "search-offscreen")
    |> assert_has(@results <> " button", count: 1)
    |> assert_has(".svelte-flow__node[data-id^='entry-']")
    |> evaluate(
      """
      document.querySelector('.svelte-flow__node[data-id^="entry-"]').getBoundingClientRect().left > innerWidth
      """,
      &assert/1
    )
    |> press(@input, "ArrowDown")
    |> assert_has(@results <> " button:focus")
    |> press(":focus", "Enter")
    |> assert_has("[aria-label='Thing inspector']", text: "Directory entry · not connected")
    |> assert_has("[aria-label='Thing inspector'] details[open]", text: "Sources")
    |> refute_has("[aria-label='Thing inspector'] form[phx-submit='read']")
    |> press("button[aria-label='Close inspector']", "Enter")
    |> assert_path("/")
    |> assert_has("#wl-board-toggle:focus")

    assert viewport(conn) == before
    assert_inert(token)
  end

  defp capture(conn, name) do
    screenshot(conn, "board-search-#{name}.png", full_page: false)
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

  defp assert_inert(token) do
    {:ok, %{room: room}} = Sessions.verify(token)
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
end
