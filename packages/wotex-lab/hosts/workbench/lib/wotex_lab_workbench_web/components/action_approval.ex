defmodule WotexLabWorkbenchWeb.Components.ActionApproval do
  @moduledoc "The explicit approval form for one fresh, granted simulated Action decision."

  use Phoenix.Component

  attr :run, :any, required: true

  @doc "Names the exact operation, input, digest, revision and expiry before approval."
  @spec action_approval(map()) :: Phoenix.LiveView.Rendered.t()
  def action_approval(assigns) do
    decision = assigns.run.decision
    assigns = assign(assigns, :decision, decision)

    ~H"""
    <section class="wl-panel wl-approval" aria-labelledby="approval-title">
      <header class="wl-panel-header">
        <h2 id="approval-title">Approve simulated Action</h2>
      </header>
      <p>This is a separate command. Running the experiment did not dispatch it.</p>
      <dl class="wl-facts">
        <div>
          <dt>Thing</dt><dd>{@decision["thing_id"]}</dd>
        </div>
        <div>
          <dt>Operation</dt><dd>{@decision["action_name"]}</dd>
        </div>
        <div>
          <dt>Input</dt><dd>{@decision["input"]}</dd>
        </div>
        <div>
          <dt>Proposal digest</dt><dd><code>{@decision["proposal_digest"]}</code></dd>
        </div>
        <div>
          <dt>State revision</dt><dd>{@decision["state_revision"]}</dd>
        </div>
        <div>
          <dt>Expires at</dt><dd>{@decision["expires_at"]}</dd>
        </div>
      </dl>
      <form id={"approve-#{@run.id}"} phx-submit="approve" class="wl-actions">
        <input type="hidden" name="decision_id" value={@decision["id"]} />
        <input type="hidden" name="proposal_digest" value={@decision["proposal_digest"]} />
        <input type="hidden" name="revision" value={@decision["state_revision"]} />
        <input type="hidden" name="expires_at" value={@decision["expires_at"]} />
        <input type="hidden" name="run_id" value={@run.id} />
        <button
          class="wl-button wl-button-primary"
          type="submit"
          phx-disable-with="Approving…"
        >Approve this simulated Action</button>
        <button
          class="wl-button wl-button-secondary"
          type="button"
          phx-click="cancel"
          phx-value-id={@run.id}
        >Cancel run</button>
      </form>
    </section>
    """
  end
end
