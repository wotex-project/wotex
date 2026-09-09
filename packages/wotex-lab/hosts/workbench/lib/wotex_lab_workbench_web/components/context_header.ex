defmodule WotexLabWorkbenchWeb.Components.ContextHeader do
  @moduledoc """
  Displays the caller's run context as a labelled description list.

  Ordered label/value pairs usually identify the run, source mode, numerical
  backend and state. Values are escaped text and retain the caller's order.
  The component performs no lookup or status inference; the LiveView supplies
  the context for its current admitted run.
  """

  use Phoenix.Component

  attr :items, :list, required: true, doc: "`{label, value}` pairs rendered as a description list"
  attr :class, :string, default: nil

  @doc "Renders the context line."
  @spec context_header(map()) :: Phoenix.LiveView.Rendered.t()
  def context_header(assigns) do
    ~H"""
    <dl class={["wl-context", @class]} aria-label="Run context">
      <div :for={{label, value} <- @items} class="wl-context-item">
        <dt>{label}</dt>
        <dd>{value}</dd>
      </div>
    </dl>
    """
  end
end
