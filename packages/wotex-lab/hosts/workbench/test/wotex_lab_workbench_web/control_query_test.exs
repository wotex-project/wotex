defmodule WotexLabWorkbenchWeb.ControlQueryTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias WotexLabWorkbench.{Experiments, Room, Sessions}

  test "a session bearer reads only its own room history through the closed descriptor", %{
    conn: conn
  } do
    {owner, room} = room_with_run("thermal")
    {:ok, binding} = Room.history(room)

    response = query(conn, owner.token, descriptor())
    answer = json_response(response, 200)
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert answer["source"] == "ets_history"
    assert answer["instance"] == binding.scope.instance
    assert answer["metric"] == "nx_operations_total"
    assert answer["digest"] =~ ~r/\Asha256:[0-9a-f]{64}\z/
    assert Enum.sum(Enum.map(answer["points"], & &1["value"])) >= 1

    required = ~w(source instance metric unit aggregation interval freshness points markers digest)
    assert Enum.all?(required, &Map.has_key?(answer, &1))

    {other, other_room} = room_with_run("window_anomaly")
    {:ok, other_binding} = Room.history(other_room)

    filtered = Map.put(descriptor(), "filters", %{"profile" => "thermal"})
    isolated = conn |> query(other.token, filtered) |> json_response(200)
    assert isolated["instance"] == other_binding.scope.instance
    refute isolated["instance"] == binding.scope.instance
    assert isolated["points"] == []

    {:ok, bare} = Sessions.open()
    on_exit(fn -> Sessions.revoke(bare.token) end)

    assert %{"code" => "unknown_history"} =
             conn |> query(bare.token, descriptor()) |> json_response(404)

    assert %{"code" => "missing_bearer"} =
             conn |> query(nil, descriptor()) |> json_response(401)

    assert conn |> query(String.duplicate("f", 32), descriptor()) |> response(403)

    for {body, status, code} <- [
          {Map.put(descriptor(), "scope", %{"instance" => other_binding.scope.instance}), 400,
           "invalid_request"},
          {Map.put(descriptor(), "limits", %{"points" => 100_000}), 400, "invalid_request"},
          {%{descriptor() | "metric" => "not_a_metric"}, 400, "invalid_request"},
          {%{descriptor() | "start_at" => iso(-2 * 3_600_000)}, 400, "invalid_range"},
          {%{descriptor() | "aggregation" => "avg"}, 422, "unsupported_query"}
        ] do
      assert %{"code" => ^code} = conn |> query(owner.token, body) |> json_response(status)
    end
  end

  test "framing and deadline refusals are explicit and release the query", %{conn: conn} do
    {owner, room} = room_with_run("thermal")
    body = Jason.encode!(descriptor())

    plain =
      conn
      |> recycle()
      |> put_req_header("content-type", "text/plain")
      |> bearer(owner.token)
      |> post("/api/v1/metrics/query", body)

    assert %{"code" => "unsupported_media_type"} = json_response(plain, 415)

    assert %{"code" => "invalid_request"} =
             conn
             |> recycle()
             |> put_req_header("content-type", "application/json")
             |> bearer(owner.token)
             |> post("/api/v1/metrics/query?instance=other", body)
             |> json_response(400)

    oversized = Map.put(descriptor(), "padding", String.duplicate("x", 4_200))

    assert %{"code" => "body_too_large"} =
             conn |> query(owner.token, oversized) |> json_response(413)

    {:ok, %{history: history}} = Room.history(room)
    :ok = :sys.suspend(history)

    try do
      assert %{"code" => "deadline_exceeded"} =
               conn |> query(owner.token, descriptor()) |> json_response(504)
    after
      :ok = :sys.resume(history)
    end

    assert conn |> query(owner.token, descriptor()) |> json_response(200)
    assert Wotex.Lab.Metrics.History.stats(history).active_queries == 0
  end

  defp room_with_run(experiment_id) do
    {:ok, session} = Sessions.open()
    on_exit(fn -> Sessions.revoke(session.token) end)
    {:ok, %{room: room}} = Sessions.admit(session.token, :run)
    {:ok, experiment} = Experiments.fetch(experiment_id)
    {:ok, params} = Experiments.admit(experiment, Experiments.defaults(experiment))
    {:ok, _} = Room.start_run(room, experiment.id, params)
    {session, room}
  end

  defp descriptor do
    %{
      "schema_version" => "1.0.0",
      "metric" => "nx_operations_total",
      "aggregation" => "sum",
      "start_at" => iso(-60_000),
      "end_at" => iso(5_000),
      "step_ms" => 5_000
    }
  end

  defp iso(offset_ms) do
    now = System.system_time(:millisecond)
    aligned = div(now, 5_000) * 5_000 + offset_ms
    aligned |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601()
  end

  defp query(conn, token, body) do
    conn = conn |> recycle() |> put_req_header("content-type", "application/json")
    conn = if token, do: bearer(conn, token), else: conn
    post(conn, "/api/v1/metrics/query", Jason.encode!(body))
  end

  defp bearer(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)
end
