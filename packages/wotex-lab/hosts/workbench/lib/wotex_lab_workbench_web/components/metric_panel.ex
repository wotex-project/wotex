defmodule WotexLabWorkbenchWeb.Components.MetricPanel do
  @moduledoc "A compact metric panel with explicit availability and freshness text."

  use Phoenix.Component

  attr :title, :string, required: true
  attr :value, :any, default: nil
  attr :unit, :string, default: nil
  attr :status, :string, default: "available"
  attr :note, :string, default: nil
  slot :inner_block

  @doc "Renders one saved metric panel; missing values are written as unavailable."
  @spec metric_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def metric_panel(assigns) do
    ~H"""
    <section class="wl-panel wl-metric-panel" aria-label={@title}>
      <header class="wl-panel-header">
        <h3>{@title}</h3>
        <span class="wl-metric-status">{@status}</span>
      </header>
      <p class="wl-metric-value">
        <%= if is_nil(@value) do %>
          <span>unavailable</span>
        <% else %>
          <span>{@value}</span><small :if={@unit}>{@unit}</small>
        <% end %>
      </p>
      <p :if={@note} class="wl-muted">{@note}</p>
      <div :if={@inner_block != []}>{render_slot(@inner_block)}</div>
    </section>
    """
  end
end
