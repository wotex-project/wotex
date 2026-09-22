defmodule WotexLabStorybookWeb.Island do
  @moduledoc "Renders the Lab-owned Svelte boundary used by Phoenix Storybook."

  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias Wotex.Lab.Island.Snapshot

  attr(:id, :string, required: true)
  attr(:component, :string, required: true)
  attr(:props, :map, required: true)
  attr(:generation, :string, default: "0")
  attr(:revision, :string, default: "0")
  attr(:capabilities, :list, default: [])
  attr(:target, :any, default: nil)
  slot(:fallback, required: true)

  @doc "Renders one semantic fallback beside its ignored Svelte mount root."
  @spec island(map()) :: Phoenix.LiveView.Rendered.t()
  def island(assigns) do
    {:ok, snapshot} =
      Snapshot.new(assigns.component, assigns.id, assigns.props,
        generation: assigns.generation,
        revision: assigns.revision,
        capabilities: assigns.capabilities
      )

    {:ok, encoded} = Snapshot.encode_inline(snapshot)

    assigns =
      assigns
      |> assign(:encoded, encoded)
      |> assign(:mount_id, assigns.id <> "--svelte")
      |> assign(:fallback_id, assigns.id <> "--fallback")
      |> assign(:ignore_readiness, JS.ignore_attributes(["data-wotex-island-state"]))

    ~H"""
    <section
      id={@id}
      data-wotex-island={@component}
      data-wotex-island-state="loading"
      data-wotex-design-system
      phx-mounted={@ignore_readiness}
    >
      <div id={@fallback_id} data-wotex-island-fallback>{render_slot(@fallback)}</div>
      <div
        id={@mount_id}
        data-wotex-island-mount
        data-wotex-island-instance={@id}
        data-wotex-island-component={@component}
        data-wotex-island-snapshot={@encoded}
        data-wotex-island-target={@target}
        phx-hook="WotexLabSvelteIsland"
        phx-update="ignore"
      >
      </div>
    </section>
    """
  end
end
