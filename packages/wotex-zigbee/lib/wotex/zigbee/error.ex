defmodule Wotex.Zigbee.Error do
  @moduledoc """
  Typed failures at the coordinator host boundary.

  The error carries a stable kind and operation, never serial bytes, network
  keys or untrusted device strings. Consumers can distinguish malformed
  frames, unsupported profiles, admission failure and lost coordinator state
  without parsing operating-system messages.
  """

  defexception [:kind, :operation]

  @type kind ::
          :invalid_config
          | :invalid_frame
          | :invalid_command
          | :invalid_value
          | :unsupported_profile
          | :version_mismatch
          | :overload
          | :timeout
          | :coordinator_lost
          | :stale_handle
          | :serial
          | :status_failure
          | :correlation_exhausted
          | :stale_epoch
          | :stale_observation
          | :unknown_route
          | :route_conflict
          | :route_expired
          | :route_mismatch
          | :network_mismatch
          | :credentials
          | :credential_denied

  @type t :: %__MODULE__{kind: kind(), operation: atom()}

  @impl Exception
  def message(%__MODULE__{kind: kind, operation: operation}),
    do: "Zigbee #{operation} failed: #{kind}"
end
