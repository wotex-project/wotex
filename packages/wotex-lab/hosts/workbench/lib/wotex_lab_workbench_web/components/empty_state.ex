defmodule WotexLabWorkbenchWeb.Components.EmptyState do
  @moduledoc "Empty and error states that explain one clear next action."

  use Phoenix.Component

  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :action, doc: "one next action"

  @doc "Renders an empty state."
  @spec empty_state(map()) :: Phoenix.LiveView.Rendered.t()
  def empty_state(assigns) do
    ~H"""
    <section class="wl-empty" aria-label={@title}>
      <h2>{@title}</h2>
      <p :if={@description}>{@description}</p>
      <div :if={@action != []} class="wl-empty-action">{render_slot(@action)}</div>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :code, :string, default: nil
  attr :message, :string, default: nil
  slot :action

  @doc "Renders an error state; the code and message are plain text."
  @spec error_state(map()) :: Phoenix.LiveView.Rendered.t()
  def error_state(assigns) do
    ~H"""
    <section class="wl-error-state" role="alert">
      <h2>{@title}</h2>
      <p :if={@code}><code>{@code}</code></p>
      <p :if={@message}>{@message}</p>
      <div :if={@action != []} class="wl-empty-action">{render_slot(@action)}</div>
    </section>
    """
  end
end
