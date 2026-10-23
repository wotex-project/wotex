defmodule WotexLabWorkbenchWeb.ThingObservationsTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias Wotex.Lab.Reference.Thing
  alias WotexLabWorkbench.{Room, Sessions, ThingReadings}
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  setup %{conn: conn} do
    conn = get(conn, "/")
    token = get_session(conn, SessionToken.key())
    on_exit(fn -> Sessions.revoke(token) end)
    {:ok, conn: recycle(conn), token: token}
  end

  test "declared observation receives real frames, is duplicate-safe and pauses without losing values",
       %{conn: conn, token: token} do
    {:ok, view, _} = live(conn, "/")
    render_click(element(view, "button[phx-click='start_room']"))
    {:ok, %{room: room}} = Sessions.verify(token)
    host = host(room, "thermostat")
    assert canvas_node(view)["value"] == "—"
    assert canvas_node(view)["identity"] == "thermostat-01"
    assert canvas_node(view)["operations"] == ["read", "observe"]
    assert Thing.stats(host).subscriptions == 0

    canvas_event(view, "observe")
    eventually(fn -> Thing.stats(host).subscriptions == 1 end)
    assert canvas_node(view)["value"] == "21.5"
    assert canvas_node(view)["status"] == "Waiting"
    assert Room.runs(room) == []
    canvas_event(view, "observe")
    assert Thing.stats(host).handler_calls == 1
    assert Thing.stats(host).subscriptions == 1
    [stream] = streams(room)
    id = :sys.get_state(stream).id

    :ok = Thing.emit(host, "temperature", 22.4, %{observed_at: 17})
    eventually(fn -> canvas_node(view)["value"] == "22.4" end)
    assert canvas_node(view)["status"] == "Live"
    assert canvas_node(view)["operations"] == ["read", "pause"]
    assert canvas_node(view)["detail"] =~ ~r/\A\d\d:\d\d:\d\d\z/

    canvas_event(view, "statistics")
    assert_patch(view, "/things")
    assert has_element?(view, "details[open] summary", "Statistics")
    assert has_element?(view, "#read-thermostat-temperature")
    assert has_element?(view, "button[phx-click='pause_observation']", "Pause")

    canvas_event(view, "pause")
    eventually(fn -> Thing.stats(host).subscriptions == 0 end)
    assert canvas_node(view)["value"] == "22.4"
    assert canvas_node(view)["status"] == "Paused"
    send(view.pid, {:wotex_runtime, id, {:ok, 99.0, %{}}})
    assert canvas_node(view)["value"] == "22.4"
    refute Process.alive?(stream)
  end

  test "stream loss and invalid numeric samples retain the last receipt and require explicit restart",
       %{conn: conn, token: token} do
    {:ok, view, _} = live(conn, "/")
    render_click(element(view, "button[phx-click='start_room']"))
    {:ok, %{room: room}} = Sessions.verify(token)
    host = host(room, "thermostat")
    canvas_event(view, "observe")
    eventually(fn -> Thing.stats(host).subscriptions == 1 end)
    :ok = Thing.emit(host, "temperature", 22.0)
    eventually(fn -> canvas_node(view)["status"] == "Live" end)
    :ok = Thing.disconnect(host)
    eventually(fn -> canvas_node(view)["status"] == "Disconnected" end)
    assert canvas_node(view)["value"] == "22.0"
    assert Thing.stats(host).subscriptions == 0
    assert canvas_node(view)["operations"] == ["read", "observe"]

    canvas_event(view, "observe")
    eventually(fn -> Thing.stats(host).subscriptions == 1 end)
    :ok = Thing.emit(host, "temperature", String.duplicate("untrusted", 2_000))
    eventually(fn -> canvas_node(view)["status"] == "Error" end)
    assert canvas_node(view)["value"] == "22.0"
    eventually(fn -> Thing.stats(host).subscriptions == 0 end)
    assert Room.runs(room) == []
  end

  test "multiple Properties retain separate receipts and documentation closes streams before restoring paused values",
       %{conn: conn, token: token} do
    {:ok, view, _} = live(conn, "/")
    render_click(element(view, "button[phx-click='start_room']"))
    {:ok, %{room: room}} = Sessions.verify(token)
    host = host(room, "thermostat")
    render_hook(view, "read", %{"thing" => "actuator", "property" => "target"})
    render_hook(view, "read", %{"thing" => "actuator", "property" => "temperature"})
    assert canvas_node(view, "thing-actuator")["value"] == "21.0"
    canvas_event(view, "observe")
    eventually(fn -> Thing.stats(host).subscriptions == 1 end)
    :ok = Thing.emit(host, "temperature", 23.5)
    eventually(fn -> canvas_node(view)["status"] == "Live" end)
    before = Thing.stats(host).handler_calls
    render_hook(view, "open_documentation", %{})
    assert_redirect(view, "/docs/start/")
    eventually(fn -> Thing.stats(host).subscriptions == 0 end)
    assert {:ok, %{canvas_readings: readings}} = Sessions.presentation(token, :read)
    assert ThingReadings.get(readings, "thermostat", "temperature").state == :paused
    {:ok, returned, _} = live(recycle(conn), "/")
    assert canvas_node(returned)["value"] == "23.5"
    assert canvas_node(returned)["status"] == "Paused"
    assert Thing.stats(host).handler_calls == before
    assert Thing.stats(host).subscriptions == 0
  end

  test "unsupported and stale controls start no stream, and receiver death reaps the owned observer",
       %{conn: conn, token: token} do
    {:ok, view, _} = live(conn, "/")
    render_hook(view, "observe", %{"thing" => "thermostat", "property" => "temperature"})
    assert {:ok, %{room: nil}} = Sessions.verify(token)
    render_click(element(view, "button[phx-click='start_room']"))
    {:ok, %{room: room}} = Sessions.verify(token)
    host = host(room, "thermostat")
    render_hook(view, "observe", %{"thing" => "actuator", "property" => "target"})
    assert streams(room) == []
    stale = snapshot(view)
    render_patch(view, "/metrics")
    canvas_event(view, "observe", "thing-thermostat", stale)
    assert Thing.stats(host).subscriptions == 0
    canvas_event(view, "observe")
    eventually(fn -> Thing.stats(host).subscriptions == 1 end)
    [stream] = streams(room)
    GenServer.stop(view.pid)
    eventually(fn -> not Process.alive?(stream) end)
    eventually(fn -> Thing.stats(host).subscriptions == 0 end)
    assert Process.alive?(room)
  end

  test "room supervisor bounds concurrent observers, keeps rooms independent and reaps them on revoke",
       %{token: token} do
    {:ok, first} = Sessions.admit(token, :start_room)
    {:ok, other} = Sessions.open()
    on_exit(fn -> Sessions.revoke(other.token) end)
    {:ok, second} = Sessions.admit(other.token, :start_room)

    assert {:error, %{code: :not_observable}} =
             Room.observe_property(first.room, "actuator", "target", self())

    watches =
      for _ <- 1..8 do
        assert {:ok, watch} = Room.observe_property(first.room, "thermostat", "temperature", self())
        watch
      end

    assert {:error, %{code: :observation_unavailable}} =
             Room.observe_property(first.room, "thermostat", "temperature", self())

    assert streams(second.room) == []
    :ok = Sessions.revoke(token)
    Enum.each(watches, fn watch -> eventually(fn -> not Process.alive?(watch.pid) end) end)
    assert Process.alive?(second.room)
  end

  test "canvas failures open the affected Property; forged and revoked reads retain admission", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/")
    render_click(element(view, "button[phx-click='start_room']"))
    {:ok, %{room: room}} = Sessions.verify(token)
    host = host(room, "thermostat")
    :ok = Thing.emit(host, "temperature", "invalid")

    canvas_event(view, "read")
    assert_patch(view, "/things")
    assert has_element?(view, "#wl-thing-inspector-thing-thermostat")

    assert has_element?(
             view,
             "#wl-property-error-thermostat-temperature",
             "Invalid numeric reading"
           )

    refute has_element?(view, ".wl-flash-error")
    assert canvas_node(view)["value"] == "—"
    assert Thing.stats(host).handler_calls == 1

    for key <- ["unknown", %{"unexpected" => "value"}] do
      render_hook(view, "read", %{"thing" => key, "property" => "temperature"})
      assert has_element?(view, ".wl-flash-error", "unsupported_property_operation")
      assert has_element?(view, "#wl-property-error-thermostat-temperature")
      assert Thing.stats(host).handler_calls == 1
    end

    :ok = Thing.emit(host, "temperature", 22.7)
    canvas_event(view, "read")
    refute has_element?(view, "#wl-property-error-thermostat-temperature")
    assert canvas_node(view)["value"] == "22.7"
    assert Thing.stats(host).handler_calls == 2
    assert Thing.stats(host).subscriptions == 0
    assert Room.runs(room) == []

    :ok = Sessions.revoke(token)

    assert render_hook(view, "read", %{"thing" => "thermostat", "property" => "temperature"}) =~
             "unknown_session"

    refute has_element?(view, "[aria-label='Thing inspector']")
  end

  defp host(room, key), do: :sys.get_state(room).things[key].pid

  defp streams(room),
    do:
      :sys.get_state(room).observations
      |> DynamicSupervisor.which_children()
      |> Enum.map(&elem(&1, 1))

  defp snapshot(view) do
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

  defp canvas_node(view, id \\ "thing-thermostat"),
    do: Enum.find(snapshot(view)["payload"]["nodes"], &(&1["id"] == id))

  defp canvas_event(view, event, id \\ "thing-thermostat", state \\ nil) do
    state = state || snapshot(view)

    render_hook(view, "wotex:island:#{state["instance_id"]}:event", %{
      "schema" => "wotex-lab-island-event/v1",
      "component" => "canvas",
      "instance_id" => state["instance_id"],
      "client_revision" => state["revision"],
      "event" => event,
      "payload" => %{"id" => id}
    })
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, attempts) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(5)
          eventually(fun, attempts - 1)
        )
  end
end
