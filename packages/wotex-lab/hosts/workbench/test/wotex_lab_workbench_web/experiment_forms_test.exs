defmodule WotexLabWorkbenchWeb.ExperimentFormsTest do
  @moduledoc false

  use WotexLabWorkbenchWeb.ConnCase, async: false

  alias WotexLabWorkbench.{Room, Sessions}
  alias WotexLabWorkbenchWeb.Plugs.SessionToken

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
    {:ok, conn: recycle(conn)}
  end

  test "numerical parameters use native number controls and their admitted bounds", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")

    for {id, min, max, step} <- [
          {"window_anomaly-seed", "1", "1000000", "1"},
          {"window_anomaly-count", "8", "512", "1"},
          {"window_anomaly-window_count", "2", "64", "1"},
          {"window_anomaly-threshold", "0.0", "100.0", "any"},
          {"window_anomaly-fill", "-50.0", "100.0", "any"},
          {"smart_room-power_budget", "100.0", "10000.0", "any"},
          {"smart_room-ttl_ms", "10", "600000", "1"}
        ] do
      assert has_element?(
               view,
               ~s(#parameter-#{id}[type="number"][step="#{step}"])
             )

      control =
        view
        |> element("#parameter-#{id}")
        |> render()
        |> LazyHTML.from_fragment()

      assert Float.parse(hd(LazyHTML.attribute(control, "min"))) == Float.parse(min)
      assert Float.parse(hd(LazyHTML.attribute(control, "max"))) == Float.parse(max)
    end
  end

  test "a refused submission retains every draft field and marks its error without a room", %{
    conn: conn
  } do
    conn = get(conn, "/")
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/")

    html = submit(view, @draft)
    assert html =~ "invalid_parameter"
    assert_draft(view, @draft)

    assert has_element?(
             view,
             ~s(#parameter-window_anomaly-count[aria-invalid="true"][aria-describedby*="-error"])
           )

    assert has_element?(view, "#parameter-window_anomaly-count-error[role='alert']")
    assert has_element?(view, "#parameter-window_anomaly-count-error", "8 to 512")
    refute has_element?(view, "#parameter-window_anomaly-seed[aria-invalid]")
    assert has_element?(view, "#run-window_anomaly button[disabled]")
    refute has_element?(view, "#run-thermal button[disabled]")

    render_change(element(view, "#theme-settings"), %{"theme" => "dark"})
    render_click(element(view, "button[phx-click='toggle_sidebar']"))
    assert_draft(view, @draft)
    assert {:ok, %{room: nil}} = Sessions.verify(token)
  end

  test "correcting a draft clears its error and only explicit submission runs the corrected inputs",
       %{
         conn: conn
       } do
    conn = get(conn, "/")
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/")
    markers = Map.new(Map.keys(@draft), &{"_unused_" <> &1, ""})
    submit(view, Map.merge(@draft, markers))
    corrected = Map.put(@draft, "count", "64")

    html = edit(view, Map.merge(corrected, markers))
    assert_draft(view, corrected)
    refute html =~ "invalid_parameter"
    refute has_element?(view, "#parameter-window_anomaly-count[aria-invalid]")
    refute has_element?(view, "#run-window_anomaly button[disabled]")
    assert {:ok, %{room: nil}} = Sessions.verify(token)

    redirect = submit(view, Map.merge(corrected, markers))
    {:ok, run_view, html} = follow_redirect(redirect, recycle(conn), "/runs/run-1")
    assert html =~ "Tensor summary"
    refute has_element?(run_view, "form[phx-submit='approve']")
    assert {:ok, %{room: room}} = Sessions.verify(token)
    assert [run] = Room.runs(room)
    assert run.status == :completed

    assert run.params == [
             seed: 42,
             count: 64,
             window_count: 12,
             threshold: 2.25,
             fill: -4.5,
             backend: Nx.BinaryBackend
           ]
  end

  test "draft change and recovery replay are local to the view and start no command", %{conn: conn} do
    conn = get(conn, "/")
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/")
    draft = Map.put(@draft, "count", "64")
    edit(view, draft)

    render_change(element(view, "#run-smart_room"), %{
      "experiment_id" => "smart_room",
      "params" => %{
        "power_budget" => "1500",
        "meter" => "off",
        "principal" => "guest",
        "ttl_ms" => "90000"
      }
    })

    assert_draft(view, draft)
    assert has_element?(view, "#parameter-smart_room-meter option[value='off'][selected]")
    assert has_element?(view, "#parameter-smart_room-principal option[value='guest'][selected]")

    {:ok, fresh_view, _} = live(recycle(conn), "/")
    assert has_element?(fresh_view, "#parameter-window_anomaly-seed[value='1']")
    edit(fresh_view, draft)
    edit(fresh_view, draft)
    assert_draft(fresh_view, draft)
    assert {:ok, %{room: nil}} = Sessions.verify(token)
    assert has_element?(fresh_view, "#run-smart_room select option[value='on'][selected]")

    other_conn = get(build_conn(), "/")
    other_token = get_session(other_conn, SessionToken.key())
    on_exit(fn -> Sessions.revoke(other_token) end)
    {:ok, other_session, _} = live(recycle(other_conn), "/")
    assert has_element?(other_session, "#parameter-window_anomaly-seed[value='1']")
  end

  test "malformed and oversized edits or submissions cannot replace a retained draft or allocate a room",
       %{
         conn: conn
       } do
    conn = get(conn, "/")
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/")
    draft = Map.put(@draft, "count", "64")
    edit(view, draft)

    for event <- ["edit_experiment", "run"],
        params <- [
          [],
          %{"seed" => ["12"]},
          %{"seed" => %{}},
          %{"seed" => String.duplicate("1", 33)},
          %{"unexpected" => "value"},
          %{"seed" => "1", "_unused_seed" => "not-empty"},
          %{"seed" => "1", "_unused_other" => ""},
          %{"_unused_seed" => ""}
        ] do
      html = render_hook(view, event, %{"experiment_id" => "window_anomaly", "params" => params})
      assert html =~ "invalid_parameters"
      assert_draft(view, draft)
      assert {:ok, %{room: nil}} = Sessions.verify(token)
    end

    assert render_hook(view, "edit_experiment", %{"experiment_id" => "other", "params" => %{}}) =~
             "unknown_experiment"

    assert_draft(view, draft)
    assert {:ok, %{room: nil}} = Sessions.verify(token)
  end

  test "an unsupported select stays visibly refused and never falls back to binary", %{conn: conn} do
    conn = get(conn, "/")
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/")
    unsupported = %{"backend" => "other-backend"}

    edit(view, unsupported)
    assert has_element?(view, "#parameter-window_anomaly-backend[aria-invalid='true']")

    assert has_element?(
             view,
             "#parameter-window_anomaly-backend option[value='other-backend'][selected]",
             "Unsupported selection"
           )

    assert has_element?(view, "#run-window_anomaly button[disabled]")
    assert submit(view, unsupported) =~ "invalid_parameter"
    assert {:ok, %{room: nil}} = Sessions.verify(token)

    edit(view, %{"backend" => "binary"})
    refute has_element?(view, "#parameter-window_anomaly-backend[aria-invalid]")
    refute has_element?(view, "#parameter-window_anomaly-backend option[value='other-backend']")
  end

  test "draft edits revalidate a revoked session before retaining input", %{conn: conn} do
    conn = get(conn, "/")
    token = get_session(conn, SessionToken.key())
    {:ok, view, _} = live(recycle(conn), "/")
    :ok = Sessions.revoke(token)

    assert edit(view, @draft) =~ "Session denied"
    refute has_element?(view, "#run-window_anomaly")
  end

  defp edit(view, params),
    do:
      render_change(element(view, "#run-window_anomaly"), %{
        "experiment_id" => "window_anomaly",
        "params" => params
      })

  defp submit(view, params),
    do:
      render_submit(element(view, "#run-window_anomaly"), %{
        "experiment_id" => "window_anomaly",
        "params" => params
      })

  defp assert_draft(view, draft) do
    for {name, value} <- draft do
      selector =
        if name == "backend",
          do: "select#parameter-window_anomaly-#{name} option[value='#{value}'][selected]",
          else: "#parameter-window_anomaly-#{name}[value='#{value}']"

      assert has_element?(view, selector), "lost draft field #{name}=#{value}"
    end
  end
end
