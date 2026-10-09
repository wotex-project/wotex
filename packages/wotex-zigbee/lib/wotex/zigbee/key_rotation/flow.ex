defmodule Wotex.Zigbee.KeyRotation.Flow do
  @moduledoc false

  alias Wotex.Zigbee.{Error, KeyRotation, Reply}
  alias Wotex.Zigbee.KeyRotation.Result
  alias Wotex.Zigbee.Network.Snapshot
  alias Wotex.Zigbee.PeerProbe.Flow, as: Probe

  @type t :: %{
          request: KeyRotation.t(),
          epoch: reference(),
          before: Snapshot.t() | nil,
          before_switch: Snapshot.t() | nil,
          after: Snapshot.t() | nil,
          admission: Reply.t() | nil,
          switch: Reply.t() | nil,
          probes: Probe.t()
        }

  @doc false
  @spec new(KeyRotation.t(), reference(), [byte()]) :: t()
  def new(request, epoch, tokens),
    do: %{
      request: request,
      epoch: epoch,
      before: nil,
      before_switch: nil,
      after: nil,
      admission: nil,
      switch: nil,
      probes: Probe.new(request.peers, epoch, tokens)
    }

  @doc false
  @spec finish(t(), Error.kind() | nil) :: Result.t()
  def finish(flow, issue) do
    peers = Probe.finish(flow.probes, issue)
    observed = KeyRotation.matches_snapshot?(flow.request, flow.after)
    complete = Enum.all?(peers, &(&1.outcome == :responsive and &1.issue == nil))
    admitted = match?(%Reply{status: 0}, flow.admission) and match?(%Reply{status: 0}, flow.switch)

    outcome =
      cond do
        issue == nil and observed and admitted and complete -> :observed_cohort_after_switch
        observed -> :partial
        true -> :unconfirmed
      end

    %Result{
      request: flow.request,
      owner_epoch: flow.epoch,
      before: flow.before,
      before_switch: flow.before_switch,
      after: flow.after,
      update: flow.admission,
      switch: flow.switch,
      peers: peers,
      outcome: outcome,
      activation: :unconfirmed,
      issue: issue
    }
  end
end
