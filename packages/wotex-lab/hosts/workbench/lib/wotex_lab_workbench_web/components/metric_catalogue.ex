defmodule WotexLabWorkbenchWeb.Components.MetricCatalogue do
  @moduledoc """
  Presents the fixed metric panel catalogue and its export controls.

  Definitions come from `WotexLabWorkbench.Observability.Panels` and include
  query semantics, units and scope. The selected panel ids form the page and
  download links; the receiving LiveView validates the selection and its
  16-panel limit. Rendering or exporting definitions starts no collector,
  database query or Grafana upload and reads no host measurements.
  """

  use Phoenix.Component

  alias Plug.Conn.Query
  alias WotexLabWorkbench.Observability.Panels

  attr :selected, :list, required: true

  @doc "Shows fixed query semantics and exports only the selected definitions."
  @spec metric_catalogue(map()) :: Phoenix.LiveView.Rendered.t()
  def metric_catalogue(assigns) do
    selected = assigns.selected

    assigns =
      assign(assigns,
        panels: Panels.all(),
        deep_link: dashboard_path("/metrics", selected),
        download_link: dashboard_path("/metrics/dashboard.json", selected)
      )

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
        <form id="dashboard-selection" phx-submit="save_dashboard" class="wl-stack">
          <fieldset class="wl-stack">
            <legend>Dashboard panels (saved only in this bounded browser session)</legend>
            <label :for={panel <- @panels} class="wl-catalogue-choice">
              <input type="checkbox" name="panels[]" value={panel.id} checked={panel.id in @selected} />
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
          <div class="wl-actions">
            <button type="submit" class="wl-button wl-button-secondary">Save arrangement</button>
            <a id="dashboard-deep-link" class="wl-button wl-button-secondary" href={@deep_link}>
              Exact link
            </a>
            <a
              id="dashboard-export"
              class="wl-button wl-button-secondary"
              href={@download_link}
              download
            >
              Download dashboard JSON
            </a>
          </div>
        </form>
      </details>
    </section>
    """
  end

  defp dashboard_path(path, selected) do
    query = Query.encode(%{"panels" => selected, "selection" => "custom"})
    path <> "?" <> query
  end
end
