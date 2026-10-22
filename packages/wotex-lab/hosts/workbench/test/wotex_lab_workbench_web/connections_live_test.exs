defmodule WotexLabWorkbenchWeb.ConnectionsLiveTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias WotexLabWorkbench.{Room, Sessions}
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  setup %{conn: conn} do
    conn = get(conn, "/")
    token = get_session(conn, SessionToken.key())
    on_exit(fn -> Sessions.revoke(token) end)
    %{conn: recycle(conn), token: token}
  end

  test "opening Connections and malformed authoring start no room or operation",
       %{conn: conn, token: token} do
    {:ok, view, _} = live(conn, "/")
    canvas_event(view, "open", %{"id" => "connections"})
    assert_patch(view, "/things?panel=connections")
    assert has_element?(view, "#wl-connections-panel", "Connections")
    assert has_element?(view, "#wl-connections-panel button[phx-click='start_room']")
    assert {:ok, %{room: nil}} = Sessions.verify(token)

    for event <- ~w(change_connection apply_connection remove_connection) do
      render_hook(view, event, %{"connection" => %{"port" => "temperature", "authority" => true}})
      assert {:ok, %{room: nil}} = Sessions.verify(token)
    end

    canvas_event(view, "propose_connection", %{
      "connection" => %{
        "source" => "thing-thermostat",
        "target" => "process-smart-room",
        "target_handle" => "temperature"
      }
    })

    assert {:ok, %{room: nil}} = Sessions.verify(token)
    refute has_element?(view, "#wl-connection-form")
  end

  test "browser unused markers admit only matching empty form metadata",
       %{conn: conn, token: token} do
    {:ok, view, _} = live(conn, "/")
    room = start_room(view, token)
    canvas_event(view, "inspect_connection", %{"id" => "temperature"})

    raw = %{
      "port" => "temperature",
      "thing" => "actuator",
      "affordance" => "temperature",
      "revision" => "0",
      "_unused_affordance" => ""
    }

    render_hook(view, "change_connection", %{
      "connection" => raw,
      "_target" => ["connection", "thing"]
    })

    assert has_element?(view, "#wl-connection-affordance option[value='target']")
    refute has_element?(view, ".wl-connection-error")
    assert Room.connections(room).revision == 0

    for invalid <- [
          Map.put(raw, "_unused_affordance", "unexpected"),
          Map.put(raw, "_unused_authority", ""),
          Map.delete(raw, "affordance"),
          Map.put(raw, "authority", "true")
        ] do
      render_hook(view, "apply_connection", %{"connection" => invalid})
      assert Room.connections(room).revision == 0
    end

    render_hook(view, "apply_connection", %{"connection" => raw})
    assert Room.connections(room).revision == 1
    assert edge(view)["source"] == "thing-actuator"
    assert Enum.all?(Room.things(room), &(&1.stats.handler_calls == 0))
  end

  test "a gesture edits a retained draft; only Apply changes the next Run's binding",
       %{conn: conn, token: token} do
    {:ok, view, _} = live(conn, "/")
    room = start_room(view, token)
    before = canvas(view)
    old_nodes = before["payload"]["nodes"]

    canvas_event(view, "propose_connection", %{
      "connection" => %{
        "source" => "thing-actuator",
        "target" => "process-smart-room",
        "target_handle" => "temperature"
      }
    })

    assert_patch(view, "/things?panel=connections")
    assert has_element?(view, "#wl-connection-thing option[value='actuator'][selected]")
    assert has_element?(view, "#wl-connection-affordance option[value='temperature'][selected]")
    assert edge(view)["source"] == "thing-thermostat"
    assert Room.connections(room).revision == 0
    assert Enum.all?(Room.things(room), &(&1.stats.handler_calls == 0))

    raw = %{
      "port" => "temperature",
      "thing" => "actuator",
      "affordance" => "target",
      "revision" => "0"
    }

    render_change(form(view, "#wl-connection-form", %{"connection" => raw}))
    render_click(element(view, "button[phx-click='connection_list']"))
    assert has_element?(view, "#wl-connections-list")
    render_click(element(view, "button[phx-click='edit_connection'][phx-value-port='temperature']"))
    assert has_element?(view, "#wl-connection-affordance option[value='target'][selected]")
    assert Room.connections(room).revision == 0

    render_submit(form(view, "#wl-connection-form", %{"connection" => raw}))
    assert Room.connections(room).revision == 1
    assert edge(view)["source"] == "thing-actuator"
    assert edge(view)["label"] == "target · °C"
    assert canvas(view)["payload"]["nodes"] == old_nodes
    assert Room.runs(room) == []
    assert Enum.all?(Room.things(room), &(&1.stats.handler_calls == 0))

    canvas_event(view, "inspect", %{"id" => "process-smart-room"})
    assert_patch(view, "/experiments?experiment=smart_room")
    render_submit(form(view, "#experiment-smart_room form"))
    assert_patch(view, "/runs/run-1")
    [run] = Room.runs(room)
    assert run.proposal["input"] == 20.0
    assert run.record.outcomes.connection_revision == 1
    assert run.status == :awaiting_approval
  end

  test "invalid or stale edits stay in their editor and cannot overwrite another view",
       %{conn: conn, token: token} do
    {:ok, first, _} = live(conn, "/")
    room = start_room(first, token)
    {:ok, second, _} = live(recycle(conn), "/")

    for view <- [first, second] do
      canvas_event(view, "inspect_connection", %{"id" => "temperature"})
      assert_patch(view, "/things?panel=connections")
    end

    raw = %{
      "port" => "temperature",
      "thing" => "actuator",
      "affordance" => "target",
      "revision" => "0"
    }

    render_change(form(first, "#wl-connection-form", %{"connection" => %{"thing" => "actuator"}}))
    render_submit(form(first, "#wl-connection-form", %{"connection" => raw}))
    render_submit(form(second, "#wl-connection-form"))
    assert has_element?(second, "#wl-connection-editor [role='alert']", "Connections changed")
    assert has_element?(second, "button[phx-click='reload_connection']")
    assert has_element?(second, "#wl-connection-thing option[value='thermostat'][selected]")
    assert Room.connections(room).revision == 1

    render_click(element(second, "button[phx-click='reload_connection']"))
    assert has_element?(second, "input[name='connection[revision]'][value='1']")
    assert has_element?(second, "#wl-connection-affordance option[value='target'][selected]")

    invalid = %{
      "port" => "temperature",
      "thing" => "meter",
      "affordance" => "power",
      "revision" => "1"
    }

    render_hook(second, "apply_connection", %{"connection" => invalid})
    assert has_element?(second, "#wl-connection-editor [role='alert']", "compatible")
    assert Room.connections(room).revision == 1

    valid = %{
      "port" => "temperature",
      "thing" => "thermostat",
      "affordance" => "temperature",
      "revision" => "1"
    }

    render_hook(second, "change_connection", %{
      "connection" => valid,
      "_target" => ["connection", "thing"]
    })

    render_submit(form(second, "#wl-connection-form"))
    assert Room.connections(room).revision == 2
    send(first.pid, :refresh_pins)
    assert edge(first)["source"] == "thing-thermostat"
    assert Enum.all?(Room.things(room), &(&1.stats.handler_calls == 0))
  end

  test "a documentation round trip retains an inert draft and applied wiring remains room owned",
       %{conn: conn, token: token} do
    {:ok, view, _} = live(conn, "/")
    room = start_room(view, token)
    canvas_event(view, "inspect_connection", %{"id" => "temperature"})
    assert_patch(view, "/things?panel=connections")

    raw = %{
      "port" => "temperature",
      "thing" => "actuator",
      "affordance" => "target",
      "revision" => "0"
    }

    render_change(form(view, "#wl-connection-form", %{"connection" => %{"thing" => "actuator"}}))
    render_change(form(view, "#wl-connection-form", %{"connection" => raw}))

    render_hook(view, "open_documentation", %{})
    assert_redirect(view, "/docs/start/")

    assert {:ok, %{connection_draft: ^raw, connection_editing: true}} =
             Sessions.presentation(token, :read)

    assert Room.connections(room).revision == 0

    {:ok, returned, _} = live(recycle(conn), "/things?panel=connections")
    assert has_element?(returned, "#wl-connection-affordance option[value='target'][selected]")
    render_submit(form(returned, "#wl-connection-form"))
    assert Room.connections(room).revision == 1

    {:ok, reloaded, _} = live(recycle(conn), "/")
    assert edge(reloaded)["source"] == "thing-actuator"
    assert Room.runs(room) == []
    assert Enum.all?(Room.things(room), &(&1.stats.handler_calls == 0))
  end

  test "Remove needs the editor revision and rejected old island snapshots cannot open a draft",
       %{conn: conn, token: token} do
    {:ok, view, _} = live(conn, "/")
    room = start_room(view, token)
    old = canvas(view)
    canvas_event(view, "inspect_connection", %{"id" => "power"})
    assert_patch(view, "/things?panel=connections")
    render_click(element(view, "button[phx-click='remove_connection']"))
    assert Room.connections(room).bindings["power"] == nil
    refute Enum.any?(canvas(view)["payload"]["edges"], &(&1["id"] == "power"))
    refute has_element?(view, "#wl-connection-form")

    canvas_event(view, "inspect_connection", %{"id" => "temperature"}, old)
    refute has_element?(view, "#wl-connection-form")
    assert Room.connections(room).revision == 1

    render_click(element(view, "button[phx-click='edit_connection'][phx-value-port='power']"))
    assert has_element?(view, "#wl-connection-form")
    render_click(element(view, "button[phx-click='cancel_connection']"))
    assert Room.connections(room).bindings["power"] == nil
    assert Room.runs(room) == []
  end

  defp start_room(view, token) do
    render_click(element(view, "button[phx-click='start_room']"))
    {:ok, %{room: room}} = Sessions.verify(token)
    room
  end

  defp canvas(view) do
    [encoded] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-wotex-island-component='canvas']")
      |> LazyHTML.attribute("data-wotex-island-snapshot")

    encoded
    |> Base.url_decode64!(padding: false)
    |> Jason.decode!()
  end

  defp edge(view), do: Enum.find(canvas(view)["payload"]["edges"], &(&1["id"] == "temperature"))

  defp canvas_event(view, event, payload, state \\ nil) do
    state = state || canvas(view)

    render_hook(view, "wotex:island:#{state["instance_id"]}:event", %{
      "schema" => "wotex-lab-island-event/v1",
      "component" => "canvas",
      "instance_id" => state["instance_id"],
      "client_revision" => state["revision"],
      "event" => event,
      "payload" => payload
    })
  end
end
