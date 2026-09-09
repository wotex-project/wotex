defmodule WotexLabWorkbenchWeb.Components.EvidenceLink do
  @moduledoc """
  Renders an evidence destination with its optional digest visible beside the label.

  Labels and digests are escaped text, and the optional download attribute
  requests browser download behavior. The caller owns destination admission and
  digest verification. Displaying a digest neither fetches the target nor
  establishes that its content matches the digest.
  """

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
