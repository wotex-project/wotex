defmodule Wotex.BACnet.Session do
  @moduledoc "Explicit client handle. Inspect omits transport state and credentials."

  @derive {Inspect, only: [:client, :timeout]}
  @enforce_keys [:client, :handle, :timeout]
  defstruct [:client, :handle, :timeout]

  @type t :: %__MODULE__{client: module(), handle: term(), timeout: pos_integer()}
end
