defmodule WotexLabWorkbenchWeb.E2E.IslandFallbackTest do
  @moduledoc false

  use PhoenixTest.Playwright.Case, async: false

  alias PlaywrightEx.{BrowserContext, Route}
  alias WotexLabWorkbench.{Room, Sessions}
  alias WotexLabWorkbenchWeb.{Endpoint, Plugs.SessionToken}

  @moduletag :e2e
  @moduletag browser_context_opts: [service_workers: "block"]
  @canvas "[data-wotex-island='canvas']"

  setup %{conn: conn} = context do
    {:ok, session} = Sessions.open()
    on_exit(fn -> Sessions.revoke(session.token) end)
    {:ok, %{room: room}} = Sessions.admit(session.token, :start_room)
    owner = self()
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

            Map.get(context, :blocked_chunk, false) and canvas_chunk?(uri.path) ->
              send(owner, {:blocked_chunk, uri.path})
              Route.abort(route, error_code: "blockedbyclient")

            true ->
              Route.continue(route)
          end
        end,
        timeout: 5_000
      )

    conn =
      add_session_cookie(
        conn,
        [value: %{SessionToken.key() => session.token}],
        Endpoint.session_options()
      )

    %{conn: conn, room: room}
  end

  @tag blocked_chunk: true
  test "a failed canvas chunk retains readings and explicit server operations", context do
    assert_backend_fallback(context, true)
    assert_received {:blocked_chunk, _}
  end

  test "a corrupt canvas snapshot retains readings and explicit server operations", context do
    {:ok, _} =
      BrowserContext.add_init_script(context.conn.context_id,
        timeout: 5_000,
        source: """
        const setAttribute = Element.prototype.setAttribute;
        const interceptAttribute = (method, element, args) => {
          const [name, value] = args;
          const invalid = name === 'data-wotex-island-snapshot' &&
            element.getAttribute('data-wotex-island-component') === 'canvas';
          return Reflect.apply(method, element, [name, invalid ? 'invalid-snapshot' : value]);
        };
        Element.prototype.setAttribute = new Proxy(setAttribute, {apply: interceptAttribute});
        const invalidate = () => {
          const mount = document.querySelector('[data-wotex-island-component="canvas"]');
          if (!mount) return;
          mount.setAttribute('data-wotex-island-snapshot', 'invalid-snapshot');
          observer.disconnect();
        };
        const observer = new MutationObserver(invalidate);
        observer.observe(document, {childList: true, subtree: true});
        """
      )

    assert_backend_fallback(context, false)
  end

  defp assert_backend_fallback(%{conn: conn, room: room}, blocked?) do
    before = Enum.map(Room.things(room), &{&1.id, &1.stats.handler_calls})

    conn
    |> visit("/")
    |> assert_has(@canvas <> "[data-wotex-island-state='failed']")
    |> assert_has("[data-wotex-island-fallback] [aria-label='Connected Things']",
      text: "Thermostat"
    )
    |> refute_has(".svelte-flow__node")

    assert Room.runs(room) == []
    assert Enum.map(Room.things(room), &{&1.id, &1.stats.handler_calls}) == before

    conn
    |> visit("/experiments")
    |> assert_has("[data-phx-main].phx-connected")
    |> click_button("#run-thermal", "Run")
    |> assert_has("#wl-run-result")

    assert [%{id: "run-1"}] = Room.runs(room)
    assert_clean_browser(blocked?)
  end

  defp canvas_chunk?(path) when is_binary(path),
    do: Regex.match?(~r{\A/assets/island-canvas-[^/]+\.js\z}, path)

  defp canvas_chunk?(_), do: false

  defp assert_clean_browser(blocked?) do
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

        assert blocked? and canvas_chunk?(path), inspect(event)
        assert_clean_browser(blocked?)
    after
      0 -> :ok
    end
  end
end
