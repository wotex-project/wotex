defmodule WotexLabWorkbenchWeb.E2E.RunPinsTest do
  @moduledoc false

  use PhoenixTest.Playwright.Case, async: false

  alias WotexLabWorkbench.{Room, Sessions}
  alias WotexLabWorkbenchWeb.{Endpoint, Plugs.SessionToken}

  @moduletag :e2e
  @pin ".svelte-flow__node[data-id^='pin-run-']"
  @menu "[role='menu'][aria-label='Run result actions']"

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

  test "a recorded capture survives rename and saved reload; Open run and repinning never replay it",
       %{conn: conn, token: token} do
    conn = capture_thermal(conn)
    {:ok, %{room: room}} = Sessions.verify(token)
    [run] = before = Room.runs(room)
    {:ok, %{pins: [original]}} = Sessions.board(token)

    assert original.run_id == run.id
    assert original.record_digest == run.record_digest
    assert hd(original.result.chart.series).points == [{0.0, 20.0}, {1.0, 22.0}]

    conn
    |> click_button("Fit connected Things")
    |> click(@pin <> " summary", "Data")
    |> assert_has(@pin <> " details[open] tbody tr", count: 2)
    |> click_button("Actions for temperature (°C)")
    |> assert_has(@menu)
    |> refute_has(@menu, text: "Refresh")
    |> refute_has(@menu, text: "Pause")
    |> press("[role='menuitem']:focus", "Enter")
    |> assert_has("#wl-run-pin")
    |> click("#wl-run-pin > details > summary", "Sources")
    |> assert_has("#wl-run-pin details[open] code", text: original.record_digest)
    |> fill_in("Title", with: "Thermal comparison")
    |> click_button("Rename")
    |> click_link("Close panel")
    |> assert_path("/")
    |> assert_has(@pin <> " header strong", text: "Thermal comparison")
    |> click_button("Save layout")
    |> assert_has("button[aria-label='Save layout'][title='Layout saved']")

    {:ok, %{pins: [renamed], layout: layout}} = Sessions.board(token)
    assert renamed.title == "Thermal comparison"
    assert Map.delete(renamed, :title) == Map.delete(original, :title)
    assert Enum.any?(layout["positions"], &(&1["id"] == original.id))

    conn
    |> visit("/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has(@pin <> " header strong", text: "Thermal comparison")
    |> assert_has(@pin, text: "Captured · completed")
    |> assert_has(@pin, count: 1)
    |> click_button("Actions for Thermal comparison")
    |> press("[role='menuitem']:focus", "ArrowDown")
    |> assert_has("[role='menuitem']:focus", text: "Open run")
    |> press(":focus", "Enter")
    |> assert_path("/runs/run-1")
    |> assert_has("#wl-run-panel-run-1", text: "Inert proposal")
    |> click_button("Pin result")
    |> assert_path("/")
    |> assert_has(@pin, count: 1)
    |> assert_has(@pin <> " header strong", text: "Thermal comparison")
    |> click_button("Actions for Thermal comparison")
    |> press("[role='menuitem']:focus", "End")
    |> assert_has("[role='menuitem']:focus", text: "Remove")
    |> press(":focus", "Enter")
    |> refute_has(@pin)

    assert {:ok, %{pins: []}} = Sessions.board(token)
    assert Room.runs(room) == before

    conn
    |> visit("/runs/run-1")
    |> assert_has("#wl-run-panel-run-1")
    |> click_button("Pin result")
    |> assert_has(@pin, count: 1)

    assert {:ok, %{pins: [repinned]}} = Sessions.board(token)
    assert repinned.id == original.id
    assert repinned.record == original.record
    assert repinned.record_digest == original.record_digest
    assert Room.runs(room) == before
  end

  test "narrow dark lookup inspects the original capture without panning or another Run", %{
    conn: conn,
    token: token
  } do
    resize(conn, 320)
    conn = capture_thermal(conn)
    {:ok, %{room: room}} = Sessions.verify(token)
    before = Room.runs(room)
    {:ok, %{pins: [pin]}} = Sessions.board(token)

    conn
    |> click_button("Board menu")
    |> select("Appearance", option: "dark")
    |> click_button("Search board")
    |> fill_in("Search board", with: "run-1")
    |> press("#wl-board-search-query", "ArrowDown")
    |> press(":focus", "Enter")
    |> assert_has("#wl-run-pin")
    |> assert_has("#wl-run-pin", text: "Captured · completed")
    |> click("#wl-run-pin > details > summary", "Sources")
    |> assert_has("#wl-run-pin details[open] code", text: pin.record_digest)
    |> click("#wl-run-pin details[open] details > summary", "Full record")
    |> assert_has("#wl-run-pin details[open] pre code")
    |> evaluate(
      "document.documentElement.scrollWidth <= innerWidth",
      &assert/1
    )
    |> press("button[aria-label='Back to search']", "Enter")
    |> assert_has("#wl-board-search-query")
    |> press(":focus", "Escape")
    |> assert_path("/")
    |> assert_has(@pin, count: 1)

    assert {:ok, %{pins: [^pin]}} = Sessions.board(token)
    assert Room.runs(room) == before
  end

  defp capture_thermal(conn) do
    conn
    |> visit("/experiments")
    |> assert_has("[data-phx-main].phx-connected")
    |> click_button("#run-thermal", "Run")
    |> assert_has("#wl-run-panel-run-1")
    |> click_button("Pin result")
    |> assert_path("/")
    |> assert_has(@pin)
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
