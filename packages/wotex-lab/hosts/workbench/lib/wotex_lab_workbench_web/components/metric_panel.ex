defmodule WotexLabWorkbenchWeb.Components.MetricPanel do
  @moduledoc """
  Displays one supplied metric value with its availability, unit and explanatory note.

  A nil value renders as unavailable; numeric zero remains a value. Status and
  freshness are supplied by the caller rather than inferred from the number.
  An optional slot holds supporting content. This presentation component does
  not read a collector or history store. Set `value_visible` to false when the
  slot carries the measurement, such as a chart, so no single value is implied.
  """

  use Phoenix.Component

  attr :title, :string, required: true
  attr :value, :any, default: nil
  attr :unit, :string, default: nil
  attr :status, :string, default: "available"
  attr :note, :string, default: nil
  attr :value_visible, :boolean, default: true
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
      <p :if={@value_visible} class="wl-metric-value">
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
