defmodule Wotex.Zigbee.ChannelMigration.Result do
  @moduledoc """
  Separate local channel and per-peer observations from one explicit migration.

  `before` and `after` preserve sequential coordinator metadata. `admission`
  is the SDK's local send status, not broadcast delivery. Each selected peer
  retains its AF admission, APS confirmation, source-checked ZCL response and
  original security disposition. A responsive peer was observed through the
  coordinator after its target-channel reading; this does not authenticate
  the peer, census the network or establish portable key/counter continuity.

  `observed_cohort` requires the target local channel and successful Basic
  observations for every requested peer. Every other admitted result retains
  partial or unconfirmed evidence, including peers never probed. Dispatch
  ends this owner epoch after observations; obtain new custody before further
  operations. No rollback, rekey, reset or re-enrollment follows automatically.
  """

  alias Wotex.Zigbee.{ChannelMigration, Error, Event, Reply, ZCL}
  alias Wotex.Zigbee.Network.Snapshot

  @enforce_keys [:request, :owner_epoch, :before, :after, :admission, :peers, :outcome, :issue]
  defstruct @enforce_keys

  @type peer_result :: %{
          peer: ChannelMigration.peer(),
          token: byte(),
          admission: Reply.t() | nil,
          confirmation: Event.t() | nil,
          response: Event.t() | nil,
          attributes: ZCL.decoded() | nil,
          outcome: :responsive | :ncp_rejected | :aps_failed | :unconfirmed,
          issue: Error.kind() | nil
        }
  @type t :: %__MODULE__{
          request: ChannelMigration.t(),
          owner_epoch: reference(),
          before: Snapshot.t() | nil,
          after: Snapshot.t() | nil,
          admission: Reply.t() | nil,
          peers: [peer_result()],
          outcome: :observed_cohort | :partial | :unconfirmed,
          issue: Error.kind() | nil
        }
end
