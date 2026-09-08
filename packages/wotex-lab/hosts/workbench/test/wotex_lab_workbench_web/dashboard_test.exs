defmodule WotexLabWorkbenchWeb.DashboardTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias WotexLabWorkbench.Sessions
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  test "catalogue UI and selected JSON export are inert, scoped and closed", %{conn: conn} do
    conn = get(conn, "/metrics")
    html = html_response(conn, 200)
    assert html =~ "Portable metric panels"
    assert html =~ "These are catalogue definitions"
    assert {:ok, %{room: nil}} = Sessions.verify(get_session(conn, SessionToken.key()))
    refute Process.whereis(WotexLabWorkbench.Observability.PromEx)

    exported = get(recycle(conn), "/metrics/dashboard.json", %{panels: ["nx_duration_seconds"]})
    dashboard = json_response(exported, 200)
    assert [panel] = dashboard["panels"]
    assert hd(panel["targets"])["expr"] =~ "histogram_quantile"
    assert get_resp_header(exported, "cache-control") == ["no-store"]

    assert get_resp_header(exported, "content-disposition") == [
             ~s(attachment; filename="wotex-lab-dashboard.json")
           ]

    assert {:ok, %{room: nil}} = Sessions.verify(get_session(conn, SessionToken.key()))

    for params <- [
          %{panels: ["caller"]},
          %{panels: "caller"},
          %{scope: "other"},
          %{query: "up"},
          %{selection: "custom"},
          %{selection: "caller"}
        ] do
      assert response(get(recycle(conn), "/metrics/dashboard.json", params), 400)
    end

    assert response(get(recycle(conn), "/metrics/dashboard.json"), 200)
    :ok = Sessions.revoke(get_session(conn, SessionToken.key()))
    assert response(get(recycle(conn), "/metrics/dashboard.json"), 403)
  end
end
