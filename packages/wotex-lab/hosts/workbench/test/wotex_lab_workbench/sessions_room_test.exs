defmodule WotexLabWorkbench.SessionsRoomTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.{Experiments, Metrics, Report, Room, Sessions}
  alias WotexLabWorkbench.Observability.Panels
  alias WotexLabWorkbench.Runs.SmartRoom

  setup do
    lab = start_supervised!({Wotex.Lab, id: "workbench-test", max_children: 128})

    registry =
      start_supervised!(
        {Sessions,
         lab: lab,
         ttl_ms: 5_000,
         sweep_ms: 50,
         max_sessions: 8,
         name: WotexLabWorkbench.SessionsRoomTest.Registry}
      )

    %{lab: lab, registry: registry}
  end

  test "opening and verifying starts no room; room teardown reaps every owned process", %{
    lab: lab,
    registry: registry
  } do
    assert {:ok, session} = Sessions.open(registry)
    assert session.room == nil
    assert session.dashboard_panels == Panels.defaults()
    assert {:ok, verified} = Sessions.verify(registry, session.token)
    assert verified.room == nil
    assert role_count(lab, :sessions) == 0
    assert role_count(lab, :things) == 0

    assert {:error, %Error{code: :unknown_command}} =
             Sessions.admit(registry, session.token, :caller_command)

    assert {:ok, live} = Sessions.admit(registry, session.token, :run)
    assert is_pid(live.room) and Process.alive?(live.room)
    state = :sys.get_state(live.room)
    owned = state.owned_local ++ Enum.map(state.owned_lab, &elem(&1, 1))

    assert :ok = Sessions.revoke(registry, session.token)
    eventually(fn -> not Process.alive?(live.room) end)
    Enum.each(owned, fn pid -> eventually(fn -> not Process.alive?(pid) end) end)
    eventually(fn -> role_count(lab, :sessions) == 0 end)
    eventually(fn -> role_count(lab, :things) == 0 end)
    assert {:error, %Error{code: :unknown_session}} = Sessions.verify(registry, session.token)
  end

  test "two sessions own distinct rooms and measurement scopes", %{registry: registry} do
    {:ok, first} = Sessions.open(registry)
    {:ok, second} = Sessions.open(registry)
    {:ok, first} = Sessions.admit(registry, first.token, :run)
    {:ok, second} = Sessions.admit(registry, second.token, :run)

    refute first.room == second.room
    {:ok, experiment} = Experiments.fetch("thermal")
    {:ok, params} = Experiments.admit(experiment, %{})
    assert {:ok, run} = Room.start_run(first.room, experiment.id, params)
    assert run.status == :completed and is_binary(run.record_digest)

    assert {:ok, first_metrics} = Metrics.query(scope: first.id)
    assert Enum.all?(first_metrics.samples, &(&1.scope == first.id))
    assert {:error, :unavailable} = Metrics.query(scope: second.id)

    assert Room.runs(second.room) == []
    assert :ok = Sessions.revoke(registry, first.token)
    assert Process.alive?(second.room)
    assert :ok = Sessions.revoke(registry, second.token)
  end

  test "smart-room dispatch requires an exact fresh approval and cannot replay", %{
    registry: registry
  } do
    {:ok, session} = Sessions.open(registry)
    {:ok, session} = Sessions.admit(registry, session.token, :run)
    {:ok, experiment} = Experiments.fetch("smart_room")
    {:ok, params} = Experiments.admit(experiment, %{})

    assert {:ok, run} = Room.start_run(session.room, experiment.id, params)
    assert run.status == :awaiting_approval
    assert run.effect == nil

    assert {:error, %Error{code: :pending_decision}} =
             Room.start_run(session.room, experiment.id, params)

    assert {:error, %Error{code: :approval_mismatch}} =
             Room.approve(session.room, run.id, %{"decision_id" => "wrong"})

    decision = run.decision

    approval = %{
      "decision_id" => decision["id"],
      "proposal_digest" => decision["proposal_digest"],
      "revision" => Integer.to_string(decision["state_revision"]),
      "expires_at" => Integer.to_string(decision["expires_at"])
    }

    assert {:ok, dispatched} = Room.approve(session.room, run.id, approval)
    assert dispatched.status == :dispatched
    assert dispatched.effect == dispatched.proposal["input"]

    assert {:error, %Error{code: :not_approvable}} =
             Room.approve(session.room, run.id, approval)

    assert {:error, %Error{code: :not_cancellable}} = Room.cancel_run(session.room, run.id)

    assert {:ok, pending} = Room.start_run(session.room, experiment.id, params)
    assert {:ok, cancelled} = Room.cancel_run(session.room, pending.id)
    assert cancelled.status == :cancelled and cancelled.decision == nil
    assert {:ok, _} = Room.start_run(session.room, experiment.id, params)
  end

  test "Thing reads, inert registration, dataset export and reports stay bounded", %{
    registry: registry
  } do
    {:ok, session} = Sessions.open(registry)
    {:ok, session} = Sessions.admit(registry, session.token, :run)

    assert length(Room.things(session.room)) == 3
    assert {:ok, reading} = Room.read_property(session.room, "thermostat", "temperature")
    assert reading.value == 21.5

    assert {:error, %Error{code: :unknown_property}} =
             Room.read_property(session.room, "thermostat", "caller")

    assert {:error, %Error{code: :unknown_thing}} =
             Room.read_property(session.room, "caller", "temperature")

    source = td("urn:test:untrusted", "<script>alert('x')</script>")
    assert {:ok, document} = Room.register_td(session.room, source)
    assert document["title"] == "<script>alert('x')</script>"

    assert Enum.any?(
             Room.things(session.room),
             &(&1.id == "urn:test:untrusted" and not &1.consumable)
           )

    assert {:error, %Error{code: :td_too_large}} =
             Room.register_td(session.room, String.duplicate("x", 16_385))

    {:ok, experiment} = Experiments.fetch("thermal")
    {:ok, params} = Experiments.admit(experiment, %{})
    assert {:ok, _} = Room.start_run(session.room, experiment.id, params)
    assert {:ok, dataset} = Room.export_dataset(session.room, limit: 100)
    assert dataset.rows > 0 and dataset.rows <= 100
    assert String.starts_with?(dataset.digest, "sha256:")

    assert {:error, :unsupported} =
             Room.verify(session.room, :no_simultaneous_heat_cool, :safe)

    snapshot = Room.snapshot(session.room)
    report = Report.build(snapshot)
    assert report["session"] == session.id
    assert report["conformance"]["status"] == "not_run"
    assert {:ok, json} = Report.encode(report)
    assert byte_size(json) < 1_048_576
    assert Jason.decode!(json)["session"] == session.id
  end

  test "session configuration, limits, themes and expiry fail explicitly", %{lab: lab} do
    assert {:error, %Error{code: :invalid_session_config}} = Sessions.start_link([])
    assert {:error, %Error{code: :invalid_session_config}} = Sessions.start_link(:bad)

    registry =
      start_supervised!(
        Supervisor.child_spec(
          {Sessions,
           lab: lab,
           ttl_ms: 100,
           sweep_ms: 10,
           max_sessions: 1,
           name: WotexLabWorkbench.SessionsRoomTest.ShortRegistry},
          id: :short_registry
        )
      )

    {:ok, session} = Sessions.open(registry)
    assert {:error, %Error{code: :session_limit}} = Sessions.open(registry)
    assert {:ok, themed} = Sessions.put_theme(registry, session.token, "dark")
    assert themed.theme == "dark"

    assert {:error, %Error{code: :invalid_theme}} =
             Sessions.put_theme(registry, session.token, "rainbow")

    assert {:ok, arranged} =
             Sessions.put_dashboard(registry, session.token, ["nx_duration_seconds"])

    assert arranged.dashboard_panels == ["nx_duration_seconds"]
    assert arranged.room == nil

    assert {:error, %Error{code: :invalid_panels}} =
             Sessions.put_dashboard(registry, session.token, ["caller"])

    Process.sleep(120)
    assert {:error, %Error{code: code}} = Sessions.verify(registry, session.token)
    assert code in [:expired_session, :unknown_session]
  end

  test "window and refused smart-room runs keep every output inert", %{registry: registry} do
    {:ok, session} = Sessions.open(registry)
    {:ok, session} = Sessions.admit(registry, session.token, :run)

    {:ok, window} = Experiments.fetch("window_anomaly")
    {:ok, window_params} = Experiments.admit(window, %{})
    assert {:ok, window_run} = Room.start_run(session.room, window.id, window_params)
    assert window_run.status == :completed
    assert window_run.proposal == nil
    assert length(window_run.timeseries) >= 2
    assert Enum.all?(window_run.assertions, &(&1.status == :pass))

    {:ok, smart} = Experiments.fetch("smart_room")

    {:ok, guest_params} =
      Experiments.admit(smart, %{"principal" => "guest", "meter" => "off"})

    assert {:ok, refused} = Room.start_run(session.room, smart.id, guest_params)
    assert refused.status == :completed
    assert refused.decision == nil and refused.effect == nil
    assert Enum.any?(refused.assertions, &(&1.id == "room:decision" and &1.status == :fail))

    assert {:error, %Error{code: :no_decision}} =
             SmartRoom.dispatch(refused, %{}, :sys.get_state(session.room))
  end

  test "room and registry reject malformed and out-of-scope commands without crashing", %{
    lab: lab,
    registry: registry
  } do
    {:ok, unopened} = Sessions.open(registry)
    assert {:error, %Error{code: :no_room}} = Sessions.admit(registry, unopened.token, :query)
    assert {:error, %Error{code: :invalid_token}} = Sessions.verify(registry, :caller)
    assert {:error, %Error{code: :unknown_session}} = Sessions.revoke(registry, "unknown")

    {:ok, session} = Sessions.admit(registry, unopened.token, :run)
    assert {:error, %Error{code: :unknown_run}} = Room.cancel_run(session.room, "missing")
    assert {:error, %Error{code: :invalid_approval}} = Room.approve(session.room, "missing", [])
    assert {:error, %Error{code: :invalid_read}} = Room.read_property(session.room, :bad, :bad)
    assert {:error, %Error{code: :td_rejected}} = Room.register_td(session.room, "{")
    assert {:error, %Error{code: :invalid_query}} = Room.export_dataset(session.room, %{})

    assert {:error, %Error{code: :invalid_query}} =
             Room.export_dataset(session.room, limit: 1, limit: 2)

    assert {:error, %Error{code: :unknown_selection}} =
             Room.verify(session.room, :caller, :caller)

    assert {:error, %Error{code: :invalid_session_config}} =
             Sessions.start_link(
               lab: lab,
               ttl_ms: 100,
               ttl_ms: 200,
               sweep_ms: 10,
               max_sessions: 1,
               name: :duplicate_options
             )
  end

  defp td(id, title) do
    Jason.encode!(%{
      "@context" => Wotex.td_context_1_1(),
      "id" => id,
      "title" => title,
      "security" => ["nosec_sc"],
      "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}}
    })
  end

  defp role_count(lab, role) do
    {^role, pid, :supervisor, _} = List.keyfind(Supervisor.which_children(lab), role, 0)
    DynamicSupervisor.count_children(pid).active
  end

  defp eventually(fun, attempts \\ 50)

  defp eventually(fun, attempts) do
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
end
