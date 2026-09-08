defmodule WotexLabWorkbenchWeb.Components.PromptComposer do
  @moduledoc "An explicit, bounded investigation form; it never represents Action approval."

  use Phoenix.Component

  attr :value, :string, default: ""
  attr :disabled, :boolean, default: true
  attr :reason, :string, default: "No investigation provider is configured."

  @doc "Renders the optional ask form and states why it is unavailable."
  @spec prompt_composer(map()) :: Phoenix.LiveView.Rendered.t()
  def prompt_composer(assigns) do
    ~H"""
    <section class="wl-panel" aria-labelledby="ask-title">
      <header class="wl-panel-header">
        <h2 id="ask-title">Ask about this run</h2>
      </header>
      <form id="investigation" phx-submit="ask" class="wl-stack">
        <label for="investigation-prompt">Question</label>
        <textarea id="investigation-prompt" name="prompt" maxlength="512" rows="3" disabled={@disabled}>{@value}</textarea>
        <p class="wl-help">{@reason}</p>
        <button class="wl-button wl-button-secondary" type="submit" disabled={@disabled}>Ask</button>
      </form>
    </section>
    """
  end
end
