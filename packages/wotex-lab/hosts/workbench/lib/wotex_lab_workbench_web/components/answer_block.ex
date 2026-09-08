defmodule WotexLabWorkbenchWeb.Components.AnswerBlock do
  @moduledoc "A restrained investigation answer with explicit source links and status text."

  use Phoenix.Component

  attr :answer, :map, required: true

  @doc "Renders escaped answer text and the evidence sources it used."
  @spec answer_block(map()) :: Phoenix.LiveView.Rendered.t()
  def answer_block(assigns) do
    ~H"""
    <section class="wl-answer" aria-live="polite" aria-atomic="true">
      <header><strong>Investigation</strong> · {@answer.status}</header>
      <p>{@answer.text}</p>
      <ul :if={Map.get(@answer, :sources, []) != []}>
        <li :for={source <- Map.get(@answer, :sources, [])}>
          <a href={source.href}>{source.label}</a>
        </li>
      </ul>
    </section>
    """
  end
end
