defmodule Wotex.Zigbee.PermitJoin.Result do
  @moduledoc """
  Fresh metadata and NCP admission for one explicit permit-join request.

  `:ncp_admitted` and `:ncp_rejected` preserve the SRSP status separately from
  actual joining state. `:unconfirmed` retains available network readings and
  a bounded issue. Credential handles, private material and callback text are
  absent. Management responses and local change indications remain in the
  owner's event queue because they cannot be correlated to this request by
  the adopted legacy MT fields. Check that queue and its drop count separately.
  """

  alias Wotex.Zigbee.{Error, PermitJoin, Reply}
  alias Wotex.Zigbee.Network.Snapshot

  @enforce_keys [:request, :owner_epoch, :network, :admission, :outcome, :issue]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          request: PermitJoin.t(),
          owner_epoch: reference(),
          network: Snapshot.t(),
          admission: Reply.t() | nil,
          outcome: :ncp_admitted | :ncp_rejected | :unconfirmed,
          issue: Error.kind() | nil
        }
end
