defmodule WotexLabWorkbench.Run do
  @moduledoc """
  One completed or failed experiment run inside a room.

  A run carries a summary, the tensor summary (dtype, shape, backend, units,
  masks and quality codes before any number), bounded timeseries, assertion
  outcomes, the cleanup result, the inert proposal, an optional granted
  decision awaiting explicit approval, the dispatch outcome and effect once
  approved, and the evidence record with its digest. Nothing in a run is an
  authorization: the room's policy decides at dispatch time.
  """

  @type status :: :completed | :failed | :awaiting_approval | :dispatched | :cancelled

  @type t :: %__MODULE__{
          id: String.t(),
          experiment: String.t(),
          attempt: pos_integer(),
          params: keyword(),
          status: status(),
          source_mode: String.t(),
          backend: String.t(),
          started_at: DateTime.t(),
          duration_ms: non_neg_integer(),
          summary: [{String.t(), String.t()}],
          tensor: map() | nil,
          timeseries: [map()],
          assertions: [%{id: String.t(), status: atom(), note: String.t()}],
          cleanup: %{status: :ok | :failed, details: map()},
          proposal: map() | nil,
          decision: map() | nil,
          dispatch: map() | nil,
          effect: term(),
          record: Wotex.Lab.Evidence.Record.t() | nil,
          record_digest: String.t() | nil,
          error: map() | nil
        }

  @enforce_keys [:id, :experiment, :attempt, :params, :status, :source_mode, :backend, :started_at]
  defstruct [
    :id,
    :experiment,
    :attempt,
    :params,
    :status,
    :source_mode,
    :backend,
    :started_at,
    duration_ms: 0,
    summary: [],
    tensor: nil,
    timeseries: [],
    assertions: [],
    cleanup: %{status: :ok, details: %{}},
    proposal: nil,
    decision: nil,
    dispatch: nil,
    effect: nil,
    record: nil,
    record_digest: nil,
    error: nil
  ]

  @doc "The plain-text state shown in the context line and badges."
  @spec state_text(t()) :: String.t()
  def state_text(%__MODULE__{status: :completed}), do: "completed"
  def state_text(%__MODULE__{status: :failed}), do: "failed"
  def state_text(%__MODULE__{status: :awaiting_approval}), do: "awaiting approval"
  def state_text(%__MODULE__{status: :dispatched}), do: "dispatched"
  def state_text(%__MODULE__{status: :cancelled}), do: "cancelled"
end
