defmodule WotexLabWorkbenchWeb.Components.ContextHeader do
  @moduledoc "The compact context line: run identity, source mode, backend and state as text."

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
