defmodule WotexLabWorkbenchWeb.ControlControllerTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias WotexLabWorkbench.{Experiments, Room, Sessions}

  test "scenario and metric catalogue endpoints expose only inert bounded descriptors", %{
    conn: conn
  } do
    scenarios = conn |> get("/api/v1/scenarios") |> json_response(200)
    assert length(scenarios["scenarios"]) == 16

    assert %{
             "schema_version" => "1.0.0",
             "id" => "thermal-nx",
             "seed" => 1,
             "max_steps" => 4
           } = Enum.find(scenarios["scenarios"], &(&1["id"] == "thermal-nx"))

    assert get_resp_header(get(recycle(conn), "/api/v1/scenarios"), "cache-control") == [
             "no-store"
           ]

    assert json_response(get(recycle(conn), "/api/v1/scenarios/consume-http"), 200)["title"] =~
             "HTTP"

    assert %{"code" => "unknown_scenario", "phase" => "control_api"} =
             recycle(conn)
             |> get("/api/v1/scenarios/not-admitted")
             |> json_response(404)

    catalogue = conn |> recycle() |> get("/api/v1/metrics/catalogue") |> json_response(200)
    assert catalogue["schema_version"] == "1.0.0"
    assert length(catalogue["metrics"]) > 10

    assert Enum.all?(catalogue["metrics"], fn metric ->
             metric["kind"] in ~w(counter gauge histogram) and is_list(metric["dimensions"])
           end)
  end

  test "evidence requires an exact session bearer and cannot cross room boundaries", %{conn: conn} do
    {:ok, owner} = Sessions.open()
    {:ok, %{room: room}} = Sessions.admit(owner.token, :run)
    {:ok, experiment} = Experiments.fetch("thermal")
    {:ok, params} = Experiments.admit(experiment, Experiments.defaults(experiment))
    {:ok, run} = Room.start_run(room, experiment.id, params)

    response =
      conn
      |> bearer(owner.token)
      |> get("/api/v1/evidence/#{run.record_digest}")

    assert %{"scenario_id" => "thermal", "schema_version" => "1.0.0"} =
             json_response(response, 200)

    assert get_resp_header(response, "cache-control") == ["no-store"]

    assert %{"code" => "missing_bearer"} =
             conn
             |> recycle()
             |> get("/api/v1/evidence/#{run.record_digest}")
             |> json_response(401)

    {:ok, stranger} = Sessions.open()

    assert %{"code" => "unknown_evidence"} =
             conn
             |> recycle()
             |> bearer(stranger.token)
             |> get("/api/v1/evidence/#{run.record_digest}")
             |> json_response(404)

    assert %{"code" => "invalid_record_id"} =
             conn
             |> recycle()
             |> bearer(owner.token)
             |> get("/api/v1/evidence/sha256:not-a-digest")
             |> json_response(400)

    :ok = Sessions.revoke(owner.token)
    :ok = Sessions.revoke(stranger.token)
  end

  defp bearer(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)
end
