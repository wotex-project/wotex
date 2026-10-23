defmodule WotexLabWorkbenchWeb.E2E.ModbusRoomsTest do
  @moduledoc false

  use PhoenixTest.Playwright.Case, async: false

  alias Wotex.Lab.Test.ModbusSimulator
  alias Wotex.Runtime.{ConsumedThing, Context}
  alias WotexLabWorkbench.{Room, Sessions}
  alias WotexLabWorkbench.Test.ModbusRoom
  alias WotexLabWorkbenchWeb.{Endpoint, Plugs.SessionToken}

  @moduletag e2e: true, simulator: true
  @moduletag timeout: 180_000
  @target "[aria-label='Thing inspector'] section[aria-label='target']"
  @temperature "[aria-label='Thing inspector'] section[aria-label='temperature']"

  setup_all do
    %{image: ModbusSimulator.prepare()}
  end

  setup %{conn: conn, image: image} do
    peer = ModbusSimulator.start(image)
    :ok = ModbusRoom.configure([ModbusRoom.profile(peer)])
    {:ok, session} = Sessions.open()

    conn =
      add_session_cookie(
        conn,
        [value: %{SessionToken.key() => session.token}],
        Endpoint.session_options()
      )

    %{conn: conn, token: session.token, peer: peer, image: image}
  end

  test "a selected simulator drives canvas readings, explicit approval and real register readback",
       %{conn: conn, token: token, peer: peer} do
    consumed = ModbusSimulator.consumed(peer)

    conn =
      conn
      |> visit("/")
      |> click_button("Board menu")
      |> click_button("Start Zone controller")
      |> assert_has(".svelte-flow__node[data-id='thing-actuator']")

    {:ok, %{room: room, room_profile: "zone"}} = Sessions.verify(token)
    assert Enum.all?(Room.things(room), &(&1.stats.state == %{} and &1.stats.handler_calls == 0))

    assert {:ok, %{payload: 21.0}} =
             ConsumedThing.read_property(
               consumed,
               "target",
               Context.new!(request_id: "simulator-readback")
             )

    conn =
      conn
      |> click_button("Actions for Thermostat")
      |> click("[role='menuitem']", "Inspect")
      |> click_button("Read temperature")
      |> assert_has(@temperature <> " .wl-inspector-reading", text: "21.5°C")
      |> refute_has("button", text: "Observe", exact: true)
      |> visit("/experiments?experiment=smart_room")
      |> click_button("#run-smart_room", "Run")
      |> assert_path("/runs/run-1")
      |> click_link("Review Action")
      |> assert_has("#approve-run-1")

    assert [%{status: :awaiting_approval, dispatch: nil}] = Room.runs(room)

    assert {:ok, %{payload: 21.0}} =
             ConsumedThing.read_property(
               consumed,
               "target",
               Context.new!(request_id: "simulator-readback")
             )

    conn =
      conn
      |> click_button("Approve Action")
      |> refute_has("#approve-run-1")

    assert [
             %{
               status: :dispatched,
               effect: 22.5,
               dispatch: ["ok", %{"payload" => "written", "operation" => "invokeaction"}]
             }
           ] = Room.runs(room)

    conn =
      conn
      |> visit("/")
      |> click_button("Actions for Actuator")
      |> click("[role='menuitem']", "Inspect")
      |> click_button("Read target")
      |> assert_has(@target <> " .wl-inspector-reading", text: "22.5°C")

    assert {:ok, %{payload: 22.5}} =
             ConsumedThing.read_property(
               consumed,
               "target",
               Context.new!(request_id: "simulator-readback")
             )

    assert [%{status: :dispatched}] = Room.runs(room)
    before = Enum.map(Room.things(room), & &1.stats.handler_calls)

    conn =
      conn
      |> visit("/runs/run-1?view=review")
      |> refute_has("#approve-run-1")

    assert Enum.map(Room.things(room), & &1.stats.handler_calls) == before

    conn
    |> click_button("Board menu")
    |> click_button("End room")
    |> refute_has(".svelte-flow__node")
    |> click_button("Board menu")
    |> click_button("Start Zone controller")
    |> assert_has(".svelte-flow__node[data-id='thing-actuator']")

    {:ok, %{room: replacement}} = Sessions.verify(token)
    assert replacement != room
    refute Process.alive?(room)
    assert Room.runs(replacement) == []
    assert Enum.all?(Room.things(replacement), &(&1.stats.state == %{}))

    assert {:ok, %{payload: 22.5}} =
             ConsumedThing.read_property(
               consumed,
               "target",
               Context.new!(request_id: "simulator-readback")
             )
  end

  test "peer loss retains the last real reading, exposes failure and never invents a replacement",
       %{conn: conn, token: token, peer: peer} do
    conn =
      conn
      |> visit("/")
      |> click_button("Board menu")
      |> click_button("Start Zone controller")
      |> click_button("Actions for Thermostat")
      |> click("[role='menuitem']", "Inspect")
      |> click_button("Read temperature")
      |> assert_has(@temperature <> " .wl-inspector-reading", text: "21.5°C")

    {:ok, %{room: room}} = Sessions.verify(token)
    :ok = ModbusSimulator.stop(peer)

    conn
    |> click_button("Read temperature")
    |> assert_has(@temperature <> " [role='alert']")
    |> assert_has(@temperature <> " .wl-inspector-reading", text: "21.5°C")
    |> refute_has(".wl-flash-error")

    thermostat = Enum.find(Room.things(room), &(&1.key == "thermostat"))
    assert thermostat.stats.handler_calls == 2
    assert thermostat.stats.rejected == 1
    assert thermostat.stats.state == %{"temperature" => 21.5}
    assert Room.runs(room) == []
  end

  test "separate simulator endpoints isolate writes and a leased endpoint refuses another session",
       %{peer: peer, image: image} do
    other_peer = ModbusSimulator.start(image)
    lab = start_supervised!({Wotex.Lab, id: "modbus-isolation", max_children: 128})

    registry =
      start_supervised!(
        {Sessions,
         lab: lab,
         ttl_ms: 60_000,
         sweep_ms: 50,
         max_sessions: 8,
         room_profiles: [ModbusRoom.profile(peer), ModbusRoom.profile(other_peer, "other")],
         name: __MODULE__.Registry}
      )

    {:ok, first} = Sessions.open(registry)
    {:ok, second} = Sessions.open(registry)
    {:ok, first} = Sessions.admit(registry, first.token, {:start_room, "zone"})

    assert {:error, %{code: :room_profile_busy}} =
             Sessions.admit(registry, second.token, {:start_room, "zone"})

    {:ok, second} = Sessions.admit(registry, second.token, {:start_room, "other"})
    assert {:ok, %{value: 21.0}} = Room.read_property(first.room, "actuator", "target")
    assert {:ok, %{value: 21.0}} = Room.read_property(second.room, "actuator", "target")
    consumed = ModbusSimulator.consumed(peer)

    assert {:ok, _} =
             ConsumedThing.write_property(
               consumed,
               "target",
               24.0,
               Context.new!(request_id: "isolation-write")
             )

    assert {:ok, %{value: 24.0}} = Room.read_property(first.room, "actuator", "target")
    assert {:ok, %{value: 21.0}} = Room.read_property(second.room, "actuator", "target")
    assert Room.runs(first.room) == []
    assert Room.runs(second.room) == []
    assert :ok = Sessions.revoke(registry, first.token)
    assert Process.alive?(second.room)
  end

  test "a failed approved attempt is terminal and cannot become another approval", %{
    conn: conn,
    token: token,
    peer: peer
  } do
    conn =
      conn
      |> visit("/")
      |> click_button("Board menu")
      |> click_button("Start Zone controller")
      |> visit("/experiments?experiment=smart_room")
      |> click_button("#run-smart_room", "Run")
      |> click_link("Review Action")
      |> assert_has("#approve-run-1")

    {:ok, %{room: room}} = Sessions.verify(token)
    :ok = ModbusSimulator.stop(peer)

    conn
    |> click_button("Approve Action")
    |> refute_has("#approve-run-1")
    |> visit("/runs/run-1?view=review")
    |> refute_has("#approve-run-1")

    assert [%{status: :failed, effect: nil, error: %{code: "dispatch_failed"}} = run] =
             Room.runs(room)

    assert ["error", %{"code" => "transport_request_failed", "phase" => "transport"}] =
             run.dispatch

    assert Enum.any?(run.assertions, &(&1.id == "room:dispatch-once" and &1.status == :fail))
    assert {:error, %{code: :not_approvable}} = Room.approve(room, run.id, %{})
    assert {:error, %{code: :not_cancellable}} = Room.cancel_run(room, run.id)
  end
end
