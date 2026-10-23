defmodule WotexLabWorkbenchWeb.WorkbenchLive do
  @moduledoc """
  The single scoped LiveView for experiments, runs, Things, metrics and evidence.

  Mounting and reconnecting only read existing state. Every event revalidates
  the signed session, and commands that need a room use the session registry's
  closed admission list. Running an experiment, approving an Action, exporting
  a dataset and asking for formal evidence are separate server commands.

  Experiment drafts are bounded and retained across patches, validation errors
  and an admitted documentation round trip. Change and form-recovery events validate
  without allocating a room or running an experiment.
  """

  use WotexLabWorkbenchWeb, :live_view

  import WotexLabWorkbenchWeb.Components.{
    BoardSearch,
    Connections,
    HistoryPanels,
    Insights,
    MetricCatalogue,
    MetricComposer,
    RunPin,
    RunResult
  }

  alias Phoenix.LiveView.JS
  alias Plug.Conn.Query
  alias Wotex.Lab.{Error, Telemetry}

  alias WotexLabWorkbench.{
    Board,
    BoardHistory,
    Canvas,
    Connections,
    Experiments,
    Formal,
    HistoryPanels,
    Insights,
    Metrics,
    Observability.Panels,
    Provenance,
    Room,
    Run,
    RunPin,
    RunPresentation,
    Sessions,
    ThingProperties,
    ThingReadings
  }

  alias WotexLabWorkbench.Investigation.{Answer, Broker, Disclosure, Provider, RunContext}

  alias WotexLabWorkbenchWeb.Components.StatusBadge
  alias WotexLabWorkbenchWeb.{Islands, Scope}

  @parameter_bytes 32

  @impl Phoenix.LiveView
  def mount(_, _, socket) do
    socket =
      socket
      |> assign_new(:denied, fn -> nil end)
      |> assign(:sidebar_open, false)
      |> assign(:experiments, Experiments.all())
      |> assign(:experiment_forms, experiment_forms())
      |> assign(:runs, [])
      |> assign(:things, [])
      |> assign(:connection_state, Connections.new([]))
      |> assign(:connection_draft, nil)
      |> assign(:connection_room, nil)
      |> assign(:connection_editing, false)
      |> assign(:connection_error, nil)
      |> assign(:connection_focus, nil)
      |> assign(:connections_open, false)
      |> assign(:board_search_open, false)
      |> assign(:board_search_query, "")
      |> assign(:board_search_error, nil)
      |> assign(:board_search_focus, nil)
      |> assign(:board_search_result, nil)
      |> assign(:snapshot, nil)
      |> assign(:metrics, nil)
      |> assign(:history, nil)
      |> assign(:history_range, HistoryPanels.default_range())
      |> assign(:dashboard_panels, socket.assigns.scope && socket.assigns.scope.dashboard_panels)
      |> assign(:run, nil)
      |> assign(:run_view, :result)
      |> assign(:run_clock, System.monotonic_time(:millisecond))
      |> assign(:charts, [])
      |> assign(:insights, nil)
      |> assign(:canvas_readings, %{})
      |> assign(:property_errors, %{})
      |> assign(:observations, %{})
      |> assign(:thing_panel, :properties)
      |> assign(:canvas_selection, nil)
      |> assign(:board, Board.empty())
      |> assign(:board_room, nil)
      |> assign(:presentation_layout, nil)
      |> assign(:presentation_revision, nil)
      |> assign(:presentation_path, "/")
      |> assign(:active_pins, MapSet.new())
      |> assign(:pin_refresh_running, false)
      |> assign(:pin_refresh_room, nil)
      |> assign(:pin_refresh_rotation, 0)
      |> assign(:metric_draft, %{metric: "nx_duration_seconds", range: "5m"})
      |> assign(:metric_result, nil)
      |> assign(:metric_room, nil)
      |> assign(:selected_pin, nil)
      |> assign(:selected_experiment, "thermal")
      |> assign(:evidence_selected, false)
      |> assign(:answer, nil)
      |> assign(:island_revision, 0)
      |> assign(:island_commands, [])
      |> assign(:investigation, investigation_state())
      |> assign(:investigation_room, nil)
      |> assign(:investigation_results, [])
      |> assign(:disclosure, Disclosure.current())
      |> refresh()
      |> restore_presentation()

    if connected?(socket), do: Process.send_after(self(), :refresh_pins, 5_000)
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(_, _, %{assigns: %{scope: nil}} = socket), do: {:noreply, socket}

  def handle_params(params, url, socket) do
    case Scope.verify(socket) do
      {:ok, scope} ->
        socket =
          socket
          |> assign(
            scope: scope,
            sidebar_open: false,
            connections_open: false,
            board_search_open: false,
            presentation_path: workbench_path(url)
          )
          |> cancel_investigation_on_navigation()
          |> load_action(socket.assigns.live_action, params)
          |> revise_islands()

        {:noreply, socket}

      {:error, error} ->
        {:noreply, deny(socket, error)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_sidebar", _, socket) do
    case Scope.verify(socket) do
      {:ok, scope} ->
        {:noreply,
         socket
         |> assign(:scope, scope)
         |> update(:sidebar_open, &(!&1))}

      {:error, error} ->
        {:noreply, deny(socket, error)}
    end
  end

  def handle_event("open_documentation", _, socket) do
    case retain_presentation(socket, socket.assigns.board.layout, socket.assigns.canvas_selection) do
      {:ok, socket} -> {:noreply, push_navigate(socket, to: "/docs/start/")}
      {:error, error} -> reject_event(socket, error)
    end
  end

  def handle_event(event, _, socket) when event in ~w(open_board_search back_to_board_search) do
    case Scope.verify(socket) do
      {:ok, scope} ->
        {:noreply,
         socket
         |> assign(
           scope: scope,
           board_search_focus:
             if(event == "back_to_board_search", do: socket.assigns.board_search_result),
           board_search_error: nil
         )
         |> push_patch(to: "/things?panel=search")}

      {:error, error} ->
        {:noreply, deny(socket, error)}
    end
  end

  def handle_event(event, params, socket) when event in ~w(search_board clear_board_search) do
    case Scope.verify(socket) do
      {:ok, scope} ->
        query = if event == "clear_board_search", do: "", else: params["query"]

        if is_binary(query) and byte_size(query) <= 128 and String.valid?(query) do
          {:noreply,
           assign(socket, scope: scope, board_search_query: query, board_search_error: nil)}
        else
          {:noreply,
           assign(socket, scope: scope, board_search_error: "Search is too long or invalid")}
        end

      {:error, error} ->
        {:noreply, deny(socket, error)}
    end
  end

  def handle_event("inspect_board_result", %{"id" => id}, socket) do
    with {:ok, _} <- Scope.verify(socket),
         {:ok, socket} <- select_canvas_node(socket, id) do
      panel =
        case Enum.find(socket.assigns.things, &(Canvas.id(&1) == id)) do
          %{consumable: false} -> :sources
          _ -> :properties
        end

      {:noreply,
       assign(socket,
         canvas_selection: id,
         board_search_result: id,
         thing_panel: panel
       )}
    else
      {:error, error} ->
        reject_event(socket, error)

      :error ->
        {:noreply, assign(socket, :board_search_error, "This result is no longer on your board")}
    end
  end

  def handle_event("inspect_board_result", _, socket),
    do: handle_event("inspect_board_result", %{"id" => nil}, socket)

  def handle_event("close_board_menu", _, socket) do
    case Scope.verify(socket) do
      {:ok, scope} -> {:noreply, assign(socket, scope: scope, sidebar_open: false)}
      {:error, error} -> {:noreply, deny(socket, error)}
    end
  end

  def handle_event("open_connections", _, socket) do
    case open_canvas_tool(socket, "connections") do
      {:ok, socket} -> {:noreply, socket}
      {:error, error} -> reject_event(socket, error)
      _ -> {:noreply, socket}
    end
  end

  def handle_event("edit_connection", %{"port" => port}, socket) do
    case edit_connection(socket, port, :retain) do
      {:ok, socket} -> {:noreply, socket}
      {:error, error} -> connection_failure(socket, error)
    end
  end

  def handle_event("reload_connection", %{"port" => port}, socket) do
    case edit_connection(socket, port, :reload) do
      {:ok, socket} -> {:noreply, socket}
      {:error, error} -> connection_failure(socket, error)
    end
  end

  def handle_event("connection_list", _, socket),
    do:
      {:noreply,
       assign(socket,
         connection_editing: false,
         connection_error: nil,
         connection_focus: connection_focus(socket)
       )}

  def handle_event("cancel_connection", _, socket),
    do:
      {:noreply,
       assign(socket,
         connection_editing: false,
         connection_draft: nil,
         connection_error: nil,
         connection_focus: connection_focus(socket)
       )}

  def handle_event("change_connection", %{"connection" => raw} = params, socket) do
    raw = connection_form(raw)

    with {:ok, scope} <- Scope.verify(socket),
         true <- Connections.draft?(raw) do
      socket =
        socket
        |> assign(:scope, scope)
        |> load_connections()

      raw = connection_choice(raw, params["_target"], socket.assigns.things)

      error =
        case Connections.change(socket.assigns.connection_state, socket.assigns.things, raw) do
          {:ok, _} -> nil
          {:error, error} -> error
        end

      {:noreply, assign(socket, connection_draft: raw, connection_error: error)}
    else
      {:error, error} -> connection_failure(socket, error)
      _ -> connection_failure(socket, connection_error())
    end
  end

  def handle_event("apply_connection", %{"connection" => raw}, socket),
    do: configure_connection(socket, :apply, connection_form(raw))

  def handle_event("remove_connection", %{"value" => ""} = raw, socket)
      when map_size(raw) == 3,
      do: handle_event("remove_connection", Map.delete(raw, "value"), socket)

  def handle_event("remove_connection", %{"port" => port, "revision" => revision} = raw, socket)
      when map_size(raw) == 2,
      do: configure_connection(socket, :remove, %{"port" => port, "revision" => revision})

  def handle_event(event, _, socket)
      when event in ~w(edit_connection reload_connection change_connection apply_connection remove_connection),
      do: connection_failure(socket, connection_error())

  def handle_event("import_thing", _, socket) do
    case open_canvas_tool(socket, "add") do
      {:ok, socket} -> {:noreply, socket}
      {:error, error} -> reject_event(socket, error)
      :error -> {:noreply, socket}
    end
  end

  def handle_event("select_experiment", %{"id" => id}, socket) do
    with {:ok, scope} <- Scope.verify(socket),
         {:ok, _} <- Experiments.fetch(id) do
      {:noreply,
       socket
       |> assign(:scope, scope)
       |> push_patch(to: "/experiments?" <> Query.encode(%{"experiment" => id}))}
    else
      {:error, error} -> reject_event(socket, error)
    end
  end

  def handle_event("set_theme", %{"theme" => theme}, socket) do
    with %{token: token} <- socket.assigns.scope,
         {:ok, session} <- Sessions.put_theme(token, theme) do
      scope = %{socket.assigns.scope | theme: session.theme, room: session.room}
      {:noreply, assign(socket, :scope, scope)}
    else
      nil -> {:noreply, deny(socket, Error.new(:denied, :session, "no session scope"))}
      {:error, error} -> reject_event(socket, error)
    end
  end

  def handle_event("start_room", _, socket) do
    command(socket, :start_room, fn scope -> {:ok, scope, nil} end)
  end

  def handle_event(event, %{"experiment_id" => id, "params" => raw}, socket)
      when event in ["edit_experiment", "run"] do
    with {:ok, scope} <- Scope.verify(socket),
         {:ok, experiment} <- Experiments.fetch(id),
         {:ok, draft} <- experiment_draft(experiment, raw) do
      admission = Experiments.admit(experiment, draft)

      error =
        case admission do
          {:ok, _} -> nil
          {:error, error} -> error
        end

      socket =
        socket
        |> assign(:scope, scope)
        |> update(:experiment_forms, &Map.put(&1, id, %{values: draft, error: error}))
        |> clear_flash(:error)

      case {event, admission} do
        {"edit_experiment", _} ->
          {:noreply, socket}

        {"run", {:error, error}} ->
          {:noreply, error_flash(socket, error)}

        {"run", {:ok, params}} ->
          command(socket, :run, &start_experiment(&1, id, params))
      end
    else
      {:error, error} -> reject_event(socket, error)
    end
  end

  def handle_event(event, _, socket) when event in ["edit_experiment", "run"] do
    reject_event(socket, Error.new(:invalid_parameters, :admission, "run form is malformed"))
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    command(socket, :cancel, fn scope ->
      with {:ok, _} <- Room.cancel_run(scope.room, id), do: {:ok, scope, nil}
    end)
  end

  def handle_event("approve", %{"run_id" => id} = approval, socket) do
    command(socket, :approve, fn scope ->
      with {:ok, _} <- Room.approve(scope.room, id, approval), do: {:ok, scope, nil}
    end)
  end

  def handle_event("read", %{"thing" => thing, "property" => property}, socket) do
    handle_thing_operation(socket, "read", thing, property)
  end

  def handle_event("observe", %{"thing" => thing, "property" => property}, socket) do
    handle_thing_operation(socket, "observe", thing, property)
  end

  def handle_event("pause_observation", %{"thing" => thing, "property" => property}, socket) do
    handle_thing_operation(socket, "pause", thing, property)
  end

  def handle_event(event, _, socket) when event in ~w(read observe pause_observation) do
    reject_event(
      socket,
      Error.new(:invalid_property_operation, :things, "Property controls changed; reopen the Thing")
    )
  end

  def handle_event("inspect_thing", %{"id" => id}, socket) do
    case select_canvas_node(assign(socket, :board_search_result, nil), id) do
      {:ok, socket} -> {:noreply, assign(socket, :thing_panel, :properties)}
      {:error, error} -> reject_event(socket, error)
      :error -> {:noreply, socket}
    end
  end

  def handle_event("close_thing", _, socket) do
    case Scope.verify(socket) do
      {:ok, scope} ->
        {:noreply,
         socket
         |> assign(scope: scope, canvas_selection: nil, board_search_result: nil)
         |> push_patch(to: "/")}

      {:error, error} ->
        {:noreply, deny(socket, error)}
    end
  end

  def handle_event("register_td", %{"thing_description" => source}, socket) do
    command(socket, :register, fn scope ->
      with {:ok, _} <- Room.register_td(scope.room, source), do: {:ok, scope, nil}
    end)
  end

  def handle_event("query_metrics", params, socket) do
    command(socket, :query, fn scope ->
      with {:ok, filters} <- metric_filters(params, scope.session_id),
           {:ok, metrics} <- Metrics.query(filters) do
        {:ok, scope, {:assign, :metrics, metrics}}
      else
        {:error, :unavailable} ->
          {:error, Error.new(:unavailable, :metrics, "no measurements exist for this session")}

        {:error, error} ->
          {:error, error}
      end
    end)
  end

  def handle_event("edit_metric_query", params, socket) do
    with {:ok, scope} <- Scope.verify(socket),
         {:ok, draft} <- metric_draft(params) do
      {:noreply, assign(socket, scope: scope, metric_draft: draft, metric_result: nil)}
    else
      {:error, error} -> reject_event(socket, error)
    end
  end

  def handle_event("compose_metric", params, socket) do
    command(socket, :query, fn scope ->
      with {:ok, draft} <- metric_draft(params),
           {:ok, binding} <- room_history(scope.room),
           {:ok, result} <- HistoryPanels.load(binding, [draft.metric], draft.range) do
        result = Map.put(result, :queried_at, System.system_time(:millisecond))
        {:ok, scope, {:metric_result, result, draft, scope.room}}
      end
    end)
  end

  def handle_event("pin_metric", _, socket) do
    with {:ok, scope} <- Scope.verify(socket),
         true <- is_pid(scope.room) and scope.room == socket.assigns.metric_room,
         {:ok, board} <-
           Sessions.change_board(scope.token, scope.room, {:pin, socket.assigns.metric_result}) do
      [result] = socket.assigns.metric_result.panels
      id = "pin-#{result.id}-#{socket.assigns.metric_result.range}"

      {:noreply,
       socket
       |> assign(scope: scope, board: board)
       |> update(:active_pins, &MapSet.put(&1, id))
       |> revise_islands()
       |> push_patch(to: "/")}
    else
      false ->
        reject_event(socket, Error.new(:room_changed, :session, "Query this room before pinning"))

      {:error, error} ->
        reject_event(socket, error)
    end
  end

  def handle_event("pin_run_chart", %{"value" => ""} = params, socket) when map_size(params) == 5,
    do: handle_event("pin_run_chart", Map.delete(params, "value"), socket)

  def handle_event(
        "pin_run_chart",
        %{"run_id" => id, "index" => index, "record_digest" => digest, "query" => encoded} = params,
        socket
      )
      when map_size(params) == 4 and is_binary(index) and is_binary(encoded) and
             byte_size(encoded) <= 1024 do
    with true <- socket.assigns.run_id == id and Regex.match?(~r/\A[0-7]\z/, index),
         {:ok, query} <- Jason.decode(encoded),
         {:ok, socket} <-
           change_board(socket, {:pin_run, id, digest, String.to_integer(index), query}) do
      socket =
        socket
        |> clear_flash(:error)
        |> assign(:canvas_selection, nil)
        |> push_patch(to: "/")

      {:noreply, socket}
    else
      {:error, %Error{} = error} ->
        reject_event(socket, error)

      _ ->
        reject_event(
          socket,
          Error.new(:unavailable_run_pin, :workbench, "Reopen the Run chart before pinning")
        )
    end
  end

  def handle_event("pin_run_chart", _, socket),
    do:
      reject_event(
        socket,
        Error.new(:unavailable_run_pin, :workbench, "Run pin request is malformed")
      )

  def handle_event("remove_pin", %{"value" => ""} = params, socket) when map_size(params) == 2,
    do: handle_event("remove_pin", Map.delete(params, "value"), socket)

  def handle_event("remove_pin", %{"pin_id" => id} = params, socket) when map_size(params) == 1 do
    case pin_action(socket, "pin_remove", id) do
      {:ok, socket} -> {:noreply, socket}
      {:error, error} -> reject_event(socket, error)
    end
  end

  def handle_event("remove_pin", _, socket),
    do: reject_event(socket, Error.new(:invalid_pin, :workbench, "Pin request is malformed"))

  def handle_event("rename_pin", %{"pin_id" => id, "title" => title}, socket) do
    case change_board(socket, {:rename, id, title}) do
      {:ok, socket} -> {:noreply, socket}
      {:error, error} -> reject_event(socket, error)
    end
  end

  def handle_event("load_history", %{"range" => range}, socket) do
    command(socket, :query, fn scope ->
      with {:ok, binding} <- room_history(scope.room),
           {:ok, history} <-
             HistoryPanels.load(binding, socket.assigns.dashboard_panels, range) do
        {:ok, scope, {:history, history}}
      end
    end)
  end

  def handle_event("load_history", _, socket) do
    reject_event(socket, Error.new(:invalid_range, :metrics, "history range is not admitted"))
  end

  def handle_event("save_dashboard", %{"panels" => panel_ids}, socket) do
    with %{token: token} <- socket.assigns.scope,
         {:ok, session} <- Sessions.put_dashboard(token, panel_ids) do
      scope = %{socket.assigns.scope | dashboard_panels: session.dashboard_panels}

      {:noreply,
       socket
       |> assign(:scope, scope)
       |> assign(:dashboard_panels, session.dashboard_panels)
       |> assign(:history, nil)
       |> put_flash(:info, "Dashboard arrangement saved for this session.")
       |> push_patch(to: dashboard_path(session.dashboard_panels))}
    else
      nil -> {:noreply, deny(socket, Error.new(:denied, :session, "no session scope"))}
      {:error, error} -> reject_event(socket, error)
    end
  end

  def handle_event("save_dashboard", _, socket) do
    reject_event(socket, Error.new(:invalid_panels, :metrics, "select 1–16 metric panels"))
  end

  def handle_event("export_dataset", _, socket) do
    command(socket, :export, fn scope ->
      with {:ok, _} <- Room.export_dataset(scope.room, scope: scope.session_id, limit: 2_000),
           do: {:ok, scope, nil}
    end)
  end

  def handle_event("inspect_run", params, socket) do
    command(socket, :query, fn scope ->
      with id when is_binary(id) <- socket.assigns[:run_id],
           {:ok, run} <- Room.fetch_run(scope.room, id),
           {:ok, insights} <- Insights.analyze(run, params) do
        {:ok, scope, {:insights, insights}}
      else
        {:error, error} -> {:error, error}
        _ -> {:error, Error.new(:unknown_run, :analytics, "no run selected in this session")}
      end
    end)
  end

  def handle_event("verify", %{"property" => property, "variant" => variant}, socket) do
    command(socket, :verify, fn scope ->
      with {:ok, property, variant} <- Formal.admit(property, variant),
           {:ok, _} <- Room.verify(scope.room, property, variant) do
        {:ok, scope, nil}
      else
        {:error, :unsupported} ->
          {:error, Error.new(:unsupported, :formal, "no verified Maude engine is configured")}

        {:error, error} ->
          {:error, error}
      end
    end)
  end

  def handle_event("ask", _, %{assigns: %{investigation: %{state: :running}}} = socket),
    do: {:noreply, socket}

  def handle_event("ask", %{"prompt" => prompt}, socket) do
    socket = if valid_prompt?(prompt), do: put_prompt(socket, prompt), else: socket

    with :ok <- admit_prompt(prompt),
         {:ok, scope} <- Scope.verify(socket),
         true <- is_pid(scope.room) and Process.alive?(scope.room),
         :ok <- investigation_available(),
         {:ok, scope} <- Scope.admit(socket, :ask),
         {:ok, current, baseline} <- investigation_context(socket, scope),
         {:ok, request} <-
           Broker.ask(prompt, run: current, baseline: baseline, room: scope.room) do
      investigation = %{state: :running, request: request, prompt: prompt}

      {:noreply,
       socket
       |> assign(:scope, scope)
       |> assign(:answer, nil)
       |> assign(:investigation_room, scope.room)
       |> assign(:investigation_results, [])
       |> assign(:investigation, investigation)}
    else
      false ->
        {:noreply, error_flash(socket, Error.new(:no_room, :session, "room is unavailable"))}

      {:error, %Error{} = error} ->
        reject_event(socket, error)

      {:error, reason} ->
        {:noreply, investigation_failure(socket, reason)}
    end
  end

  def handle_event("ask", _, socket) do
    {:noreply, investigation_failure(socket, :invalid_prompt)}
  end

  def handle_event("edit_prompt", %{"prompt" => prompt}, socket) do
    with {:ok, scope} <- Scope.verify(socket),
         true <- valid_prompt?(prompt) and socket.assigns.investigation.state != :running do
      state = investigation_state()

      {:noreply,
       socket
       |> assign(:scope, scope)
       |> assign(:investigation, %{state | prompt: prompt})}
    else
      {:error, error} -> reject_event(socket, error)
      _ -> {:noreply, socket}
    end
  end

  def handle_event("edit_prompt", _, socket), do: {:noreply, socket}

  def handle_event("pin_investigation_metric", %{"index" => index}, socket) do
    with {:ok, scope} <- Scope.verify(socket),
         true <- scope.room != nil and scope.room == socket.assigns.investigation_room,
         true <- is_binary(index) and index in ~w(0 1 2 3 4 5 6 7),
         history when is_map(history) <-
           Enum.at(socket.assigns.investigation_results, String.to_integer(index)),
         {:ok, board} <- Sessions.change_board(scope.token, scope.room, {:pin, history}) do
      [panel] = history.panels
      id = "pin-#{panel.id}-#{history.range}"

      {:noreply,
       socket
       |> assign(scope: scope, board: board)
       |> update(:active_pins, &MapSet.put(&1, id))
       |> revise_islands()
       |> push_patch(to: "/")}
    else
      {:error, error} ->
        reject_event(socket, error)

      _ ->
        reject_event(
          socket,
          Error.new(:unknown_pin_result, :metrics, "Choose a recorded result from this room")
        )
    end
  end

  def handle_event("pin_investigation_metric", _, socket),
    do:
      reject_event(
        socket,
        Error.new(:unknown_pin_result, :metrics, "Choose a recorded result from this room")
      )

  def handle_event("cancel_investigation", _, socket) do
    with {:ok, scope} <- Scope.admit(socket, :ask),
         %{state: :running, request: request} <- socket.assigns.investigation,
         :ok <- Broker.cancel(request) do
      {:noreply, assign(socket, :scope, scope)}
    else
      {:error, %Error{} = error} -> {:noreply, error_flash(socket, error)}
      {:error, reason} -> {:noreply, investigation_failure(socket, reason)}
      _ -> {:noreply, investigation_failure(socket, :unknown_investigation)}
    end
  end

  def handle_event("wotex:island:" <> event, payload, socket) do
    cond do
      String.ends_with?(event, ":resync") ->
        instance_id = String.trim_trailing(event, ":resync")
        resync_island(socket, instance_id)

      String.ends_with?(event, ":event") ->
        instance_id = String.trim_trailing(event, ":event")
        admit_island_event(socket, instance_id, payload)

      true ->
        {:reply, %{"status" => "rejected"}, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:wotex_runtime, id, event}, socket) do
    case Enum.find(socket.assigns.observations, fn {_, watch} -> watch.id == id end) do
      {key, watch} -> receive_observation(socket, key, watch, event)
      _ -> {:noreply, socket}
    end
  end

  def handle_info({:DOWN, monitor, :process, _, _}, socket) do
    case Enum.find(socket.assigns.observations, fn {_, watch} -> watch.monitor == monitor end) do
      {key, watch} ->
        receive_observation(socket, key, watch, {:status, :transport_down})

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info(
        {:investigation, request, result},
        %{assigns: %{investigation: %{state: :running, request: request}}} = socket
      ) do
    with {:ok, scope} <- Scope.verify(socket),
         true <- scope.room == socket.assigns.investigation_room do
      results = investigation_results(result)

      answer =
        result
        |> Answer.from_result(provider_status())
        |> link_metric_sources(results)

      investigation = %{state: :idle, request: nil, prompt: socket.assigns.investigation.prompt}

      {:noreply,
       assign(socket,
         scope: scope,
         answer: answer,
         investigation: investigation,
         investigation_results: results
       )}
    else
      {:error, error} -> reject_event(socket, error)
      _ -> {:noreply, cancel_investigation_on_navigation(socket)}
    end
  end

  def handle_info(:refresh_pins, socket) do
    Process.send_after(self(), :refresh_pins, 5_000)

    case Scope.verify(socket) do
      {:ok, scope} ->
        before =
          {socket.assigns.board, socket.assigns.active_pins, socket.assigns.canvas_readings,
           socket.assigns.connection_state, socket.assigns.runs}

        socket =
          socket
          |> assign(:scope, scope)
          |> load_board()
          |> load_connections()
          |> refresh_run_state()
          |> update(
            :canvas_readings,
            &ThingReadings.expire(&1, System.monotonic_time(:millisecond))
          )

        socket =
          if socket.assigns.live_action == :run and socket.assigns.run_view == :review,
            do: assign(socket, :run_clock, System.monotonic_time(:millisecond)),
            else: socket

        socket =
          if before ==
               {socket.assigns.board, socket.assigns.active_pins, socket.assigns.canvas_readings,
                socket.assigns.connection_state, socket.assigns.runs},
             do: socket,
             else: revise_islands(socket)

        pins =
          Enum.filter(socket.assigns.board.pins, &MapSet.member?(socket.assigns.active_pins, &1.id))

        {:noreply, start_pin_refresh(socket, pins)}

      {:error, error} ->
        {:noreply, deny(socket, error)}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def handle_async(:pin_refresh, {:ok, histories}, socket) do
    with {:ok, scope} <- Scope.verify(socket),
         true <- scope.room == socket.assigns.pin_refresh_room,
         {:ok, board} <- Sessions.change_board(scope.token, scope.room, {:refresh, histories}) do
      {:noreply,
       socket
       |> assign(scope: scope, board: board, pin_refresh_running: false)
       |> revise_islands()}
    else
      false -> {:noreply, assign(socket, pin_refresh_running: false, active_pins: MapSet.new())}
      {:error, error} -> reject_event(assign(socket, :pin_refresh_running, false), error)
    end
  end

  def handle_async(:pin_refresh, {:exit, _}, socket),
    do:
      reject_event(
        assign(socket, :pin_refresh_running, false),
        Error.new(:history_unavailable, :metrics, "Refresh failed; previous data retained")
      )

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <%= if @scope do %>
      <.shell
        theme={@scope.theme}
        sidebar_open={@sidebar_open}
        current={nav_item(@live_action)}
        canvas={true}
      >
        <:context><.context_header items={context(@scope, @run)} /></:context>
        <:actions>
          <button id="wl-board-search" type="button" phx-click="open_board_search">
            <img class="wl-menu-icon" src="/icons/search.svg" alt="" width="16" height="16" />
            <span>Search board</span><kbd>⌘ / Ctrl K</kbd>
          </button>
          <button type="button" phx-click="open_connections">Connections</button>
          <button type="button" phx-click="import_thing">Add Thing Description</button>
          <.link :if={@scope.room} patch="/evidence" class="wl-nav-link">Session report</.link>
        </:actions>
        <div :if={Phoenix.Flash.get(@flash, :info)} class="wl-flash" role="status">
          {Phoenix.Flash.get(@flash, :info)}
        </div>
        <div :if={Phoenix.Flash.get(@flash, :error)} class="wl-flash wl-flash-error" role="alert">
          {Phoenix.Flash.get(@flash, :error)}
        </div>
        <h1 class="wl-sr-only">Lab room</h1>
        <div id="wl-workspace" class="wl-things-workspace">
          <.canvas_view
            things={@things}
            runs={@runs}
            readings={@canvas_readings}
            selection={@canvas_selection}
            connections={@connection_state}
            board={@board}
            active_pins={@active_pins}
            session_id={@scope.session_id}
            island_revision={@island_revision}
            empty={
              is_nil(@scope.room) && @live_action in [:workbench, :things] &&
                @canvas_selection != "import" && !@connections_open && !@board_search_open
            }
          />
          <%= case @live_action do %>
            <% :experiments -> %>
              <.tool_panel
                id="wl-experiments-panel"
                title="Experiments"
                menu_open={@sidebar_open}
                back_event={if @board_search_result == "process-smart-room", do: "back_to_board_search"}
                return_label="Back to search"
                restore_canvas_focus={@board_search_result != "process-smart-room"}
              >
                <.experiments_view
                  experiments={@experiments}
                  selected={@selected_experiment}
                  forms={@experiment_forms}
                  runs={@runs}
                  room={@scope.room}
                />
              </.tool_panel>
            <% :run -> %>
              <.tool_panel
                id={if @run, do: "wl-run-panel-#{@run.id}", else: "wl-run-panel"}
                title={RunPresentation.title(@run, @run_view)}
                menu_open={@sidebar_open}
                return_path={
                  if @run && @run_view != :result,
                    do: RunPresentation.path(@run, :result),
                    else: experiment_path(@run)
                }
                return_label={if @run_view == :result, do: "Back to experiment", else: "Back to result"}
              >
                <.run_view
                  run={@run}
                  view={@run_view}
                  now={@run_clock}
                  charts={@charts}
                  insights={@insights}
                  investigation={@investigation}
                  answer={@answer}
                  disclosure={@disclosure}
                  session_id={@scope.session_id}
                  island_revision={@island_revision}
                />
                <.investigation_metrics results={@investigation_results} />
              </.tool_panel>
            <% :things -> %>
              <%= cond do %>
                <% @board_search_open -> %>
                  <.tool_panel
                    id="wl-board-search-panel"
                    title="Search board"
                    menu_open={@sidebar_open}
                    restore_canvas_focus={false}
                    autofocus={false}
                  >
                    <.board_search
                      things={@things}
                      runs={@runs}
                      readings={@canvas_readings}
                      connections={@connection_state}
                      board={@board}
                      query={@board_search_query}
                      error={@board_search_error}
                      focus_id={@board_search_focus}
                    />
                  </.tool_panel>
                <% @connections_open -> %>
                  <.tool_panel
                    id="wl-connections-panel"
                    title={
                      if @connection_editing && @connection_draft,
                        do: Connections.title(@connection_draft["port"]),
                        else: "Connections"
                    }
                    menu_open={@sidebar_open}
                    back_event={if @connection_editing, do: "connection_list"}
                    return_label="Back to connections"
                  >
                    <.connections_view
                      room={@scope.room}
                      model={@connection_state}
                      things={@things}
                      readings={@canvas_readings}
                      observations={@observations}
                      draft={if @connection_editing, do: @connection_draft}
                      error={@connection_error}
                      focus_port={@connection_focus}
                    />
                  </.tool_panel>
                <% true -> %>
                  <.things_view
                    things={@things}
                    room={@scope.room}
                    readings={@canvas_readings}
                    errors={@property_errors}
                    selection={@canvas_selection}
                    observations={@observations}
                    panel={@thing_panel}
                    menu_open={@sidebar_open}
                    search_return={
                      not is_nil(@board_search_result) && @board_search_result == @canvas_selection
                    }
                  />
              <% end %>
            <% :metrics -> %>
              <.tool_panel
                id="wl-metrics-panel"
                title={if run_pin?(@board, @selected_pin), do: "Pinned result", else: "Metrics"}
                menu_open={@sidebar_open}
                back_event={
                  if @selected_pin && @selected_pin == @board_search_result, do: "back_to_board_search"
                }
                return_label="Back to search"
                restore_canvas_focus={is_nil(@selected_pin) || @selected_pin != @board_search_result}
              >
                <div :if={is_nil(@selected_pin)} class="wl-stack">
                  <.prompt_composer
                    title="Ask"
                    compact
                    allow_draft
                    change_event="edit_prompt"
                    value={@investigation.prompt}
                    running={@investigation.state == :running}
                    disabled={@investigation.state != :idle or is_nil(@scope.room)}
                    reason={metrics_prompt_reason(@investigation, @scope.room)}
                    disclosure={@disclosure}
                  />
                  <.answer_block :if={@answer} answer={@answer} compact />
                  <.investigation_metrics results={@investigation_results} />
                </div>
                <details
                  :if={is_nil(@selected_pin)}
                  id="metric-query-builder"
                  class="wl-disclosure"
                  open={
                    @investigation.state == :disabled or @metric_result != nil or is_nil(@scope.room)
                  }
                >
                  <summary>Build query</summary>
                  <.metric_composer
                    room={@scope.room}
                    draft={@metric_draft}
                    result={@metric_result}
                    pin={nil}
                    selected_pin={nil}
                  />
                </details>
                <.metric_composer
                  :if={@selected_pin && !run_pin?(@board, @selected_pin)}
                  room={@scope.room}
                  draft={@metric_draft}
                  result={@metric_result}
                  pin={selected_pin(@board, @selected_pin)}
                  selected_pin={@selected_pin}
                />
                <.run_pin
                  :if={run_pin?(@board, @selected_pin)}
                  pin={selected_pin(@board, @selected_pin)}
                />
                <details :if={is_nil(@selected_pin)} class="wl-disclosure">
                  <summary>Session measurements</summary>
                  <.metrics_view
                    metrics={@metrics}
                    history={@history}
                    history_range={@history_range}
                    room={@scope.room}
                    dashboard_panels={@dashboard_panels}
                    session_id={@scope.session_id}
                    island_revision={@island_revision}
                  />
                </details>
              </.tool_panel>
            <% :evidence -> %>
              <.tool_panel
                id="wl-evidence-panel"
                title={if @evidence_selected, do: "Sources", else: "Session report"}
                menu_open={@sidebar_open}
                return_path={if @run, do: "/runs/#{@run.id}", else: "/"}
                return_label="Back to run"
              >
                <.evidence_view
                  snapshot={@snapshot}
                  room={@scope.room}
                  answer={@answer}
                  investigation={@investigation}
                  disclosure={@disclosure}
                  subject={@run}
                  selected={@evidence_selected}
                />
                <.investigation_metrics results={@investigation_results} />
              </.tool_panel>
            <% _ -> %>
          <% end %>
        </div>
      </.shell>
    <% else %>
      <div
        class="wotex-lab wl-denied"
        data-wotex-design-system
        data-wotex-theme="system"
      >
        <.error_state
          title="Session denied"
          code={@denied || "denied"}
          message="Open a fresh bounded session to continue."
        >
          <:action><a class="wl-button wl-button-primary" href="/session/new">New session</a></:action>
        </.error_state>
      </div>
    <% end %>
    """
  end

  attr(:things, :list, required: true)
  attr(:runs, :list, required: true)
  attr(:readings, :map, required: true)
  attr(:selection, :string, default: nil)
  attr(:connections, :map, required: true)
  attr(:session_id, :string, required: true)
  attr(:island_revision, :integer, required: true)
  attr(:empty, :boolean, required: true)
  attr(:board, :map, required: true)
  attr(:active_pins, :any, required: true)

  defp canvas_view(assigns) do
    props =
      Canvas.props(
        assigns.things,
        assigns.runs,
        assigns.readings,
        assigns.selection,
        assigns.connections
      )
      |> Board.decorate(assigns.board, assigns.active_pins)

    assigns = assign(assigns, :props, props)

    ~H"""
    <Islands.canvas_island
      id={Islands.id(@session_id, "connected-things")}
      props={@props}
      revision={@island_revision}
    >
      <:fallback>
        <ul aria-label="Connected Things">
          <li :for={node <- @props["nodes"]}>
            <button type="button" phx-click="inspect_thing" phx-value-id={node["id"]}>{node["title"]}</button>
            <span>{node["value"]} {node["unit"]} · {node["status"]}</span>
          </li>
        </ul>
        <ul :if={@props["pins"] != []} aria-label="Workbench pins">
          <li :for={pin <- @props["pins"]}>
            <button type="button" phx-click="inspect_thing" phx-value-id={pin["id"]}>{pin["title"]}</button>
            <span>{pin["state"]}</span>
          </li>
        </ul>
      </:fallback>
    </Islands.canvas_island>
    <div :if={@empty} class="wl-things-empty">
      <h2>Connect your room</h2>
      <button class="wl-button wl-button-primary" phx-click="start_room">Start room</button>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:menu_open, :boolean, required: true)
  attr(:return_path, :string, default: "/")
  attr(:return_label, :string, default: "Back to experiment")
  attr(:back_event, :string, default: nil)
  attr(:restore_canvas_focus, :boolean, default: true)
  attr(:autofocus, :boolean, default: true)
  slot(:inner_block, required: true)

  defp tool_panel(assigns) do
    ~H"""
    <aside
      id={@id}
      class="wl-workbench-panel"
      aria-labelledby={@id <> "-title"}
      phx-mounted={if @autofocus, do: JS.focus_first(to: "##{@id}")}
      phx-window-keydown={
        if !@menu_open,
          do:
            JS.patch("/")
            |> JS.focus(to: "#wl-board-toggle")
            |> restore_canvas_focus(@restore_canvas_focus)
      }
      phx-key="Escape"
    >
      <header class="wl-workbench-panel-header">
        <button
          :if={@back_event}
          type="button"
          phx-click={@back_event}
          class="wl-panel-close"
          aria-label={@return_label}
        >
          <img class="wl-menu-icon" src="/icons/chevron-left.svg" alt="" width="14" height="14" />
        </button>
        <.link
          :if={is_nil(@back_event) && @return_path != "/"}
          patch={@return_path}
          class="wl-panel-close"
          aria-label={@return_label}
        >
          <img class="wl-menu-icon" src="/icons/chevron-left.svg" alt="" width="14" height="14" />
        </.link>
        <h2 id={@id <> "-title"}>{@title}</h2>
        <.link
          patch="/"
          class="wl-panel-close"
          aria-label="Close panel"
          phx-click={JS.focus(to: "#wl-board-toggle") |> restore_canvas_focus(@restore_canvas_focus)}
        ><img class="wl-menu-icon" src="/icons/x.svg" alt="" width="14" height="14" /></.link>
      </header>
      <div class="wl-workbench-panel-body">{render_slot(@inner_block)}</div>
    </aside>
    """
  end

  defp restore_canvas_focus(js, true), do: JS.dispatch(js, "wotex:restore-canvas-focus")
  defp restore_canvas_focus(js, false), do: js

  attr(:experiments, :list, required: true)
  attr(:selected, :string, required: true)
  attr(:forms, :map, required: true)
  attr(:runs, :list, required: true)
  attr(:room, :any, required: true)

  defp experiments_view(assigns) do
    ~H"""
    <nav class="wl-experiment-tabs" aria-label="Choose experiment">
      <button
        :for={experiment <- @experiments}
        type="button"
        phx-click="select_experiment"
        phx-value-id={experiment.id}
        aria-pressed={to_string(experiment.id == @selected)}
        aria-controls={"experiment-#{experiment.id}"}
      >
        {experiment_label(experiment.id)}
      </button>
    </nav>
    <button :if={is_nil(@room)} class="wl-button wl-button-secondary" phx-click="start_room">Start disposable room</button>
    <section
      :for={experiment <- @experiments}
      id={"experiment-#{experiment.id}"}
      aria-label={experiment_label(experiment.id)}
      hidden={experiment.id != @selected}
    >
      <form
        id={"run-#{experiment.id}"}
        phx-change="edit_experiment"
        phx-submit="run"
        class="wl-stack wl-experiment-form"
      >
        <input type="hidden" name="experiment_id" value={experiment.id} />
        <.parameter_field
          :for={parameter <- experiment.parameters}
          experiment={experiment.id}
          parameter={parameter}
          state={Map.fetch!(@forms, experiment.id)}
        />
        <button
          class="wl-button wl-button-primary"
          type="submit"
          disabled={not is_nil(Map.fetch!(@forms, experiment.id).error)}
          phx-disable-with="Running…"
        >Run experiment</button>
      </form>
      <details class="wl-disclosure">
        <summary>Sources</summary>
        <p>{experiment.summary}</p>
        <dl class="wl-provenance">
          <div :for={{label, value} <- Enum.sort(experiment.provenance)}>
            <dt>{label}</dt><dd>{value}</dd>
          </div>
        </dl>
        <ul>
          <li :for={call <- experiment.public_calls}><code>{call}</code></li>
        </ul>
        <dl class="wl-meta-list">
          <%= for parameter <- experiment.parameters do %>
            <dt>{parameter.label}</dt><dd>{parameter.help}</dd>
          <% end %>
        </dl>
      </details>
    </section>
    <section :if={@runs != []} class="wl-section">
      <h3>Recent runs</h3>
      <.data_table id="recent-runs" caption="Recent experiment runs" rows={@runs}>
        <:col :let={run} label="Run"><.link patch={"/runs/#{run.id}"}>{run.id}</.link></:col>
        <:col :let={run} label="Experiment">{experiment_label(run.experiment)}</:col>
        <:col :let={run} label="State">
          <.status_badge status={Run.state_text(run)} kind={StatusBadge.kind_for(run.status)} />
        </:col>
      </.data_table>
    </section>
    """
  end

  defp experiment_label("thermal"), do: "Thermal"
  defp experiment_label("window_anomaly"), do: "Anomaly"
  defp experiment_label("smart_room"), do: "Smart room"
  defp experiment_label(_), do: "Experiment"

  defp experiment_path(%Run{experiment: id}),
    do: "/experiments?" <> Query.encode(%{"experiment" => id})

  defp experiment_path(_), do: "/experiments"

  attr(:parameter, :map, required: true)
  attr(:experiment, :string, required: true)
  attr(:state, :map, required: true)

  defp parameter_field(assigns) do
    parameter = assigns.parameter
    value = Map.fetch!(assigns.state.values, parameter.name)
    options = Enum.map(parameter.options || [], fn {label, _} -> {label, label} end)

    options =
      if parameter.type == :select and not List.keymember?(options, value, 1),
        do: [{"Unsupported selection", value} | options],
        else: options

    assigns =
      assigns
      |> assign(
        :control_type,
        if(parameter.type == :select, do: "select", else: "number")
      )
      |> assign(:options, options)
      |> assign(:fixed, parameter.type == :select and length(options) == 1)
      |> assign(:value, value)
      |> assign(:error, parameter_error(assigns.state.error, parameter))
      |> assign(:step, parameter_step(parameter.type))

    ~H"""
    <div :if={@fixed} class="wl-config-fixed">
      <span class="wl-muted">{@parameter.label}</span><span>{@value}</span>
      <input
        type="hidden"
        id={"parameter-#{@experiment}-#{@parameter.name}"}
        name={"params[#{@parameter.name}]"}
        value={@value}
      />
    </div>
    <.field
      :if={!@fixed}
      id={"parameter-#{@experiment}-#{@parameter.name}"}
      name={"params[#{@parameter.name}]"}
      label={@parameter.label}
      type={@control_type}
      value={@value}
      options={@options}
      help={@parameter.help}
      error={@error}
      min={@parameter.min}
      max={@parameter.max}
      step={@step}
    />
    """
  end

  defp parameter_step(:integer), do: "1"
  defp parameter_step(:float), do: "any"
  defp parameter_step(:select), do: nil

  defp experiment_forms do
    Map.new(Experiments.all(), fn experiment ->
      {experiment.id, %{values: Experiments.defaults(experiment), error: nil}}
    end)
  end

  defp experiment_draft(experiment, raw) when is_map(raw) and not is_struct(raw) do
    defaults = Experiments.defaults(experiment)

    if map_size(raw) <= 2 * map_size(defaults) and
         Enum.all?(raw, &draft_entry?(&1, defaults, raw)) do
      {:ok, Map.merge(defaults, Map.take(raw, Map.keys(defaults)))}
    else
      malformed_experiment_draft()
    end
  end

  defp experiment_draft(_, _), do: malformed_experiment_draft()

  defp draft_entry?({"_unused_" <> name, ""}, defaults, raw),
    do: Map.has_key?(defaults, name) and Map.has_key?(raw, name)

  defp draft_entry?({name, value}, defaults, _),
    do:
      Map.has_key?(defaults, name) and is_binary(value) and
        byte_size(value) <= @parameter_bytes and String.valid?(value)

  defp malformed_experiment_draft do
    {:error,
     Error.new(:invalid_parameters, :admission, "run form requires bounded parameter strings")}
  end

  defp parameter_error(%Error{path: path}, parameter) do
    if path == "/" <> parameter.name do
      case parameter.type do
        :select -> "Choose one of: " <> Enum.map_join(parameter.options, ", ", &elem(&1, 0))
        :integer -> "Enter an integer from #{parameter.min} to #{parameter.max}."
        :float -> "Enter a number from #{parameter.min} to #{parameter.max}."
      end
    end
  end

  defp parameter_error(_, _), do: nil

  attr(:run, :any, required: true)
  attr(:view, :atom, required: true)
  attr(:now, :integer, required: true)
  attr(:charts, :list, required: true)
  attr(:insights, :any, required: true)
  attr(:investigation, :map, required: true)
  attr(:disclosure, :map, required: true)
  attr(:answer, :any, required: true)
  attr(:session_id, :string, required: true)
  attr(:island_revision, :integer, required: true)

  defp run_view(assigns) do
    assigns =
      assign(
        assigns,
        :chart_links,
        Enum.with_index(assigns.charts, fn _, index ->
          chart_path(assigns.run, assigns.insights, index)
        end)
      )

    ~H"""
    <.error_state
      :if={is_nil(@run)}
      title="Run unavailable"
      code="unknown_run"
      message="This run is not in the current session."
    />
    <div :if={@run} class="wl-run-context">
      <%= case @view do %>
        <% :result -> %>
          <.run_result
            run={@run}
            charts={@charts}
            chart_links={@chart_links}
            analysed={@insights != nil}
            query={RunPin.query(@insights)}
          />
        <% :data -> %>
          <.tensor_summary :if={@run.tensor} summary={@run.tensor} />
          <p :if={is_nil(@run.tensor)} class="wl-muted">No tensor was produced.</p>
        <% :analysis -> %>
          <.insights :if={@run.timeseries != []} run={@run} insights={@insights} />
          <p :if={@run.timeseries == []} class="wl-muted">No series to analyse.</p>
          <div :for={{chart, index} <- Enum.with_index(@charts)} class="wl-stack">
            <.chart
              id={"run-chart-#{index}"}
              chart={RunPresentation.display_chart(@run, chart)}
              permalink={Enum.at(@chart_links, index)}
              compact
            />
            <.run_pin_control run={@run} chart={chart} index={index} query={RunPin.query(@insights)} />
          </div>
        <% :details -> %>
          <.run_details run={@run} />
        <% :review -> %>
          <.action_approval
            :if={@run.status == :awaiting_approval}
            run={@run}
            remaining_ms={@run.decision["expires_at"] - @now}
          />
          <div :if={@run.status != :awaiting_approval} class="wl-stack">
            <.status_badge status={Run.state_text(@run)} kind={StatusBadge.kind_for(@run.status)} />
            <p>No pending Action.</p>
            <.link patch={RunPresentation.path(@run, :result)} class="wl-button wl-button-secondary">Return to result</.link>
          </div>
        <% :ask -> %>
          <.prompt_composer
            disabled={@investigation.state != :idle}
            running={@investigation.state == :running}
            reason={prompt_reason(@investigation, true)}
            value={@investigation.prompt}
            disclosure={@disclosure}
            compact
          />
          <.answer_block :if={@answer} answer={@answer} compact />
      <% end %>
    </div>
    """
  end

  attr(:run, :any, required: true)

  defp run_details(assigns) do
    ~H"""
    <div class="wl-stack">
      <dl class="wl-meta-list">
        <dt>Run</dt><dd>{@run.id}</dd>
        <dt>State</dt><dd>{Run.state_text(@run)}</dd>
        <dt>Started</dt><dd>
          <time datetime={DateTime.to_iso8601(@run.started_at)}>{DateTime.to_iso8601(@run.started_at)}</time>
        </dd>
        <dt>Duration</dt><dd>{@run.duration_ms} ms</dd>
        <dt>Backend</dt><dd>{@run.backend}</dd>
        <dt>Source mode</dt><dd>{@run.source_mode}</dd>
        <dt>Cleanup</dt><dd>{@run.cleanup.status}</dd>
      </dl>
      <dl :if={@run.summary != []} class="wl-meta-list">
        <%= for {label, value} <- @run.summary do %>
          <dt>{label}</dt><dd>{value}</dd>
        <% end %>
      </dl>
      <details class="wl-disclosure">
        <summary>Parameters</summary>
        <dl class="wl-meta-list">
          <%= for {key, value} <- @run.params do %>
            <dt>{key}</dt><dd>{inspect(value)}</dd>
          <% end %>
        </dl>
      </details>
      <.data_table id="run-assertions" caption="Run assertions" rows={@run.assertions}>
        <:col :let={row} label="Assertion">{row.id}</:col>
        <:col :let={row} label="Status">
          <.status_badge status={Atom.to_string(row.status)} kind={StatusBadge.kind_for(row.status)} />
        </:col>
        <:col :let={row} label="Note">{row.note}</:col>
      </.data_table>
      <div class="wl-actions">
        <.link
          patch={"/evidence?" <> Query.encode(%{"run" => @run.id})}
          class="wl-button wl-button-secondary"
        >Sources</.link>
        <a href={RunPresentation.report_path(@run)} download class="wl-button wl-button-secondary">Export report</a>
      </div>
    </div>
    """
  end

  attr(:things, :list, required: true)
  attr(:room, :any, required: true)
  attr(:readings, :map, required: true)

  attr(:selection, :any, default: nil)
  attr(:menu_open, :boolean, default: false)
  attr(:observations, :map, required: true)
  attr(:errors, :map, required: true)
  attr(:panel, :atom, required: true)
  attr(:search_return, :boolean, default: false)

  defp things_view(assigns) do
    selected = Enum.find(assigns.things, &(Canvas.id(&1) == assigns.selection))

    assigns =
      assigns
      |> assign(:selected, selected)
      |> assign(:properties, if(selected, do: ThingProperties.rows(selected), else: []))
      |> assign(
        :receipts,
        if(selected, do: property_receipts(selected, assigns.readings), else: [])
      )
      |> assign(
        :failures,
        if(selected, do: property_failures(selected, assigns.errors), else: [])
      )

    ~H"""
    <aside
      :if={@selected || @selection == "import"}
      id={"wl-thing-inspector-#{@selection}"}
      class="wl-thing-inspector"
      aria-label="Thing inspector"
      phx-mounted={JS.focus_first(to: "#wl-thing-inspector-#{@selection}")}
      phx-window-keydown={
        if !@menu_open,
          do:
            JS.push("close_thing")
            |> JS.focus(
              to:
                if(@selection == "import" || @search_return,
                  do: "#wl-board-toggle",
                  else: ".svelte-flow__node[data-id='#{@selection}']"
                )
            )
      }
      phx-key="Escape"
    >
      <header>
        <button
          :if={@search_return}
          type="button"
          class="wl-panel-close"
          phx-click="back_to_board_search"
          aria-label="Back to search"
        ><img class="wl-menu-icon" src="/icons/chevron-left.svg" alt="" width="14" height="14" /></button>
        <h2>
          {cond do
            @selected -> Canvas.title(@selected)
            @selection == "import" -> "Add Thing"
            true -> "Smart room"
          end}
        </h2>
        <button
          type="button"
          class="wl-panel-close"
          phx-click={
            JS.push("close_thing")
            |> JS.focus(
              to:
                if(@selection == "import" || @search_return,
                  do: "#wl-board-toggle",
                  else: ".svelte-flow__node[data-id='#{@selection}']"
                )
            )
          }
          aria-label="Close inspector"
        ><img class="wl-menu-icon" src="/icons/x.svg" alt="" width="14" height="14" /></button>
      </header>
      <%= cond do %>
        <% @selection == "import" -> %>
          <button :if={is_nil(@room)} class="wl-button wl-button-primary" phx-click="start_room">Start room</button>
          <form
            :if={@room}
            id="register-td"
            phx-submit="register_td"
            class="wl-stack"
            phx-mounted={JS.focus(to: "#thing-description")}
          >
            <.field
              id="thing-description"
              name="thing_description"
              label="Thing Description JSON"
              type="textarea"
              maxlength="16384"
              rows="8"
              help="Inert Directory entry"
            />
            <button
              class="wl-button wl-button-secondary"
              type="submit"
              phx-disable-with="Registering…"
            >Register TD</button>
          </form>
        <% @selected -> %>
          <p :if={!@selected.consumable} class="wl-muted">Directory entry · not connected</p>
          <section :for={property <- @properties} class="wl-thing-property" aria-label={property.name}>
            <% reading = ThingReadings.get(@readings, @selected.key, property.name) %>
            <% watching = Map.has_key?(@observations, @selected.key <> "/" <> property.name) %>
            <% error = Map.get(@errors, {@selected.key, property.name}) %>
            <% error_id = "wl-property-error-#{@selected.key}-#{property.name}" %>
            <header>
              <h3>{property.name}</h3><span class="wl-muted">{if reading,
                do: ThingReadings.status(reading),
                else: "Not read"}</span>
            </header>
            <div class="wl-inspector-reading">
              <strong>{if reading, do: inspect(reading.value), else: "—"}</strong><span>{property.unit}</span>
            </div>
            <p :if={reading} class="wl-muted wl-receipt-time">
              <time datetime={reading.read_at} title={reading.read_at}>{ThingReadings.time(reading)}</time>
            </p>
            <div class="wl-actions">
              <form
                :if={property.readable}
                id={"read-#{@selected.key}-#{property.name}"}
                phx-submit="read"
              >
                <input type="hidden" name="thing" value={@selected.key} /><input
                  type="hidden"
                  name="property"
                  value={property.name}
                />
                <button
                  class="wl-button wl-button-secondary"
                  type="submit"
                  phx-disable-with="Reading…"
                  aria-describedby={if error, do: error_id}
                >Read {property.name}</button>
              </form>
              <button
                :if={property.observable}
                class="wl-button wl-button-secondary"
                type="button"
                phx-click={if watching, do: "pause_observation", else: "observe"}
                phx-value-thing={@selected.key}
                phx-value-property={property.name}
                aria-describedby={if error, do: error_id}
              >
                {if watching, do: "Pause", else: "Observe"}
              </button>
            </div>
            <p :if={error} id={error_id} class="wl-error wl-help wl-property-error" role="alert">
              {property_error_text(error)}
            </p>
          </section>
          <details
            id={"wl-thing-#{@selection}-#{@panel}-statistics"}
            class="wl-disclosure"
            open={@panel == :statistics}
            phx-mounted={JS.ignore_attributes("open")}
          >
            <summary>Statistics</summary>
            <dl class="wl-thing-stats">
              <dt>Requests</dt><dd>{@selected.stats.handler_calls}</dd>
              <dt>Rejected</dt><dd>{@selected.stats.rejected}</dd>
              <dt>Observers</dt><dd>{@selected.stats.subscriptions}</dd>
            </dl>
          </details>
          <details
            id={"wl-thing-#{@selection}-#{@panel}-sources"}
            class="wl-disclosure"
            open={@panel == :sources}
            phx-mounted={JS.ignore_attributes("open")}
          >
            <summary>Sources</summary>
            <dl>
              <dt>Thing ID</dt><dd>{@selected.id}</dd><dt>Transport</dt><dd>{@selected.transport}</dd>
            </dl>
            <dl :for={{property, reading} <- @receipts}>
              <dt>{property} receipt</dt><dd>
                <time datetime={reading.read_at}>{reading.read_at}</time>
              </dd>
            </dl>
            <dl :if={@failures != []} class="wl-property-errors">
              <%= for {property, error} <- @failures do %>
                <dt>{property} error</dt><dd><code>{error.code}</code></dd>
              <% end %>
            </dl>
            <pre class="wl-thing-source"><code>{Jason.encode!(@selected.document, pretty: true)}</code></pre>
          </details>
        <% true -> %>
          <p>Observe and propose</p><.link patch="/experiments?experiment=smart_room">Configure experiment</.link>
      <% end %>
    </aside>
    """
  end

  defp property_receipts(thing, readings) do
    for property <- ThingProperties.rows(thing),
        reading <- [ThingReadings.get(readings, thing.key, property.name)],
        not is_nil(reading),
        do: {property.name, reading}
  end

  defp property_failures(thing, errors) do
    for property <- ThingProperties.rows(thing),
        error <- [Map.get(errors, {thing.key, property.name})],
        not is_nil(error),
        do: {property.name, error}
  end

  defp property_error_text(%{code: :invalid_property_reading}), do: "Invalid numeric reading"
  defp property_error_text(%{operation: "read"}), do: "Read unavailable"
  defp property_error_text(%{operation: "observe"}), do: "Observation unavailable"
  defp property_error_text(_), do: "Operation unavailable"

  attr(:metrics, :any, required: true)
  attr(:room, :any, required: true)
  attr(:dashboard_panels, :list, required: true)
  attr(:history, :any, required: true)
  attr(:history_range, :string, required: true)
  attr(:session_id, :string, required: true)
  attr(:island_revision, :integer, required: true)

  defp metrics_view(assigns) do
    latest = assigns.metrics && List.last(assigns.metrics.samples)
    {grid_columns, grid_rows} = metric_grid(assigns.metrics)

    assigns =
      assign(assigns, latest: latest, grid_columns: grid_columns, grid_rows: grid_rows)

    ~H"""
    <div :if={@room} class="wl-stack">
      <form id="metric-query" phx-submit="query_metrics" class="wl-filter-bar">
        <.field
          id="metric-component"
          name="component"
          label="Component"
          type="select"
          value=""
          options={
            [{"all", ""}] ++
              Enum.map(Wotex.Lab.Telemetry.components(), &{Atom.to_string(&1), Atom.to_string(&1)})
          }
        /><.field
          id="metric-operation"
          name="operation"
          label="Operation"
          type="select"
          value=""
          options={
            [{"all", ""}] ++
              Enum.map(Wotex.Lab.Telemetry.operations(), &{Atom.to_string(&1), Atom.to_string(&1)})
          }
        /><button
          class="wl-button wl-button-secondary"
          type="submit"
          phx-disable-with="Refreshing…"
        >Refresh</button>
      </form>
      <.empty_state
        :if={is_nil(@metrics)}
        title="No session measurements"
        description="Missing data is unavailable, never rendered as zero."
      />
      <div :if={@metrics} class="wl-metric-grid">
        <.metric_panel
          title="Retained samples"
          value={length(@metrics.samples)}
          unit="samples"
          status="available"
          note={"watermark #{@metrics.watermark}; overwritten #{@metrics.loss.overwritten}"}
        />
        <.metric_panel
          title="Freshness"
          value={@metrics.freshness_ms}
          unit="ms"
          status={if is_nil(@metrics.freshness_ms), do: "unavailable", else: "available"}
        />
        <.metric_panel
          title="Latest duration"
          value={@latest && @latest.duration_ms}
          unit="ms"
          status={if @latest, do: "available", else: "unavailable"}
        />
      </div>
      <.data_grid_island
        :if={@metrics}
        id={Islands.id(@session_id, "metric-samples")}
        label="Bounded session metric samples"
        columns={@grid_columns}
        rows={@grid_rows}
        revision={@island_revision}
      >
        <:fallback>
          <.data_table
            id="metric-samples"
            caption="Bounded session metric samples"
            rows={@metrics.samples}
          >
            <:col :let={row} label="Sequence">{row.sequence}</:col><:col :let={row} label="Event">
              {row.component}.{row.operation}.{row.event}
            </:col><:col :let={row} label="Duration">
              {if is_nil(row.duration_ms), do: "not measured", else: "#{row.duration_ms} ms"}
            </:col><:col :let={row} label="Outcome">{row.outcome || "none"}</:col>
          </.data_table>
        </:fallback>
      </.data_grid_island>
      <button
        class="wl-button wl-button-secondary"
        phx-click="export_dataset"
        phx-disable-with="Freezing…"
      >Freeze visible measurements as dataset</button>
    </div>
    <.history_panels :if={@room} history={@history} range={@history_range} />
    <.metric_catalogue selected={@dashboard_panels} />
    """
  end

  attr(:snapshot, :any, required: true)
  attr(:subject, :any, required: true)
  attr(:selected, :boolean, required: true)
  attr(:room, :any, required: true)
  attr(:answer, :any, required: true)
  attr(:investigation, :map, required: true)
  attr(:disclosure, :map, required: true)

  defp evidence_view(assigns) do
    properties = Enum.map(Formal.properties(), fn {id, text} -> {text, Atom.to_string(id)} end)
    variants = Enum.map(Formal.variants(), &{Atom.to_string(&1), Atom.to_string(&1)})

    snapshot =
      cond do
        not assigns.selected ->
          assigns.snapshot

        is_nil(assigns.subject) or is_nil(assigns.snapshot) ->
          nil

        true ->
          %{
            assigns.snapshot
            | runs: Enum.filter(assigns.snapshot.runs, &(&1.id == assigns.subject.id))
          }
      end

    assigns = assign(assigns, properties: properties, variants: variants, snapshot: snapshot)

    ~H"""
    <.error_state
      :if={@selected && is_nil(@subject)}
      title="Run unavailable"
      code="unknown_run"
      message="This run is not in the current session."
    />
    <button :if={is_nil(@room) && !@selected} class="wl-button wl-button-primary" phx-click="start_room">Start disposable room</button>
    <.empty_state
      :if={is_nil(@room) && !@selected}
      title="No evidence yet"
      description="Start a room; the report remains scoped to this signed session."
    />
    <.run_sources :if={@selected && @subject} run={@subject} />
    <div :if={@snapshot && !@selected} class="wl-stack">
      <h3 :if={@subject}>{experiment_label(@subject.experiment)} · {@subject.id}</h3>
      <div class="wl-actions">
        <.evidence_link href="/evidence/report.json" label="Export session report" download={true} />
      </div>
      <.data_table id="evidence-runs" caption="Run evidence" rows={@snapshot.runs}>
        <:col :let={run} label="Run"><.link patch={"/runs/#{run.id}"}>{run.id}</.link></:col><:col
          :let={run}
          label="State"
        >
          {Run.state_text(run)}
        </:col><:col :let={run} label="Digest"><code>{run.record_digest || "missing"}</code></:col>
      </.data_table>
      <.tensor_summary :if={@subject && @subject.tensor} summary={@subject.tensor} />
      <section class="wl-panel">
        <h2>Formal model evidence</h2><p>
          Results apply only to the pinned finite model and never authorize an Action.
        </p><form id="formal-verify" phx-submit="verify" class="wl-filter-bar">
          <.field
            id="formal-property"
            name="property"
            label="Property"
            type="select"
            value={elem(hd(@properties), 1)}
            options={@properties}
          /><.field
            id="formal-variant"
            name="variant"
            label="Model variant"
            type="select"
            value={elem(hd(@variants), 1)}
            options={@variants}
          /><button
            class="wl-button wl-button-secondary"
            type="submit"
            phx-disable-with="Verifying…"
          >Verify model</button>
        </form><p :if={@snapshot.formal == []} class="wl-muted">not run</p><ul>
          <li :for={result <- @snapshot.formal}>
            {result.status} · model {result.model.id} · depth {result.bounds.max_depth}
          </li>
        </ul>
      </section>
      <.prompt_composer
        disabled={@investigation.state != :idle or @snapshot.runs == []}
        running={@investigation.state == :running}
        reason={prompt_reason(@investigation, @snapshot.runs != [])}
        value={@investigation.prompt}
        disclosure={@disclosure}
      /><.answer_block :if={@answer} answer={@answer} />
    </div>
    """
  end

  defp start_experiment(scope, id, params) do
    with {:ok, run} <- Room.start_run(scope.room, id, params) do
      {:ok, scope, {:navigate, "/runs/#{run.id}"}}
    end
  end

  defp command(socket, command, fun) do
    with {:ok, scope} <- Scope.admit(socket, command),
         true <- is_pid(scope.room) and Process.alive?(scope.room),
         {:ok, scope, effect} <- fun.(scope) do
      socket =
        if socket.assigns.scope.room == scope.room do
          socket
        else
          socket
          |> stop_observations()
          |> assign(canvas_readings: %{}, property_errors: %{}, insights: nil)
        end

      socket =
        socket
        |> assign(:scope, scope)
        |> refresh()
        |> apply_effect(effect)
        |> revise_islands()

      {:noreply, socket}
    else
      false -> {:noreply, error_flash(socket, Error.new(:no_room, :session, "room is unavailable"))}
      {:error, error} -> reject_event(socket, error)
    end
  end

  defp handle_thing_operation(socket, operation, thing, property) do
    case thing_operation(socket, operation, thing, property) do
      {:ok, socket} -> {:noreply, revise_islands(socket)}
      {:error, error} -> {:noreply, property_failure(socket, operation, thing, property, error)}
    end
  end

  defp thing_operation(socket, operation, key, name) do
    with {:ok, scope} <- Scope.verify(socket),
         true <- is_pid(scope.room) and Process.alive?(scope.room),
         %{} = thing <- Enum.find(socket.assigns.things, &(&1.key == key)),
         %{} = property <- Enum.find(ThingProperties.rows(thing), &(&1.name == name)),
         true <-
           (operation == "read" and property.readable) or
             (operation in ~w(observe pause) and property.observable),
         {:ok, socket} <-
           perform_thing_operation(assign(socket, :scope, scope), operation, key, name) do
      {:ok, update(socket, :property_errors, &Map.delete(&1, {key, name}))}
    else
      {:error, error} ->
        {:error, error}

      _ ->
        {:error,
         Error.new(:unsupported_property_operation, :things, "Property operation is unavailable")}
    end
  end

  defp property_failure(socket, operation, key, name, %{code: code} = error)
       when operation in ~w(read observe pause) and is_atom(code) do
    with {:ok, scope} <- Scope.verify(socket),
         true <- is_pid(scope.room) and scope.room == socket.assigns.board_room,
         %{} = thing <- Enum.find(socket.assigns.things, &(&1.key == key)),
         true <- Enum.any?(ThingProperties.rows(thing), &(&1.name == name)) do
      socket =
        socket
        |> assign(:scope, scope)
        |> refresh_thing_stats(scope.room)
        |> update(:property_errors, &Map.put(&1, {key, name}, %{operation: operation, code: code}))

      if socket.assigns.live_action == :things and
           socket.assigns.canvas_selection == Canvas.id(thing) and
           not socket.assigns.board_search_open and not socket.assigns.connections_open do
        socket
      else
        case select_canvas_node(socket, Canvas.id(thing)) do
          {:ok, socket} -> socket
          _ -> error_flash(socket, error)
        end
      end
    else
      {:error, denied} -> deny(socket, denied)
      _ -> error_flash(socket, error)
    end
  end

  defp property_failure(socket, _, _, _, error) do
    case Scope.verify(socket) do
      {:ok, scope} -> error_flash(assign(socket, :scope, scope), error)
      {:error, denied} -> deny(socket, denied)
    end
  end

  defp load_connections(%{assigns: %{scope: %{room: room}}} = socket) when is_pid(room) do
    if Process.alive?(room) do
      model = safe(fn -> Room.connections(room) end, socket.assigns.connection_state)
      assign(socket, :connection_state, model)
    else
      assign(socket, :connection_state, Connections.new([]))
    end
  end

  defp load_connections(socket), do: assign(socket, :connection_state, Connections.new([]))

  defp edit_connection(socket, port, mode) do
    with {:ok, scope} <- Scope.verify(socket),
         true <- is_pid(scope.room) and Process.alive?(scope.room) do
      socket =
        socket
        |> assign(:scope, scope)
        |> refresh()

      existing = socket.assigns.connection_draft

      retain? =
        (mode == :retain and socket.assigns.connection_room == scope.room and existing) &&
          existing["port"] == port

      with {:ok, draft} <-
             if(retain?,
               do: {:ok, existing},
               else: Connections.draft(socket.assigns.connection_state, socket.assigns.things, port)
             ) do
        error =
          case Connections.change(socket.assigns.connection_state, socket.assigns.things, draft) do
            {:ok, _} -> nil
            {:error, error} -> error
          end

        {:ok,
         socket
         |> assign(
           connection_draft: draft,
           connection_room: scope.room,
           connection_editing: true,
           connection_error: error,
           connections_open: true,
           sidebar_open: false
         )
         |> push_patch(to: "/things?panel=connections")}
      end
    else
      {:error, error} -> {:error, error}
      _ -> {:error, Error.new(:no_room, :connections, "Start a room first")}
    end
  end

  defp connection_form(raw) when is_map(raw) and not is_struct(raw) do
    fields = Map.new(~w(affordance port revision thing), &{&1, true})

    if map_size(raw) <= 8 and Enum.all?(raw, &draft_entry?(&1, fields, raw)),
      do: Map.take(raw, Map.keys(fields)),
      else: raw
  end

  defp connection_form(raw), do: raw

  defp connection_choice(raw, ["connection", "thing"], things) do
    options = Enum.filter(Connections.options(things, raw["port"]), &(&1.thing == raw["thing"]))

    case Enum.find(options, &(&1.affordance == raw["affordance"])) || List.first(options) do
      nil -> raw
      option -> Map.put(raw, "affordance", option.affordance)
    end
  end

  defp connection_choice(raw, _, _), do: raw

  defp configure_connection(socket, operation, raw) do
    socket =
      if operation == :apply and Connections.draft?(raw),
        do: assign(socket, :connection_draft, raw),
        else: socket

    initial =
      case operation do
        :apply -> Connections.change(socket.assigns.connection_state, socket.assigns.things, raw)
        :remove -> Connections.remove(socket.assigns.connection_state, raw)
      end

    with {:ok, _} <- initial,
         {:ok, scope} <- Scope.admit(socket, :configure),
         true <- is_pid(scope.room) and Process.alive?(scope.room),
         true <- scope.room == socket.assigns.connection_room,
         {:ok, _} <- Room.configure_connection(scope.room, operation, raw) do
      {:noreply,
       socket
       |> assign(
         scope: scope,
         connection_draft: nil,
         connection_editing: false,
         connection_error: nil,
         connection_focus: raw["port"]
       )
       |> refresh()
       |> revise_islands()
       |> put_flash(
         :info,
         if(operation == :remove, do: "Connection removed", else: "Connection applied")
       )}
    else
      {:error, error} ->
        connection_failure(socket, error)

      _ ->
        connection_failure(
          socket,
          Error.new(:room_changed, :connections, "Room changed. Reopen the connection")
        )
    end
  end

  defp connection_failure(socket, error) do
    case Scope.verify(socket) do
      {:ok, scope} ->
        {:noreply,
         socket
         |> assign(scope: scope, connection_error: error)
         |> load_connections()}

      {:error, denied} ->
        {:noreply, deny(socket, denied)}
    end
  end

  defp connection_error,
    do: Error.new(:invalid_connection, :connections, "Connection parameters are malformed")

  defp connection_focus(%{assigns: %{connection_draft: %{"port" => port}}}), do: port
  defp connection_focus(_), do: nil

  defp perform_thing_operation(socket, "read", key, name) do
    with {:ok, scope} <- Scope.admit(socket, :read),
         {:ok, result} <- Room.read_property(scope.room, key, name),
         {:ok, result} <- admit_reading(result) do
      state =
        if Map.has_key?(socket.assigns.observations, key <> "/" <> name), do: :waiting, else: :read

      {:ok,
       socket
       |> refresh()
       |> update(:canvas_readings, &ThingReadings.put(&1, receipt(result, state)))}
    end
  end

  defp perform_thing_operation(socket, "observe", key, name) do
    identity = key <> "/" <> name

    if Map.has_key?(socket.assigns.observations, identity) do
      {:ok, socket}
    else
      with {:ok, scope} <- Scope.admit(socket, :observe),
           {:ok, watch} <- Room.observe_property(scope.room, key, name, self()) do
        with {:ok, result} <- Room.read_property(scope.room, key, name),
             {:ok, result} <- admit_reading(result) do
          watch = Map.merge(watch, %{monitor: Process.monitor(watch.pid), room: scope.room})

          {:ok,
           socket
           |> refresh()
           |> update(:observations, &Map.put(&1, identity, watch))
           |> update(:canvas_readings, &ThingReadings.put(&1, receipt(result, :waiting)))}
        else
          {:error, error} ->
            Wotex.Runtime.Subscription.stop(watch.pid)
            {:error, error}
        end
      end
    end
  end

  defp perform_thing_operation(socket, "pause", key, name),
    do: {:ok, finish_observation(socket, key <> "/" <> name, :paused)}

  defp admit_reading(%{value: value} = result)
       when is_number(value) and value >= -1.0e100 and value <= 1.0e100, do: {:ok, result}

  defp admit_reading(_),
    do:
      {:error,
       Error.new(
         :invalid_property_reading,
         :things,
         "Reference Property requires a bounded numeric value"
       )}

  defp receipt(result, state) do
    Map.merge(result, %{
      state: state,
      read_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      received_ms: System.monotonic_time(:millisecond)
    })
  end

  defp receive_observation(socket, key, watch, event) do
    with {:ok, scope} <- Scope.verify(socket),
         true <- scope.room == watch.room do
      socket = assign(socket, :scope, scope)

      socket =
        case event do
          {:ok, value, _} when is_number(value) and value >= -1.0e100 and value <= 1.0e100 ->
            reading =
              receipt(
                %{
                  thing: watch.thing,
                  property: watch.property,
                  value: value,
                  status: :ok,
                  source: :observation
                },
                :live
              )

            update(socket, :canvas_readings, &ThingReadings.put(&1, reading))

          {:status, :reconnected} ->
            socket

          {:status, _} ->
            finish_observation(socket, key, :disconnected)

          _ ->
            finish_observation(socket, key, :error)
        end

      socket = refresh_thing_stats(socket, watch.room)
      {:noreply, revise_islands(socket)}
    else
      {:error, error} ->
        {:noreply, deny(socket, error)}

      _ ->
        socket =
          socket
          |> stop_observations()
          |> refresh()

        {:noreply, revise_islands(socket)}
    end
  end

  defp finish_observation(socket, key, state) do
    {watch, observations} = Map.pop(socket.assigns.observations, key)

    if watch do
      Process.demonitor(watch.monitor, [:flush])
      Wotex.Runtime.Subscription.stop(watch.pid)
    end

    socket = if watch, do: refresh_thing_stats(socket, watch.room), else: socket

    socket
    |> assign(:observations, observations)
    |> update(:canvas_readings, fn readings ->
      if Map.has_key?(readings, key), do: put_in(readings, [key, :state], state), else: readings
    end)
  end

  defp stop_observations(socket) do
    Enum.reduce(Map.keys(socket.assigns.observations), socket, &finish_observation(&2, &1, :paused))
  end

  defp refresh_thing_stats(%{assigns: %{scope: %{room: room}}} = socket, room) when is_pid(room) do
    if Process.alive?(room),
      do: assign(socket, :things, safe(fn -> Room.things(room) end, socket.assigns.things)),
      else: socket
  end

  defp refresh_thing_stats(socket, _), do: socket

  defp apply_effect(socket, nil), do: socket
  defp apply_effect(socket, {:assign, key, value}), do: assign(socket, key, value)

  defp apply_effect(socket, {:navigate, path}), do: push_patch(socket, to: path)

  defp apply_effect(socket, {:history, history}),
    do: assign(socket, history: history, history_range: history.range)

  defp apply_effect(socket, {:metric_result, result, draft, room}),
    do: assign(socket, metric_result: result, metric_draft: draft, metric_room: room)

  defp apply_effect(socket, {:insights, insights}),
    do: assign(socket, insights: insights, charts: insights.charts)

  defp resync_island(socket, instance_id) do
    with {:ok, scope} <- Scope.verify(socket),
         {:ok, descriptor} <- island_descriptor(socket, scope.session_id, instance_id),
         {:ok, snapshot} <- Islands.snapshot(descriptor, socket.assigns.island_revision) do
      {:noreply,
       socket
       |> assign(:scope, scope)
       |> push_event("wotex:island:#{instance_id}:snapshot", snapshot)}
    else
      {:error, %Error{} = error} -> {:reply, %{"status" => "rejected"}, deny(socket, error)}
      _ -> {:reply, %{"status" => "rejected"}, socket}
    end
  end

  defp admit_island_event(socket, instance_id, payload) do
    with {:ok, scope} <- Scope.verify(socket),
         {:ok, descriptor} <- island_descriptor(socket, scope.session_id, instance_id),
         true <- payload["client_revision"] == to_string(socket.assigns.island_revision),
         {:ok, event} <- Islands.validate_event(descriptor.component, instance_id, payload) do
      acknowledge_island_event(assign(socket, :scope, scope), descriptor.component, event)
    else
      {:error, %Error{} = error} -> {:reply, %{"status" => "rejected"}, deny(socket, error)}
      _ -> {:reply, %{"status" => "rejected"}, socket}
    end
  end

  defp acknowledge_island_event(socket, "canvas", %{
         "event" => "inspect_connection",
         "payload" => %{"id" => id}
       }) do
    case edit_connection(socket, id, :retain) do
      {:ok, socket} -> {:reply, %{"status" => "accepted"}, socket}
      _ -> {:reply, %{"status" => "rejected"}, socket}
    end
  end

  defp acknowledge_island_event(socket, "canvas", %{
         "event" => "propose_connection",
         "payload" => %{"connection" => raw}
       }) do
    with {:ok, scope} <- Scope.verify(socket),
         true <- is_pid(scope.room) and Process.alive?(scope.room) do
      socket =
        socket
        |> assign(:scope, scope)
        |> refresh()

      ids = canvas_ids(socket)

      with true <- is_map(raw) and raw["source"] in ids and raw["target"] in ids,
           {:ok, draft} <-
             Connections.gesture(socket.assigns.connection_state, socket.assigns.things, raw) do
        {:reply, %{"status" => "accepted"},
         socket
         |> assign(
           connection_draft: draft,
           connection_room: scope.room,
           connection_editing: true,
           connection_error: nil,
           connections_open: true,
           sidebar_open: false
         )
         |> push_patch(to: "/things?panel=connections")}
      else
        _ -> {:reply, %{"status" => "rejected"}, socket}
      end
    else
      _ -> {:reply, %{"status" => "rejected"}, socket}
    end
  end

  defp acknowledge_island_event(socket, "canvas", %{
         "event" => "inspect",
         "payload" => %{"id" => id}
       }) do
    case select_canvas_node(socket, id) do
      {:ok, socket} -> {:reply, %{"status" => "accepted"}, socket}
      {:error, error} -> {:reply, %{"status" => "rejected"}, deny(socket, error)}
      :error -> {:reply, %{"status" => "rejected"}, socket}
    end
  end

  defp acknowledge_island_event(socket, "canvas", %{"event" => "open", "payload" => %{"id" => id}}) do
    case open_canvas_tool(socket, id) do
      {:ok, socket} -> {:reply, %{"status" => "accepted"}, socket}
      {:error, error} -> {:reply, %{"status" => "rejected"}, deny(socket, error)}
      :error -> {:reply, %{"status" => "rejected"}, socket}
    end
  end

  defp acknowledge_island_event(socket, "canvas", %{"event" => event, "payload" => %{"id" => id}})
       when event in ~w(read observe pause statistics sources) do
    case Enum.find(socket.assigns.things, &(Canvas.id(&1) == id)) do
      nil ->
        {:reply, %{"status" => "rejected"}, socket}

      thing ->
        result =
          if event in ~w(statistics sources) do
            case select_canvas_node(socket, id) do
              {:ok, socket} ->
                {:ok,
                 assign(
                   socket,
                   :thing_panel,
                   if(event == "statistics", do: :statistics, else: :sources)
                 )}

              error ->
                error
            end
          else
            thing_operation(socket, event, thing.key, ThingProperties.primary(thing))
          end

        case result do
          {:ok, socket} ->
            socket = assign(socket, :canvas_selection, id)
            {:reply, %{"status" => "accepted"}, revise_islands(socket)}

          {:error, error} ->
            {:reply, %{"status" => "rejected", "feedback" => "host"},
             property_failure(socket, event, thing.key, ThingProperties.primary(thing), error)}

          _ ->
            {:reply, %{"status" => "rejected"}, socket}
        end
    end
  end

  defp acknowledge_island_event(socket, "canvas", %{
         "event" => "open_documentation",
         "payload" => %{"view" => %{"layout" => layout, "selection" => selected} = view}
       })
       when map_size(view) == 2 do
    ids = canvas_ids(socket)

    with true <- selected == "" or selected in ids,
         {:ok, _} <- Board.change(socket.assigns.board, {:layout, layout, ids}),
         {:ok, socket} <-
           retain_presentation(socket, layout, if(selected == "", do: nil, else: selected)) do
      {:reply, %{"status" => "accepted"}, socket}
    else
      {:error, error} -> rejected_island(socket, error)
      _ -> {:reply, %{"status" => "rejected"}, socket}
    end
  end

  defp acknowledge_island_event(socket, "canvas", %{"event" => "open_documentation"}),
    do: {:reply, %{"status" => "rejected"}, socket}

  defp acknowledge_island_event(socket, "canvas", %{
         "event" => "save_layout",
         "payload" => %{"layout" => layout}
       }) do
    ids =
      Enum.map(
        Canvas.props(
          socket.assigns.things,
          socket.assigns.runs,
          socket.assigns.canvas_readings,
          nil,
          socket.assigns.connection_state
        )[
          "nodes"
        ],
        & &1["id"]
      )

    case change_board(socket, {:layout, layout, ids}) do
      {:ok, socket} -> {:reply, %{"status" => "accepted"}, socket}
      {:error, error} -> rejected_island(socket, error)
    end
  end

  defp acknowledge_island_event(socket, "canvas", %{"event" => event, "payload" => %{"id" => id}})
       when event in ~w(pin_refresh pin_pause pin_resume pin_remove pin_open_run) do
    case pin_action(socket, event, id) do
      {:ok, socket} -> {:reply, %{"status" => "accepted"}, socket}
      {:error, error} -> rejected_island(socket, error)
    end
  end

  defp acknowledge_island_event(socket, _, %{"command_id" => nil}) do
    {:reply, %{"status" => "accepted"}, socket}
  end

  defp acknowledge_island_event(socket, _, %{"command_id" => command_id}) do
    if command_id in socket.assigns.island_commands do
      {:reply, %{"status" => "duplicate"}, socket}
    else
      commands = Enum.take([command_id | socket.assigns.island_commands], 64)
      {:reply, %{"status" => "accepted"}, assign(socket, :island_commands, commands)}
    end
  end

  defp rejected_island(socket, error) do
    {:noreply, socket} = reject_event(socket, error)
    {:reply, %{"status" => "rejected"}, socket}
  end

  defp island_descriptor(socket, session_id, instance_id) do
    contextual =
      case socket.assigns.live_action do
        :run ->
          chart_descriptors(socket.assigns.charts, session_id)

        :metrics ->
          [metric_grid_descriptor(socket.assigns.metrics, session_id)]

        _ ->
          []
      end

    canvas = %{
      component: "canvas",
      id: Islands.id(session_id, "connected-things"),
      props:
        Canvas.props(
          socket.assigns.things,
          socket.assigns.runs,
          socket.assigns.canvas_readings,
          socket.assigns.canvas_selection,
          socket.assigns.connection_state
        )
        |> Board.decorate(socket.assigns.board, socket.assigns.active_pins)
    }

    descriptors = [canvas | contextual]

    case Enum.find(descriptors, &(&1 && &1.id == instance_id)) do
      nil -> {:error, :unknown_island}
      descriptor -> {:ok, descriptor}
    end
  end

  defp select_canvas_node(socket, "pin-" <> _ = id) do
    with {:ok, scope} <- Scope.verify(socket),
         {:ok, board} <- Sessions.board(scope.token),
         {:ok, _} <- Board.fetch(board, id) do
      {:ok,
       socket
       |> assign(scope: scope, board: board, selected_pin: id, board_search_result: nil)
       |> push_patch(to: "/metrics?" <> Query.encode(%{"pin" => id}))}
    else
      {:error, %Error{code: :unknown_pin}} -> :error
      {:error, error} -> {:error, error}
    end
  end

  defp select_canvas_node(socket, id) when is_binary(id) do
    case Scope.verify(socket) do
      {:ok, scope} ->
        socket =
          socket
          |> assign(:scope, scope)
          |> assign(:board_search_result, nil)
          |> refresh()

        props =
          Canvas.props(
            socket.assigns.things,
            socket.assigns.runs,
            socket.assigns.canvas_readings,
            nil,
            socket.assigns.connection_state
          )

        if Enum.any?(props["nodes"], &(&1["id"] == id)) do
          socket =
            socket
            |> assign(:canvas_selection, id)
            |> revise_islands()

          socket =
            cond do
              id == "process-smart-room" ->
                push_patch(socket, to: "/experiments?experiment=smart_room")

              socket.assigns.live_action == :things and not socket.assigns.connections_open and
                  not socket.assigns.board_search_open ->
                socket

              true ->
                push_patch(socket, to: "/things")
            end

          {:ok, socket}
        else
          :error
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp select_canvas_node(_, _), do: :error

  defp open_canvas_tool(socket, tool) when tool in ~w(add connections experiments metrics) do
    case Scope.verify(socket) do
      {:ok, scope} ->
        path =
          case tool do
            "add" ->
              "/things?panel=import"

            "connections" ->
              "/things?panel=connections"

            "experiments" ->
              "/experiments?" <> Query.encode(%{"experiment" => socket.assigns.selected_experiment})

            "metrics" ->
              "/metrics"
          end

        {:ok,
         socket
         |> assign(
           scope: scope,
           sidebar_open: false,
           connection_editing: false,
           connections_open: tool == "connections",
           board_search_result: nil
         )
         |> push_patch(to: path)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp open_canvas_tool(_, _), do: :error

  defp chart_descriptors(charts, session_id) do
    charts
    |> Enum.with_index()
    |> Enum.map(fn {chart, index} ->
      %{
        component: "chart",
        id: Islands.id(session_id, "run-chart-#{index}"),
        props: Islands.chart_props(chart)
      }
    end)
  end

  defp metric_grid_descriptor(nil, _), do: nil

  defp metric_grid_descriptor(metrics, session_id) do
    {columns, rows} = metric_grid(metrics)

    %{
      component: "data-grid",
      id: Islands.id(session_id, "metric-samples"),
      props: Islands.data_grid_props("Bounded session metric samples", columns, rows)
    }
  end

  defp metric_grid(nil), do: {[], []}

  defp metric_grid(metrics) do
    columns = [
      %{"key" => "sequence", "label" => "Sequence"},
      %{"key" => "event", "label" => "Event"},
      %{"key" => "duration", "label" => "Duration"},
      %{"key" => "outcome", "label" => "Outcome"}
    ]

    rows =
      metrics.samples
      |> Enum.take(100)
      |> Enum.map(fn row ->
        %{
          "key" => "sample-#{row.sequence}",
          "values" => %{
            "sequence" => to_string(row.sequence),
            "event" => "#{row.component}.#{row.operation}.#{row.event}",
            "duration" =>
              if(is_nil(row.duration_ms), do: "not measured", else: "#{row.duration_ms} ms"),
            "outcome" => to_string(row.outcome || "none")
          }
        }
      end)

    {columns, rows}
  end

  defp revise_islands(socket), do: update(socket, :island_revision, &(&1 + 1))

  defp selected_pin(board, id) do
    case Board.fetch(board, id) do
      {:ok, pin} -> pin
      _ -> nil
    end
  end

  defp run_pin?(board, id), do: match?(%{kind: :run}, selected_pin(board, id))

  defp metric_draft(params) when is_map(params) do
    keys = Map.keys(params) -- ~w(_target _unused_metric _unused_range)
    target? = not Map.has_key?(params, "_target") or params["_target"] in [["metric"], ["range"]]

    unused? =
      Enum.all?(
        ~w(_unused_metric _unused_range),
        &(not Map.has_key?(params, &1) or params[&1] == "")
      )

    with true <- Enum.sort(keys) == ~w(metric range) and target? and unused?,
         true <- params["range"] in HistoryPanels.ranges(),
         {:ok, [_]} <- Panels.select([params["metric"]]) do
      {:ok, %{metric: params["metric"], range: params["range"]}}
    else
      _ ->
        {:error,
         Error.new(:invalid_metric_query, :metrics, "Choose a catalogue metric and supported range")}
    end
  end

  defp metric_draft(_),
    do: {:error, Error.new(:invalid_metric_query, :metrics, "Query is malformed")}

  defp load_board(%{assigns: %{scope: %{token: token, room: room}}} = socket) do
    case Sessions.board(token) do
      {:ok, board} ->
        board =
          if socket.assigns.presentation_layout != nil and
               socket.assigns.presentation_revision == board.revision do
            %{board | layout: socket.assigns.presentation_layout}
          else
            board
          end

        active =
          if socket.assigns.board_room == room, do: socket.assigns.active_pins, else: MapSet.new()

        eligible = MapSet.new(for pin <- board.pins, not pin.paused, do: pin.id)

        socket =
          assign(socket,
            board: board,
            board_room: room,
            property_errors:
              if(socket.assigns.board_room == room, do: socket.assigns.property_errors, else: %{}),
            active_pins: MapSet.intersection(active, eligible)
          )

        if socket.assigns.metric_room in [nil, room],
          do: socket,
          else: assign(socket, metric_result: nil, metric_room: nil)

      _ ->
        assign(socket, board: Board.empty(), active_pins: MapSet.new())
    end
  end

  defp load_board(socket), do: socket

  defp change_board(socket, operation) do
    with {:ok, scope} <- Scope.verify(socket),
         {:ok, board} <- Sessions.change_board(scope.token, scope.room, operation) do
      {:ok,
       socket
       |> assign(scope: scope, board: board)
       |> revise_islands()}
    end
  end

  defp pin_action(socket, event, id) do
    with {:ok, scope} <- Scope.verify(socket),
         {:ok, board} <- Sessions.board(scope.token),
         {:ok, pin} <- Board.fetch(board, id) do
      socket
      |> assign(scope: scope, board: board)
      |> apply_pin_action(pin, event)
    end
  end

  defp apply_pin_action(socket, %{kind: :run, error: nil} = pin, "pin_open_run"),
    do: {:ok, push_patch(socket, to: pin.path)}

  defp apply_pin_action(_, %{kind: :run}, event) when event != "pin_remove",
    do:
      {:error,
       Error.new(:invalid_board_operation, :workbench, "Captured Run pins cannot refresh or resume")}

  defp apply_pin_action(_, _, "pin_open_run"),
    do: {:error, Error.new(:invalid_board_operation, :workbench, "Choose a captured Run pin")}

  defp apply_pin_action(socket, pin, event) do
    id = pin.id

    case event do
      "pin_remove" ->
        with {:ok, socket} <- change_board(socket, {:remove, id}) do
          socket = update(socket, :active_pins, &MapSet.delete(&1, id))

          {:ok,
           if(socket.assigns.selected_pin == id, do: push_patch(socket, to: "/"), else: socket)}
        end

      "pin_pause" ->
        with {:ok, socket} <- change_board(socket, {:pause, id, true}) do
          {:ok, update(socket, :active_pins, &MapSet.delete(&1, id))}
        end

      "pin_resume" ->
        with {:ok, scope} <- Scope.admit(socket, :query),
             {:ok, socket} <- change_board(assign(socket, :scope, scope), {:pause, id, false}) do
          socket = update(socket, :active_pins, &MapSet.put(&1, id))
          {:ok, start_pin_refresh(socket, [pin])}
        end

      "pin_refresh" ->
        with {:ok, scope} <- Scope.admit(socket, :query),
             do: {:ok, start_pin_refresh(assign(socket, :scope, scope), [pin])}
    end
  end

  defp start_pin_refresh(%{assigns: %{pin_refresh_running: true}} = socket, _), do: socket
  defp start_pin_refresh(socket, []), do: socket

  defp start_pin_refresh(socket, pins) do
    case room_history(socket.assigns.scope.room) do
      {:ok, binding} ->
        rotation = socket.assigns.pin_refresh_rotation

        socket
        |> assign(
          pin_refresh_running: true,
          pin_refresh_room: socket.assigns.scope.room,
          pin_refresh_rotation: rotation + 1
        )
        |> start_async(:pin_refresh, fn -> BoardHistory.load(binding, pins, rotation) end)

      {:error, _} ->
        socket
    end
  end

  defp refresh(%{assigns: %{scope: %{room: room, session_id: session_id}}} = socket)
       when is_pid(room) do
    socket = load_board(socket)

    if Process.alive?(room) do
      runs = safe(fn -> Room.runs(room) end, [])
      things = safe(fn -> Room.things(room) end, [])
      snapshot = safe(fn -> Room.snapshot(room) end, nil)

      metrics =
        case Metrics.query(scope: session_id, limit: 2_000) do
          {:ok, result} -> result
          {:error, :unavailable} -> nil
        end

      socket
      |> assign(:runs, runs)
      |> assign(:things, things)
      |> load_connections()
      |> assign(:snapshot, snapshot)
      |> assign(:metrics, metrics)
      |> reload_run()
    else
      empty_room(socket)
    end
  end

  defp refresh(socket), do: empty_room(load_board(socket))

  defp empty_room(socket) do
    socket
    |> stop_observations()
    |> assign(:runs, [])
    |> assign(:things, [])
    |> assign(:connection_state, Connections.new([]))
    |> assign(:snapshot, nil)
    |> assign(:metrics, nil)
    |> assign(:history, nil)
    |> assign(:run, nil)
    |> assign(:charts, [])
    |> assign(:insights, nil)
    |> assign(:canvas_readings, %{})
    |> assign(:property_errors, %{})
    |> assign(:metric_result, nil)
    |> assign(:metric_room, nil)
    |> assign(:investigation_results, [])
    |> assign(:investigation_room, nil)
    |> assign(:answer, nil)
    |> assign(:active_pins, MapSet.new())
    |> update(:board, &Board.clear_results/1)
  end

  defp load_action(socket, :run, %{"id" => id} = params) do
    socket =
      if socket.assigns[:run_id] != id,
        do: assign(socket, answer: nil, investigation_results: []),
        else: socket

    socket =
      socket
      |> assign(:run_id, id)
      |> refresh()
      |> reload_run()

    case RunPresentation.view(params) do
      {:ok, view} ->
        socket = assign(socket, run_view: view, run_clock: System.monotonic_time(:millisecond))

        if Map.has_key?(params, "analysis"),
          do: load_analysis(socket, params["analysis"]),
          else: socket

      {:error, error} ->
        error_flash(assign(socket, :run_view, :result), error)
    end
  end

  defp load_action(socket, :experiments, params) do
    selected =
      case params do
        %{} when map_size(params) == 0 ->
          {:ok, socket.assigns.selected_experiment}

        %{"experiment" => id} when map_size(params) == 1 ->
          with {:ok, experiment} <- Experiments.fetch(id), do: {:ok, experiment.id}

        _ ->
          {:error, Error.new(:invalid_parameters, :admission, "experiment link is malformed")}
      end

    socket =
      socket
      |> assign(:run_id, nil)
      |> refresh()

    case selected do
      {:ok, id} -> assign(socket, :selected_experiment, id)
      {:error, error} -> error_flash(socket, error)
    end
  end

  defp load_action(socket, :things, %{"panel" => "connections"} = params)
       when map_size(params) == 1 do
    socket
    |> assign(run_id: nil, connections_open: true)
    |> refresh()
  end

  defp load_action(socket, :things, %{"panel" => "search"} = params)
       when map_size(params) == 1 do
    socket
    |> assign(run_id: nil, board_search_open: true)
    |> refresh()
  end

  defp load_action(socket, :things, %{"panel" => "import"} = params) when map_size(params) == 1 do
    socket
    |> assign(run_id: nil, canvas_selection: "import")
    |> refresh()
  end

  defp load_action(socket, :things, params) when map_size(params) == 0,
    do:
      socket
      |> assign(:run_id, nil)
      |> refresh()

  defp load_action(socket, :things, _) do
    socket
    |> assign(run_id: nil, canvas_selection: nil)
    |> refresh()
    |> error_flash(Error.new(:invalid_parameters, :admission, "Thing link is malformed"))
  end

  defp load_action(socket, :metrics, params) do
    selected =
      case params do
        %{} when map_size(params) == 0 ->
          {:ok, socket.assigns.scope.dashboard_panels}

        %{"panels" => panel_ids, "selection" => "custom"} when map_size(params) == 2 ->
          with {:ok, panels} <- Panels.select(panel_ids), do: {:ok, Enum.map(panels, & &1.id)}

        %{"pin" => id} when map_size(params) == 1 ->
          with {:ok, board} <- Sessions.board(socket.assigns.scope.token),
               {:ok, _} <- Board.fetch(board, id),
               do: {:ok, socket.assigns.scope.dashboard_panels}

        _ ->
          {:error, Error.new(:invalid_panels, :metrics, "metric deep link is not admitted")}
      end

    case selected do
      {:ok, panel_ids} ->
        socket
        |> assign(:run_id, nil)
        |> assign(:selected_pin, params["pin"])
        |> assign(:dashboard_panels, panel_ids)
        |> assign(:history, nil)
        |> refresh()

      {:error, error} ->
        socket
        |> assign(:run_id, nil)
        |> assign(:selected_pin, params["pin"])
        |> assign(:dashboard_panels, socket.assigns.scope.dashboard_panels)
        |> refresh()
        |> error_flash(error)
    end
  end

  defp load_action(socket, :evidence, params) do
    case params do
      %{} when map_size(params) == 0 ->
        socket
        |> assign(run_id: nil, evidence_selected: false)
        |> refresh()

      %{"run" => id} when map_size(params) == 1 and is_binary(id) and byte_size(id) <= 128 ->
        socket
        |> assign(run_id: id, evidence_selected: true)
        |> refresh()

      _ ->
        socket
        |> assign(run_id: nil, evidence_selected: true)
        |> refresh()
        |> error_flash(Error.new(:invalid_parameters, :admission, "evidence link is malformed"))
    end
  end

  defp load_action(socket, :workbench, _),
    do: refresh(assign(socket, run_id: nil, board_search_result: nil))

  defp load_action(socket, _, _), do: refresh(assign(socket, :run_id, nil))

  defp dashboard_path(panel_ids) do
    "/metrics?" <> Query.encode(%{"panels" => panel_ids, "selection" => "custom"})
  end

  defp load_analysis(%{assigns: %{run: %Run{} = run}} = socket, params) do
    case Insights.analyze(run, params) do
      {:ok, insights} -> apply_effect(socket, {:insights, insights})
      {:error, error} -> error_flash(socket, error)
    end
  end

  defp load_analysis(socket, _), do: socket

  defp chart_path(run, nil, index), do: "/runs/#{URI.encode(run.id)}#run-chart-#{index}"

  defp chart_path(_, insights, index),
    do: Insights.path(insights) <> "#run-chart-#{index}"

  defp refresh_run_state(%{assigns: %{live_action: action, scope: %{room: room}}} = socket)
       when action in [:run, :evidence] and is_pid(room) do
    socket
    |> assign(:runs, safe(fn -> Room.runs(room) end, []))
    |> reload_run()
  end

  defp refresh_run_state(%{assigns: %{live_action: action, scope: %{room: nil}}} = socket)
       when action in [:run, :evidence],
       do: empty_room(socket)

  defp refresh_run_state(socket), do: socket

  defp reload_run(%{assigns: %{run_id: id, scope: %{room: room}}} = socket)
       when is_binary(id) and is_pid(room) do
    case safe(fn -> Room.fetch_run(room, id) end, {:error, :unavailable}) do
      {:ok, run} ->
        case socket.assigns.insights do
          %{run_id: run_id} = insights when run_id == run.id ->
            assign(socket, run: run, charts: insights.charts)

          _ ->
            assign(socket, run: run, charts: RunPresentation.charts(run), insights: nil)
        end

      {:error, _} ->
        assign(socket, run: nil, charts: [], insights: nil)
    end
  end

  defp reload_run(socket), do: assign(socket, run: nil, charts: [])

  defp canvas_ids(socket) do
    props =
      Canvas.props(
        socket.assigns.things,
        socket.assigns.runs,
        socket.assigns.canvas_readings,
        nil,
        socket.assigns.connection_state
      )

    Enum.map(props["nodes"], & &1["id"]) ++ Enum.map(socket.assigns.board.pins, & &1.id)
  end

  defp retain_presentation(socket, layout, selection) do
    with {:ok, scope} <- Scope.verify(socket),
         true <- scope.room == socket.assigns.board_room do
      assigns = socket.assigns

      value = %{
        path: assigns.presentation_path,
        layout: layout,
        experiment_forms: assigns.experiment_forms,
        selected_experiment: assigns.selected_experiment,
        canvas_readings: ThingReadings.pause(assigns.canvas_readings),
        canvas_selection: selection,
        metric_draft: assigns.metric_draft,
        prompt: assigns.investigation.prompt,
        metric_result: assigns.metric_result,
        answer: assigns.answer,
        investigation_results: assigns.investigation_results,
        connection_draft: assigns.connection_draft,
        connection_editing: assigns.connection_editing
      }

      with :ok <- Sessions.put_presentation(scope.token, scope.room, value),
           do: {:ok, finish_presentation(socket, scope)}
    else
      false -> {:error, Error.new(:room_changed, :session, "Room changed; reopen documentation")}
      error -> error
    end
  end

  defp finish_presentation(socket, scope) do
    socket
    |> stop_observations()
    |> assign(:scope, scope)
    |> cancel_investigation_on_navigation()
  end

  defp restore_presentation(%{assigns: %{scope: %{token: token, room: room}}} = socket) do
    mode = if connected?(socket), do: :take, else: :read

    case Sessions.presentation(token, mode) do
      {:ok, value} when is_map(value) ->
        socket
        |> assign(
          Map.take(
            value,
            ~w(experiment_forms selected_experiment canvas_readings canvas_selection metric_draft metric_result answer investigation_results connection_draft connection_editing)a
          )
        )
        |> assign(
          presentation_layout: value.layout,
          presentation_revision: socket.assigns.board.revision,
          board: %{socket.assigns.board | layout: value.layout || socket.assigns.board.layout},
          investigation: %{investigation_state() | prompt: value.prompt},
          investigation_room: room,
          metric_room: room,
          connection_room: room
        )

      _ ->
        socket
    end
  end

  defp restore_presentation(socket), do: socket

  defp workbench_path(url) do
    uri = URI.parse(url)
    path = uri.path <> if(uri.query, do: "?" <> uri.query, else: "")
    if WotexLabWorkbench.Presentation.path?(path), do: path, else: "/"
  end

  defp investigation_context(socket, scope) do
    runs = safe(fn -> Room.runs(scope.room) end, [])
    selected_id = if(socket.assigns.live_action in [:run, :evidence], do: socket.assigns[:run_id])

    case RunContext.select(runs, selected_id) do
      {:error, :no_run} when socket.assigns.live_action == :metrics -> {:ok, nil, nil}
      other -> other
    end
  end

  defp cancel_investigation_on_navigation(
         %{assigns: %{investigation: %{state: :running, request: request}}} = socket
       ) do
    _ = Broker.cancel(request)

    socket
    |> assign(:investigation, %{investigation_state() | prompt: socket.assigns.investigation.prompt})
    |> assign(answer: nil, investigation_results: [], investigation_room: nil)
  end

  defp cancel_investigation_on_navigation(socket), do: socket

  defp investigation_state do
    case Broker.status() do
      %{running: true} -> %{state: :busy, request: nil, prompt: ""}
      %{running: false} -> %{state: :idle, request: nil, prompt: ""}
      _ -> %{state: :disabled, request: nil, prompt: ""}
    end
  end

  defp prompt_reason(%{state: :running}, _),
    do: "Read-only investigation running; leaving this view cancels its owner-bound worker."

  defp prompt_reason(%{state: :idle}, true),
    do: "Trusted-local only; one bounded read-only investigation, with no Action capability."

  defp prompt_reason(%{state: :idle}, false),
    do: "Run an experiment before asking about its evidence."

  defp prompt_reason(%{state: :busy}, _),
    do: "Another trusted-local investigation is running; this host does not queue prompts."

  defp prompt_reason(_, _),
    do: "No investigation provider is configured."

  defp investigation_failure(socket, reason) do
    answer = Answer.from_result({:error, reason}, provider_status())
    investigation = %{investigation_state() | prompt: socket.assigns.investigation.prompt}
    assign(socket, answer: answer, investigation: investigation, investigation_results: [])
  end

  defp valid_prompt?(prompt),
    do:
      is_binary(prompt) and String.valid?(prompt) and byte_size(prompt) <= 4_096 and
        String.length(prompt) <= 512

  defp put_prompt(socket, prompt),
    do: assign(socket, :investigation, %{socket.assigns.investigation | prompt: prompt})

  defp admit_prompt(prompt),
    do:
      if(valid_prompt?(prompt) and String.trim(prompt) != "",
        do: :ok,
        else: {:error, :invalid_prompt}
      )

  defp investigation_available do
    case Broker.status() do
      %{running: false} -> :ok
      %{running: true} -> {:error, :investigation_busy}
      _ -> {:error, :investigation_disabled}
    end
  end

  defp metrics_prompt_reason(%{state: :idle}, nil), do: "Start a room to ask about its metrics."
  defp metrics_prompt_reason(%{state: :idle}, _), do: "Room history · last 5 min"
  defp metrics_prompt_reason(%{state: :running}, _), do: "Investigating…"

  defp metrics_prompt_reason(%{state: :busy}, _),
    do: "Investigation busy. Edit the question to retry."

  defp metrics_prompt_reason(_, _), do: "Provider unavailable. Use Build query."

  defp investigation_results({:ok, %{metric_results: results}}) when is_list(results),
    do: Enum.take(results, 8)

  defp investigation_results(_), do: []

  defp link_metric_sources(answer, results) do
    destinations =
      for {history, index} <- Enum.with_index(results),
          panel <- history.panels,
          digest <- panel.digests,
          into: %{},
          do: {"Recorded evidence " <> digest, "#investigation-metric-#{index}"}

    %{
      answer
      | sources:
          Enum.map(answer.sources, fn source ->
            case Map.fetch(destinations, source.label) do
              {:ok, href} -> %{source | href: href}
              :error -> source
            end
          end)
    }
  end

  defp provider_status do
    Provider.status()
  catch
    :exit, _ -> %{}
  end

  defp metric_filters(params, scope) do
    with {:ok, component} <- known(params["component"], Telemetry.components()),
         {:ok, operation} <- known(params["operation"], Telemetry.operations()) do
      {:ok,
       [scope: scope, component: component, operation: operation, limit: 2_000]
       |> Enum.reject(fn {_, value} -> is_nil(value) end)}
    end
  end

  defp known(value, _) when value in [nil, ""], do: {:ok, nil}

  defp known(value, allowed) when is_binary(value) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> {:error, Error.new(:invalid_filter, :metrics, "metric filter is not admitted")}
      atom -> {:ok, atom}
    end
  end

  defp known(_, _),
    do: {:error, Error.new(:invalid_filter, :metrics, "metric filter is not admitted")}

  defp room_history(room) do
    Room.history(room)
  catch
    :exit, _ -> {:error, Error.new(:history_unavailable, :metrics, "room history is unavailable")}
  end

  defp safe(fun, fallback) do
    fun.()
  catch
    :exit, _ -> fallback
  end

  defp context(_, %Run{} = run) do
    [
      {"run", run.id},
      {"source", run.source_mode},
      {"backend", run.backend},
      {"state", Run.state_text(run)}
    ]
  end

  defp context(scope, nil),
    do: [
      {"session", scope.session_id},
      {"source", Provenance.source_mode()},
      {"backend", "none"},
      {"state", if(scope.room, do: "ready", else: "no room")}
    ]

  defp nav_item(:run), do: :experiments
  defp nav_item(action) when action in [:things, :evidence], do: :workbench
  defp nav_item(action), do: action

  defp deny(socket, %Error{code: code}) do
    socket
    |> stop_observations()
    |> assign(scope: nil, denied: Atom.to_string(code))
  end

  defp error_flash(socket, %Error{} = error),
    do: put_flash(socket, :error, "#{error.code}: #{error.message}")

  defp error_flash(socket, other),
    do: put_flash(socket, :error, "operation failed: #{inspect(other, limit: 4)}")

  defp reject_event(socket, error) do
    case Scope.verify(socket) do
      {:ok, scope} -> {:noreply, error_flash(assign(socket, :scope, scope), error)}
      {:error, denied} -> {:noreply, deny(socket, denied)}
    end
  end
end
