defmodule WotexLabWorkbenchWeb.DashboardTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Plug.Conn.Query
  alias WotexLabWorkbench.Sessions
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  test "catalogue UI and selected JSON export are inert, scoped and closed", %{conn: conn} do
    conn = get(conn, "/metrics")
    html = html_response(conn, 200)
    assert html =~ "Portable metric panels"
    assert html =~ "These are catalogue definitions"
    assert html =~ "Exact link"
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

  test "dashboard arrangements persist per session and exact links remain closed", %{conn: conn} do
    conn = get(conn, "/metrics")
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/metrics")

    assert has_element?(view, ~s(#dashboard-selection input[value="nx_batch_rows"][checked]))

    html =
      render_submit(element(view, "#dashboard-selection"), %{
        "panels" => ["nx_duration_seconds"]
      })

    assert html =~ "Dashboard arrangement saved"
    assert {:ok, %{dashboard_panels: ["nx_duration_seconds"], room: nil}} = Sessions.verify(token)
    assert has_element?(view, ~s(#dashboard-selection input[value="nx_duration_seconds"][checked]))
    refute has_element?(view, ~s(#dashboard-selection input[value="nx_batch_rows"][checked]))

    exact =
      "/metrics?" <>
        Query.encode(%{
          "panels" => ["nx_operations_total", "nx_batch_fill_ratio"],
          "selection" => "custom"
        })

    assert {:ok, linked, _} = live(recycle(conn), exact)

    assert has_element?(
             linked,
             ~s(#dashboard-selection input[value="nx_operations_total"][checked])
           )

    assert has_element?(
             linked,
             ~s(#dashboard-selection input[value="nx_batch_fill_ratio"][checked])
           )

    refute has_element?(
             linked,
             ~s(#dashboard-selection input[value="nx_duration_seconds"][checked])
           )

    assert {:ok, %{dashboard_panels: ["nx_duration_seconds"]}} = Sessions.verify(token)

    assert {:ok, refused, refused_html} =
             live(recycle(conn), "/metrics?selection=custom&panels[]=caller")

    assert refused_html =~ "invalid_panels"

    assert has_element?(
             refused,
             ~s(#dashboard-selection input[value="nx_duration_seconds"][checked])
           )
  end

  test "saved panels query only their own room history on explicit request", %{conn: conn} do
    conn = get(conn, "/")
    {:ok, view, _} = live(recycle(conn), "/")
    render_click(element(view, "button[phx-click='start_room']"))

    redirect =
      render_submit(element(view, "#run-thermal"), %{
        "experiment_id" => "thermal",
        "params" => %{"backend" => "binary"}
      })

    {:ok, _, _} = follow_redirect(redirect, recycle(conn), "/runs/run-1")

    {:ok, metrics, html} = live(recycle(conn), "/metrics")
    assert html =~ "Session history panels"
    assert html =~ "History not loaded"
    refute has_element?(metrics, "#history-results")

    html = render_submit(element(metrics, "#history-query"), %{"range" => "5m"})
    assert has_element?(metrics, "#history-chart-nx_operations_total svg.wl-chart-svg")
    assert has_element?(metrics, "#history-chart-nx_duration_seconds svg.wl-chart-svg")
    assert html =~ "rate per step in count/second; 3 of 3 label sets"
    assert html =~ "Range 5m ending"
    assert html =~ "Query digests (3)"

    html = render_submit(element(metrics, "#history-query"), %{"range" => "2h"})
    assert html =~ "invalid_range"
    assert render_hook(metrics, "load_history", %{"caller" => "5m"}) =~ "invalid_range"

    html =
      render_submit(element(metrics, "#dashboard-selection"), %{
        "panels" => ["directory_operations_total"]
      })

    refute html =~ "history-results"
    html = render_submit(element(metrics, "#history-query"), %{"range" => "15m"})
    assert html =~ "No captured series in this range; nothing is drawn as zero."
    refute has_element?(metrics, "#history-chart-directory_operations_total")

    other = build_conn() |> get("/")
    {:ok, other_view, _} = live(recycle(other), "/metrics")
    refute has_element?(other_view, "#history-query")
    render_click(element(other_view, "button[phx-click='start_room']"))
    html = render_submit(element(other_view, "#history-query"), %{"range" => "5m"})
    assert html =~ "0 of 0 label sets"
    refute has_element?(other_view, "#history-chart-nx_operations_total")

    :ok = Sessions.revoke(get_session(conn, SessionToken.key()))

    assert render_submit(element(metrics, "#history-query"), %{"range" => "5m"}) =~
             "unknown_session"
  end
end
