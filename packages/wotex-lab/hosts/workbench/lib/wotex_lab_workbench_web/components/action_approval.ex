defmodule WotexLabWorkbenchWeb.Components.ActionApproval do
  @moduledoc """
  Renders the approval form for a supplied simulated Action decision.

  The form exposes the Thing, Action input, proposal digest, state revision
  and expiry before submitting the `approve` event. Hidden fields identify
  that decision; the LiveView must revalidate them against its owned run.
  Rendering the form performs no authorization or Action dispatch. Cancellation
  is a separate event tied to the same run.
  """

  use Phoenix.Component

  attr :run, :any, required: true
  attr :remaining_ms, :integer, default: nil

  @doc "Names the exact operation, input, digest, revision and expiry before approval."
  @spec action_approval(map()) :: Phoenix.LiveView.Rendered.t()
  def action_approval(assigns) do
    decision = assigns.run.decision

    assigns =
      assign(assigns,
        decision: decision,
        expired: is_integer(assigns.remaining_ms) and assigns.remaining_ms <= 0
      )

    ~H"""
    <section class="wl-panel wl-approval" aria-labelledby="approval-title">
      <header class="wl-panel-header">
        <h2 id="approval-title">Approve simulated Action</h2>
      </header>
      <p>One simulated Action. Running the experiment did not dispatch it.</p>
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
          <dt>Expiry</dt><dd>{expiry(@remaining_ms, @decision)}</dd>
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
          disabled={@expired}
          phx-disable-with="Approving…"
        >Approve Action</button>
        <button
          class="wl-button wl-button-secondary"
          type="button"
          phx-click="cancel"
          phx-value-id={@run.id}
        >Cancel run</button>
      </form>
      <details class="wl-disclosure">
        <summary>Decision clock</summary>
        <dl class="wl-meta-list">
          <dt>Expires at (monotonic ms)</dt><dd>{@decision["expires_at"]}</dd>
        </dl>
      </details>
    </section>
    """
  end

  defp expiry(nil, decision), do: to_string(decision["expires_at"])
  defp expiry(remaining, _) when remaining <= 0, do: "Expired · cancel this run"
  defp expiry(remaining, _), do: "#{div(remaining + 999, 1_000)} s remaining"
end
