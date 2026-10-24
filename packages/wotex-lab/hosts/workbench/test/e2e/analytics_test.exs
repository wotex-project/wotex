defmodule WotexLabWorkbenchWeb.E2E.AnalyticsTest do
  @moduledoc false

  use PhoenixTest.Playwright.Case, async: false

  alias PlaywrightEx.Frame
  alias WotexLabWorkbench.Observability.Panels
  alias WotexLabWorkbench.{Room, Sessions}
  alias WotexLabWorkbenchWeb.{Endpoint, Plugs.SessionToken}

  @moduletag :e2e

  setup %{conn: conn} do
    {:ok, session} = Sessions.open()
    on_exit(fn -> Sessions.revoke(session.token) end)
    :ok = PlaywrightEx.subscribe(conn.page_id)
    :ok = PlaywrightEx.subscribe(conn.context_id)

    conn =
      add_session_cookie(
        conn,
        [value: %{SessionToken.key() => session.token}],
        Endpoint.session_options()
      )

    %{conn: conn, token: session.token}
  end

  test "analysis marks and exact links inspect the original run without replay", %{
    conn: conn,
    token: token
  } do
    conn =
      conn
      |> thermal()
      |> visit("/runs/run-1?view=analysis")
      |> assert_has("#run-analysis")

    {:ok, %{room: room}} = Sessions.verify(token)
    before = Room.runs(room)

    for {mark, element} <- [{"point", "circle"}, {"area", "polygon"}, {"line", "polyline"}] do
      conn
      |> select("Chart mark", option: mark)
      |> click_button("Apply analysis")
      |> assert_has("#run-insights")
      |> assert_has("#run-chart-0 .wl-chart-series #{element}")

      alternatives =
        if mark == "line", do: ["polygon"], else: ~w(circle polygon polyline) -- [element]

      for other <- alternatives,
          do: refute_has(conn, "#run-chart-0 .wl-chart-series #{other}")
    end

    analysis = value(conn, "document.querySelector('#analysis-deep-link').getAttribute('href')")
    assert Plug.Conn.Query.decode(URI.parse(analysis).query)["analysis"]["mark"] == "line"

    chart =
      value(conn, "document.querySelector('#run-chart-0 .wl-chart-link').getAttribute('href')")

    assert String.ends_with?(chart, "#run-chart-0")

    conn
    |> visit(chart)
    |> assert_has("#run-insights")
    |> assert_has("#analysis-preview tbody tr")
    |> evaluate("location.hash", &assert(&1 == "#run-chart-0"))

    assert value(conn, "document.querySelectorAll('#analysis-preview tbody tr').length") <= 100

    conn
    |> visit("/runs/run-1?view=analysis")
    |> assert_has("#run-analysis")
    |> refute_has("#run-insights")

    assert Room.runs(room) == before
    assert_clean_browser()
  end

  test "a Thing Description title stays literal text rather than executable markup", %{
    conn: conn,
    token: token
  } do
    {:ok, %{room: room}} = Sessions.admit(token, :start_room)

    title =
      ~s(<img src=x onerror="window.__wotexHostile=1"><script>window.__wotexHostile=2</script>)

    description =
      JSON.encode!(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "id" => "urn:test:hostile",
        "title" => title,
        "security" => ["nosec_sc"],
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}}
      })

    conn
    |> visit("/things?panel=import")
    |> assert_has("[data-phx-main].phx-connected")
    |> fill_in("Thing Description JSON", with: description)
    |> click_button("Register TD")
    |> assert_has(".svelte-flow__node strong", text: "<script>window.__wotexHostile=2</script>")
    |> refute_has(".svelte-flow__node img[src='x']")
    |> refute_has(".svelte-flow__node script")
    |> evaluate("typeof window.__wotexHostile", &assert(&1 == "undefined"))

    assert title in value(
             conn,
             "Array.from(document.querySelectorAll('.svelte-flow__node strong'), (node) => node.textContent)"
           )

    assert Room.runs(room) == []
    assert_clean_browser()
  end

  test "a saved catalogue arrangement exports only its exact definitions", %{
    conn: conn,
    token: token
  } do
    conn =
      conn
      |> visit("/metrics")
      |> catalogue()

    panels = Panels.all()
    assert_has(conn, "#dashboard-selection input[type='checkbox']", count: length(panels))

    for panel <- panels,
        do:
          uncheck(conn, "#dashboard-selection input[value='#{panel.id}']", panel.title,
            exact: false
          )

    panel = Enum.find(panels, &(&1.id == "nx_duration_seconds"))

    conn
    |> check("#dashboard-selection input[value='#{panel.id}']", panel.title, exact: false)
    |> click_button("Save arrangement")
    |> assert_has(".wl-flash[role='status']", text: "Dashboard arrangement saved")
    |> visit("/metrics")
    |> catalogue()
    |> assert_has("#dashboard-selection input:checked", count: 1)
    |> assert_has("#dashboard-selection input[value='#{panel.id}']:checked")

    path = value(conn, "document.querySelector('#dashboard-deep-link').getAttribute('href')")

    assert Plug.Conn.Query.decode(URI.parse(path).query) == %{
             "panels" => [panel.id],
             "selection" => "custom"
           }

    conn
    |> click_link("Download dashboard JSON")
    |> assert_download(fn download ->
      assert download.name == "wotex-lab-dashboard.json"
      assert byte_size(download.content) <= 65_536
      assert [%{"targets" => [%{"expr" => query}]}] = JSON.decode!(download.content)["panels"]
      assert query == panel.query
    end)

    assert {:ok, %{room: nil}} = Sessions.verify(token)
    assert_clean_browser()
  end

  test "keyboard-loaded history reflows and reload does not replay the query", %{
    conn: conn,
    token: token
  } do
    conn =
      conn
      |> thermal()
      |> visit("/metrics")
      |> measurements()
      |> assert_has("#history-query")

    {:ok, %{room: room}} = Sessions.verify(token)
    before = Room.runs(room)
    refute_has(conn, "#history-results")

    conn
    |> select("#history-range", "Range", option: "5m")
    |> press("#history-query button[type='submit']", "Enter")
    |> assert_has("#history-results[aria-live='polite']")
    |> assert_has("#history-chart-nx_duration_seconds .wl-chart-svg")

    response =
      PlaywrightEx.send(
        %{
          guid: conn.page_id,
          method: :set_viewport_size,
          params: %{viewport_size: %{width: 375, height: 812}}
        },
        timeout: 5_000
      )

    refute Map.has_key?(response, :error)
    assert value(conn, "document.documentElement.scrollWidth <= innerWidth")

    conn
    |> visit("/metrics")
    |> measurements()
    |> assert_has("#history-query")
    |> refute_has("#history-results")

    assert Room.runs(room) == before
    assert_clean_browser()
  end

  test "unconfigured investigation and formal engines remain unavailable without effects", %{
    conn: conn,
    token: token
  } do
    conn = thermal(conn) |> visit("/runs/run-1?view=ask")
    {:ok, %{room: room}} = Sessions.verify(token)
    before = Room.snapshot(room)

    conn
    |> assert_has("#investigation-prompt[disabled]")
    |> assert_has("#investigation button[type='submit'][disabled]")
    |> assert_has("#investigation", text: "No investigation provider is configured.")
    |> refute_has("#investigation-disclosure")
    |> visit("/evidence")
    |> click_button("Verify model")
    |> assert_has(".wl-flash[role='alert']", text: "no verified Maude engine is configured")

    after_request = Room.snapshot(room)
    assert after_request.runs == before.runs
    assert after_request.datasets == before.datasets
    assert after_request.formal == []
    assert_clean_browser()
  end

  defp thermal(conn) do
    conn
    |> visit("/experiments")
    |> assert_has("[data-phx-main].phx-connected")
    |> click_button("#run-thermal", "Run")
    |> assert_has("#wl-run-result")
  end

  defp measurements(conn),
    do: click(conn, "details > summary", "Session measurements")

  defp catalogue(conn) do
    conn
    |> measurements()
    |> press("#metric-catalogue summary", "Enter")
    |> assert_has("#dashboard-selection")
  end

  defp value(conn, expression) do
    {:ok, result} = Frame.evaluate(conn.frame_id, expression: expression, timeout: 5_000)
    result
  end

  defp assert_clean_browser do
    refute_received {:playwright_msg, %{method: :page_error}}
    refute_received {:playwright_msg, %{method: :dialog}}
    refute_received {:playwright_msg, %{method: :console, params: %{type: "error"}}}
  end
end
