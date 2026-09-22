defmodule WotexLabStorybookWeb.StorybookTest do
  use WotexLabStorybookWeb.ConnCase, async: true

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
    assert Application.spec(:phoenix_storybook, :vsn) |> to_string() == "1.3.0"
  end
end
