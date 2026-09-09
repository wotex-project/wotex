defmodule WotexLabWorkbenchWeb.Components.EmptyState do
  @moduledoc """
  Renders explanatory states when a view has no result or an operation fails.

  Empty states contain a title, optional description and an action slot.
  Error states use an alert region and render the supplied code and message as
  escaped text. The caller selects a useful next action and supplies bounded,
  public diagnostics; this component does not inspect exceptions or retry work.
  """

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
