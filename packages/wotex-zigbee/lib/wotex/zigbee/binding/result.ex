defmodule Wotex.Zigbee.Binding.Result do
  @moduledoc """
  Separate NCP admission and source-matched peer status for one binding request.

  `:peer_reported_success` or `:peer_reported_failure` requires NCP admission
  status zero and a matching Bind/Unbind callback within the owner's absolute
  deadline. `:unconfirmed` retains available observations and the bounded
  issue when admission fails or the workflow ends without both observations.
  An early callback cannot override a later NCP rejection.

  The callback echoes no endpoint, cluster, target or independent host token.
  Retained request fields remain caller context, not peer-verified fields.
  Source/operation retirement prevents reuse within an owner epoch; it does
  not authenticate a radio peer, establish replay protection or prove future
  reporting, delivery, wakefulness or physical effect. This MT callback has
  no security-disposition field; none is invented.
  """

  alias Wotex.Zigbee.{Binding, Error, Event, Reply}

  @enforce_keys [:request, :owner_epoch, :outcome, :admission, :response, :issue]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          request: Binding.t(),
          owner_epoch: reference(),
          outcome: :peer_reported_success | :peer_reported_failure | :unconfirmed,
          admission: Reply.t() | nil,
          response: Event.t() | nil,
          issue: Error.kind() | :ncp_rejected | nil
        }
end
