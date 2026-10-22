defmodule WotexLabWorkbenchWeb.Components.TensorSummary do
  @moduledoc """
  Presents tensor metadata and an already bounded value preview.

  The caller supplies layout, backend, feature order, shape, dtype, units and
  quality alongside the preview's row, feature and element limits. Observed
  and filled counts describe that preview rather than the full batch. This
  component renders the summary without reading tensor storage or transferring
  values from a numerical backend.
  """

  use Phoenix.Component

  attr :summary, :map, required: true

  @doc "Renders metadata before the bounded value preview."
  @spec tensor_summary(map()) :: Phoenix.LiveView.Rendered.t()
  def tensor_summary(assigns) do
    ~H"""
    <section class="wl-panel" aria-labelledby="tensor-summary-title">
      <header class="wl-panel-header">
        <h2 id="tensor-summary-title">Tensor summary</h2>
      </header>
      <dl class="wl-facts">
        <div>
          <dt>Layout</dt><dd>{@summary.layout}</dd>
        </div>
        <div>
          <dt>Backend</dt><dd>{@summary.backend}</dd>
        </div>
        <div>
          <dt>Rows</dt><dd>{@summary.rows}</dd>
        </div>
        <div>
          <dt>Quality dtype</dt><dd>{@summary.quality.dtype}</dd>
        </div>
        <div>
          <dt>Quality shape</dt><dd>{inspect(@summary.quality.shape, charlists: :as_lists)}</dd>
        </div>
      </dl>
      <p class="wl-preview-bounds">
        Preview {@summary.preview_bounds.rows}/{@summary.rows} rows · {@summary.preview_bounds.features}/{@summary.preview_bounds.total_features} features · ≤ {@summary.preview_bounds.elements_per_feature} values/cell{if @summary.preview_bounds.truncated,
          do: " · Truncated"}
      </p>
      <p class="wl-sr-only">Observed/filled counts describe preview elements, not the full batch.</p>
      <div class="wl-table-wrap" role="region" aria-label="Feature metadata" tabindex="0">
        <table>
          <caption>Feature metadata</caption>
          <thead>
            <tr>
              <th scope="col">Feature</th><th scope="col">dtype</th><th scope="col">shape</th><th scope="col">
                unit
              </th><th scope="col">observed</th><th scope="col">filled</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={feature <- @summary.features}>
              <th scope="row">{feature.name}</th>
              <td>{feature.dtype}</td><td>{inspect(feature.shape, charlists: :as_lists)}</td><td>
                {feature.unit}
              </td>
              <td>{feature.observed}</td><td>{feature.filled}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="wl-table-wrap" role="region" aria-label="Bounded value preview" tabindex="0">
        <table aria-label="Bounded value preview; masked values remain labelled">
          <caption>Value preview</caption>
          <thead>
            <tr>
              <th scope="col">Time</th><th :for={name <- @summary.feature_order} scope="col">{name}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @summary.preview}>
              <th scope="row">{row.timestamp}</th><td :for={cell <- row.cells}>
                {cell.text} · quality {cell.quality}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end
end
