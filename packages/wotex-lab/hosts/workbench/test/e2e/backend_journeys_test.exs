defmodule WotexLabWorkbenchWeb.E2E.BackendJourneysTest do
  @moduledoc false

  use PhoenixTest.Playwright.Case, async: false

  alias WotexLabWorkbench.{Metrics, Room, Sessions}
  alias WotexLabWorkbench.Observability.Panels
  alias WotexLabWorkbenchWeb.{Endpoint, Plugs.SessionToken}

  @moduletag :e2e
  @metric_pin ".svelte-flow__node-metric"
  @menu "[role='menu'][aria-label='Metric actions']"

  setup %{conn: conn} do
    {:ok, session} = Sessions.open()
    on_exit(fn -> Sessions.revoke(session.token) end)

    conn =
      add_session_cookie(
        conn,
        [value: %{SessionToken.key() => session.token}],
        Endpoint.session_options()
      )

    %{conn: conn, token: session.token, session_id: session.id}
  end

  test "an executed metric query pins backend measurements and restores its saved capture paused",
       %{
         conn: conn,
         token: token
       } do
    panel = Enum.find(Panels.all(), &(&1.id == "nx_duration_seconds"))

    conn =
      conn
      |> visit("/experiments")
      |> click_button("#run-thermal", "Run")
      |> assert_path("/runs/run-1")
      |> assert_has("#wl-run-result")
      |> visit("/metrics")
      |> select("Metric", option: panel.title)
      |> select("Range", option: "5m")
      |> click_button("#metric-compose-query > button", "Query", exact: true)
      |> assert_has("#composed-metric-chart svg")
      |> click_button("Pin to workbench")
      |> assert_path("/")
      |> assert_has(@metric_pin)

    {:ok, %{room: room}} = Sessions.verify(token)
    runs = Room.runs(room)
    {:ok, %{pins: [pin]}} = Sessions.board(token)
    assert pin.metric == "nx_duration_seconds"

    assert Enum.any?(pin.result.chart.series, fn series ->
             Enum.any?(series.points, fn {_, value} -> is_number(value) end)
           end)

    conn =
      conn
      |> click_button("Save layout")
      |> assert_has("button[aria-label='Save layout'][title='Layout saved']")
      |> visit("/")
      |> assert_has(@metric_pin, text: "Paused")
      |> click_button("Actions for #{pin.title}")
      |> click(@menu <> " [role='menuitem']", "Rename / sources")
      |> assert_has("#rename-pin")
      |> fill_in("Title", with: "Measured duration")
      |> click_button("Rename")
      |> click_link("Close panel")
      |> assert_has(@metric_pin, text: "Measured duration")

    {:ok, %{pins: [restored]}} = Sessions.board(token)
    assert restored.result == pin.result
    assert restored.window == pin.window
    assert Map.delete(restored, :title) == Map.delete(pin, :title)
    assert Room.runs(room) == runs

    conn
    |> click_button("Actions for Measured duration")
    |> assert_has(@menu <> " [role='menuitem']", text: "Resume")
    |> click(@menu <> " [role='menuitem']", "Remove")
    |> refute_has(@metric_pin)

    assert {:ok, %{pins: []}} = Sessions.board(token)
  end

  test "metrics freeze and downloaded evidence contain only the owning backend records", %{
    conn: conn,
    token: token,
    session_id: session_id
  } do
    conn =
      conn
      |> visit("/experiments")
      |> click_button("#run-thermal", "Run")
      |> assert_path("/runs/run-1")
      |> assert_has("#wl-run-result")
      |> click_link("Export report")
      |> assert_download(fn download ->
        assert download.name == "wotex-lab-run-evidence.json"
        report = JSON.decode!(download.content)
        assert report["session"] == session_id
        assert report["scope"] == %{"kind" => "run", "run_id" => "run-1"}
        assert [%{"id" => "run-1", "record_digest" => "sha256:" <> _}] = report["runs"]
        assert report["datasets"] == []
      end)
      |> visit("/metrics")
      |> click("details > summary", "Session measurements")
      |> select("Component", option: "scenario")
      |> select("Operation", option: "inference")
      |> click_button("#metric-query > button", "Refresh", exact: true)
      |> click_button("Freeze visible measurements as dataset")
      |> assert_has(".wl-flash[role='status']", text: "Frozen dataset-1")

    {:ok, %{room: room}} = Sessions.verify(token)
    assert [dataset] = Room.snapshot(room).datasets
    {:ok, measurements} = Metrics.query(scope: session_id)

    expected =
      Enum.map(
        measurements.samples,
        &Map.take(&1, [:sequence, :at, :component, :operation, :event, :duration_ms, :outcome])
      )

    assert Enum.all?(dataset.samples, &(&1 in expected))
    assert length(dataset.samples) == dataset.rows
    assert dataset.rows > 0
    assert %DateTime{} = dataset.frozen_at

    conn
    |> visit("/evidence")
    |> assert_has("#evidence-runs", text: "run-1")
    |> assert_has("#evidence-datasets", text: dataset.digest)
    |> click_link("a[href='/evidence/datasets/dataset-1']", "Download")
    |> assert_download(fn download ->
      assert download.name == "wotex-lab-dataset-1.json"
      capture = JSON.decode!(download.content)
      assert capture["digest"] == dataset.digest
      assert capture["rows"] == length(capture["samples"])
      assert capture["source"]["scope"] == session_id
    end)
    |> click_link("Export session report")
    |> assert_download(fn download ->
      assert download.name == "wotex-lab-evidence.json"
      report = JSON.decode!(download.content)
      assert report["session"] == session_id
      assert length(report["runs"]) == 1
      assert length(report["datasets"]) == 1
      assert hd(report["datasets"])["samples"] != []
    end)

    assert [%{id: "run-1"}] = Room.runs(room)
  end

  test "review and cancellation stay inert and an explicit approval dispatches only once", %{
    conn: conn,
    token: token
  } do
    conn =
      conn
      |> visit("/experiments?experiment=smart_room")
      |> click_button("#run-smart_room", "Run")
      |> assert_path("/runs/run-1")
      |> click_link("Review Action")
      |> assert_path("/runs/run-1", query_params: %{"view" => "review"})
      |> assert_has("#approve-run-1")

    {:ok, %{room: room}} = Sessions.verify(token)
    assert [%{status: :awaiting_approval, dispatch: nil}] = Room.runs(room)
    before = handler_calls(room)

    conn =
      conn
      |> click_link("Back to result")
      |> click_link("Review Action")
      |> assert_has("#approve-run-1")

    assert handler_calls(room) == before

    conn =
      conn
      |> click_button("Cancel run")
      |> refute_has("#approve-run-1")
      |> visit("/experiments?experiment=smart_room")
      |> click_button("#run-smart_room", "Run")
      |> assert_path("/runs/run-2")
      |> click_link("Review Action")
      |> click_button("Approve Action")
      |> refute_has("#approve-run-2")
      |> assert_has("#wl-run-panel-run-2", text: "No pending Action")

    assert [%{status: :dispatched}, %{status: :cancelled, dispatch: nil}] = Room.runs(room)
    after_dispatch = handler_calls(room)

    conn
    |> visit("/runs/run-2?view=review")
    |> assert_has("#wl-run-panel-run-2", text: "No pending Action")
    |> refute_has("#approve-run-2")

    assert handler_calls(room) == after_dispatch
  end

  defp handler_calls(room), do: Enum.map(Room.things(room), &{&1.id, &1.stats.handler_calls})
end
