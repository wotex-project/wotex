defmodule WotexLabWorkbenchWeb.WorkbenchLive do
  @moduledoc """
  The single scoped LiveView for experiments, runs, Things, metrics and evidence.

  Mounting and reconnecting only read existing state. Every event revalidates
  the signed session, and commands that need a room use the session registry's
  closed admission list. Running an experiment, approving an Action, exporting
  a dataset and asking for formal evidence are separate server commands.

  Experiment drafts are bounded, local to this view and retained across
  patches and validation errors. Change and form-recovery events validate
  without allocating a room or running an experiment.
  """

  use WotexLabWorkbenchWeb, :live_view

  import WotexLabWorkbenchWeb.Components.{HistoryPanels, Insights, MetricCatalogue}

  alias Phoenix.LiveView.JS
  alias Plug.Conn.Query
  alias Wotex.Lab.{Error, Telemetry}

  alias WotexLabWorkbench.{
    Canvas,
    Chart,
    Experiments,
    Formal,
    HistoryPanels,
    Insights,
    Metrics,
    Observability.Panels,
    Provenance,
    Room,
    Run,
    Sessions
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
      |> assign(:snapshot, nil)
      |> assign(:metrics, nil)
      |> assign(:history, nil)
      |> assign(:history_range, HistoryPanels.default_range())
      |> assign(:dashboard_panels, socket.assigns.scope && socket.assigns.scope.dashboard_panels)
      |> assign(:run, nil)
      |> assign(:charts, [])
      |> assign(:insights, nil)
      |> assign(:canvas_readings, %{})
      |> assign(:canvas_selection, nil)
      |> assign(:selected_experiment, "thermal")
      |> assign(:evidence_selected, false)
      |> assign(:answer, nil)
      |> assign(:island_revision, 0)
      |> assign(:island_commands, [])
      |> assign(:investigation, investigation_state())
      |> assign(:disclosure, Disclosure.current())
      |> refresh()

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(_, _, %{assigns: %{scope: nil}} = socket), do: {:noreply, socket}

  def handle_params(params, _, socket) do
    case Scope.verify(socket) do
      {:ok, scope} ->
        socket =
          socket
          |> assign(scope: scope, sidebar_open: false)
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

  def handle_event("close_board_menu", _, socket) do
    case Scope.verify(socket) do
      {:ok, scope} -> {:noreply, assign(socket, scope: scope, sidebar_open: false)}
      {:error, error} -> {:noreply, deny(socket, error)}
    end
  end

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
    command(socket, :read, fn scope ->
      with {:ok, result} <- Room.read_property(scope.room, thing, property) do
        result = Map.put(result, :read_at, DateTime.utc_now() |> DateTime.to_iso8601())
        {:ok, scope, {:reading, result}}
      end
    end)
  end

  def handle_event("inspect_thing", %{"id" => id}, socket) do
    case select_canvas_node(socket, id) do
      {:ok, socket} -> {:noreply, socket}
      {:error, error} -> reject_event(socket, error)
      :error -> {:noreply, socket}
    end
  end

  def handle_event("close_thing", _, socket) do
    case Scope.verify(socket) do
      {:ok, scope} ->
        {:noreply,
         socket
         |> assign(scope: scope, canvas_selection: nil)
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

  def handle_event("ask", %{"prompt" => prompt}, socket) do
    with {:ok, scope} <- Scope.admit(socket, :ask),
         true <- is_pid(scope.room) and Process.alive?(scope.room),
         {:ok, current, baseline} <- investigation_context(socket, scope),
         {:ok, request} <-
           Broker.ask(prompt, run: current, baseline: baseline, room: scope.room) do
      investigation = %{state: :running, request: request, prompt: prompt}

      {:noreply,
       socket
       |> assign(:scope, scope)
       |> assign(:answer, nil)
       |> assign(:investigation, investigation)}
    else
      false ->
        {:noreply, error_flash(socket, Error.new(:no_room, :session, "room is unavailable"))}

      {:error, %Error{} = error} ->
        {:noreply, error_flash(socket, error)}

      {:error, reason} ->
        {:noreply, investigation_failure(socket, reason)}
    end
  end

  def handle_event("ask", _, socket) do
    {:noreply, investigation_failure(socket, :invalid_prompt)}
  end

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
  def handle_info(
        {:investigation, request, result},
        %{assigns: %{investigation: %{state: :running, request: request}}} = socket
      ) do
    answer = Answer.from_result(result, provider_status())
    investigation = %{state: :idle, request: nil, prompt: ""}
    {:noreply, assign(socket, answer: answer, investigation: investigation)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

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
            session_id={@scope.session_id}
            island_revision={@island_revision}
            empty={
              is_nil(@scope.room) && @live_action in [:workbench, :things] &&
                @canvas_selection != "import"
            }
          />
          <%= case @live_action do %>
            <% :experiments -> %>
              <.tool_panel id="wl-experiments-panel" title="Experiments" menu_open={@sidebar_open}>
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
                title={if @run, do: "Run #{@run.id}", else: "Run unavailable"}
                menu_open={@sidebar_open}
                return_path={experiment_path(@run)}
              >
                <.run_view
                  run={@run}
                  charts={@charts}
                  insights={@insights}
                  investigation={@investigation}
                  answer={@answer}
                  disclosure={@disclosure}
                  session_id={@scope.session_id}
                  island_revision={@island_revision}
                />
              </.tool_panel>
            <% :things -> %>
              <.things_view
                things={@things}
                room={@scope.room}
                readings={@canvas_readings}
                selection={@canvas_selection}
                menu_open={@sidebar_open}
              />
            <% :metrics -> %>
              <.tool_panel id="wl-metrics-panel" title="Metrics" menu_open={@sidebar_open}>
                <.metrics_view
                  metrics={@metrics}
                  history={@history}
                  history_range={@history_range}
                  room={@scope.room}
                  dashboard_panels={@dashboard_panels}
                  session_id={@scope.session_id}
                  island_revision={@island_revision}
                />
              </.tool_panel>
            <% :evidence -> %>
              <.tool_panel
                id="wl-evidence-panel"
                title={if @evidence_selected, do: "Run evidence", else: "Session report"}
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
  attr(:session_id, :string, required: true)
  attr(:island_revision, :integer, required: true)
  attr(:empty, :boolean, required: true)

  defp canvas_view(assigns) do
    assigns = assign(assigns, :props, Canvas.props(assigns.things, assigns.runs, assigns.readings))

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
  slot(:inner_block, required: true)

  defp tool_panel(assigns) do
    ~H"""
    <aside
      id={@id}
      class="wl-workbench-panel"
      aria-labelledby={@id <> "-title"}
      phx-mounted={JS.focus_first(to: "##{@id}")}
      phx-window-keydown={if !@menu_open, do: JS.patch("/") |> JS.focus(to: "#wl-board-toggle")}
      phx-key="Escape"
    >
      <header class="wl-workbench-panel-header">
        <.link
          :if={@return_path != "/"}
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
          phx-click={JS.focus(to: "#wl-board-toggle")}
        >×</.link>
      </header>
      <div class="wl-workbench-panel-body">{render_slot(@inner_block)}</div>
    </aside>
    """
  end

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
      |> assign(:value, value)
      |> assign(:error, parameter_error(assigns.state.error, parameter))
      |> assign(:step, parameter_step(parameter.type))

    ~H"""
    <.field
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
  attr(:charts, :list, required: true)
  attr(:insights, :any, required: true)
  attr(:investigation, :map, required: true)
  attr(:disclosure, :map, required: true)
  attr(:answer, :any, required: true)
  attr(:session_id, :string, required: true)
  attr(:island_revision, :integer, required: true)

  defp run_view(assigns) do
    ~H"""
    <.error_state
      :if={is_nil(@run)}
      title="Run unavailable"
      code="unknown_run"
      message="This run is not in the current session."
    />
    <div :if={@run}>
      <header class="wl-page-header">
        <div>
          <p class="wl-eyebrow">Run {@run.id}</p><h1>{@run.experiment}</h1>
        </div>
        <.status_badge status={Run.state_text(@run)} kind={StatusBadge.kind_for(@run.status)} />
      </header>
      <.error_state
        :if={@run.error}
        title="Run failed"
        code={@run.error.code}
        message={@run.error.message}
      />
      <dl class="wl-summary">
        <div :for={{label, value} <- @run.summary}>
          <dt>{label}</dt><dd>{value}</dd>
        </div>
      </dl>
      <.action_approval :if={@run.status == :awaiting_approval} run={@run} />
      <.tensor_summary :if={@run.tensor} summary={@run.tensor} />
      <.insights :if={@run.timeseries != []} run={@run} insights={@insights} />
      <section :if={@charts != []} class="wl-section">
        <h2>Timeseries</h2>
        <.chart_island
          :for={{chart, index} <- Enum.with_index(@charts)}
          id={Islands.id(@session_id, "run-chart-#{index}")}
          chart={chart}
          revision={@island_revision}
        >
          <:fallback>
            <.chart
              id={"run-chart-#{index}"}
              chart={chart}
              permalink={chart_path(@run, @insights, index)}
            />
          </:fallback>
        </.chart_island>
      </section>
      <.data_table id="run-assertions" caption="Run assertions" rows={@run.assertions}>
        <:col :let={row} label="Assertion">{row.id}</:col>
        <:col :let={row} label="Status">
          <.status_badge status={Atom.to_string(row.status)} kind={StatusBadge.kind_for(row.status)} />
        </:col>
        <:col :let={row} label="Note">{row.note}</:col>
      </.data_table>
      <section class="wl-panel">
        <h2>Cleanup</h2><p>{@run.cleanup.status}: disposable room-owned resources</p>
      </section>
      <.link
        :if={@run.record_digest}
        patch={"/evidence?" <> Query.encode(%{"run" => @run.id})}
        class="wl-evidence-link"
      >
        <span>Inspect run evidence</span><code>{@run.record_digest}</code>
      </.link>
      <.prompt_composer
        disabled={@investigation.state != :idle}
        running={@investigation.state == :running}
        reason={prompt_reason(@investigation, true)}
        value={@investigation.prompt}
        disclosure={@disclosure}
      />
      <.answer_block :if={@answer} answer={@answer} />
    </div>
    """
  end

  attr(:things, :list, required: true)
  attr(:room, :any, required: true)
  attr(:readings, :map, required: true)

  attr(:selection, :any, default: nil)
  attr(:menu_open, :boolean, default: false)

  defp things_view(assigns) do
    selected = Enum.find(assigns.things, &(Canvas.id(&1) == assigns.selection))

    assigns =
      assigns
      |> assign(:selected, selected)
      |> assign(:read_result, selected && Map.get(assigns.readings, selected.key))

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
                if(@selection == "import",
                  do: "#wl-board-toggle",
                  else: ".svelte-flow__node[data-id='#{@selection}']"
                )
            )
      }
      phx-key="Escape"
    >
      <header>
        <h2>
          {cond do
            @selected -> @selected.title
            @selection == "import" -> "Add Thing"
            true -> "Smart room"
          end}
        </h2>
        <button
          type="button"
          class="wl-button wl-button-secondary"
          phx-click={
            JS.push("close_thing")
            |> JS.focus(
              to:
                if(@selection == "import",
                  do: "#wl-board-toggle",
                  else: ".svelte-flow__node[data-id='#{@selection}']"
                )
            )
          }
          aria-label="Close inspector"
        >×</button>
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
          <dl>
            <dt>Thing ID</dt><dd>{@selected.id}</dd><dt>Transport</dt><dd>{@selected.transport}</dd>
          </dl>
          <details class="wl-disclosure">
            <summary>Sources</summary>
            <pre class="wl-thing-source"><code>{Jason.encode!(@selected.document, pretty: true)}</code></pre>
          </details>
          <form
            :for={property <- Map.keys(@selected.document["properties"] || %{})}
            :if={@selected.consumable}
            id={"read-#{@selected.key}-#{property}"}
            phx-submit="read"
            class="wl-actions"
          >
            <input type="hidden" name="thing" value={@selected.key} /><input
              type="hidden"
              name="property"
              value={property}
            />
            <button class="wl-button wl-button-secondary" type="submit" phx-disable-with="Reading…">
              Read {property}
            </button>
          </form>
          <section :if={@read_result && @read_result.thing == @selected.key} aria-live="polite">
            <h3>Latest reading</h3>
            <div class="wl-inspector-reading">
              <strong>{inspect(@read_result.value)}</strong><span>{property_unit(
                @selected,
                @read_result.property
              )}</span>
            </div>
            <p class="wl-muted">{@read_result.property} · {@read_result.status}</p>
            <p class="wl-muted">Read at {@read_result.read_at}</p>
          </section>
        <% true -> %>
          <p>Observe and propose</p><.link patch="/experiments?experiment=smart_room">Configure experiment</.link>
      <% end %>
    </aside>
    """
  end

  defp property_unit(thing, property) do
    case get_in(thing.document, ["properties", property, "unit"]) do
      "Cel" -> "°C"
      unit when is_binary(unit) -> unit
      _ -> ""
    end
  end

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
    <header class="wl-page-header">
      <div>
        <p class="wl-eyebrow">Metrics</p><h1>Session measurements</h1>
      </div><button :if={is_nil(@room)} class="wl-button wl-button-primary" phx-click="start_room">Start disposable room</button>
    </header>
    <.empty_state
      :if={is_nil(@room)}
      title="No room"
      description="Start a room, then run an experiment to collect scoped measurements."
    />
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
    <div :if={@snapshot} class="wl-stack">
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
      <section :if={!@selected} class="wl-panel">
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
        if socket.assigns.scope.room == scope.room,
          do: socket,
          else: assign(socket, canvas_readings: %{}, insights: nil)

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

  defp apply_effect(socket, nil), do: socket
  defp apply_effect(socket, {:assign, key, value}), do: assign(socket, key, value)

  defp apply_effect(socket, {:reading, result}),
    do: update(socket, :canvas_readings, &Map.put(&1, result.thing, result))

  defp apply_effect(socket, {:navigate, path}), do: push_patch(socket, to: path)

  defp apply_effect(socket, {:history, history}),
    do: assign(socket, history: history, history_range: history.range)

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
        Canvas.props(socket.assigns.things, socket.assigns.runs, socket.assigns.canvas_readings)
    }

    descriptors = [canvas | contextual]

    case Enum.find(descriptors, &(&1 && &1.id == instance_id)) do
      nil -> {:error, :unknown_island}
      descriptor -> {:ok, descriptor}
    end
  end

  defp select_canvas_node(socket, id) when is_binary(id) do
    case Scope.verify(socket) do
      {:ok, scope} ->
        socket =
          socket
          |> assign(:scope, scope)
          |> refresh()

        props =
          Canvas.props(socket.assigns.things, socket.assigns.runs, socket.assigns.canvas_readings)

        if Enum.any?(props["nodes"], &(&1["id"] == id)) do
          socket =
            socket
            |> assign(:canvas_selection, id)
            |> revise_islands()

          socket =
            cond do
              id == "process-smart-room" ->
                push_patch(socket, to: "/experiments?experiment=smart_room")

              socket.assigns.live_action == :things ->
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

  defp open_canvas_tool(socket, tool) when tool in ~w(add experiments metrics) do
    case Scope.verify(socket) do
      {:ok, scope} ->
        path =
          case tool do
            "add" ->
              "/things?panel=import"

            "experiments" ->
              "/experiments?" <> Query.encode(%{"experiment" => socket.assigns.selected_experiment})

            "metrics" ->
              "/metrics"
          end

        {:ok,
         socket
         |> assign(scope: scope, sidebar_open: false)
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

  defp refresh(%{assigns: %{scope: %{room: room, session_id: session_id}}} = socket)
       when is_pid(room) do
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
      |> assign(:snapshot, snapshot)
      |> assign(:metrics, metrics)
      |> reload_run()
    else
      empty_room(socket)
    end
  end

  defp refresh(socket), do: empty_room(socket)

  defp empty_room(socket) do
    socket
    |> assign(:runs, [])
    |> assign(:things, [])
    |> assign(:snapshot, nil)
    |> assign(:metrics, nil)
    |> assign(:history, nil)
    |> assign(:run, nil)
    |> assign(:charts, [])
    |> assign(:insights, nil)
    |> assign(:canvas_readings, %{})
  end

  defp load_action(socket, :run, %{"id" => id} = params) do
    socket =
      socket
      |> assign(:run_id, id)
      |> refresh()
      |> reload_run()

    case params do
      %{} when map_size(params) == 1 ->
        socket

      %{"id" => ^id, "analysis" => analysis} when map_size(params) == 2 ->
        load_analysis(socket, analysis)

      _ ->
        error_flash(socket, Error.new(:invalid_analysis_query, :analytics, "run link is malformed"))
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

        _ ->
          {:error, Error.new(:invalid_panels, :metrics, "metric deep link is not admitted")}
      end

    case selected do
      {:ok, panel_ids} ->
        socket
        |> assign(:run_id, nil)
        |> assign(:dashboard_panels, panel_ids)
        |> assign(:history, nil)
        |> refresh()

      {:error, error} ->
        socket
        |> assign(:run_id, nil)
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

  defp reload_run(%{assigns: %{run_id: id, scope: %{room: room}}} = socket)
       when is_binary(id) and is_pid(room) do
    case safe(fn -> Room.fetch_run(room, id) end, {:error, :unavailable}) do
      {:ok, run} ->
        case socket.assigns.insights do
          %{run_id: run_id} = insights when run_id == run.id ->
            assign(socket, run: run, charts: insights.charts)

          _ ->
            assign(socket, run: run, charts: charts(run), insights: nil)
        end

      {:error, _} ->
        assign(socket, run: nil, charts: [], insights: nil)
    end
  end

  defp reload_run(socket), do: assign(socket, run: nil, charts: [])

  defp charts(%Run{} = run) do
    Enum.flat_map(run.timeseries, fn series ->
      case Chart.new(
             title: series.name,
             x: %{field: "time", title: "event time"},
             y: %{field: "value", title: series.unit},
             series: [%{name: series.name, points: series.points}]
           ) do
        {:ok, chart} -> [chart]
        {:error, _} -> []
      end
    end)
  end

  defp investigation_context(socket, scope) do
    runs = safe(fn -> Room.runs(scope.room) end, [])
    selected_id = if(socket.assigns.live_action in [:run, :evidence], do: socket.assigns[:run_id])
    RunContext.select(runs, selected_id)
  end

  defp cancel_investigation_on_navigation(
         %{assigns: %{investigation: %{state: :running, request: request}}} = socket
       ) do
    _ = Broker.cancel(request)
    socket
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
    investigation = investigation_state()
    assign(socket, answer: answer, investigation: investigation)
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
    assign(socket, scope: nil, denied: Atom.to_string(code))
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
