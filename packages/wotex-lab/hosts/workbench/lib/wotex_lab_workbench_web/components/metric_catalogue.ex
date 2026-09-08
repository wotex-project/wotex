defmodule WotexLabWorkbenchWeb.Components.MetricCatalogue do
  @moduledoc "Read-only catalogue-derived panel selection; never reads host-wide measurements."

  use Phoenix.Component

  alias WotexLabWorkbench.Observability.Panels

  @doc "Shows fixed query semantics and exports only the selected definitions."
  @spec metric_catalogue(map()) :: Phoenix.LiveView.Rendered.t()
  def metric_catalogue(assigns) do
    assigns = assign(assigns, panels: Panels.all(), defaults: Panels.defaults())

    ~H"""
    <section id="metric-catalogue" class="wl-panel">
      <header class="wl-panel-header">
        <h2>Portable metric panels</h2>
      </header>
      <p>
        These are catalogue definitions, not measurements from this session. The optional
        operator-owned PromEx collector describes the whole Workbench Lab instance.
        No collector, database or Grafana upload starts when you open or export this catalogue.
      </p>
      <details>
        <summary>Choose up to 16 panels and inspect their queries</summary>
        <form id="dashboard-export" action="/metrics/dashboard.json" method="get" class="wl-stack">
          <input type="hidden" name="selection" value="custom" />
          <fieldset class="wl-stack">
            <legend>Dashboard panels (four numerical panels selected initially)</legend>
            <label :for={panel <- @panels} class="wl-catalogue-choice">
              <input type="checkbox" name="panels[]" value={panel.id} checked={panel.id in @defaults} />
              <span>
                <strong>{panel.title}</strong><br />
                <span>{panel.aggregation} · {panel.display_unit} · {panel.scope} scope</span><br />
                <code class="wl-query-code">{panel.query}</code>
              </span>
            </label>
          </fieldset>
          <p class="wl-muted">
            Five-minute rates preserve counter resets. Histogram p95 is estimated from fixed
            buckets; it is not an average of percentiles. Missing data remains unavailable.
            Select a Prometheus-compatible source when importing the JSON in Grafana.
          </p>
          <button type="submit" class="wl-button wl-button-secondary">Download dashboard JSON</button>
        </form>
      </details>
    </section>
    """
  end
end
