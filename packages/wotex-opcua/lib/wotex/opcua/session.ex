defmodule Wotex.OPCUA.Session do
  @moduledoc """
  Carries the client handle and timeout for one OPC UA connection.

  `Wotex.OPCUA.connect/1` creates a `t:t/0` after the selected
  `Wotex.OPCUA.Client` accepts its endpoint and security configuration. The
  `client` field identifies the implementation, `handle` contains its opaque
  session state, and `timeout` supplies the finite budget passed through
  `Wotex.OPCUA.send/2`. Custom clients must enforce their callback timeout.

  The struct is an explicit caller-held capability. It is not registered
  globally and does not itself own credentials, trust anchors, or a persistent
  server session. Its inspection representation omits the opaque handle so
  security and transport state are not printed. The consumer releases owned
  resources with `Wotex.OPCUA.disconnect/1` or uses
  `Wotex.OPCUA.with_connection/2` for deterministic cleanup.
  """

  @derive {Inspect, only: [:client, :timeout]}
  @enforce_keys [:client, :handle, :timeout]
  defstruct [:client, :handle, :timeout]

  @type t :: %__MODULE__{client: module(), handle: term(), timeout: pos_integer()}
end
