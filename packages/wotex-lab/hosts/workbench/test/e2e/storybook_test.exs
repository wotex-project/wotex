defmodule WotexLabWorkbenchWeb.E2E.StorybookTest do
  @moduledoc false

  use PhoenixTest.Playwright.Case, async: false

  alias PlaywrightEx.Frame
  alias WotexLabWorkbench.Test.StorybookServer

  @moduletag :e2e
  @moduletag timeout: 180_000

  setup_all do
    directory = Path.expand("../../storybook-static", __DIR__)
    index = Path.join(directory, "index.json")
    assert File.regular?(index), "Build the catalogue first: pnpm run storybook:build"

    server =
      start_supervised!(
        {Bandit,
         plug: {StorybookServer, directory}, ip: {127, 0, 0, 1}, port: 0, startup_log: false}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    stories =
      index
      |> File.read!()
      |> JSON.decode!()
      |> Map.fetch!("entries")

    %{origin: "http://127.0.0.1:#{port}", stories: stories}
  end

  test "every published story renders and passes the accessibility addon in both themes", context do
    stories = Enum.filter(context.stories, fn {_, entry} -> entry["type"] == "story" end)
    assert length(stories) >= 30

    failures =
      for {id, _} <- stories, theme <- ["light", "dark"] do
        conn =
          context.conn
          |> story(context.origin, id)
          |> evaluate(
            "document.documentElement.setAttribute('data-wotex-theme', '#{theme}')",
            fn _ -> :ok end
          )

        assert {:ok, result} =
                 Frame.evaluate(conn.frame_id, expression: accessibility_scan(id), timeout: 15_000)

        if result != [], do: {id, theme, result}
      end
      |> Enum.reject(&is_nil/1)

    assert failures == [], inspect(failures, pretty: true, limit: :infinity)
  end

  test "component tabs and menus support keyboard selection and disabled buttons stay inert", %{
    conn: conn,
    origin: origin
  } do
    conn
    |> story(origin, "navigation-tabs--default")
    |> press("[role='tab'][aria-selected='true']", "End")
    |> assert_has("[role='tab']:focus[aria-selected='true']")
    |> press(":focus", "Home")
    |> assert_has("[role='tab']:first-child:focus[aria-selected='true']")

    conn
    |> story(origin, "overlays-menu--open")
    |> press("[role='menuitem']:first-child", "End")
    |> assert_has("[role='menuitem']:last-child:focus")
    |> press(":focus", "Home")
    |> assert_has("[role='menuitem']:first-child:focus")

    conn
    |> story(origin, "primitives-button--disabled")
    |> assert_has("button:disabled")
    |> press("body", "Tab")
    |> refute_has("button:focus")

    conn
    |> story(origin, "overlays-tooltip--default")
    |> assert_has(".wl-tooltip[title] button")
    |> press(".wl-tooltip button", "Space")
    |> assert_has(".wl-tooltip button:focus")
  end

  test "island grids and tabs retain keyboard focus and empty grids expose a status", %{
    conn: conn,
    origin: origin
  } do
    conn
    |> story(origin, "lab-islands-data-grid--connected")
    |> press("[role='gridcell'][tabindex='0']", "ArrowRight")
    |> assert_has("[role='gridcell'][aria-colindex='2']:focus")
    |> press(":focus", "Home")
    |> assert_has("[role='gridcell'][aria-colindex='1']:focus")
    |> press(":focus", "Enter")
    |> assert_has("[role='gridcell']:focus")

    for id <- ["lab-islands-data-grid--empty", "data-grid--empty"] do
      conn
      |> story(origin, id)
      |> assert_has("[role='status']", text: "No rows")
      |> refute_has("[role='grid']")
    end

    conn
    |> story(origin, "lab-islands-tabs--connected")
    |> press("[role='tab'][aria-selected='true']", "End")
    |> assert_has("[role='tab']:last-child:focus[aria-selected='true']")
    |> press(":focus", "Home")
    |> assert_has("[role='tab']:first-child:focus[aria-selected='true']")
  end

  test "menus skip disabled entries and native Enter activates exactly once", %{
    conn: conn,
    origin: origin
  } do
    conn
    |> story(origin, "overlays-menu--disabled-items")
    |> press("[role='menuitem']:first-child", "End")
    |> assert_has("[role='menuitem']:last-child:focus")
    |> press(":focus", "ArrowUp")
    |> assert_has("[role='menuitem']:first-child:focus")
    |> press(":focus", "Enter")
    |> assert_has("output", text: "view 1")
    |> press(":focus", "Space")
    |> assert_has("output", text: "view 2")
  end

  defp story(conn, origin, id) do
    conn = visit(conn, "#{origin}/iframe.html?id=#{id}&viewMode=story")

    assert {:ok, _} =
             Frame.wait_for_selector(conn.frame_id,
               selector: "#storybook-root > *",
               state: "attached",
               strict: false,
               timeout: 5_000
             )

    refute_has(conn, ".sb-errordisplay")
  end

  defp accessibility_scan(id) do
    """
    new Promise((resolve, reject) => {
      const channel = window.__STORYBOOK_ADDONS_CHANNEL__
      const timer = setTimeout(() => reject(new Error('Accessibility scan timed out')), 10000)
      channel.once('storybook/a11y/result', (result) => {
        clearTimeout(timer)
        resolve(result.violations.map(({id, nodes}) => ({id, targets: nodes.map(n => n.target)})))
      })
      channel.once('storybook/a11y/error', reject)
      channel.emit('storybook/a11y/manual', #{JSON.encode!(id)})
    })
    """
  end
end
