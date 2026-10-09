defmodule Wotex.Zigbee.ChannelMigration.Flow do
  @moduledoc false

  alias Wotex.Zigbee.{ChannelMigration, Error, Reply}
  alias Wotex.Zigbee.ChannelMigration.Result
  alias Wotex.Zigbee.Network.Snapshot
  alias Wotex.Zigbee.PeerProbe.Flow, as: Probe

  @type t :: %{
          request: ChannelMigration.t(),
          epoch: reference(),
          before: Snapshot.t() | nil,
          after: Snapshot.t() | nil,
          admission: Reply.t() | nil,
          probes: Probe.t()
        }

  @doc false
  @spec new(ChannelMigration.t(), reference(), [byte()]) :: t()
  def new(request, epoch, tokens),
    do: %{
      request: request,
      epoch: epoch,
      before: nil,
      after: nil,
      admission: nil,
      probes: Probe.new(request.peers, epoch, tokens)
    }

  @doc false
  @spec finish(t(), Error.kind() | nil) :: Result.t()
  def finish(flow, issue) do
    peers = Probe.finish(flow.probes, issue)
    observed = ChannelMigration.matches_snapshot?(flow.request, flow.after, :after)
    complete = Enum.all?(peers, &(&1.outcome == :responsive and &1.issue == nil))

    outcome =
      cond do
        issue == nil and observed and complete -> :observed_cohort
        observed -> :partial
        true -> :unconfirmed
      end

    %Result{
      request: flow.request,
      owner_epoch: flow.epoch,
      before: flow.before,
      after: flow.after,
      admission: flow.admission,
      peers: peers,
      outcome: outcome,
      issue: issue
    }
  end
end
