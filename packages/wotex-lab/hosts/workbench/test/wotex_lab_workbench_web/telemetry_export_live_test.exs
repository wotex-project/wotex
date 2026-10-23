defmodule WotexLabWorkbenchWeb.TelemetryExportLiveTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias WotexLabWorkbench.{Metrics, Room, Sessions}
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  test "Freeze retains the selected component and operation and exports its exact captured rows", %{
    conn: conn
  } do
    conn = get(conn, "/") |> track_session()
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/experiments")
    render_submit(element(view, "#run-thermal"))
    render_patch(view, "/metrics")
    {:ok, session} = Sessions.verify(token)
    Metrics.record(session.id, :policy, :dispatch, %{duration: 7}, %{outcome: :ok})

    render_submit(element(view, "#metric-query"), %{
      "component" => "scenario",
      "operation" => "inference"
    })

    assert has_element?(view, "#metric-component option[value='scenario'][selected]")
    assert has_element?(view, "#metric-operation option[value='inference'][selected]")
    render_click(element(view, "button[phx-click='export_dataset']"))
    [frozen] = Room.snapshot(session.room).datasets
    assert frozen.rows > 0
    assert frozen.query.component == :scenario
    assert frozen.query.operation == :inference
    assert Enum.all?(frozen.samples, &(&1.component == :scenario and &1.operation == :inference))
    assert has_element?(view, "#metric-component option[value='scenario'][selected]")

    Metrics.record(session.id, :scenario, :inference, %{duration: 9}, %{outcome: :ok})

    render_submit(element(view, "#metric-query"), %{
      "component" => "scenario",
      "operation" => "inference"
    })

    assert Room.snapshot(session.room).datasets == [frozen]

    report = get(recycle(conn), "/evidence/report.json") |> json_response(200)
    assert [dataset] = report["datasets"]
    assert dataset["rows"] == length(dataset["samples"])
    assert dataset["digest"] == frozen.digest
    assert Enum.map(dataset["samples"], & &1["sequence"]) == Enum.map(frozen.samples, & &1.sequence)
  end
end
