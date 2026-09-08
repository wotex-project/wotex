defmodule WotexLabWorkbenchWeb.Components.TensorSummary do
  @moduledoc "A bounded tensor summary that presents dtype, shape, units, masks and quality first."

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
          <dt>Quality shape</dt><dd>{inspect(@summary.quality.shape)}</dd>
        </div>
      </dl>
      <p>
        Preview: {@summary.preview_bounds.rows} of {@summary.rows} rows, {@summary.preview_bounds.features} of {@summary.preview_bounds.total_features} features;
        at most {@summary.preview_bounds.elements_per_feature} elements per feature cell. {if @summary.preview_bounds.truncated,
          do: "Preview truncated."} Observed/filled counts describe preview elements, not the full batch.
      </p>
      <div class="wl-table-wrap">
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
              <td>{feature.dtype}</td><td>{inspect(feature.shape)}</td><td>{feature.unit}</td>
              <td>{feature.observed}</td><td>{feature.filled}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="wl-table-wrap">
        <table>
          <caption>Bounded value preview; masked values remain labelled</caption>
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
