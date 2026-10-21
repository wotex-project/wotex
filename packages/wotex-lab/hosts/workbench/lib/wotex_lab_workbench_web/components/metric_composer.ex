defmodule WotexLabWorkbenchWeb.Components.MetricComposer do
  @moduledoc """
  Compact source-labelled query/result and pin inspection on the workbench.
  Rendering performs no query. Only the server-supplied executed result can be
  pinned; the browser submits catalogue/range identifiers and a bounded title.
  """
  use Phoenix.Component

  import WotexLabWorkbenchWeb.Components.{Chart, Field}
  alias WotexLabWorkbench.{Board, HistoryPanels}
  alias WotexLabWorkbench.Observability.Panels

  attr :room, :any, required: true
  attr :draft, :map, required: true
  attr :result, :any, required: true
  attr :pin, :any, required: true
  attr :selected_pin, :any, required: true

  @doc "Renders a query builder or one selected pin, retaining actual data identity."
  @spec metric_composer(map()) :: Phoenix.LiveView.Rendered.t()
  def metric_composer(assigns) do
    assigns =
      assign(assigns,
        metrics: Enum.map(Panels.all(), &{&1.title, &1.id}),
        ranges: Enum.map(HistoryPanels.ranges(), &{&1, &1})
      )

    ~H"""
    <%= if @selected_pin do %>
      <p :if={is_nil(@pin)} role="alert">Pin unavailable</p>
      <div :if={@pin} class="wl-stack">
        <form id="rename-pin" phx-submit="rename_pin" class="wl-stack">
          <input type="hidden" name="pin_id" value={@pin.id} />
          <.field id="pin-title" name="title" label="Title" value={@pin.title} maxlength="128" />
          <button class="wl-button wl-button-secondary" type="submit">Rename</button>
        </form>
        <dl class="wl-metric-source">
          <div>
            <dt>Source</dt><dd>Room history</dd>
          </div>
          <div>
            <dt>Metric</dt><dd><code>{@pin.metric}</code></dd>
          </div>
          <div>
            <dt>Range</dt><dd>{@pin.range} · {@pin.window.step_ms / 1000} s steps</dd>
          </div>
          <div>
            <dt>Data window</dt><dd>{time(@pin.window.start_ms)} – {time(@pin.window.end_ms)}</dd>
          </div>
          <div>
            <dt>Last check</dt><dd>{time(@pin.checked_at)}</dd>
          </div>
        </dl>
        <p :if={@pin.error} role="status">{@pin.error}. Previous data retained.</p>
        <.chart
          :if={@pin.result && @pin.result.chart}
          id="selected-pin-chart"
          chart={@pin.result.chart}
          compact
        />
        <details :if={@pin.result} class="wl-disclosure">
          <summary>Sources</summary>
          <p>{@pin.result.aggregation} · {@pin.result.display_unit}</p>
          <p>{@pin.result.series_shown} / {@pin.result.series_total} label sets</p>
          <p>
            Automatic refresh is limited to the connected workbench. Restored pins stay paused until Resume.
          </p>
          <ul>
            <li :for={digest <- @pin.result.digests}><code>{digest}</code></li>
          </ul>
        </details>
        <.link patch="/metrics">Build query</.link>
      </div>
    <% else %>
      <p class="wl-muted">Room history</p>
      <button :if={is_nil(@room)} class="wl-button wl-button-primary" phx-click="start_room">Start room</button>
      <form
        id="metric-compose-query"
        phx-change="edit_metric_query"
        phx-submit="compose_metric"
        class="wl-stack"
      >
        <.field
          id="compose-metric"
          name="metric"
          label="Metric"
          type="select"
          value={@draft.metric}
          options={@metrics}
        />
        <.field
          id="compose-range"
          name="range"
          label="Range"
          type="select"
          value={@draft.range}
          options={@ranges}
        />
        <button
          class="wl-button wl-button-secondary"
          type="submit"
          disabled={is_nil(@room)}
          phx-disable-with="Querying…"
        >Query</button>
      </form>
      <section :if={@result} id="metric-compose-result" class="wl-stack" aria-live="polite">
        <p class="wl-muted">{@result.range} · {time(@result.end_ms)}</p>
        <div :for={panel <- @result.panels}>
          <.chart :if={panel.chart} id="composed-metric-chart" chart={panel.chart} compact />
          <p :if={!Board.measured?(panel)}>No samples in this range</p>
          <button
            class="wl-button wl-button-primary"
            phx-click="pin_metric"
            disabled={!Board.measured?(panel)}
          >Pin to workbench</button>
          <details class="wl-disclosure">
            <summary>View query / sources</summary>
            <dl class="wl-metric-source">
              <div>
                <dt>Metric</dt><dd><code>{panel.id}</code></dd>
              </div>
              <div>
                <dt>Aggregation</dt><dd>{panel.aggregation}</dd>
              </div>
              <div>
                <dt>Unit</dt><dd>{panel.display_unit}</dd>
              </div>
              <div>
                <dt>Range</dt><dd>{time(@result.start_ms)} – {time(@result.end_ms)}</dd>
              </div>
              <div>
                <dt>Step</dt><dd>{@result.step_ms / 1000} s</dd>
              </div>
              <div>
                <dt>Series</dt><dd>{panel.series_shown} / {panel.series_total} label sets</dd>
              </div>
            </dl>
            <ul>
              <li :for={digest <- panel.digests}><code>{digest}</code></li>
            </ul>
          </details>
        </div>
      </section>
    <% end %>
    """
  end

  defp time(ms) do
    ms
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.to_iso8601()
  end

  attr :results, :list, required: true

  @doc "Renders recorded investigation charts with server-indexed Pin controls."
  @spec investigation_metrics(map()) :: Phoenix.LiveView.Rendered.t()
  def investigation_metrics(assigns) do
    ~H"""
    <section
      :for={{history, index} <- Enum.with_index(@results)}
      id={"investigation-metric-#{index}"}
      class="wl-stack wl-investigation-metric"
    >
      <div :for={panel <- history.panels} class="wl-stack">
        <.chart :if={panel.chart} id={"investigation-chart-#{index}"} chart={panel.chart} compact />
        <p class="wl-muted">Room history · {history.range} · {time(history.end_ms)}</p>
        <button
          class="wl-button wl-button-primary"
          type="button"
          phx-click="pin_investigation_metric"
          phx-value-index={index}
          disabled={!Board.measured?(panel)}
        >Pin to workbench</button>
        <details class="wl-disclosure">
          <summary>View query / sources</summary>
          <dl class="wl-metric-source">
            <div>
              <dt>Metric</dt><dd><code>{panel.id}</code></dd>
            </div>
            <div>
              <dt>Aggregation</dt><dd>{panel.aggregation}</dd>
            </div>
            <div>
              <dt>Unit</dt><dd>{panel.display_unit}</dd>
            </div>
            <div>
              <dt>Window</dt><dd>{time(history.start_ms)} – {time(history.end_ms)}</dd>
            </div>
            <div>
              <dt>Step</dt><dd>{history.step_ms / 1000} s</dd>
            </div>
            <div>
              <dt>Series</dt><dd>{panel.series_shown} / {panel.series_total} label sets</dd>
            </div>
          </dl>
          <ul>
            <li :for={digest <- panel.digests}><code>{digest}</code></li>
          </ul>
        </details>
      </div>
    </section>
    """
  end
end
