defmodule WotexLabWorkbenchWeb.Components.Shell do
  @moduledoc """
  A floating board menu and one main workspace, themed through the Wotex Lab
  semantic-token contract. Session details and appearance stay inside the menu.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @items [
    {:workbench, "Workbench", "/"},
    {:experiments, "Experiments", "/experiments"},
    {:metrics, "Metrics", "/metrics"},
    {:docs, "Docs", "/docs/start/"}
  ]
  @icons %{
    experiments: "flask-conical",
    workbench: "waypoints",
    metrics: "chart-no-axes-combined",
    docs: "book-open"
  }

  @doc "Board menu destinations as `{id, label, path}`."
  @spec items() :: [{atom(), String.t(), String.t()}]
  def items, do: @items

  attr(:theme, :string, default: "system", doc: "system, light, dark or contrast")
  attr(:sidebar_open, :boolean, default: false, doc: "whether the board menu is expanded")
  attr(:current, :atom, default: :experiments, doc: "the active destination")
  attr(:canvas, :boolean, default: false, doc: "whether the main workspace fills the viewport")
  attr(:title, :string, default: "WoTEx Lab workbench")
  slot(:context, doc: "session details inside the board menu")
  slot(:actions, doc: "contextual board actions")
  slot(:settings, doc: "replaces the default appearance settings")
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
      class={["wotex-lab", "wl-shell", @canvas && "wl-shell-canvas"]}
      data-wotex-design-system
      data-wotex-theme={theme(@theme)}
      data-theme={theme(@theme)}
      data-wotex-token-digest={@design_contract["token_digest"]}
      data-wotex-component-digest={@design_contract["component_registry_digest"]}
      data-wotex-fixture-digest={@design_contract["story_fixture_digest"]}
      data-wotex-stylesheet-digest={@design_contract["stylesheet_digest"]}
      phx-mounted={JS.ignore_attributes(["data-layout-profile"])}
    >
      <a class="wl-skip" href="#main">Skip to main content</a>
      <header class="wl-board-chrome" aria-label={@title}>
        <button
          id="wl-board-toggle"
          type="button"
          class="wl-board-toggle"
          aria-label="Board menu"
          phx-click="toggle_sidebar"
          aria-expanded={to_string(@sidebar_open)}
          aria-controls="wl-sidebar"
        >
          <img class="wl-board-logo" src="/brand/wotex.svg" alt="WoTEx" width="28" height="20" />
          <span>Lab room</span>
          <img class="wl-menu-icon" src="/icons/chevron-down.svg" alt="" width="14" height="14" />
        </button>
        <nav
          id="wl-sidebar"
          class="wl-board-menu"
          aria-label="Workbench"
          hidden={!@sidebar_open}
          phx-click-away={@sidebar_open && "close_board_menu"}
          phx-window-keydown={
            if @sidebar_open, do: JS.push("close_board_menu") |> JS.focus(to: "#wl-board-toggle")
          }
          phx-key="Escape"
        >
          <ul class="wl-nav">
            <li :for={{id, label, path} <- @items}>
              <.link
                :if={id != :docs}
                patch={path}
                class="wl-nav-link"
                aria-current={if id == @current, do: "page"}
              >
                <img
                  class="wl-menu-icon"
                  src={"/icons/#{Map.fetch!(@icons, id)}.svg"}
                  alt=""
                  width="16"
                  height="16"
                />
                <span>{label}</span>
              </.link>
              <.link
                :if={id == :docs}
                href={path}
                id="wl-documentation-link"
                phx-hook="WotexDocumentationLink"
                class="wl-nav-link"
              >
                <img class="wl-menu-icon" src="/icons/book-open.svg" alt="" width="16" height="16" />
                <span>{label}</span>
              </.link>
            </li>
          </ul>
          <div :if={@actions != []} class="wl-board-actions">{render_slot(@actions)}</div>
          <div class="wl-board-settings">
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
          <details :if={@context != []} class="wl-board-context">
            <summary>Session</summary>
            {render_slot(@context)}
          </details>
        </nav>
      </header>
      <main
        id="main"
        class="wl-main"
        tabindex="-1"
        phx-mounted={JS.ignore_attributes(["data-layout-profile"])}
      >
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
