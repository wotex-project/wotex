defmodule WotexLabWorkbenchWeb.Components.Shell do
  @moduledoc """
  The workbench shell: skip link, collapsible sidebar navigation, compact
  context line and one main workspace, themed through the Wotex Lab
  semantic-token contract.
  """

  use Phoenix.Component

  import WotexLabWorkbenchWeb.Components.Button

  @items [
    {:experiments, "Experiments", "/"},
    {:things, "Things", "/things"},
    {:metrics, "Metrics", "/metrics"},
    {:evidence, "Evidence", "/evidence"},
    {:docs, "Docs", "/docs/start/"}
  ]
  @icons %{
    experiments: "M9 3v5l-4.5 8a3 3 0 0 0 2.6 4.5h9.8a3 3 0 0 0 2.6-4.5L15 8V3M8 12h8",
    things: "m4 7 8-4 8 4-8 4-8-4Zm0 0v10l8 4 8-4V7M12 11v10",
    metrics: "M4 19V9m5 10V5m5 14v-7m5 7V3",
    evidence: "M6 3h9l3 3v15H6V3Zm8 0v4h4M9 12l2 2 4-5",
    docs:
      "M4 5.5A2.5 2.5 0 0 1 6.5 3H12v17H6.5A2.5 2.5 0 0 0 4 22V5.5Zm16 0A2.5 2.5 0 0 0 17.5 3H12v17h5.5A2.5 2.5 0 0 1 20 22V5.5Z"
  }

  @doc "Sidebar items as `{id, label, path}`."
  @spec items() :: [{atom(), String.t(), String.t()}]
  def items, do: @items

  attr(:theme, :string, default: "system", doc: "system, light, dark or contrast")
  attr(:sidebar_open, :boolean, default: true)
  attr(:current, :atom, default: :experiments, doc: "the active sidebar item")
  attr(:title, :string, default: "WoTEx Lab workbench")
  slot(:context, doc: "the compact context line")
  slot(:settings, doc: "replaces the default theme settings at the sidebar bottom")
  slot(:inner_block, required: true)

  @doc "Renders the shell around the main workspace."
  @spec shell(map()) :: Phoenix.LiveView.Rendered.t()
  def shell(assigns) do
    assigns =
      assigns
      |> assign(:items, @items)
      |> assign(:icons, @icons)
      |> assign(:design_contract, design_contract())

    ~H"""
    <div
      class={["wotex-lab", "wl-shell", @sidebar_open && "wl-shell-open"]}
      data-wotex-design-system
      data-wotex-theme={theme(@theme)}
      data-theme={theme(@theme)}
      data-wotex-token-digest={@design_contract["token_digest"]}
      data-wotex-component-digest={@design_contract["component_registry_digest"]}
      data-wotex-fixture-digest={@design_contract["story_fixture_digest"]}
      data-wotex-stylesheet-digest={@design_contract["stylesheet_digest"]}
    >
      <a class="wl-skip" href="#main">Skip to main content</a>
      <header class="wl-topbar">
        <.icon_button
          label={if @sidebar_open, do: "Collapse sidebar", else: "Expand sidebar"}
          icon={:menu}
          phx-click="toggle_sidebar"
          aria-expanded={to_string(@sidebar_open)}
          aria-controls="wl-sidebar"
        />
        <span class="wl-brand" aria-label={@title}>
          <span class="wl-brand-mark" aria-hidden="true">
            <svg viewBox="0 0 24 24" focusable="false">
              <path d="M3 4.5 7.5 20 12 9.5 16.5 20 21 4.5" />
            </svg>
          </span>
          <span class="wl-brand-copy"><strong>WoTEx</strong><small>Lab workbench</small></span>
        </span>
        <div class="wl-context-slot">{render_slot(@context)}</div>
      </header>
      <nav id="wl-sidebar" class="wl-sidebar" aria-label="Workbench" hidden={!@sidebar_open}>
        <ul class="wl-nav">
          <li :for={{id, label, path} <- @items}>
            <.link navigate={path} class="wl-nav-link" aria-current={if id == @current, do: "page"}>
              <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                <path d={Map.fetch!(@icons, id)} />
              </svg>
              <span>{label}</span>
            </.link>
          </li>
        </ul>
        <div class="wl-sidebar-footer">
          <%= if @settings == [] do %>
            <form id="theme-settings" phx-change="set_theme" class="wl-settings">
              <label for="wl-theme">Appearance</label>
              <select id="wl-theme" name="theme">
                <option
                  :for={value <- ~w(system light dark contrast)}
                  value={value}
                  selected={value == @theme}
                >
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
  defp theme("contrast"), do: "contrast"
  defp theme(_), do: nil

  defp design_contract do
    {:ok, contract} = WotexLabWorkbench.Documentation.DesignContract.current()
    contract
  end
end
