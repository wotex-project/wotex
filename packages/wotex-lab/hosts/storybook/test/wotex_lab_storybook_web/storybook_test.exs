defmodule WotexLabStorybookWeb.StorybookTest do
  @moduledoc false

  use WotexLabStorybookWeb.ConnCase, async: true

  test "serves the manager CSS locally without remote font imports", %{conn: conn} do
    stylesheet = get(conn, "/storybook/assets/css/phoenix_storybook.css")
    body = response(stylesheet, 200)
    assert byte_size(body) > 1_000
    refute body =~ "fonts.googleapis.com"
    refute body =~ ~r/@import\s+(?:url\(\s*)?["']?(?:https?:)?\/\//i
    [etag] = get_resp_header(stylesheet, "etag")

    cached =
      conn
      |> recycle()
      |> put_req_header("if-none-match", etag)
      |> get("/storybook/assets/css/phoenix_storybook.css")

    assert response(cached, 304) == ""
  end

  test "the selected manager theme reaches every fixture", %{conn: conn} do
    for theme <- ~w(light dark contrast system) do
      {:ok, view, _} = live(conn, "/storybook/islands?theme=#{theme}")

      for id <- ~w(reporting-chart data-grid navigation-tabs) do
        assert has_element?(view, "[data-fixture-id='#{id}'][data-wotex-theme='#{theme}']")
      end
    end
  end

  test "serves a secured local storybook with the shared contract", %{conn: conn} do
    conn = get(conn, "/storybook/islands")

    assert html_response(conn, 200) =~ "Live island integration"
    assert get_resp_header(conn, "content-security-policy") != []
    assert get_resp_header(conn, "x-frame-options") == ["DENY"]
    refute response(conn, 200) =~ "https://kit.fontawesome.com"
  end

  test "renders every semantic fallback and advances a real LiveComponent", %{conn: conn} do
    {:ok, view, html} = live(conn, "/storybook/islands")

    assert html =~ ~s(data-fixture-id="reporting-chart")
    assert html =~ ~s(data-fixture-id="data-grid")
    assert html =~ ~s(data-fixture-id="navigation-tabs")
    assert html =~ ~s(data-semantic-fallback="reporting-chart")
    assert html =~ ~s(data-semantic-fallback="data-grid")
    assert html =~ ~s(data-semantic-fallback="navigation-tabs")

    for id <- ~w(reporting-chart data-grid navigation-tabs) do
      {:ok, snapshot} = WotexLabStorybook.DesignContract.fixture(id)

      assert has_element?(
               view,
               ~s([data-fixture-id="#{id}"][data-fixture-payload-digest="#{snapshot.payload_digest}"])
             )
    end

    assert has_element?(view, ~s([data-semantic-fallback="reporting-chart"]), "20.4")
    assert has_element?(view, ~s([data-semantic-fallback="reporting-chart"]), "Temperature °C")
    assert has_element?(view, ~s([data-semantic-fallback="data-grid"]), "Protocol")
    assert has_element?(view, ~s([data-semantic-fallback="data-grid"]), "Modbus")

    assert has_element?(
             view,
             ~s([data-semantic-fallback="navigation-tabs"]),
             "Causal operation spans"
           )

    assert view
           |> element(~s([data-fixture-id="navigation-tabs"] button), "Advance server revision")
           |> render_click() =~ ~s(data-server-revision="2")
  end

  test "serves the real island hook, generated CSS, and immutable chunks", %{conn: conn} do
    loader = get(conn, "/contract-assets/storybook-loader.js")
    assert response(loader, 200) =~ "WotexLabSvelteIsland"
    assert response(loader, 200) =~ "/contract-assets/storybook-module.js"
    assert get_resp_header(loader, "etag") != []

    js = get(recycle(conn), "/contract-assets/storybook-module.js")
    assert redirected_to(js, 302) =~ ~r|\A/assets/workbench-[A-Za-z0-9_-]+\.js\z|
    assert get_resp_header(js, "cache-control") == ["no-store"]

    css = get(recycle(conn), "/contract-assets/design-system.css")
    assert response(css, 200) =~ "--wotex-semantic-color-canvas"
    assert response(css, 200) =~ ".wotex-lab[data-wotex-design-system]"

    static = Application.fetch_env!(:wotex_lab_storybook, :workbench_static)
    manifest_path = Path.join(static, ".vite/manifest.json")

    manifest = Jason.decode!(File.read!(manifest_path))
    file = manifest["assets/storybook.ts"]["file"]
    ["assets", name] = Path.split(file)

    chunk = get(recycle(conn), "/assets/#{name}")
    assert response(chunk, 200) =~ "storybook"
    assert get_resp_header(chunk, "cache-control") == ["public, max-age=31536000, immutable"]
  end

  test "locks the reviewed Phoenix Storybook line" do
    assert Application.spec(:phoenix_storybook, :vsn) |> to_string() == "1.5.0"
  end

  test "an unavailable fixture renders no replacement island or sample" do
    html =
      render_component(WotexLabStorybookWeb.IslandLive,
        id: "unavailable",
        fixture_id: "unknown"
      )

    assert html =~ "Story fixture unavailable"
    refute html =~ "data-semantic-fallback"
    refute html =~ "data-wotex-island"
  end
end
