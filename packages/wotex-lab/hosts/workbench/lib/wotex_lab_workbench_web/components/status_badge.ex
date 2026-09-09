defmodule WotexLabWorkbenchWeb.Components.StatusBadge do
  @moduledoc """
  Displays a status label with an optional semantic colour.

  `kind_for/1` maps the listed common status values to success, danger, warning
  or information styling and uses neutral styling for every other value.
  The label remains visible text. The mapping is presentation only; it does
  not classify evidence, grant authority or change an underlying run state.
  """

  use Phoenix.Component

  @kinds ~w(neutral info success warning danger)a

  attr :status, :string, required: true, doc: "the visible status text"
  attr :kind, :atom, default: :neutral, values: @kinds

  @doc "Renders the badge."
  @spec status_badge(map()) :: Phoenix.LiveView.Rendered.t()
  def status_badge(assigns) do
    ~H"""
    <span class={["wl-badge", "wl-badge-#{@kind}"]}>{@status}</span>
    """
  end

  @doc "Maps common status words to a badge kind."
  @spec kind_for(term()) :: atom()
  def kind_for(status)
      when status in [:pass, :completed, :dispatched, :granted, :ok, "pass", "completed", "ok"],
      do: :success

  def kind_for(status) when status in [:fail, :failed, :error, :denied, "fail", "failed", "error"],
    do: :danger

  def kind_for(status)
      when status in [
             :awaiting_approval,
             :inconclusive,
             :timeout,
             :stale,
             "awaiting approval",
             "stale"
           ],
      do: :warning

  def kind_for(status) when status in [:running, :loading, "running", "loading"], do: :info
  def kind_for(_status), do: :neutral
end
