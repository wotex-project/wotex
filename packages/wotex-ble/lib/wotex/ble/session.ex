defmodule Wotex.BLE.Session do
  @moduledoc """
  Carries the client handle and timeout for one BLE connection.

  `Wotex.BLE.connect/1` creates a `t:t/0` after the selected
  `Wotex.BLE.Client` accepts its configuration. The `client` field identifies
  the implementation, `handle` stores its opaque session value, and `timeout`
  is supplied to each call through `Wotex.BLE.send/2`; the selected client
  enforces it.

  The struct is an explicit caller-held capability. It is not registered
  globally. The selected backend and its explicit lifecycle options determine
  whether its resources include a device connection. Its inspection representation omits the opaque handle so
  operating-system state and possible transport details are not printed.
  Callers release owned resources with `Wotex.BLE.disconnect/1` or use
  `Wotex.BLE.with_connection/2` for deterministic cleanup.
  """

  @derive {Inspect, only: [:client, :timeout]}
  @enforce_keys [:client, :handle, :timeout]
  defstruct [:client, :handle, :timeout]

  @type t :: %__MODULE__{client: module(), handle: term(), timeout: pos_integer()}
end
