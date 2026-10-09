defmodule Wotex.Zigbee.KeyRotation.Result do
  @moduledoc """
  Partial key-update/switch and per-peer observations without private material.

  `update` and `switch` retain separate send statuses. A failed update can
  still replace the local alternate key; a failed broadcast switch can still
  schedule a local change. `before`, `before_switch` and `after` retain raw
  network metadata, which contains no active key sequence or counter proof.

  `observed_cohort_after_switch` requires both admissions, unchanged network
  metadata and complete Basic observations for the selected cohort. It does
  not identify the key used by any peer. `activation` remains `unconfirmed`;
  independent key/counter qualification is required before treating rotation
  as established. Every selected peer is retained, including unprobed peers.
  The owner closes after any key write; no rollback or reset follows.
  """

  alias Wotex.Zigbee.{ChannelMigration, Error, KeyRotation, Reply}
  alias Wotex.Zigbee.Network.Snapshot

  @enforce_keys [
    :request,
    :owner_epoch,
    :before,
    :before_switch,
    :after,
    :update,
    :switch,
    :peers,
    :outcome,
    :activation,
    :issue
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          request: KeyRotation.t(),
          owner_epoch: reference(),
          before: Snapshot.t() | nil,
          before_switch: Snapshot.t() | nil,
          after: Snapshot.t() | nil,
          update: Reply.t() | nil,
          switch: Reply.t() | nil,
          peers: [ChannelMigration.Result.peer_result()],
          outcome: :observed_cohort_after_switch | :partial | :unconfirmed,
          activation: :unconfirmed,
          issue: Error.kind() | nil
        }
end
