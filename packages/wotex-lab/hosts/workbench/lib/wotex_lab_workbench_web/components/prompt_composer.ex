defmodule WotexLabWorkbenchWeb.Components.PromptComposer do
  @moduledoc """
  Renders the optional investigation prompt and cancellation controls.

  The textarea advertises a 512-character browser limit and is disabled by
  default. The caller supplies the availability reason and running state.
  Submissions emit `ask`; cancellation emits `cancel_investigation`. The
  receiving LiveView enforces its own admission and size limits. Neither
  rendering nor submitting this form grants approval for an Action. An
  available `disclosure` from `WotexLabWorkbench.Investigation.Disclosure` is
  shown before the question: whether data leaves this host, its destinations,
  the bounded content sent and what is not sent.
  """

  use Phoenix.Component

  attr :value, :string, default: ""
  attr :disabled, :boolean, default: true
  attr :running, :boolean, default: false
  attr :reason, :string, default: "No investigation provider is configured."
  attr :disclosure, :map, default: nil
  attr :title, :string, default: "Ask about this run"
  attr :change_event, :string, default: nil
  attr :allow_draft, :boolean, default: false
  attr :compact, :boolean, default: false

  @doc "Renders the optional ask form and states why it is unavailable."
  @spec prompt_composer(map()) :: Phoenix.LiveView.Rendered.t()
  def prompt_composer(assigns) do
    ~H"""
    <section class={["wl-panel", @compact && "wl-prompt-compact"]} aria-labelledby="ask-title">
      <header class="wl-panel-header">
        <h2 id="ask-title">{@title}</h2>
      </header>
      <form id="investigation" phx-submit="ask" phx-change={@change_event} class="wl-stack">
        <label for="investigation-prompt">Question</label>
        <textarea
          id="investigation-prompt"
          name="prompt"
          maxlength="512"
          rows="3"
          disabled={@running or (@disabled and not @allow_draft)}
        >{@value}</textarea>
        <p class="wl-help">{@reason}</p>
        <details
          :if={@disclosure && @disclosure.available}
          id="investigation-disclosure"
          class="wl-stack"
          open={!@compact}
        >
          <summary>
            <strong>{if @disclosure.leaves_host,
              do: "Data leaves this host",
              else: "Data stays on this host"}</strong>
          </summary>
          <p>Destination: {Enum.join(@disclosure.destinations, "; ")}.</p>
          <p>Each request can include:</p>
          <ul>
            <li :for={item <- @disclosure.sent}>{item}</li>
          </ul>
          <p class="wl-help">{@disclosure.withheld}</p>
        </details>
        <div class="wl-actions">
          <button class="wl-button wl-button-secondary" type="submit" disabled={@disabled}>Ask</button>
          <button
            :if={@running}
            class="wl-button wl-button-secondary"
            type="button"
            phx-click="cancel_investigation"
          >
            Cancel investigation
          </button>
        </div>
      </form>
    </section>
    """
  end
end
