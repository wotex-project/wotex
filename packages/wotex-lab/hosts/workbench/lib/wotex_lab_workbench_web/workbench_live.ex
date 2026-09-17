defmodule WotexLabWorkbenchWeb.WorkbenchLive do
  @moduledoc """
  The single scoped LiveView for experiments, runs, Things, metrics and evidence.

  Mounting and reconnecting only read existing state. Every event revalidates
  the signed session, and commands that need a room use the session registry's
  closed admission list. Running an experiment, approving an Action, exporting
  a dataset and asking for formal evidence are separate server commands.
  """

  use WotexLabWorkbenchWeb, :live_view

  alias Plug.Conn.Query
  alias Wotex.Lab.Error
  alias Wotex.Lab.Telemetry

  alias WotexLabWorkbench.{
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

  import WotexLabWorkbenchWeb.Components.HistoryPanels
  import WotexLabWorkbenchWeb.Components.Insights
  import WotexLabWorkbenchWeb.Components.MetricCatalogue
  alias WotexLabWorkbenchWeb.Components.StatusBadge
  alias WotexLabWorkbenchWeb.Scope

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_new(:denied, fn -> nil end)
      |> assign(:sidebar_open, true)
      |> assign(:experiments, Experiments.all())
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
      |> assign(:read_result, nil)
      |> assign(:answer, nil)
      |> assign(:investigation, investigation_state())
      |> assign(:disclosure, Disclosure.current())
      |> refresh()

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    socket = cancel_investigation_on_navigation(socket)
    {:noreply, load_action(socket, socket.assigns.live_action, params)}
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_sidebar", _params, socket) do
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

  def handle_event("set_theme", %{"theme" => theme}, socket) do
    with %{token: token} <- socket.assigns.scope,
         {:ok, session} <- Sessions.put_theme(token, theme) do
      scope = %{socket.assigns.scope | theme: session.theme, room: session.room}
      {:noreply, assign(socket, :scope, scope)}
    else
      nil -> {:noreply, deny(socket, Error.new(:denied, :session, "no session scope"))}
      {:error, error} -> {:noreply, error_flash(socket, error)}
    end
  end

  def handle_event("start_room", _params, socket) do
    command(socket, :start_room, fn scope -> {:ok, scope, nil} end)
  end

  def handle_event("run", %{"experiment_id" => id, "params" => raw}, socket) do
    command(socket, :run, fn scope ->
      with {:ok, experiment} <- Experiments.fetch(id),
           {:ok, params} <- Experiments.admit(experiment, raw),
           {:ok, run} <- Room.start_run(scope.room, id, params) do
        {:ok, scope, {:navigate, "/runs/#{run.id}"}}
      end
    end)
  end

  def handle_event("run", _params, socket) do
    reject_event(socket, Error.new(:invalid_parameters, :admission, "run form is malformed"))
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    command(socket, :cancel, fn scope ->
      with {:ok, _run} <- Room.cancel_run(scope.room, id), do: {:ok, scope, nil}
    end)
  end

  def handle_event("approve", %{"run_id" => id} = approval, socket) do
    command(socket, :approve, fn scope ->
      with {:ok, _run} <- Room.approve(scope.room, id, approval), do: {:ok, scope, nil}
    end)
  end

  def handle_event("read", %{"thing" => thing, "property" => property}, socket) do
    command(socket, :read, fn scope ->
      with {:ok, result} <- Room.read_property(scope.room, thing, property) do
        {:ok, scope, {:assign, :read_result, result}}
      end
    end)
  end

  def handle_event("register_td", %{"thing_description" => source}, socket) do
    command(socket, :register, fn scope ->
      with {:ok, _document} <- Room.register_td(scope.room, source), do: {:ok, scope, nil}
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
      {:error, error} -> {:noreply, error_flash(socket, error)}
    end
  end

  def handle_event("save_dashboard", _params, socket) do
    reject_event(socket, Error.new(:invalid_panels, :metrics, "select 1–16 metric panels"))
  end

  def handle_event("export_dataset", _params, socket) do
    command(socket, :export, fn scope ->
      with {:ok, _dataset} <- Room.export_dataset(scope.room, scope: scope.session_id, limit: 2_000),
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
        _missing -> {:error, Error.new(:unknown_run, :analytics, "no run selected in this session")}
      end
    end)
  end

  def handle_event("verify", %{"property" => property, "variant" => variant}, socket) do
    command(socket, :verify, fn scope ->
      with {:ok, property, variant} <- Formal.admit(property, variant),
           {:ok, _result} <- Room.verify(scope.room, property, variant) do
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

  def handle_event("ask", _params, socket) do
    {:noreply, investigation_failure(socket, :invalid_prompt)}
  end

  def handle_event("cancel_investigation", _params, socket) do
    with {:ok, scope} <- Scope.admit(socket, :ask),
         %{state: :running, request: request} <- socket.assigns.investigation,
         :ok <- Broker.cancel(request) do
      {:noreply, assign(socket, :scope, scope)}
    else
      {:error, %Error{} = error} -> {:noreply, error_flash(socket, error)}
      {:error, reason} -> {:noreply, investigation_failure(socket, reason)}
      _not_running -> {:noreply, investigation_failure(socket, :unknown_investigation)}
    end
  end

  @impl Phoenix.LiveView
  def handle_info(
        {:investigation, request, result},
        %{assigns: %{investigation: %{state: :running, request: request}}} = socket
      ) do
    answer = Answer.from_result(result, provider_status())
    investigation = %{state: :idle, request: nil, prompt: ""}
    {:noreply, socket |> assign(:answer, answer) |> assign(:investigation, investigation)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <%= if @scope do %>
      <.shell
        theme={@scope.theme}
        sidebar_open={@sidebar_open}
        current={nav_item(@live_action)}
      >
        <:context><.context_header items={context(@scope, @run)} /></:context>
        <div :if={Phoenix.Flash.get(@flash, :info)} class="wl-flash" role="status">
          {Phoenix.Flash.get(@flash, :info)}
        </div>
        <div :if={Phoenix.Flash.get(@flash, :error)} class="wl-flash wl-flash-error" role="alert">
          {Phoenix.Flash.get(@flash, :error)}
        </div>
        <%= case @live_action do %>
          <% :experiments -> %>
            <.experiments_view experiments={@experiments} runs={@runs} room={@scope.room} />
          <% :run -> %>
            <.run_view
              run={@run}
              charts={@charts}
              insights={@insights}
              investigation={@investigation}
              answer={@answer}
              disclosure={@disclosure}
            />
          <% :things -> %>
            <.things_view things={@things} room={@scope.room} read_result={@read_result} />
          <% :metrics -> %>
            <.metrics_view
              metrics={@metrics}
              history={@history}
              history_range={@history_range}
              room={@scope.room}
              dashboard_panels={@dashboard_panels}
            />
          <% :evidence -> %>
            <.evidence_view
              snapshot={@snapshot}
              room={@scope.room}
              answer={@answer}
              investigation={@investigation}
              disclosure={@disclosure}
            />
        <% end %>
      </.shell>
    <% else %>
      <div class="wotex-lab wl-denied">
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

  attr :experiments, :list, required: true
  attr :runs, :list, required: true
  attr :room, :any, required: true

  defp experiments_view(assigns) do
    ~H"""
    <header class="wl-page-header">
      <div>
        <p class="wl-eyebrow">Experiments</p><h1>Numerical workbench</h1>
      </div>
      <button :if={is_nil(@room)} class="wl-button wl-button-primary" phx-click="start_room">Start disposable room</button>
    </header>
    <p class="wl-lede">
      Run admitted Nx experiments, inspect tensors and keep every proposal inert until a separate policy decision.
    </p>
    <div class="wl-card-grid">
      <article :for={experiment <- @experiments} class="wl-card">
        <p class="wl-eyebrow">{experiment.kind |> Atom.to_string() |> String.replace("_", " ")}</p>
        <h2>{experiment.title}</h2>
        <p>{experiment.summary}</p>
        <dl class="wl-provenance">
          <div :for={{label, value} <- Enum.sort(experiment.provenance)}>
            <dt>{label}</dt><dd>{value}</dd>
          </div>
        </dl>
        <form id={"run-#{experiment.id}"} phx-submit="run" class="wl-stack">
          <input type="hidden" name="experiment_id" value={experiment.id} />
          <.parameter_field
            :for={parameter <- experiment.parameters}
            experiment={experiment.id}
            parameter={parameter}
          />
          <button class="wl-button wl-button-primary" type="submit" phx-disable-with="Running…">
            Run experiment
          </button>
        </form>
        <details>
          <summary>Public calls</summary><ul>
            <li :for={call <- experiment.public_calls}><code>{call}</code></li>
          </ul>
        </details>
      </article>
    </div>
    <section class="wl-section">
      <h2>Recent runs</h2>
      <.empty_state
        :if={@runs == []}
        title="No runs yet"
        description="Choose an admitted experiment above."
      />
      <.data_table :if={@runs != []} id="recent-runs" caption="Recent experiment runs" rows={@runs}>
        <:col :let={run} label="Run"><.link navigate={"/runs/#{run.id}"}>{run.id}</.link></:col>
        <:col :let={run} label="Experiment">{run.experiment}</:col>
        <:col :let={run} label="State">
          <.status_badge status={Run.state_text(run)} kind={StatusBadge.kind_for(run.status)} />
        </:col>
        <:col :let={run} label="Duration">{run.duration_ms} ms</:col>
      </.data_table>
    </section>
    """
  end

  attr :parameter, :map, required: true
  attr :experiment, :string, required: true

  defp parameter_field(assigns) do
    parameter = assigns.parameter
    options = Enum.map(parameter.options || [], fn {label, _value} -> {label, label} end)

    assigns =
      assigns
      |> assign(
        :control_type,
        if(parameter.type == :select, do: "select", else: Atom.to_string(parameter.type))
      )
      |> assign(:options, options)

    ~H"""
    <.field
      id={"parameter-#{@experiment}-#{@parameter.name}"}
      name={"params[#{@parameter.name}]"}
      label={@parameter.label}
      type={@control_type}
      value={@parameter.default}
      options={@options}
      help={@parameter.help}
      min={@parameter.min}
      max={@parameter.max}
      step={if @parameter.type == :float, do: "any", else: nil}
    />
    """
  end

  attr :run, :any, required: true
  attr :charts, :list, required: true
  attr :insights, :any, required: true
  attr :investigation, :map, required: true
  attr :disclosure, :map, required: true
  attr :answer, :any, required: true

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
        <h2>Timeseries</h2><.chart
          :for={{chart, index} <- Enum.with_index(@charts)}
          id={"run-chart-#{index}"}
          chart={chart}
          permalink={chart_path(@run, @insights, index)}
        />
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
      <.evidence_link
        :if={@run.record_digest}
        href="/evidence"
        label="Inspect run evidence"
        digest={@run.record_digest}
      />
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

  attr :things, :list, required: true
  attr :room, :any, required: true
  attr :read_result, :any, required: true

  defp things_view(assigns) do
    ~H"""
    <header class="wl-page-header">
      <div>
        <p class="wl-eyebrow">Things</p><h1>Disposable Things</h1>
      </div><button :if={is_nil(@room)} class="wl-button wl-button-primary" phx-click="start_room">Start disposable room</button>
    </header>
    <.empty_state
      :if={is_nil(@room)}
      title="No room"
      description="Start a disposable room; mounting this page starts nothing."
    />
    <div :if={@room} class="wl-stack">
      <article :for={thing <- @things} class="wl-card">
        <div class="wl-card-heading">
          <div>
            <p class="wl-eyebrow">{thing.transport}</p><h2>{thing.title}</h2>
          </div><.status_badge
            status={if thing.consumable, do: "consumable", else: "inert entry"}
            kind={if thing.consumable, do: :success, else: :neutral}
          />
        </div>
        <p><code>{thing.id}</code></p><p class="wl-muted">{thing.owner}</p>
        <form
          :for={property <- Map.keys(thing.document["properties"] || %{})}
          :if={thing.consumable}
          id={"read-#{thing.key}-#{property}"}
          phx-submit="read"
          class="wl-actions"
        >
          <input type="hidden" name="thing" value={thing.key} /><input
            type="hidden"
            name="property"
            value={property}
          />
          <button class="wl-button wl-button-secondary" type="submit" phx-disable-with="Reading…">
            Read {property}
          </button>
        </form>
      </article>
      <section :if={@read_result} class="wl-panel" aria-live="polite">
        <h2>Latest reading</h2><p>
          {@read_result.thing}.{@read_result.property}: <strong>{inspect(@read_result.value)}</strong>
          · HTTP/runtime status {@read_result.status}
        </p>
      </section>
      <section class="wl-panel">
        <h2>Register an inert TD</h2><form id="register-td" phx-submit="register_td" class="wl-stack">
          <.field
            id="thing-description"
            name="thing_description"
            label="Thing Description JSON"
            type="textarea"
            maxlength="16384"
            rows="8"
            help="Validated and stored in this session Directory only; no transport is created."
          /><button
            class="wl-button wl-button-secondary"
            type="submit"
            phx-disable-with="Registering…"
          >Register TD</button>
        </form>
      </section>
    </div>
    """
  end

  attr :metrics, :any, required: true
  attr :room, :any, required: true
  attr :dashboard_panels, :list, required: true
  attr :history, :any, required: true
  attr :history_range, :string, required: true

  defp metrics_view(assigns) do
    latest = assigns.metrics && List.last(assigns.metrics.samples)
    assigns = assign(assigns, :latest, latest)

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
      <.data_table
        :if={@metrics}
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

  attr :snapshot, :any, required: true
  attr :room, :any, required: true
  attr :answer, :any, required: true
  attr :investigation, :map, required: true
  attr :disclosure, :map, required: true

  defp evidence_view(assigns) do
    properties = Enum.map(Formal.properties(), fn {id, text} -> {text, Atom.to_string(id)} end)
    variants = Enum.map(Formal.variants(), &{Atom.to_string(&1), Atom.to_string(&1)})
    assigns = assigns |> assign(:properties, properties) |> assign(:variants, variants)

    ~H"""
    <header class="wl-page-header">
      <div>
        <p class="wl-eyebrow">Evidence</p><h1>Bounded session report</h1>
      </div><button :if={is_nil(@room)} class="wl-button wl-button-primary" phx-click="start_room">Start disposable room</button>
    </header>
    <.empty_state
      :if={is_nil(@room)}
      title="No evidence yet"
      description="Start a room; the report remains scoped to this signed session."
    />
    <div :if={@snapshot} class="wl-stack">
      <div class="wl-actions">
        <.evidence_link href="/evidence/report.json" label="Export JSON report" download={true} />
      </div>
      <.data_table id="evidence-runs" caption="Run evidence" rows={@snapshot.runs}>
        <:col :let={run} label="Run"><.link navigate={"/runs/#{run.id}"}>{run.id}</.link></:col><:col
          :let={run}
          label="State"
        >
          {Run.state_text(run)}
        </:col><:col :let={run} label="Digest"><code>{run.record_digest || "missing"}</code></:col>
      </.data_table>
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

  defp command(socket, command, fun) do
    with {:ok, scope} <- Scope.admit(socket, command),
         true <- is_pid(scope.room) and Process.alive?(scope.room),
         {:ok, scope, effect} <- fun.(scope) do
      socket = socket |> assign(:scope, scope) |> refresh() |> apply_effect(effect)
      {:noreply, socket}
    else
      false -> {:noreply, error_flash(socket, Error.new(:no_room, :session, "room is unavailable"))}
      {:error, error} -> {:noreply, error_flash(socket, error)}
    end
  end

  defp apply_effect(socket, nil), do: socket
  defp apply_effect(socket, {:assign, key, value}), do: assign(socket, key, value)
  defp apply_effect(socket, {:navigate, path}), do: push_navigate(socket, to: path)

  defp apply_effect(socket, {:history, history}),
    do: socket |> assign(:history, history) |> assign(:history_range, history.range)

  defp apply_effect(socket, {:insights, insights}),
    do: socket |> assign(:insights, insights) |> assign(:charts, insights.charts)

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
  end

  defp load_action(socket, :run, %{"id" => id} = params) do
    socket = socket |> assign(:run_id, id) |> refresh() |> reload_run()

    case params do
      %{} when map_size(params) == 1 ->
        socket

      %{"id" => ^id, "analysis" => analysis} when map_size(params) == 2 ->
        load_analysis(socket, analysis)

      _other ->
        error_flash(socket, Error.new(:invalid_analysis_query, :analytics, "run link is malformed"))
    end
  end

  defp load_action(socket, :metrics, params) do
    selected =
      case params do
        %{} when map_size(params) == 0 ->
          {:ok, socket.assigns.scope.dashboard_panels}

        %{"panels" => panel_ids, "selection" => "custom"} when map_size(params) == 2 ->
          with {:ok, panels} <- Panels.select(panel_ids), do: {:ok, Enum.map(panels, & &1.id)}

        _other ->
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

  defp load_action(socket, _action, _params), do: socket |> assign(:run_id, nil) |> refresh()

  defp dashboard_path(panel_ids) do
    "/metrics?" <> Query.encode(%{"panels" => panel_ids, "selection" => "custom"})
  end

  defp load_analysis(%{assigns: %{run: %Run{} = run}} = socket, params) do
    case Insights.analyze(run, params) do
      {:ok, insights} -> apply_effect(socket, {:insights, insights})
      {:error, error} -> error_flash(socket, error)
    end
  end

  defp load_analysis(socket, _params), do: socket

  defp chart_path(run, nil, index), do: "/runs/#{URI.encode(run.id)}#run-chart-#{index}"

  defp chart_path(_run, insights, index),
    do: Insights.path(insights) <> "#run-chart-#{index}"

  defp reload_run(%{assigns: %{run_id: id, scope: %{room: room}}} = socket)
       when is_binary(id) and is_pid(room) do
    case safe(fn -> Room.fetch_run(room, id) end, {:error, :unavailable}) do
      {:ok, run} ->
        case socket.assigns.insights do
          %{run_id: run_id} = insights when run_id == run.id ->
            socket |> assign(:run, run) |> assign(:charts, insights.charts)

          _other ->
            socket |> assign(:run, run) |> assign(:charts, charts(run)) |> assign(:insights, nil)
        end

      {:error, _error} ->
        socket |> assign(:run, nil) |> assign(:charts, []) |> assign(:insights, nil)
    end
  end

  defp reload_run(socket), do: socket

  defp charts(%Run{} = run) do
    Enum.flat_map(run.timeseries, fn series ->
      case Chart.new(
             title: series.name,
             x: %{field: "time", title: "event time"},
             y: %{field: "value", title: series.unit},
             series: [%{name: series.name, points: series.points}]
           ) do
        {:ok, chart} -> [chart]
        {:error, _error} -> []
      end
    end)
  end

  defp investigation_context(socket, scope) do
    runs = safe(fn -> Room.runs(scope.room) end, [])
    selected_id = if(socket.assigns.live_action == :run, do: socket.assigns[:run_id])
    RunContext.select(runs, selected_id)
  end

  defp cancel_investigation_on_navigation(
         %{assigns: %{investigation: %{state: :running, request: request}}} = socket
       ) do
    _result = Broker.cancel(request)
    socket
  end

  defp cancel_investigation_on_navigation(socket), do: socket

  defp investigation_state do
    case Broker.status() do
      %{running: true} -> %{state: :busy, request: nil, prompt: ""}
      %{running: false} -> %{state: :idle, request: nil, prompt: ""}
      _unavailable -> %{state: :disabled, request: nil, prompt: ""}
    end
  end

  defp prompt_reason(%{state: :running}, _context?),
    do: "Read-only investigation running; leaving this view cancels its owner-bound worker."

  defp prompt_reason(%{state: :idle}, true),
    do: "Trusted-local only; one bounded read-only investigation, with no Action capability."

  defp prompt_reason(%{state: :idle}, false),
    do: "Run an experiment before asking about its evidence."

  defp prompt_reason(%{state: :busy}, _context?),
    do: "Another trusted-local investigation is running; this host does not queue prompts."

  defp prompt_reason(_investigation, _context?),
    do: "No investigation provider is configured."

  defp investigation_failure(socket, reason) do
    answer = Answer.from_result({:error, reason}, provider_status())
    investigation = investigation_state()
    socket |> assign(:answer, answer) |> assign(:investigation, investigation)
  end

  defp provider_status do
    Provider.status()
  catch
    :exit, _reason -> %{}
  end

  defp metric_filters(params, scope) do
    with {:ok, component} <- known(params["component"], Telemetry.components()),
         {:ok, operation} <- known(params["operation"], Telemetry.operations()) do
      {:ok,
       [scope: scope, component: component, operation: operation, limit: 2_000]
       |> Enum.reject(fn {_key, value} -> is_nil(value) end)}
    end
  end

  defp known(value, _allowed) when value in [nil, ""], do: {:ok, nil}

  defp known(value, allowed) when is_binary(value) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> {:error, Error.new(:invalid_filter, :metrics, "metric filter is not admitted")}
      atom -> {:ok, atom}
    end
  end

  defp known(_value, _allowed),
    do: {:error, Error.new(:invalid_filter, :metrics, "metric filter is not admitted")}

  defp room_history(room) do
    Room.history(room)
  catch
    :exit, _ -> {:error, Error.new(:history_unavailable, :metrics, "room history is unavailable")}
  end

  defp safe(fun, fallback) do
    fun.()
  catch
    :exit, _reason -> fallback
  end

  defp context(_scope, %Run{} = run) do
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
  defp nav_item(action), do: action

  defp deny(socket, %Error{code: code}) do
    socket |> assign(:scope, nil) |> assign(:denied, Atom.to_string(code))
  end

  defp error_flash(socket, %Error{} = error),
    do: put_flash(socket, :error, "#{error.code}: #{error.message}")

  defp error_flash(socket, other),
    do: put_flash(socket, :error, "operation failed: #{inspect(other, limit: 4)}")

  defp reject_event(socket, error) do
    case Scope.verify(socket) do
      {:ok, scope} -> {:noreply, socket |> assign(:scope, scope) |> error_flash(error)}
      {:error, denied} -> {:noreply, deny(socket, denied)}
    end
  end
end
