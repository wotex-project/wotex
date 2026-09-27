defmodule Wotex.Zigbee.Handle do
  @moduledoc """
  Opaque capability for one negotiated coordinator owner epoch.

  A stopped or replaced owner cannot be reactivated by serial descriptor or
  USB path reuse. Consumers pass this value to `Wotex.Zigbee` without
  inspecting its fields.
  """

  @enforce_keys [:owner, :epoch, :timeout_ms]
  defstruct [:owner, :epoch, :timeout_ms]

  @opaque t :: %__MODULE__{owner: pid(), epoch: reference(), timeout_ms: pos_integer()}
end
