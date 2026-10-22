defmodule WotexLabWorkbenchWeb.BoardSearchLiveTest do
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

  test "empty lookup and rejected query shapes allocate no room", %{conn: conn, token: token} do
    {:ok, view, _} = live(conn, "/things?panel=search")
    assert has_element?(view, "#wl-board-search-content", "Your board is empty")

    for query <- [String.duplicate("a", 129), ["thermostat"], %{}, nil] do
      render_hook(view, "search_board", %{"query" => query})
      assert has_element?(view, "#wl-board-search-content [role='alert']", "invalid")
      assert has_element?(view, "#wl-board-search-query[value='']")
      assert {:ok, %{room: nil}} = Sessions.verify(token)
    end

    render_hook(view, "search_board", %{"query" => String.duplicate("é", 64)})
    refute has_element?(view, "#wl-board-search-content [role='alert']")
    render_hook(view, "search_board", %{"query" => String.duplicate("é", 65)})
    assert has_element?(view, "#wl-board-search-content [role='alert']")
    assert has_element?(view, "#wl-board-search-query[value='#{String.duplicate("é", 64)}']")
    render_hook(view, "clear_board_search", %{})
    assert has_element?(view, "#wl-board-search-query[value='']")

    for raw <- [%{}, %{"id" => nil}, %{"id" => []}, %{"id" => String.duplicate("a", 129)}] do
      render_hook(view, "inspect_board_result", raw)
      assert has_element?(view, "[role='alert']", "no longer on your board")
    end

    assert {:ok, %{room: nil}} = Sessions.verify(token)
    :ok = Sessions.revoke(token)
    render_hook(view, "search_board", %{"query" => "stale"})
    refute has_element?(view, "#wl-board-search-panel")
    refute has_element?(view, "[data-wotex-island='canvas']")
  end

  test "find, inspect and Back retain the query and selected result without reading", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/")
    render_click(element(view, "button[phx-click='start_room']"))
    {:ok, %{room: room}} = Sessions.verify(token)
    render_click(element(view, "#wl-board-search"))
    assert_patch(view, "/things?panel=search")
    assert titles(view) == ["Actuator", "Energy meter", "Smart room", "Thermostat"]

    render_change(form(view, "#wl-board-search-form"), %{"query" => " THERMOstat 01 "})
    assert titles(view) == ["Thermostat"]
    render_click(element(view, "button[aria-label='Inspect Thermostat']"))
    assert_patch(view, "/things")
    assert has_element?(view, "#wl-thing-inspector-thing-thermostat")
    assert has_element?(view, "button[aria-label='Back to search']")

    render_click(element(view, "button[aria-label='Back to search']"))
    assert_patch(view, "/things?panel=search")
    assert has_element?(view, "#wl-board-search-query[value=' THERMOstat 01 ']")
    assert focus(view) == "#wl-search-result-thing-thermostat"

    render_change(form(view, "#wl-board-search-form"), %{"query" => "no matching object"})
    assert has_element?(view, "#wl-board-search-content", "No matches")
    refute has_element?(view, "#wl-board-search-results button")
    render_hook(view, "inspect_board_result", %{"id" => "thing-foreign"})
    assert has_element?(view, "[role='alert']", "no longer on your board")
    render_click(element(view, "button[aria-label='Clear search']"))
    assert length(titles(view)) == 4
    assert_inert(room)
  end

  test "a process result opens its configuration and returns without running", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/")
    render_click(element(view, "button[phx-click='start_room']"))
    {:ok, %{room: room}} = Sessions.verify(token)
    render_click(element(view, "#wl-board-search"))
    render_change(form(view, "#wl-board-search-form"), %{"query" => "process"})
    assert titles(view) == ["Smart room"]
    render_click(element(view, "button[aria-label='Inspect Smart room']"))
    assert_patch(view, "/experiments?experiment=smart_room")
    assert has_element?(view, "#experiment-smart_room:not([hidden])")
    render_click(element(view, "button[aria-label='Back to search']"))
    assert_patch(view, "/things?panel=search")
    assert focus(view) == "#wl-search-result-process-smart-room"
    assert_inert(room)
  end

  test "owned Run pins can be found and renamed without replay and foreign pins are refused", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/experiments")
    render_hook(view, "run", %{"experiment_id" => "thermal", "params" => %{}})
    assert_patch(view, "/runs/run-1")
    {:ok, %{room: room}} = Sessions.verify(token)
    render_click(element(view, "button[phx-click='pin_run_chart']"))
    {:ok, %{pins: [pin]}} = Sessions.board(token)
    before = Room.runs(room)
    stats = Enum.map(Room.things(room), & &1.stats)
    render_click(element(view, "#wl-board-search"))
    render_change(form(view, "#wl-board-search-form"), %{"query" => "run-1"})
    assert titles(view) == [pin.title]
    render_click(element(view, "#wl-search-result-#{pin.id}"))
    assert_patch(view, "/metrics?pin=#{pin.id}")
    render_submit(form(view, "#rename-run-pin"), %{"pin_id" => pin.id, "title" => "Comparison"})
    render_click(element(view, "button[aria-label='Back to search']"))
    assert_patch(view, "/things?panel=search")
    assert titles(view) == ["Comparison"]
    assert focus(view) == "#wl-search-result-#{pin.id}"
    assert Room.runs(room) == before
    assert Enum.map(Room.things(room), & &1.stats) == stats

    other_conn =
      build_conn()
      |> get("/")
      |> track_session()

    {:ok, other, _} = live(recycle(other_conn), "/things?panel=search")
    render_hook(other, "inspect_board_result", %{"id" => pin.id})
    refute has_element?(other, "#wl-run-pin")
    assert has_element?(other, "[role='alert']", "no longer on your board")
  end

  test "Directory text stays escaped and lookup never consumes an inert entry", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/")
    render_click(element(view, "button[phx-click='start_room']"))
    {:ok, %{room: room}} = Sessions.verify(token)

    source =
      Jason.encode!(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:test:search-entry",
        "title" => "<script>alert('search')</script>",
        "security" => ["nosec_sc"],
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}}
      })

    assert {:ok, _} = Room.register_td(room, source)
    render_click(element(view, "#wl-board-search"))
    html = render_change(form(view, "#wl-board-search-form"), %{"query" => "search-entry"})
    assert titles(view) == ["<script>alert('search')</script>"]
    assert html =~ "&lt;script&gt;"
    refute has_element?(view, "#wl-board-search-results script")
    render_click(element(view, "#wl-board-search-results button"))
    assert_patch(view, "/things")
    assert has_element?(view, "[aria-label='Thing inspector']", "Directory entry · not connected")
    assert has_element?(view, "[aria-label='Thing inspector'] details[open]", "Sources")
    assert_inert(room)
  end

  test "history pins remain read-only search subjects without refreshing their data", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/experiments")
    render_submit(form(view, "#run-thermal"))
    render_patch(view, "/metrics")

    render_submit(form(view, "#metric-compose-query"), %{
      "metric" => "nx_duration_seconds",
      "range" => "5m"
    })

    render_click(element(view, "button[phx-click='pin_metric']"))
    {:ok, %{pins: [pin]} = before} = Sessions.board(token)
    render_click(element(view, "#wl-board-search"))
    render_change(form(view, "#wl-board-search-form"), %{"query" => "nx_duration room"})
    assert titles(view) == [pin.title]
    render_click(element(view, "#wl-search-result-#{pin.id}"))
    assert_patch(view, "/metrics?pin=#{pin.id}")
    assert has_element?(view, "#rename-pin")
    render_click(element(view, "button[aria-label='Back to search']"))
    assert_patch(view, "/things?panel=search")
    assert {:ok, ^before} = Sessions.board(token)
  end

  defp titles(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#wl-board-search-results strong")
    |> Enum.map(&LazyHTML.text/1)
  end

  defp focus(view) do
    [encoded] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#wl-board-search-content")
      |> LazyHTML.attribute("data-focus-target")

    encoded
  end

  defp assert_inert(room) do
    assert Room.runs(room) == []
    assert Enum.all?(Room.things(room), &(&1.stats.handler_calls == 0))
  end
end
