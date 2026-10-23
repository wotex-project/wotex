defmodule WotexLabWorkbenchWeb.E2E.IslandReconnectTest do
  @moduledoc false

  use PhoenixTest.Playwright.Case, async: false

  alias PlaywrightEx.Frame
  alias WotexLabWorkbench.{Room, Sessions}
  alias WotexLabWorkbenchWeb.{Endpoint, Plugs.SessionToken}

  @moduletag :e2e
  @canvas "[data-wotex-island='canvas']"

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

  test "a restarted LiveView accepts a fresh generation without replaying a completed Run", %{
    conn: conn,
    token: token
  } do
    conn =
      conn
      |> visit("/experiments")
      |> assert_has("[data-phx-main].phx-connected")
      |> click_button("#run-thermal", "Run")
      |> assert_has("#wl-run-panel-run-1")
      |> click_link("Close panel")
      |> assert_path("/")
      |> assert_has(@canvas <> "[data-wotex-island-state='mounted']")

    before = snapshot(conn)
    {:ok, %{room: room}} = Sessions.verify(token)
    runs = Room.runs(room)
    assert [%{id: "run-1"}] = runs
    handlers = Enum.map(Room.things(room), &{&1.id, &1.stats.handler_calls})

    conn
    |> evaluate("window.liveSocket.disconnect()", fn _ -> :ok end)
    |> assert_has(@canvas <> "[data-wotex-island-state='disconnected']")
    |> evaluate("window.liveSocket.connect()", fn _ -> :ok end)
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has(@canvas <> "[data-wotex-island-state='mounted']")
    |> assert_has(".svelte-flow__node[data-id='thing-thermostat']")
    |> click_button("Actions for Thermostat")
    |> click("[role='menuitem']", "Inspect")
    |> assert_has("[aria-label='Thing inspector']")

    after_mount = snapshot(conn)
    assert after_mount["instance_id"] == before["instance_id"]
    assert String.to_integer(after_mount["generation"]) > String.to_integer(before["generation"])
    assert after_mount["capabilities"] == before["capabilities"]
    assert Room.runs(room) == runs
    assert Enum.map(Room.things(room), &{&1.id, &1.stats.handler_calls}) == handlers
  end

  defp snapshot(conn) do
    {:ok, encoded} =
      Frame.evaluate(conn.frame_id,
        expression:
          "document.querySelector('[data-wotex-island-component=canvas]').dataset.wotexIslandSnapshot",
        timeout: 5_000
      )

    encoded
    |> Base.url_decode64!(padding: false)
    |> JSON.decode!()
  end
end
