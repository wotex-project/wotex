defmodule WotexLabWorkbenchWeb.Components.AnswerBlock do
  @moduledoc """
  Presents an admitted investigation answer as facts, hypotheses and evidence gaps.

  The supplied answer includes provider and model identity, a suggested next
  check and optional source links. HEEx escapes the answer text; it is not
  interpreted as Markdown or executable content. The caller admits source
  destinations before rendering. This component neither calls a model nor
  executes the suggested check.
  """

  use Phoenix.Component

  attr :answer, :map, required: true

  @doc "Renders escaped facts, hypotheses, missing evidence and the next safe check."
  @spec answer_block(map()) :: Phoenix.LiveView.Rendered.t()
  def answer_block(assigns) do
    ~H"""
    <section class="wl-answer" aria-live="polite" aria-atomic="true">
      <header><strong>Investigation</strong> · {@answer.status}</header>
      <p class="wl-muted">Provider: {@answer.provider} · model: {@answer.model}</p>
      <h3>Observed facts</h3>
      <ul>
        <li :for={item <- @answer.observed}>{item}</li>
      </ul>
      <h3>Hypotheses</h3>
      <p :if={@answer.hypotheses == []} class="wl-muted">None reported.</p>
      <ul :if={@answer.hypotheses != []}>
        <li :for={item <- @answer.hypotheses}>{item}</li>
      </ul>
      <h3>Missing evidence</h3>
      <p :if={@answer.missing == []} class="wl-muted">None reported.</p>
      <ul :if={@answer.missing != []}>
        <li :for={item <- @answer.missing}>{item}</li>
      </ul>
      <h3>Next safe read-only check</h3>
      <p>{@answer.next_check}</p>
      <ul :if={Map.get(@answer, :sources, []) != []}>
        <li :for={source <- Map.get(@answer, :sources, [])}>
          <a href={source.href}>{source.label}</a>
        </li>
      </ul>
    </section>
    """
  end
end
