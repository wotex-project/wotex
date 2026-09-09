defmodule Wotex.BACnet.Session do
  @moduledoc """
  Carries the client handle and timeout for one BACnet connection.

  A `t:t/0` is created by `Wotex.BACnet.connect/1` after the selected
  `Wotex.BACnet.Client` accepts its options. The `client` field identifies that
  implementation, `handle` is its opaque session value, and `timeout` supplies
  the finite request budget used by `Wotex.BACnet.send/2`. Custom clients must
  implement the timeout and cleanup behavior required by their callback contract.

  The struct is an explicit capability held by the caller. It is not registered
  globally and does not imply ownership of any process beyond the selected
  client contract. Its inspection representation omits the opaque handle so
  adapter state and possible credential-bearing transport details are not
  printed accidentally. The consumer must still call
  `Wotex.BACnet.disconnect/1` or use `Wotex.BACnet.with_connection/2` to release
  owned resources.
  """

  @derive {Inspect, only: [:client, :timeout]}
  @enforce_keys [:client, :handle, :timeout]
  defstruct [:client, :handle, :timeout]

  @type t :: %__MODULE__{client: module(), handle: term(), timeout: pos_integer()}
end
