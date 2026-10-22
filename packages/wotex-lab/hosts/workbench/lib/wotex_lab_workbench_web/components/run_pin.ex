defmodule WotexLabWorkbenchWeb.Components.RunPin do
  @moduledoc "Captured Run result, original record and pin presentation controls."

  use WotexLabWorkbenchWeb, :html

  attr(:pin, :map, required: true)

  @doc "Renders an already-owned capture without refreshing or running its source."
  @spec run_pin(map()) :: Phoenix.LiveView.Rendered.t()
  def run_pin(assigns) do
    ~H"""
    <section id="wl-run-pin" class="wl-stack" aria-label="Pinned Run result">
      <form id="rename-run-pin" phx-submit="rename_pin" class="wl-stack">
        <input type="hidden" name="pin_id" value={@pin.id} />
        <.field id="run-pin-title" name="title" label="Title" value={@pin.title} maxlength={128} />
        <div class="wl-actions"><button class="wl-button wl-button-secondary">Rename</button></div>
      </form>
      <div :if={@pin.outcome} class="wl-run-outcome">
        <p class="wl-muted">{@pin.outcome.label}</p>
        <div class="wl-run-value">
          <strong>{@pin.outcome.value}</strong><span>{@pin.outcome.unit}</span>
        </div>
      </div>
      <p class="wl-muted">{@pin.error || "Captured · #{@pin.captured_state}"}</p>
      <.chart :if={@pin.result} id="pinned-run-chart" chart={@pin.result.chart} compact />
      <div class="wl-actions">
        <.link :if={is_nil(@pin.error)} patch={@pin.path} class="wl-button wl-button-secondary">Open run</.link>
        <button
          type="button"
          class="wl-button wl-button-secondary"
          phx-click="remove_pin"
          phx-value-pin_id={@pin.id}
        >Remove</button>
      </div>
      <details class="wl-disclosure">
        <summary>Sources</summary>
        <dl class="wl-meta-list">
          <dt>Run</dt><dd>{@pin.run_id}</dd>
          <dt>Started</dt><dd>{@pin.started_at}</dd>
          <dt>Source mode</dt><dd>{@pin.source_mode}</dd>
          <dt>Captured record</dt><dd><code>{@pin.record_digest}</code></dd>
          <dt>Analysis</dt><dd>
            <code :if={@pin.query}>{Jason.encode!(@pin.query)}</code><span :if={is_nil(@pin.query)}>Original series</span>
          </dd>
        </dl>
        <details :if={@pin.record} class="wl-disclosure">
          <summary>Full record</summary><pre><code>{Jason.encode!(@pin.record, pretty: true)}</code></pre>
        </details>
      </details>
    </section>
    """
  end
end
