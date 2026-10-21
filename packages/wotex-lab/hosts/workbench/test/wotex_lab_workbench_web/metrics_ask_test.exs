defmodule WotexLabWorkbenchWeb.MetricsAskTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias WotexLabWorkbench.{Investigation.ContextStore, Investigation.Skill, Room, Sessions}
  alias WotexLabWorkbench.Observability.Supervisor, as: ObservabilitySupervisor
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  test "Ask returns the executed room chart, links its sources and pins without querying again", %{
    conn: conn
  } do
    owner = self()

    start_tree(fn ->
      summary = Skill.callbacks()["lab_metric_query"].("nx_batch_rows", "last")
      [history] = ContextStore.metric_results()
      send(owner, {:recorded_history, history})
      [%{digest: digest} | _] = summary.queries

      {:ok,
       [%{context: "Room measurements", observation: "Recorded rows #{digest}", snapshots: []}]}
    end)

    conn = get(conn, "/") |> track_session()
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/experiments")
    render_submit(element(view, "#run-thermal"))
    assert_patch(view, "/runs/run-1")
    render_patch(view, "/metrics")
    render_change(element(view, "#investigation"), %{"prompt" => "Show batch rows"})
    render_submit(element(view, "#investigation"), %{"prompt" => "Show batch rows"})
    assert_receive {:recorded_history, history}, 1_000
    html = until_result(view)
    assert html =~ "Recorded rows [1]"
    assert has_element?(view, "a[href='#investigation-metric-0']")
    assert has_element?(view, "#investigation-prompt", "Show batch rows")
    assert ContextStore.metric_results() == []
    render_click(element(view, "button[phx-click='pin_investigation_metric']"))
    assert_patch(view, "/")
    assert {:ok, %{pins: [pin]}} = Sessions.board(token)
    assert pin.result.chart == hd(history.panels).chart
    assert pin.window == Map.take(history, [:start_ms, :end_ms, :step_ms])
    assert {:ok, scope} = Sessions.verify(token)
    assert length(Room.runs(scope.room)) == 1
  end

  test "an unavailable provider retains an editable question and exposes the query fallback without allocating a room",
       %{conn: conn} do
    conn = get(conn, "/") |> track_session()
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/metrics")
    assert has_element?(view, "#investigation button[type='submit'][disabled]")
    refute has_element?(view, "#investigation-prompt[disabled]")
    assert has_element?(view, "#metric-query-builder[open]")
    render_change(element(view, "#investigation"), %{"prompt" => "Show execution duration"})
    render_patch(view, "/")
    render_patch(view, "/metrics")
    assert has_element?(view, "#investigation-prompt", "Show execution duration")
    render_change(element(view, "#investigation"), %{"prompt" => String.duplicate("x", 513)})
    assert has_element?(view, "#investigation-prompt", "Show execution duration")
    render_hook(view, "pin_investigation_metric", %{"index" => "0"})
    assert {:ok, %{room: nil}} = Sessions.verify(token)
    assert {:ok, %{pins: []}} = Sessions.board(token)
  end

  test "a metrics question needs no prior run and a duplicate submit cannot replace its active owner",
       %{conn: conn} do
    start_tree(:block)
    conn = get(conn, "/") |> track_session()
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/metrics")
    render_click(element(view, "button[phx-click='start_room']"))
    render_submit(element(view, "#investigation"), %{"prompt" => "Inspect this room"})
    assert_receive {:fake_investigation_started, worker, "Inspect this room"}, 1_000
    assert_receive {:fake_investigation_context, %{available: false}, %{available: false}}, 1_000
    render_hook(view, "ask", %{"prompt" => "Replacement"})
    assert has_element?(view, "#investigation-prompt", "Inspect this room")
    refute_receive {:fake_investigation_started, _, "Replacement"}
    monitor = Process.monitor(worker)
    render_patch(view, "/")
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
    render_patch(view, "/metrics")
    assert has_element?(view, "#investigation-prompt", "Inspect this room")
    refute has_element?(view, "#investigation-metric-0")
    assert {:ok, scope} = Sessions.verify(token)
    assert Room.runs(scope.room) == []
  end

  defp until_result(view, attempts \\ 100) do
    if has_element?(view, "#investigation-metric-0") do
      render(view)
    else
      assert attempts > 0, "investigation did not return a recorded chart"
      Process.sleep(10)
      until_result(view, attempts - 1)
    end
  end

  defp start_tree(script) do
    keys = [:beamlens_operator_runner, :fake_investigation_result, :fake_investigation_owner]
    saved = Map.new(keys, &{&1, Application.get_env(:wotex_lab_workbench, &1)})

    Application.put_env(
      :wotex_lab_workbench,
      :beamlens_operator_runner,
      WotexLabWorkbench.FakeInvestigationRunner
    )

    Application.put_env(:wotex_lab_workbench, :fake_investigation_result, script)
    Application.put_env(:wotex_lab_workbench, :fake_investigation_owner, self())

    on_exit(fn ->
      for {key, value} <- saved do
        if value == nil,
          do: Application.delete_env(:wotex_lab_workbench, key),
          else: Application.put_env(:wotex_lab_workbench, key, value)
      end
    end)

    capability = String.duplicate("c", 43)

    registry = %{
      primary: "Test",
      clients: [
        %{
          name: "Test",
          provider: "openai-generic",
          options: %{base_url: "http://127.0.0.1:1/v1", model: "test", api_key: capability}
        }
      ]
    }

    start_supervised!(
      {ObservabilitySupervisor,
       history: [interval_ms: 60_000], beamlens: %{capability: capability, registry: registry}}
    )
  end
end
