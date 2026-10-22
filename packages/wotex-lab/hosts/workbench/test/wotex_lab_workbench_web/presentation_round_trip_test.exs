defmodule WotexLabWorkbenchWeb.PresentationRoundTripTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias WotexLabWorkbench.{Room, Sessions}
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

  @path "/experiments?experiment=window_anomaly"
  @draft %{
    "seed" => "42",
    "count" => "513",
    "window_count" => "12",
    "threshold" => "2.25",
    "fill" => "-4.5",
    "backend" => "binary"
  }

  setup %{conn: conn} do
    conn = get(conn, "/")
    token = get_session(conn, SessionToken.key())
    on_exit(fn -> Sessions.revoke(token) end)
    {:ok, conn: recycle(conn), token: token}
  end

  test "documentation return retains an invalid experiment draft without starting a room", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, @path)

    render_change(element(view, "#run-window_anomaly"), %{
      "experiment_id" => "window_anomaly",
      "params" => @draft
    })

    render_hook(view, "open_documentation", %{})
    assert_redirect(view, "/docs/start/")
    assert {:ok, %{room: nil}} = Sessions.verify(token)

    docs = get(recycle(conn), "/docs/start/") |> html_response(200)
    assert docs =~ "href=\"/experiments?experiment=window_anomaly\""
    {:ok, returned, _} = live(recycle(conn), @path)

    assert has_element?(
             returned,
             "#parameter-window_anomaly-count[value='513'][aria-invalid='true']"
           )

    assert has_element?(returned, "#parameter-window_anomaly-fill[value='-4.5']")
    assert has_element?(returned, "#run-window_anomaly button[disabled]")
    assert {:ok, %{room: nil}} = Sessions.verify(token)
    assert {:ok, nil} = Sessions.presentation(token, :read)
  end

  test "unsaved geometry, selection and explicit readings return without replacing Save layout", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/things")
    render_click(element(view, "button[phx-click='start_room']"))
    render_hook(view, "read", %{"thing" => "thermostat", "property" => "temperature"})
    render_patch(view, @path)

    render_change(element(view, "#run-window_anomaly"), %{
      "experiment_id" => "window_anomaly",
      "params" => @draft
    })

    assert {:ok, %{room: room}} = Sessions.verify(token)
    saved = layout(10, 1)
    assert {:ok, _} = Sessions.change_board(token, room, {:layout, saved, ["thing-thermostat"]})
    render_patch(view, @path)
    current = layout(420, 0.8)
    open_docs(view, %{"layout" => current, "selection" => "thing-thermostat"})

    assert {:ok, %{layout: ^current, canvas_readings: readings}} =
             Sessions.presentation(token, :read)

    assert readings["thermostat/temperature"].value == 21.5
    assert {:ok, %{layout: ^saved}} = Sessions.board(token)
    assert Room.runs(room) == []
    GenServer.stop(view.pid)

    {:ok, returned, _} = live(recycle(conn), @path)
    snapshot = snapshot(returned)
    assert snapshot["payload"]["view"] == [current["viewport"]]
    assert snapshot["payload"]["selection"] == "thing-thermostat"
    thermostat = Enum.find(snapshot["payload"]["nodes"], &(&1["id"] == "thing-thermostat"))
    assert thermostat["x"] == 420 and thermostat["value"] == "21.5"

    assert has_element?(
             returned,
             "#parameter-window_anomaly-count[value='513'][aria-invalid='true']"
           )

    assert {:ok, %{layout: ^saved}} = Sessions.board(token)
    assert Room.runs(room) == []
  end

  test "malformed or foreign canvas state cannot replace a retained presentation", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/")

    for value <- [
          %{},
          %{"layout" => layout(1, 1), "selection" => "foreign"},
          %{"layout" => layout(1, 1), "selection" => "", "command" => "run"}
        ] do
      open_docs(view, value)
      assert {:ok, nil} = Sessions.presentation(token, :read)
    end

    assert {:ok, %{room: nil}} = Sessions.verify(token)
    render_hook(view, "open_documentation", %{})
    assert_redirect(view, "/docs/start/")
    assert {:ok, retained} = Sessions.presentation(token, :read)

    assert {:error, %{code: :invalid_presentation}} =
             Sessions.put_presentation(token, nil, %{
               retained
               | prompt: String.duplicate("x", 300_000)
             })

    assert {:ok, ^retained} = Sessions.presentation(token, :read)

    assert {:error, %{code: :invalid_presentation}} =
             Sessions.put_presentation(token, nil, %{retained | answer: %{worker: self()}})

    other = get(build_conn(), "/")
    other_token = get_session(other, SessionToken.key())
    on_exit(fn -> Sessions.revoke(other_token) end)
    assert {:ok, nil} = Sessions.presentation(other_token, :read)
    assert :ok = Sessions.revoke(token)
    assert {:error, _} = Sessions.presentation(token, :read)
    assert get(recycle(conn), "/docs/start/") |> html_response(200) =~ "href=\"/\""
  end

  test "room death drops retained readings and state without starting a replacement", %{
    conn: conn,
    token: token
  } do
    {:ok, view, _} = live(conn, "/")
    render_click(element(view, "button[phx-click='start_room']"))
    assert {:ok, %{room: room}} = Sessions.verify(token)
    open_docs(view, %{"layout" => layout(420, 0.8), "selection" => "thing-thermostat"})
    assert {:ok, %{layout: _}} = Sessions.presentation(token, :read)
    monitor = Process.monitor(room)
    Process.exit(room, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^room, _}
    assert eventually(fn -> match?({:ok, %{room: nil}}, Sessions.verify(token)) end)
    assert {:ok, nil} = Sessions.presentation(token, :read)
  end

  defp eventually(fun, attempts \\ 40)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.(),
      do: true,
      else:
        (
          Process.sleep(5)
          eventually(fun, attempts - 1)
        )
  end

  defp layout(x, zoom),
    do: %{
      "positions" => [%{"id" => "thing-thermostat", "x" => x, "y" => 235}],
      "viewport" => %{"x" => -20, "y" => 40, "zoom" => zoom}
    }

  defp open_docs(view, value) do
    current = snapshot(view)

    render_hook(view, "wotex:island:#{current["instance_id"]}:event", %{
      "schema" => "wotex-lab-island-event/v1",
      "component" => "canvas",
      "instance_id" => current["instance_id"],
      "client_revision" => current["revision"],
      "event" => "open_documentation",
      "payload" => %{"view" => value}
    })
  end

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
end
