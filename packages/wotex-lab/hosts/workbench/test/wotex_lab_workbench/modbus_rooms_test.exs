defmodule WotexLabWorkbench.ModbusRoomsTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias Wotex.Runtime.Request
  alias WotexLabWorkbench.{Experiments, ModbusThing, Room, Sessions}
  alias WotexLabWorkbench.Test.ScriptedModbusPeer

  @profile %{id: "zone", title: "Zone", host: {127, 0, 0, 1}, port: 1, unit_id: 1}

  setup do
    lab = start_supervised!({Wotex.Lab, id: "modbus-rooms", max_children: 128})

    registry =
      start_supervised!(
        {Sessions,
         lab: lab,
         ttl_ms: 60_000,
         sweep_ms: 50,
         max_sessions: 8,
         room_profiles: [@profile],
         name: __MODULE__.Registry}
      )

    %{lab: lab, registry: registry}
  end

  test "selection is passive, exclusive, idempotent and released by explicit end", %{
    registry: registry
  } do
    {:ok, first} = Sessions.open(registry)
    {:ok, second} = Sessions.open(registry)
    assert {:ok, [_, %{available: true}]} = Sessions.room_profiles(registry, first.token)
    assert {:ok, %{room: nil}} = Sessions.verify(registry, first.token)

    assert {:error, %Error{code: :unknown_room_profile}} =
             Sessions.admit(registry, first.token, {:start_room, "caller"})

    assert {:ok, first} = Sessions.admit(registry, first.token, {:start_room, "zone"})
    room = first.room
    actors = owned_workers(room)
    assert length(actors) == 4
    assert Enum.all?(Room.things(room), &(&1.stats.handler_calls == 0 and &1.stats.state == %{}))
    assert {:ok, %{room: ^room}} = Sessions.admit(registry, first.token, {:start_room, "zone"})
    assert {:ok, [_, %{available: false}]} = Sessions.room_profiles(registry, second.token)

    assert {:error, %Error{code: :room_profile_busy}} =
             Sessions.admit(registry, second.token, {:start_room, "zone"})

    assert {:error, %Error{code: :room_exists}} =
             Sessions.admit(registry, first.token, {:start_room, "loopback"})

    assert {:ok, %{room: nil, room_profile: nil, presentation: nil}} =
             Sessions.end_room(registry, first.token, first.room)

    refute Process.alive?(room)
    assert Enum.all?(actors, &(not Process.alive?(&1)))
    assert {:ok, second} = Sessions.admit(registry, second.token, {:start_room, "zone"})
    assert second.room != room
    assert {:error, %Error{code: :room_changed}} = Sessions.end_room(registry, second.token, nil)
    assert {:ok, %{room: nil}} = Sessions.end_room(registry, second.token, second.room)
    assert {:ok, %{room: nil}} = Sessions.end_room(registry, second.token, nil)
    {:ok, first} = Sessions.admit(registry, first.token, :start_room)
    assert {:error, %Error{code: :room_changed}} = Sessions.end_room(registry, first.token, room)
    assert Process.alive?(first.room)
  end

  test "invalid host profiles refuse startup before optional service admission" do
    previous = Application.fetch_env(:wotex_lab_workbench, :room_profiles)
    Application.put_env(:wotex_lab_workbench, :room_profiles, [%{@profile | port: 0}])

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:wotex_lab_workbench, :room_profiles, value)
        :error -> Application.delete_env(:wotex_lab_workbench, :room_profiles)
      end
    end)

    registry = Process.whereis(Sessions)

    assert {:error, %Error{code: :invalid_room_profiles}} =
             WotexLabWorkbench.Application.start(:normal, [])

    assert Process.whereis(Sessions) == registry
  end

  @tag capture_log: true
  test "room death reaps transport owners before reuse and stale DOWN cannot free a replacement", %{
    registry: registry
  } do
    {:ok, session} = Sessions.open(registry)
    {:ok, session} = Sessions.admit(registry, session.token, {:start_room, "zone"})
    actors = owned_workers(session.room)
    old = session.room

    {monitor, _} =
      Enum.find(:sys.get_state(registry).monitors, fn {_, {_, pid, _}} -> pid == old end)

    Process.exit(old, :kill)
    eventually(fn -> match?({:ok, %{room: nil}}, Sessions.verify(registry, session.token)) end)
    assert Enum.all?(actors, &(not Process.alive?(&1)))
    {:ok, replacement} = Sessions.admit(registry, session.token, {:start_room, "zone"})
    send(registry, {:DOWN, monitor, :process, old, :killed})
    assert {:ok, %{room: room}} = Sessions.verify(registry, session.token)
    assert room == replacement.room
    {:ok, other} = Sessions.open(registry)

    assert {:error, %Error{code: :room_profile_busy}} =
             Sessions.admit(registry, other.token, {:start_room, "zone"})
  end

  test "registry loss retires the room and all its Modbus actors", %{registry: registry} do
    {:ok, session} = Sessions.open(registry)
    {:ok, session} = Sessions.admit(registry, session.token, {:start_room, "zone"})
    actors = owned_workers(session.room)
    stop_supervised!(Sessions)
    eventually(fn -> not Process.alive?(session.room) end)
    assert Enum.all?(actors, &(not Process.alive?(&1)))
  end

  test "a failed Thing retires its loopback room without replaying or leaking a replacement", %{
    registry: registry
  } do
    {:ok, session} = Sessions.open(registry)
    {:ok, session} = Sessions.admit(registry, session.token, :start_room)
    children = owned_workers(session.room)
    thing = :sys.get_state(session.room).things["thermostat"].pid
    Process.exit(thing, :kill)
    eventually(fn -> not Process.alive?(session.room) end)
    assert Enum.all?(children, &(not Process.alive?(&1)))
    assert {:ok, %{room: nil}} = Sessions.verify(registry, session.token)
  end

  test "failed startup rolls back without retaining a lease", %{lab: lab} do
    {:things, things, _, _} = List.keyfind(Supervisor.which_children(lab), :things, 0)
    :ok = Supervisor.terminate_child(lab, :things)
    refute Process.alive?(things)
    {:ok, session} = Sessions.open(__MODULE__.Registry)

    assert {:error, %Error{code: :room_unavailable}} =
             Sessions.admit(__MODULE__.Registry, session.token, {:start_room, "zone"})

    assert {:ok, [_, %{available: true}]} =
             Sessions.room_profiles(__MODULE__.Registry, session.token)

    assert {:ok, %{room: nil}} = Sessions.verify(__MODULE__.Registry, session.token)
    assert {:ok, _} = Supervisor.restart_child(lab, :things)

    assert {:ok, %{room: room}} =
             Sessions.admit(__MODULE__.Registry, session.token, {:start_room, "zone"})

    assert Process.alive?(room)
  end

  test "partial startup reaps actors before refusing the room" do
    lab =
      start_supervised!(
        Supervisor.child_spec({Wotex.Lab, id: "small-modbus", max_children: 2}, id: :small_lab)
      )

    registry =
      start_supervised!(
        Supervisor.child_spec(
          {Sessions,
           lab: lab,
           ttl_ms: 5_000,
           sweep_ms: 50,
           max_sessions: 1,
           room_profiles: [@profile],
           name: __MODULE__.SmallRegistry},
          id: :small_registry
        )
      )

    {:ok, session} = Sessions.open(registry)

    assert {:error, %Error{code: :room_unavailable}} =
             Sessions.admit(registry, session.token, {:start_room, "zone"})

    {:things, things, _, _} = List.keyfind(Supervisor.which_children(lab), :things, 0)
    assert DynamicSupervisor.count_children(things).active == 0
    assert {:ok, [_, %{available: true}]} = Sessions.room_profiles(registry, session.token)
  end

  test "expiry discards ownership and permits a new session to select the endpoint", %{lab: lab} do
    registry =
      start_supervised!(
        Supervisor.child_spec(
          {Sessions,
           lab: lab,
           ttl_ms: 500,
           sweep_ms: 10,
           max_sessions: 2,
           room_profiles: [@profile],
           name: __MODULE__.ExpiringRegistry},
          id: :expiring_registry
        )
      )

    {:ok, session} = Sessions.open(registry)
    {:ok, session} = Sessions.admit(registry, session.token, {:start_room, "zone"})
    actors = owned_workers(session.room)
    eventually(fn -> not Process.alive?(session.room) end)
    assert Enum.all?(actors, &(not Process.alive?(&1)))
    {:ok, fresh} = Sessions.open(registry)
    assert {:ok, %{room: room}} = Sessions.admit(registry, fresh.token, {:start_room, "zone"})
    assert room != session.room
  end

  test "actors reject foreign callers, start without I/O and stop with their owner" do
    owner = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> Process.exit(owner, :kill) end)
    actor = start_supervised!({ModbusThing, owner: owner})
    assert %{handler_calls: 0, state: %{}} = ModbusThing.stats(actor)
    assert {:error, %{code: :invalid_transport_context}} = ModbusThing.request(nil, nil, actor)
    assert {:error, %{code: :invalid_transport_context}} = ModbusThing.bind_policy(actor, self())
    assert ModbusThing.stats(actor).handler_calls == 0
    assert {:error, %{code: :not_supported}} = ModbusThing.subscribe(nil, nil, nil, actor)
    assert {:error, %{code: :not_supported}} = ModbusThing.unsubscribe(nil, nil, nil, actor)
    assert {:error, %{code: :invalid_options}} = ModbusThing.start_link([])
    assert {:error, %{code: :invalid_options}} = ModbusThing.start_link(owner: self(), extra: true)
    send(owner, :stop)
    eventually(fn -> not Process.alive?(actor) end)
  end

  test "only the owner binds one policy and policy calls are limited to Actions" do
    actor = start_supervised!({ModbusThing, owner: self()})
    policy = spawn(fn -> policy_calls(actor) end)
    on_exit(fn -> Process.exit(policy, :kill) end)
    assert :ok = ModbusThing.bind_policy(actor, policy)
    assert {:error, %{code: :invalid_transport_context}} = ModbusThing.bind_policy(actor, self())

    send(policy, {:request, self(), request(:readproperty)})
    assert_receive {:reply, {:error, %{code: :invalid_transport_context}}}
    assert ModbusThing.stats(actor).handler_calls == 0

    send(policy, {:request, self(), request(:invokeaction)})
    assert_receive {:reply, {:error, %{code: :invalid_transport_context}}}
    assert ModbusThing.stats(actor).handler_calls == 1
    assert ModbusThing.stats(actor).rejected == 1
  end

  test "actor loss during a mutating RPC preserves unknown effect" do
    {dead, monitor} = spawn_monitor(fn -> :ok end)
    assert_receive {:DOWN, ^monitor, :process, ^dead, :normal}

    for operation <- [:writeproperty, :invokeaction] do
      assert {:error, %{code: :disconnected, effect: :unknown, retryable: false}} =
               ModbusThing.request(request(operation), nil, dead)
    end

    assert {:error, %{code: :disconnected, effect: :none}} =
             ModbusThing.request(request(:readproperty), nil, dead)
  end

  test "a lost write acknowledgement is terminal even when the peer changed its registers", %{
    lab: lab
  } do
    peer = ScriptedModbusPeer.start()
    profile = %{@profile | host: peer.host, port: peer.port}

    registry =
      start_supervised!(
        Supervisor.child_spec(
          {Sessions,
           lab: lab,
           ttl_ms: 60_000,
           sweep_ms: 50,
           max_sessions: 1,
           room_profiles: [profile],
           name: __MODULE__.WireRegistry},
          id: :wire_registry
        )
      )

    {:ok, session} = Sessions.open(registry)
    {:ok, session} = Sessions.admit(registry, session.token, {:start_room, "zone"})
    {:ok, experiment} = Experiments.fetch("smart_room")
    {:ok, params} = Experiments.admit(experiment, %{})
    assert {:ok, run} = Room.start_run(session.room, experiment.id, params)
    assert run.status == :awaiting_approval
    decision = run.decision

    approval = %{
      "decision_id" => decision["id"],
      "proposal_digest" => decision["proposal_digest"],
      "revision" => Integer.to_string(decision["state_revision"]),
      "expires_at" => Integer.to_string(decision["expires_at"])
    }

    assert {:ok, failed} = Room.approve(session.room, run.id, approval)
    assert failed.status == :failed and failed.effect == nil
    assert ["error", %{"code" => "transport_request_failed"}] = failed.dispatch
    assert_receive {:scripted_modbus, <<1, 16, _::binary>>}
    assert {:ok, %{value: 22.5}} = Room.read_property(session.room, "actuator", "target")
    assert {:error, %{code: :not_approvable}} = Room.approve(session.room, run.id, approval)
    assert {:error, %{code: :not_cancellable}} = Room.cancel_run(session.room, run.id)
    refute_received {:scripted_modbus, <<1, 16, _::binary>>}
    assert {:ok, %{effect: nil, status: :failed}} = Room.fetch_run(session.room, run.id)
  end

  defp owned_workers(room), do: Enum.map(Room.owned_children(room), &elem(&1, 1))

  defp request(operation), do: struct(Request, operation: operation)

  defp policy_calls(actor) do
    receive do
      {:request, caller, request} ->
        send(caller, {:reply, ModbusThing.request(request, nil, actor)})
        policy_calls(actor)
    end
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end
end
