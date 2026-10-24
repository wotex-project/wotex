defmodule WotexLabStorybookWeb.E2E.IslandsTest do
  @moduledoc false

  use PhoenixTest.Playwright.Case, async: false

  alias PlaywrightEx.{BrowserContext, Frame, Route}
  alias WotexLabStorybookWeb.Endpoint

  @moduletag :e2e
  @moduletag browser_context_opts: [service_workers: "block"]
  @moduletag timeout: 120_000
  @fixtures ~w(reporting-chart data-grid navigation-tabs)

  setup %{conn: conn} = context do
    owner = self()
    blocked? = Map.get(context, :blocked_chunks, false)
    {:ok, {_, port}} = Endpoint.server_info(:http)
    :ok = PlaywrightEx.subscribe(conn.page_id)
    :ok = PlaywrightEx.subscribe(conn.context_id)

    {:ok, _} =
      BrowserContext.route(
        conn.context_id,
        "**/*",
        fn route, request ->
          uri = URI.parse(request.url)

          cond do
            uri.scheme != "http" or uri.host != "127.0.0.1" or uri.port != port ->
              send(owner, {:external_request, request.url})
              Route.abort(route, error_code: "blockedbyclient")

            blocked? and component_chunk?(uri.path) ->
              send(owner, {:blocked_chunk, uri.path})
              Route.abort(route, error_code: "blockedbyclient")

            true ->
              Route.continue(route)
          end
        end,
        timeout: 5_000
      )

    :ok
  end

  test "real islands preserve keyboard focus across a server revision", %{conn: conn} do
    conn =
      conn
      |> visit("/storybook/islands")
      |> mounted()

    assert_handoff(conn, false)
    assert length(Enum.uniq(identities(conn))) == 3

    conn
    |> click("[data-fixture-id='reporting-chart'] tbody tr:first-child .wl-island-chart-inspect")
    |> assert_has("[data-fixture-id='reporting-chart'] .wl-island-table")

    conn
    |> press("[data-fixture-id='data-grid'] [role='gridcell'][tabindex='0']", "ArrowRight")
    |> assert_has("[data-fixture-id='data-grid'] [role='gridcell']:focus")
    |> press("[data-fixture-id='data-grid'] [role='gridcell']:focus", "Enter")

    tabs = "[data-fixture-id='navigation-tabs']"

    conn
    |> press(tabs <> " [role='tab'][tabindex='0']", "ArrowRight")
    |> assert_has(tabs <> " [role='tab']:focus[aria-selected='true']")

    focused = value(conn, "document.activeElement.id")

    conn
    |> evaluate(
      "document.activeElement.closest('[data-fixture-id]').querySelector('header button').click()"
    )
    |> assert_has(tabs <> "[data-server-revision='2']")
    |> assert_has(tabs <> " [role='tab']:focus[aria-selected='true']")

    assert value(conn, "document.activeElement.id") == focused
    assert_clean_browser()
  end

  test "disconnect restores semantic fallbacks and reconnect admits fresh snapshots", %{
    conn: conn
  } do
    conn =
      conn
      |> visit("/storybook/islands")
      |> mounted()

    before = snapshots(conn)

    conn |> evaluate("window.liveSocket.disconnect()")

    for id <- @fixtures,
        do: assert_has(conn, fixture(id) <> " [data-wotex-island-state='disconnected']")

    assert_handoff(conn, true)

    conn
    |> evaluate("window.liveSocket.connect()")
    |> mounted()

    assert_handoff(conn, false)
    after_mount = snapshots(conn)

    assert Enum.map(after_mount, & &1["instance_id"]) == Enum.map(before, & &1["instance_id"])

    for {old, new} <- Enum.zip(before, after_mount) do
      assert String.to_integer(new["generation"]) > String.to_integer(old["generation"])
      assert new["payload_digest"] == old["payload_digest"]
      assert new["capabilities"] == old["capabilities"]
    end

    assert_clean_browser()
  end

  @tag blocked_chunks: true
  test "failed chunks retain all fallbacks and real server controls", %{conn: conn} do
    conn =
      conn
      |> visit("/storybook/islands")
      |> connected()

    for id <- @fixtures do
      conn
      |> assert_has(fixture(id) <> " [data-wotex-island-state='failed']")
      |> click_button(fixture(id) <> " header button", "Advance server revision")
      |> assert_has(fixture(id) <> "[data-server-revision='2']")
    end

    assert_handoff(conn, true)
    assert_received {:blocked_chunk, _}
    assert_clean_browser(true)
  end

  test "selected themes, narrow reflow, zoom and reduced motion reach the islands", %{conn: conn} do
    colors =
      for theme <- ~w(light dark contrast system) do
        conn =
          conn
          |> visit("/storybook/islands?theme=#{theme}")
          |> mounted()

        assert_has(conn, "[data-fixture-id][data-wotex-theme='#{theme}']", count: 3)

        value(
          conn,
          "(() => { const root = document.querySelector('[data-fixture-id=\"navigation-tabs\"]'); const style = getComputedStyle(root); const island = getComputedStyle(root.querySelector('.wl-island-tabs')); return [style.backgroundColor, style.color, style.borderColor, island.backgroundColor]; })()"
        )
      end

    assert length(Enum.uniq(Enum.take(colors, 3))) == 3
    command(conn.page_id, :set_viewport_size, %{viewport_size: %{width: 320, height: 900}})
    assert value(conn, "document.documentElement.scrollWidth <= innerWidth")

    %{session: %{guid: session}} =
      command(conn.context_id, "newCDPSession", %{page: %{guid: conn.page_id}})

    command(session, :send, %{
      method: "Emulation.setDeviceMetricsOverride",
      params: %{
        width: 320,
        height: 225,
        screenWidth: 1280,
        screenHeight: 900,
        deviceScaleFactor: 4,
        mobile: false
      }
    })

    assert value(
             conn,
             "[devicePixelRatio, innerWidth, document.documentElement.scrollWidth <= innerWidth]"
           ) == [4, 320, true]

    command(session, :send, %{method: "Emulation.clearDeviceMetricsOverride"})
    command(session, :detach, %{})
    command(conn.page_id, :emulate_media, %{reduced_motion: "reduce"})

    assert value(conn, """
           [...document.querySelectorAll('[data-fixture-id] *')].every((element) => {
             const style = getComputedStyle(element);
             return [style.animationDuration, style.transitionDuration].every((values) =>
               values.split(',').every((value) => {
           const milliseconds = value.trim().endsWith('ms') ? parseFloat(value) : parseFloat(value) * 1000;
           return milliseconds <= 0.01;
           }));
           })
           """)

    assert_clean_browser()
  end

  test "one malformed snapshot cannot mount or disable neighboring islands", %{conn: conn} do
    {:ok, _} =
      BrowserContext.add_init_script(conn.context_id,
        timeout: 5_000,
        source: """
        const setAttribute = Element.prototype.setAttribute;
        const interceptAttribute = (method, element, args) => {
          const [name, value] = args;
          const invalid = name === 'data-wotex-island-snapshot' &&
            element.getAttribute('data-wotex-island-component') === 'tabs';
          return Reflect.apply(method, element, [name, invalid ? 'invalid-snapshot' : value]);
        };
        Element.prototype.setAttribute = new Proxy(setAttribute, {apply: interceptAttribute});
        const invalidate = () => {
          const mount = document.querySelector('[data-wotex-island-component="tabs"]');
          if (!mount) return;
          mount.setAttribute('data-wotex-island-snapshot', 'invalid-snapshot');
          observer.disconnect();
        };
        const observer = new MutationObserver(invalidate);
        observer.observe(document, {childList: true, subtree: true});
        """
      )

    conn
    |> visit("/storybook/islands")
    |> assert_has(fixture("navigation-tabs") <> " [data-wotex-island-state='failed']")
    |> assert_has(fixture("reporting-chart") <> " [data-wotex-island-state='mounted']")
    |> assert_has(fixture("data-grid") <> " [data-wotex-island-state='mounted']")
    |> click_button(fixture("navigation-tabs") <> " header button", "Advance server revision")
    |> assert_has(fixture("navigation-tabs") <> "[data-server-revision='2']")

    assert value(
             conn,
             "getComputedStyle(document.querySelector('[data-fixture-id=\"navigation-tabs\"] [data-wotex-island-fallback]')).display !== 'none'"
           )

    assert_clean_browser()
  end

  @tag browser_context_opts: [java_script_enabled: false, service_workers: "block"]
  test "all three semantic fallbacks remain available without JavaScript", %{conn: conn} do
    conn = conn |> visit("/storybook/islands")
    for id <- @fixtures, do: assert_has(conn, "[data-semantic-fallback='#{id}']")
    refute_has(conn, "[data-wotex-island-mount] > *")
    assert_handoff(conn, true)
    assert_clean_browser()
  end

  defp fixture(id), do: "[data-fixture-id='#{id}']"

  defp connected(conn) do
    assert {:ok, true} =
             Frame.expect(conn.frame_id,
               expression: "to.have.count",
               selector: "[data-phx-main].phx-connected",
               expected_number: 1,
               timeout: 5_000
             )

    conn
  end

  defp component_chunk?(path) when is_binary(path),
    do: Regex.match?(~r{\A/assets/island-(?:chart|data-grid|tabs)-[^/]+\.js\z}, path)

  defp component_chunk?(_), do: false

  defp mounted(conn) do
    conn = connected(conn)

    for id <- @fixtures,
        do: assert_has(conn, fixture(id) <> " [data-wotex-island-state='mounted']")

    conn
  end

  defp identities(conn), do: Enum.map(snapshots(conn), & &1["instance_id"])

  defp snapshots(conn) do
    value(
      conn,
      "[...document.querySelectorAll('[data-wotex-island-snapshot]')].map((element) => element.dataset.wotexIslandSnapshot)"
    )
    |> Enum.map(fn encoded ->
      encoded
      |> Base.url_decode64!(padding: false)
      |> JSON.decode!()
    end)
  end

  defp assert_handoff(conn, visible) do
    assert value(conn, """
           [...document.querySelectorAll('[data-wotex-island]')].every((element) => {
             const fallback = getComputedStyle(element.querySelector('[data-wotex-island-fallback]')).display;
             const mount = getComputedStyle(element.querySelector('[data-wotex-island-mount]')).display;
             return (fallback !== 'none') === #{visible} && (mount === 'none') === #{visible};
           })
           """)
  end

  defp value(conn, expression) do
    assert {:ok, result} = Frame.evaluate(conn.frame_id, expression: expression, timeout: 5_000)
    result
  end

  defp command(guid, method, params) do
    response = PlaywrightEx.send(%{guid: guid, method: method, params: params}, timeout: 5_000)
    refute Map.has_key?(response, :error), inspect(response)
    Map.get(response, :result, %{})
  end

  defp assert_clean_browser(blocked? \\ false) do
    refute_received {:external_request, _}
    refute_received {:playwright_msg, %{method: :page_error}}

    receive do
      {:playwright_msg, %{method: :console, params: %{type: "error"} = params}} = event ->
        path =
          params
          |> get_in([:location, :url])
          |> to_string()
          |> URI.parse()
          |> Map.get(:path)

        assert blocked? and component_chunk?(path),
               inspect(event)

        assert_clean_browser(blocked?)
    after
      0 -> :ok
    end
  end
end
