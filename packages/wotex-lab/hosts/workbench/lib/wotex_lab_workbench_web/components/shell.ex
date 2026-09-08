defmodule WotexLabWorkbenchWeb.Components.Shell do
  @moduledoc """
  The workbench shell: skip link, collapsible sidebar navigation, compact
  context line and one main workspace, themed through `data-theme`.
  """

  use Phoenix.Component

  import WotexLabWorkbenchWeb.Components.Button

  @items [
    {:experiments, "Experiments", "/"},
    {:things, "Things", "/things"},
    {:metrics, "Metrics", "/metrics"},
    {:evidence, "Evidence", "/evidence"}
  ]

  @doc "Sidebar items as `{id, label, path}`."
  @spec items() :: [{atom(), String.t(), String.t()}]
  def items, do: @items

  attr :theme, :string, default: "system", doc: "system, light or dark"
  attr :sidebar_open, :boolean, default: true
  attr :current, :atom, default: :experiments, doc: "the active sidebar item"
  attr :title, :string, default: "WoTEx Lab workbench"
  slot :context, doc: "the compact context line"
  slot :settings, doc: "replaces the default theme settings at the sidebar bottom"
  slot :inner_block, required: true

  @doc "Renders the shell around the main workspace."
  @spec shell(map()) :: Phoenix.LiveView.Rendered.t()
  def shell(assigns) do
    assigns = assign(assigns, :items, @items)

    ~H"""
    <div class={["wotex-lab", "wl-shell", @sidebar_open && "wl-shell-open"]} data-theme={theme(@theme)}>
      <a class="wl-skip" href="#main">Skip to main content</a>
      <header class="wl-topbar">
        <.icon_button
          label={if @sidebar_open, do: "Collapse sidebar", else: "Expand sidebar"}
          icon={:menu}
          phx-click="toggle_sidebar"
          aria-expanded={to_string(@sidebar_open)}
          aria-controls="wl-sidebar"
        />
        <span class="wl-brand">{@title}</span>
        <div class="wl-context-slot">{render_slot(@context)}</div>
      </header>
      <nav id="wl-sidebar" class="wl-sidebar" aria-label="Workbench" hidden={!@sidebar_open}>
        <ul class="wl-nav">
          <li :for={{id, label, path} <- @items}>
            <.link navigate={path} class="wl-nav-link" aria-current={if id == @current, do: "page"}>
              {label}
            </.link>
          </li>
        </ul>
        <div class="wl-sidebar-footer">
          <%= if @settings == [] do %>
            <form id="theme-settings" phx-change="set_theme" class="wl-settings">
              <label for="wl-theme">Theme</label>
              <select id="wl-theme" name="theme">
                <option :for={value <- ~w(system light dark)} value={value} selected={value == @theme}>
                  {value}
                </option>
              </select>
            </form>
            <a class="wl-nav-link wl-nav-muted" href="/session/new">New session</a>
          <% else %>
            {render_slot(@settings)}
          <% end %>
        </div>
      </nav>
      <main id="main" class="wl-main" tabindex="-1">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  defp theme("light"), do: "light"
  defp theme("dark"), do: "dark"
  defp theme(_system), do: nil
end
