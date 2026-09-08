defmodule WotexLabWorkbenchWeb.Components.Button do
  @moduledoc """
  Buttons with accessible names. A disabled button is a presentation state
  only: the server admits every command on its own.
  """

  use Phoenix.Component

  @icons %{
    menu: "M3 6h18M3 12h18M3 18h18",
    close: "M6 6l12 12M18 6L6 18",
    refresh: "M4 12a8 8 0 0 1 14-5l2 2M20 4v5h-5M20 12a8 8 0 0 1-14 5l-2-2M4 20v-5h5",
    download: "M12 4v12m0 0l-4-4m4 4l4-4M4 20h16"
  }

  attr :type, :string, default: "button"
  attr :variant, :atom, default: :secondary, values: [:primary, :secondary, :danger]
  attr :disabled, :boolean, default: false

  attr :rest, :global,
    include: ~w(form name value phx-click phx-value-id phx-disable-with aria-describedby)

  slot :inner_block, required: true

  @doc "A text button."
  @spec button(map()) :: Phoenix.LiveView.Rendered.t()
  def button(assigns) do
    ~H"""
    <button type={@type} class={["wl-button", "wl-button-#{@variant}"]} disabled={@disabled} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :label, :string, required: true, doc: "the accessible name"
  attr :icon, :atom, required: true, values: Map.keys(@icons)
  attr :rest, :global, include: ~w(phx-click aria-expanded aria-controls disabled)

  @doc "An icon-only button whose name is its label."
  @spec icon_button(map()) :: Phoenix.LiveView.Rendered.t()
  def icon_button(assigns) do
    assigns = assign(assigns, :path, Map.fetch!(@icons, assigns.icon))

    ~H"""
    <button type="button" class="wl-icon-button" aria-label={@label} title={@label} {@rest}>
      <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false">
        <path d={@path} fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" />
      </svg>
    </button>
    """
  end
end
