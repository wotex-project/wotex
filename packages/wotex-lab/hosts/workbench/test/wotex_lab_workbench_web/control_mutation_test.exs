defmodule WotexLabWorkbenchWeb.ControlMutationTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.{Control, Room, Sessions}
  alias WotexLabWorkbench.Control.{Ledger, Limits}

  setup do
    {:ok, owner} = Sessions.open()
    {:ok, stranger} = Sessions.open()

    on_exit(fn ->
      _ = Sessions.revoke(owner.token)
      _ = Sessions.revoke(stranger.token)
    end)

    %{owner: owner, stranger: stranger}
  end

  test "mutations stay refused without host opt-in", %{conn: conn, owner: owner} do
    enabled = Application.fetch_env!(:wotex_lab_workbench, :control_mutations)
    Application.put_env(:wotex_lab_workbench, :control_mutations, false)
    on_exit(fn -> Application.put_env(:wotex_lab_workbench, :control_mutations, enabled) end)

    for path <- ["/api/v1/runs", "/api/v1/runs/run-1/cancel", "/api/v1/runs/run-1/approval"] do
      assert %{"code" => "mutations_disabled", "phase" => "control_api"} =
               conn
               |> mutation(path, owner.token, "disabled", start_body())
               |> json_response(403)
    end

    assert {:ok, %{room: nil}} = Sessions.verify(owner.token)
  end

  test "transport, key and body admission refuse before any room starts", %{
    conn: conn,
    owner: owner
  } do
    refusals = [
      {403, "origin_refused", [{"origin", "https://attacker.example"}], start_body(), ""},
      {415, "unsupported_media_type", [{"content-type", "text/plain"}], start_body(), ""},
      {400, "invalid_request", [], start_body(), "?experiment_id=thermal"},
      {413, "body_too_large", [], Map.put(start_body(), "padding", String.duplicate("a", 4_100)),
       ""},
      {400, "invalid_body", [], Map.put(start_body(), "url", "https://example.com/"), ""},
      {400, "invalid_body", [], Map.delete(start_body(), "deadline_ms"), ""},
      {400, "invalid_body", [], %{start_body() | "deadline_ms" => 30_001}, ""},
      {400, "invalid_body", [], %{start_body() | "experiment_id" => 7}, ""},
      {400, "invalid_body", [], Map.put(start_body(), "parameters", %{"seed" => 3}), ""},
      {400, "invalid_body", [], Map.put(start_body(), "parameters", ["seed"]), ""},
      {422, "unknown_experiment", [], %{start_body() | "experiment_id" => "caller"}, ""},
      {422, "unknown_parameter", [], Map.put(start_body(), "parameters", %{"path" => "/"}), ""},
      {422, "invalid_parameter", [],
       %{
         "experiment_id" => "window_anomaly",
         "parameters" => %{"count" => "9999"},
         "deadline_ms" => 5_000
       }, ""}
    ]

    for {status, code, headers, body, query} <- refusals do
      assert %{"code" => ^code} =
               conn
               |> mutation("/api/v1/runs" <> query, owner.token, "admission", body, headers)
               |> json_response(status)
    end

    for key <- [nil, "", "has space", String.duplicate("k", 129)] do
      assert %{"code" => "invalid_idempotency_key"} =
               conn
               |> mutation("/api/v1/runs", owner.token, key, start_body())
               |> json_response(400)
    end

    assert %{"code" => "missing_bearer"} =
             conn
             |> recycle()
             |> put_req_header("content-type", "application/json")
             |> put_req_header("idempotency-key", "no-bearer")
             |> post("/api/v1/runs", Jason.encode!(start_body()))
             |> json_response(401)

    assert %{"code" => "unknown_session", "phase" => "session"} =
             conn
             |> mutation("/api/v1/runs", String.duplicate("u", 43), "unknown", start_body())
             |> json_response(403)

    assert %{"code" => "invalid_body", "path" => "/"} =
             conn
             |> mutation("/api/v1/runs/run-1/cancel", owner.token, "cancel", %{
               "deadline_ms" => 1_000,
               "reason" => "caller"
             })
             |> json_response(400)

    assert %{"code" => "unknown_run"} =
             conn
             |> mutation(
               "/api/v1/runs/" <> String.duplicate("r", 65) <> "/cancel",
               owner.token,
               "long",
               %{"deadline_ms" => 1_000}
             )
             |> json_response(404)

    duplicated =
      conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> bearer(owner.token)
      |> put_req_header("idempotency-key", "two-origins")

    assert %{"code" => "origin_refused"} =
             %{
               duplicated
               | req_headers: [
                   {"origin", "https://client.example"},
                   {"origin", "https://attacker.example"} | duplicated.req_headers
                 ]
             }
             |> post("/api/v1/runs", Jason.encode!(start_body()))
             |> json_response(403)

    assert {:ok, %{room: nil}} = Sessions.verify(owner.token)

    for {origin, status} <- [
          {"https://client.example", 201},
          {WotexLabWorkbenchWeb.Endpoint.url(), 201}
        ] do
      assert conn
             |> mutation("/api/v1/runs", owner.token, "origin-" <> origin, start_body(), [
               {"origin", origin}
             ])
             |> json_response(status)
    end
  end

  test "startRun executes once per key and the run stays bound to its session", %{
    conn: conn,
    owner: owner,
    stranger: stranger
  } do
    first = mutation(conn, "/api/v1/runs", owner.token, "start-1", start_body())

    assert %{"id" => run_id, "status" => "completed", "experiment" => "thermal"} =
             run = json_response(first, 201)

    assert get_resp_header(first, "idempotent-replayed") == []
    assert get_resp_header(first, "cache-control") == ["no-store"]
    assert "sha256:" <> _ = run["record_digest"]
    refute Map.has_key?(run, "tensor")
    assert Enum.all?(run["assertions"], &(&1["status"] in ~w(pass fail not_run)))

    replay =
      mutation(conn, "/api/v1/runs", owner.token, "start-1", %{start_body() | "deadline_ms" => 9})

    assert json_response(replay, 201)["id"] == run_id
    assert get_resp_header(replay, "idempotent-replayed") == ["true"]

    {:ok, %{room: room}} = Sessions.verify(owner.token)
    assert length(Room.runs(room)) == 1

    assert %{"code" => "idempotency_key_reused"} =
             conn
             |> mutation("/api/v1/runs", owner.token, "start-1", %{
               "experiment_id" => "window_anomaly",
               "parameters" => %{"seed" => "2"},
               "deadline_ms" => 5_000
             })
             |> json_response(422)

    assert %{"id" => second_id, "experiment" => "window_anomaly"} =
             conn
             |> mutation("/api/v1/runs", owner.token, "start-2", %{
               "experiment_id" => "window_anomaly",
               "parameters" => %{"seed" => "2"},
               "deadline_ms" => 5_000
             })
             |> json_response(201)

    assert second_id != run_id
    assert length(Room.runs(room)) == 2

    read = json_response(get(bearer(conn, owner.token), "/api/v1/runs/" <> run_id), 200)
    assert read == run

    assert %{"schema_version" => "1.0.0"} =
             conn
             |> bearer(owner.token)
             |> get("/api/v1/evidence/" <> run["record_digest"])
             |> json_response(200)

    assert %{"code" => "unknown_run"} =
             json_response(get(bearer(conn, stranger.token), "/api/v1/runs/" <> run_id), 404)

    assert {:ok, _} = Sessions.admit(stranger.token, :start_room)

    assert %{"code" => "unknown_run"} =
             json_response(get(bearer(conn, stranger.token), "/api/v1/runs/" <> run_id), 404)

    assert %{"code" => "unknown_run"} =
             conn
             |> bearer(owner.token)
             |> get("/api/v1/runs/" <> String.duplicate("r", 65))
             |> json_response(404)

    assert %{"code" => "missing_bearer"} =
             json_response(get(recycle(conn), "/api/v1/runs/" <> run_id), 401)

    assert %{"code" => "unknown_session"} =
             conn
             |> bearer(String.duplicate("u", 43))
             |> get("/api/v1/runs/" <> run_id)
             |> json_response(403)
  end

  test "approval must name the granted decision and dispatches at most once", %{
    conn: conn,
    owner: owner,
    stranger: stranger
  } do
    %{"id" => run_id, "status" => "awaiting_approval", "decision" => decision} =
      conn
      |> mutation("/api/v1/runs", owner.token, "room", smart_room_body())
      |> json_response(201)

    path = "/api/v1/runs/#{run_id}/approval"
    approval = approval_body(decision)

    assert %{"code" => "unknown_run"} =
             json_response(mutation(conn, path, stranger.token, "foreign", approval), 404)

    for {field, value} <- [
          {"thing_id", "urn:wotex:lab:other"},
          {"action_name", "setMode"},
          {"input", decision["input"] + 1},
          {"proposal_digest", "sha256:" <> String.duplicate("0", 64)},
          {"state_revision", decision["state_revision"] + 1}
        ] do
      assert %{"code" => "approval_mismatch"} =
               conn
               |> mutation(path, owner.token, "mismatch-" <> field, %{approval | field => value})
               |> json_response(409)
    end

    assert %{"code" => "invalid_body", "path" => "/proposal_digest"} =
             conn
             |> mutation(path, owner.token, "bad-digest", %{approval | "proposal_digest" => "x"})
             |> json_response(400)

    assert %{"code" => "invalid_body", "path" => "/input"} =
             conn
             |> mutation(path, owner.token, "bad-input", %{approval | "input" => "21"})
             |> json_response(400)

    assert %{"code" => "invalid_body", "path" => "/state_revision"} =
             conn
             |> mutation(path, owner.token, "bad-revision", %{approval | "state_revision" => 1.5})
             |> json_response(400)

    {:ok, %{room: room}} = Sessions.verify(owner.token)
    assert {:ok, %{status: :awaiting_approval}} = Room.fetch_run(room, run_id)

    approved = mutation(conn, path, owner.token, "approve", approval)
    assert %{"status" => "dispatched", "effect" => effect} = json_response(approved, 200)
    assert effect == decision["input"]

    replayed = mutation(conn, path, owner.token, "approve", %{approval | "deadline_ms" => 2_000})
    assert json_response(replayed, 200)["status"] == "dispatched"
    assert get_resp_header(replayed, "idempotent-replayed") == ["true"]

    assert %{"code" => "not_approvable"} =
             json_response(mutation(conn, path, owner.token, "approve-again", approval), 409)

    %{policy: %{decisions: [recorded]}} = Room.snapshot(room)
    assert recorded.status == :dispatched
    assert length(recorded.attempts) == 1

    mismatch =
      mutation(conn, path, owner.token, "mismatch-thing_id", %{
        approval
        | "thing_id" => "urn:wotex:lab:other"
      })

    assert json_response(mismatch, 409)["code"] == "approval_mismatch"
    assert get_resp_header(mismatch, "idempotent-replayed") == ["true"]
  end

  test "cancellation revokes the pending decision and refuses later approval", %{
    conn: conn,
    owner: owner
  } do
    assert %{"code" => "unknown_run"} =
             conn
             |> mutation("/api/v1/runs/run-1/cancel", owner.token, "no-room", %{
               "deadline_ms" => 1_000
             })
             |> json_response(404)

    %{"id" => run_id, "decision" => decision} =
      conn
      |> mutation("/api/v1/runs", owner.token, "room", smart_room_body())
      |> json_response(201)

    cancel = "/api/v1/runs/#{run_id}/cancel"

    assert %{"status" => "cancelled", "decision" => nil} =
             conn
             |> mutation(cancel, owner.token, "cancel", %{"deadline_ms" => 1_000})
             |> json_response(200)

    assert %{"code" => "not_cancellable"} =
             conn
             |> mutation(cancel, owner.token, "cancel-again", %{"deadline_ms" => 1_000})
             |> json_response(409)

    assert %{"code" => "not_approvable"} =
             conn
             |> mutation(
               "/api/v1/runs/#{run_id}/approval",
               owner.token,
               "late",
               approval_body(decision)
             )
             |> json_response(409)

    assert %{"code" => "unknown_run"} =
             conn
             |> mutation("/api/v1/runs/run-99/cancel", owner.token, "unknown", %{
               "deadline_ms" => 1_000
             })
             |> json_response(404)
  end

  test "a busy room answers at the deadline and never starts the expired command", %{
    conn: conn,
    owner: owner
  } do
    {:ok, %{room: room}} = Sessions.admit(owner.token, :start_room)
    :ok = :sys.suspend(room)

    try do
      assert %{"code" => "deadline_exceeded"} =
               conn
               |> mutation("/api/v1/runs", owner.token, "late", %{
                 start_body()
                 | "deadline_ms" => 50
               })
               |> json_response(504)
    after
      :ok = :sys.resume(room)
    end

    assert Room.runs(room) == []

    assert %{"id" => _} =
             conn
             |> mutation("/api/v1/runs", owner.token, "late", start_body())
             |> json_response(201)

    Sessions.revoke(owner.token)

    assert %{"code" => "unknown_session"} =
             conn
             |> mutation("/api/v1/runs", owner.token, "revoked", start_body())
             |> json_response(403)
  end

  test "rooms retain a bounded identity set and report an unavailable room" do
    {:ok, session} = Sessions.open()
    on_exit(fn -> Sessions.revoke(session.token) end)
    {:ok, %{room: room}} = Sessions.admit(session.token, :start_room)
    later = System.monotonic_time(:millisecond) + 5_000

    control = fn key, deadline_at ->
      Room.control(
        room,
        %{key: key, fingerprint: "fingerprint", command: {:cancel, "run-404"}},
        deadline_at,
        1_000
      )
    end

    earlier = System.monotonic_time(:millisecond) - 1
    assert {:error, %Error{code: :deadline_exceeded}} = control.("expired", earlier)
    assert {:executed, {:error, %Error{code: :unknown_run}}} = control.("expired", later)

    for index <- 2..Ledger.capacity() do
      assert {:executed, {:error, %Error{}}} = control.("key-#{index}", later)
    end

    assert {:error, %Error{code: :idempotency_capacity}} = control.("one-too-many", later)
    assert {:replayed, {:error, %Error{code: :unknown_run}}} = control.("key-2", later)

    {:ok, admitted} =
      Control.admit_mutation(:cancel_run, "run-1", "dead-room", %{"deadline_ms" => 100})

    dead = spawn(fn -> :ok end)
    ref = Process.monitor(dead)
    assert_receive {:DOWN, ^ref, :process, ^dead, _reason}

    assert {:error, :refused, %Error{code: :room_unavailable}} = Control.mutate(dead, admitted)
  end

  test "rate and concurrency limits answer before the room", %{conn: conn, owner: owner} do
    holder = hold_slots([owner.id])

    assert %{"code" => "concurrency_limited"} =
             conn
             |> mutation("/api/v1/runs/run-1/cancel", owner.token, "busy", %{"deadline_ms" => 100})
             |> json_response(429)

    release(holder)

    host = hold_slots(for index <- 1..4, do: "host-#{index}")

    assert %{"code" => "concurrency_limited"} =
             conn
             |> mutation("/api/v1/runs/run-1/cancel", owner.token, "host", %{"deadline_ms" => 100})
             |> json_response(429)

    release(host)
    limits = Application.fetch_env!(:wotex_lab_workbench, :control_mutations)

    # The slot held for the owner above already counted as one admission.
    for index <- 2..limits[:max_requests] do
      assert %{"code" => "unknown_run"} =
               conn
               |> mutation("/api/v1/runs/run-1/cancel", owner.token, "rate-#{index}", %{
                 "deadline_ms" => 100
               })
               |> json_response(404)
    end

    limited =
      mutation(conn, "/api/v1/runs/run-1/cancel", owner.token, "rate-over", %{"deadline_ms" => 100})

    assert %{"code" => "rate_limited"} = json_response(limited, 429)
    assert [seconds] = get_resp_header(limited, "retry-after")
    assert String.to_integer(seconds) in 1..60
    assert {:ok, %{room: nil}} = Sessions.verify(owner.token)
  end

  defp hold_slots(session_ids) do
    parent = self()

    holder =
      spawn(fn ->
        Enum.each(session_ids, fn id -> {:ok, _} = Limits.acquire(id) end)
        send(parent, {:holding, self()})

        receive do
          :release -> :ok
        end
      end)

    assert_receive {:holding, ^holder}
    holder
  end

  defp release(holder) do
    ref = Process.monitor(holder)
    send(holder, :release)
    assert_receive {:DOWN, ^ref, :process, ^holder, _reason}
    eventually(fn -> map_size(:sys.get_state(Limits).slots) == 0 end)
  end

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() ->
        :ok

      attempts == 0 ->
        flunk("condition did not become true")

      true ->
        Process.sleep(10)
        eventually(fun, attempts - 1)
    end
  end

  defp start_body,
    do: %{
      "experiment_id" => "thermal",
      "parameters" => %{"backend" => "binary"},
      "deadline_ms" => 10_000
    }

  defp smart_room_body,
    do: %{"experiment_id" => "smart_room", "parameters" => %{}, "deadline_ms" => 10_000}

  defp approval_body(decision),
    do: %{
      "decision_id" => decision["id"],
      "thing_id" => decision["thing_id"],
      "action_name" => decision["action_name"],
      "input" => decision["input"],
      "proposal_digest" => decision["proposal_digest"],
      "state_revision" => decision["state_revision"],
      "expires_at" => decision["expires_at"],
      "deadline_ms" => 10_000
    }

  defp mutation(conn, path, token, key, body, headers \\ []) do
    conn =
      conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> bearer(token)

    conn = if key, do: put_req_header(conn, "idempotency-key", key), else: conn

    headers
    |> Enum.reduce(conn, fn {name, value}, acc -> put_req_header(acc, name, value) end)
    |> post(path, Jason.encode!(body))
  end

  defp bearer(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)
end
