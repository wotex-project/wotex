defmodule WotexLabWorkbenchWeb.E2E.DocumentationTest do
  @moduledoc false

  use PhoenixTest.Playwright.Case, async: false

  alias PlaywrightEx.{BrowserContext, Frame, Route}
  alias WotexLabWorkbench.Documentation.BrowserFixture
  alias WotexLabWorkbench.Sessions
  alias WotexLabWorkbench.Test.DocumentationServer
  alias WotexLabWorkbenchWeb.Endpoint

  @moduletag :e2e
  @moduletag :documentation
  @moduletag browser_context_opts: [service_workers: "block"]
  @moduletag timeout: 120_000
  @input "[data-doc-search-input]"
  @results "[data-doc-search-results][data-doc-search-state='ready']"
  @queries [
    {"guide constellation", "Start"},
    {"member orbital decoder", "Wotex.Thing"},
    {"protocol beacon", "Bluetooth beacon"},
    {"specification covenant", "Datagram contract"},
    {"evidence lantern", "Release proof"},
    {"notebook tensor", "Tensor notebook"},
    {"API operation widget flight", "Widget API"},
    {"decode", "decode/1"}
  ]
  @filters [
    collection: "family_docs",
    kind: "guide",
    locale: "en",
    audience: "public",
    version: "0.1.0",
    tag: "start",
    status: "stable"
  ]

  setup_all do
    assert Code.ensure_loaded?(PhoenixAssets.DocShell.StaticRenderer),
           "Supply the renderer candidate when running documentation acceptance"

    root =
      Path.join(
        System.tmp_dir!(),
        "wotex-documentation-e2e-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, {_, live_port}} = Endpoint.server_info(:http)

    %{built: built, destination: directory} =
      BrowserFixture.build(
        destination: Path.join(root, "site"),
        port: live_port,
        pagefind_executable: Path.expand("../../node_modules/.bin/pagefind", __DIR__)
      )

    settings = [
      documentation_site_path: built.hosted_artifact,
      documentation_search_root: Path.join(Path.dirname(built.hosted_artifact), "search")
    ]

    previous = for {key, _} <- settings, do: {key, Application.fetch_env(:wotex_lab_workbench, key)}

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:wotex_lab_workbench, key, value)
          :error -> Application.delete_env(:wotex_lab_workbench, key)
        end
      end
    end)

    Application.put_all_env(wotex_lab_workbench: settings)

    server =
      start_supervised!(
        {Bandit,
         plug: {DocumentationServer, directory}, ip: {127, 0, 0, 1}, port: 0, startup_log: false}
      )

    {:ok, {_, static_port}} = ThousandIsland.listener_info(server)

    %{
      origins: [live: "http://127.0.0.1:#{live_port}", static: "http://127.0.0.1:#{static_port}"],
      cohort_digest: built.site.cohort_digest
    }
  end

  setup %{conn: conn, origins: origins} do
    owner = self()
    :ok = PlaywrightEx.subscribe(conn.page_id)
    :ok = PlaywrightEx.subscribe(conn.context_id)

    {:ok, _} =
      BrowserContext.route(
        conn.context_id,
        "**/*",
        fn route, request ->
          uri = URI.parse(request.url)
          origin = "#{uri.scheme}://#{uri.host}:#{uri.port}"
          send(owner, {:documentation_request, uri.path})

          if origin in Keyword.values(origins) do
            {:ok, _} = Route.continue(route)
          else
            send(owner, {:documentation_external, request.url})
            {:ok, _} = Route.abort(route, error_code: "blockedbyclient")
          end
        end,
        timeout: 5_000
      )

    :ok
  end

  test "hosted and static readers share content and load Pagefind only after keyboard search",
       context do
    session_count = Sessions.count()

    readers =
      for {kind, origin} <- context.origins do
        conn =
          context.conn
          |> visit(origin <> "/docs/start/")
          |> assert_has("article")

        refute Enum.any?(requests(), &String.contains?(&1, "pagefind"))
        before = reader(conn)

        conn
        |> press("body", "Control+k")
        |> assert_has(@input <> ":focus")

        for {query, title} <- @queries, do: search(conn, query, title)

        paths = requests()

        assert Enum.any?(paths, &String.ends_with?(&1, "/pagefind.js")), inspect({kind, paths})
        assert Enum.any?(paths, &String.contains?(&1, ".pf_")), inspect({kind, paths})

        assert value(conn, "document.querySelector('.doc-shell').dataset.cohortDigest") ==
                 context.cohort_digest

        assert_clean_browser()
        before
      end

    assert Enum.at(readers, 0) == Enum.at(readers, 1)
    assert Sessions.count() == session_count
  end

  test "member search opens the admitted signature and prose without losing source identity", %{
    conn: conn,
    origins: origins
  } do
    for {_, origin} <- origins do
      conn =
        conn
        |> visit(origin <> "/docs/start/")
        |> click_button("Search documentation")

      search(conn, "decode", "decode/1")
      search(conn, "Decode one admitted Thing Description", "decode/1")

      conn
      |> press(@input, "ArrowDown")
      |> press(@input, "ArrowUp")
      |> press(@input, "Enter")
      |> assert_has("h1", text: "decode/1")
      |> assert_has("article", text: "decode(document)")
      |> assert_has("article", text: "Decode one admitted Thing Description.")
      |> assert_has("a[href*='/tree/" <> String.duplicate("a", 40) <> "']")

      assert_clean_browser()
    end
  end

  test "all seven facets and compact scope controls filter the real index on both surfaces", %{
    conn: conn,
    origins: origins
  } do
    for {_, origin} <- origins do
      conn =
        conn
        |> visit(origin <> "/docs/start/")
        |> click_button("Search documentation")

      conn |> press(".doc-search-filters > summary", "Enter")

      for {name, option} <- @filters do
        clear_filters(conn)

        assert {:ok, _} =
                 Frame.select_option(conn.frame_id,
                   selector: "[data-doc-search-filter='#{name}']",
                   options: option,
                   timeout: 5_000
                 )

        search(conn, "guide constellation", "Start")
      end

      clear_filters(conn)
      conn |> click_button("Guides")
      search(conn, "guide constellation", "Start")
      conn |> click_button(nil, "API", exact: true)
      search(conn, "member orbital decoder", "Wotex.Thing")
      conn |> click_button(nil, "Packages", exact: true)
      search(conn, "wotex documentation", "wotex")
      conn |> click_button("All docs")
      assert_clean_browser()
    end
  end

  test "reflow, 400 percent zoom, themes and reduced motion preserve the reader", %{
    conn: conn,
    origins: origins
  } do
    for {_, origin} <- origins do
      conn = conn |> visit(origin <> "/docs/start/")
      command(conn.page_id, :set_viewport_size, %{viewport_size: %{width: 320, height: 900}})
      assert value(conn, "document.documentElement.scrollWidth <= innerWidth")

      conn
      |> click_button("Browse documentation")
      |> assert_has("[data-doc-nav][data-doc-nav-state='open']")

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

      conn |> press(".doc-reader-settings > summary", "Enter")

      for {label, theme} <- [
            {"Light", "light"},
            {"Dark", "dark"},
            {"Contrast", "contrast"},
            {"System", "system"}
          ] do
        conn
        |> click_button(nil, label, exact: true)
        |> assert_has(".doc-shell[data-wotex-theme='#{theme}']")
        |> assert_has("[data-doc-theme-value='#{theme}'][aria-pressed='true']")
      end

      command(conn.page_id, :emulate_media, %{reduced_motion: "reduce", forced_colors: "active"})

      assert value(
               conn,
               "matchMedia('(prefers-reduced-motion: reduce)').matches && matchMedia('(forced-colors: active)').matches"
             )

      assert value(conn, """
             Array.from(document.querySelectorAll('.doc-shell *')).every(element => {
               const style = getComputedStyle(element)
               return [style.animationDuration, style.transitionDuration].flatMap(value => value.split(',')).every(value => {
                 const amount = parseFloat(value) || 0
                 return (value.trim().endsWith('ms') ? amount : amount * 1000) <= 0.01
               })
             })
             """)

      assert_clean_browser()
    end
  end

  test "RTL and missing pages retain navigation, search and the Workbench return route", %{
    conn: conn,
    origins: origins
  } do
    for {kind, origin} <- origins do
      conn
      |> visit(origin <> "/docs/start/rtl-guide/")
      |> assert_has(".doc-shell[dir='rtl'][lang='ar']")

      conn =
        conn
        |> visit(origin <> "/docs/not-present/")
        |> assert_has("h1", text: "Page not found")
        |> assert_has("nav[aria-label='Documentation']")
        |> assert_has("[data-doc-search-open]", count: 1)
        |> assert_has("a[aria-label='Return to workbench'][href='/']")

      assert value(conn, "performance.getEntriesByType('navigation')[0].responseStatus") ==
               if(kind == :static, do: 404, else: 200)

      assert_clean_browser()
    end
  end

  @tag browser_context_opts: [java_script_enabled: false, service_workers: "block"]
  test "both surfaces retain article and native navigation without JavaScript", %{
    conn: conn,
    origins: origins
  } do
    for {_, origin} <- origins do
      conn
      |> visit(origin <> "/docs/start/")
      |> assert_has("article")
      |> assert_has("nav[aria-label='Documentation']")
      |> press("noscript summary", "Enter")
      |> assert_has("noscript nav a")

      assert_clean_browser()
    end
  end

  defp search(conn, query, title) do
    assert {:ok, _} = Frame.fill(conn.frame_id, selector: @input, value: query, timeout: 5_000)
    assert_has(conn, @results, text: title)
  end

  defp clear_filters(conn) do
    for {name, _} <- @filters do
      assert {:ok, _} =
               Frame.select_option(conn.frame_id,
                 selector: "[data-doc-search-filter='#{name}']",
                 options: "",
                 timeout: 5_000
               )
    end
  end

  defp reader(conn) do
    value(conn, """
    ({
      title: document.querySelector('h1')?.textContent?.trim(),
      article: document.querySelector('article')?.textContent?.replace(/\\s+/g, ' ').trim(),
      headings: Array.from(document.querySelectorAll('article h1, article h2, article h3'), item => item.textContent?.trim()),
      navigation: Array.from(document.querySelectorAll('nav[aria-label=Documentation] a'), item => [item.textContent?.trim(), item.getAttribute('href')]),
      searchName: document.querySelector('[data-doc-search-open]')?.textContent?.trim(),
      renderer: document.querySelector('.doc-shell').hasAttribute('data-pa-doc-shell')
    })
    """)
  end

  defp value(conn, expression) do
    assert {:ok, result} = Frame.evaluate(conn.frame_id, expression: expression, timeout: 5_000)
    result
  end

  # PlaywrightEx 0.15 exposes no helpers for these driver operations. The names
  # and parameter shapes are verified against the pinned Playwright 1.64 driver.
  defp command(guid, method, params) do
    response = PlaywrightEx.send(%{guid: guid, method: method, params: params}, timeout: 5_000)
    refute Map.has_key?(response, :error), inspect(response)
    Map.get(response, :result, %{})
  end

  defp requests(paths \\ []) do
    receive do
      {:documentation_request, path} -> requests([path | paths])
    after
      0 -> Enum.reverse(paths)
    end
  end

  defp assert_clean_browser do
    refute_received {:documentation_external, _}
    refute_received {:playwright_msg, %{method: :page_error}}

    receive do
      {:playwright_msg,
       %{method: :console, params: %{type: "error", location: %{url: url}}} = event} ->
        assert URI.parse(url).path == "/docs/not-present/", inspect(event)
        assert_clean_browser()
    after
      0 -> :ok
    end
  end
end
