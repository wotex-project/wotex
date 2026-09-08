defmodule WotexLabWorkbenchWeb.Components.EvidenceLink do
  @moduledoc "A source/evidence link that keeps its digest visible in text."

  use Phoenix.Component

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :digest, :string, default: nil
  attr :download, :boolean, default: false

  @doc "Renders a link and optional digest without interpreting either value as markup."
  @spec evidence_link(map()) :: Phoenix.LiveView.Rendered.t()
  def evidence_link(assigns) do
    ~H"""
    <a class="wl-evidence-link" href={@href} download={@download}>
      <span>{@label}</span><code :if={@digest}>{@digest}</code>
    </a>
    """
  end
end
