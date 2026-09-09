defmodule WotexLabWorkbenchWeb.Components.Tabs do
  @moduledoc """
  Renders a server-selected tab list and the supplied panel slots.

  Tab ids connect buttons and panels through ARIA attributes. The active tab
  controls focus eligibility and panel visibility; clicking sends its id in
  the configured LiveView event. The parent validates the id and updates state.
  Hidden panels are still rendered, so their slots must not rely on visibility
  to prevent work or restrict access.
  """

  use Phoenix.Component

  attr :id, :string, required: true
  attr :active, :string, required: true
  attr :event, :string, default: "select_tab", doc: "the event pushed with `phx-value-tab`"

  slot :tab, required: true do
    attr :id, :string, required: true
    attr :label, :string, required: true
  end

  @doc "Renders the tab list and the active panel."
  @spec tabs(map()) :: Phoenix.LiveView.Rendered.t()
  def tabs(assigns) do
    ~H"""
    <div class="wl-tabs" id={@id}>
      <div role="tablist" class="wl-tablist" aria-label="Sections">
        <button
          :for={tab <- @tab}
          type="button"
          role="tab"
          id={"#{@id}-tab-#{tab.id}"}
          aria-selected={to_string(tab.id == @active)}
          aria-controls={"#{@id}-panel-#{tab.id}"}
          tabindex={if tab.id == @active, do: "0", else: "-1"}
          phx-click={@event}
          phx-value-tab={tab.id}
          class="wl-tab"
        >
          {tab.label}
        </button>
      </div>
      <div
        :for={tab <- @tab}
        role="tabpanel"
        id={"#{@id}-panel-#{tab.id}"}
        aria-labelledby={"#{@id}-tab-#{tab.id}"}
        hidden={tab.id != @active}
        class="wl-tabpanel"
      >
        {render_slot(tab)}
      </div>
    </div>
    """
  end
end
