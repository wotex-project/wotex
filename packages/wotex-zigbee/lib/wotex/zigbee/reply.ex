defmodule Wotex.Zigbee.Reply do
  @moduledoc """
  Immediate ZNP synchronous response to a host request.

  `status: 0` means the NCP admitted the request. It is not an APS
  acknowledgement, ZDO response, ZCL result, report or physical effect.
  Later indications are available through `Wotex.Zigbee.drain_events/2`.
  """

  @enforce_keys [:subsystem, :id, :status, :payload]
  defstruct [:subsystem, :id, :status, :payload]

  @type t :: %__MODULE__{
          subsystem: 0..31,
          id: 0..255,
          status: 0..255,
          payload: binary()
        }
end
