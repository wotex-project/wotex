defmodule WotexLabWorkbenchWeb.E2E.EmptyWorkbenchTest do
  @moduledoc false

  use PhoenixTest.Playwright.Case, async: false

  alias PlaywrightEx.Frame
  alias WotexLabWorkbench.Sessions
  alias WotexLabWorkbenchWeb.{Endpoint, Plugs.SessionToken}

  @moduletag :e2e
  @canvas "[data-wotex-island='canvas']"

  test "every unopened tool stays empty until the backend admits an operation", %{conn: conn} do
    {:ok, session} = Sessions.open()
    on_exit(fn -> Sessions.revoke(session.token) end)

    conn =
      add_session_cookie(
        conn,
        [value: %{SessionToken.key() => session.token}],
        Endpoint.session_options()
      )

    for route <- ["/", "/things", "/experiments", "/metrics", "/evidence", "/runs/run-1"] do
      page =
        conn
        |> visit(route)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has(@canvas <> "[data-wotex-island-state='mounted']")
        |> refute_has(".svelte-flow__node")
        |> refute_has("#metric-compose-result")
        |> refute_has("#evidence-runs")

      {:ok, encoded} =
        Frame.evaluate(page.frame_id,
          expression:
            "document.querySelector('[data-wotex-island-component=canvas]').dataset.wotexIslandSnapshot",
          timeout: 5_000
        )

      snapshot =
        encoded
        |> Base.url_decode64!(padding: false)
        |> JSON.decode!()

      assert snapshot["payload"]["nodes"] == []
      assert snapshot["payload"]["edges"] == []
      assert Map.get(snapshot["payload"], "pins", []) == []
      assert {:ok, %{room: nil}} = Sessions.verify(session.token)
    end

    conn
    |> visit("/docs/start/")
    |> assert_has("#doc-main")

    assert {:ok, %{room: nil}} = Sessions.verify(session.token)
  end
end
