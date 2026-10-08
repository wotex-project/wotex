defmodule Wotex.Zigbee.ZCL.Configuration.Request do
  @moduledoc """
  Inert, bounded context for one explicit ZCL write or reporting request.

  Build this value through `Wotex.Zigbee.ZCL.Configuration`. Put its `payload`
  in a `Wotex.Zigbee.DataRequest` after consumer authorization. Retain the
  complete value to interpret later responses. Construction performs no I/O,
  retry, reporting change or binding operation.
  """

  @enforce_keys [:command, :sequence, :direction, :manufacturer, :records, :payload]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          command: :write_attributes | :configure_reporting | :read_reporting,
          sequence: byte(),
          direction: Wotex.Zigbee.ZCL.direction(),
          manufacturer: 0..0xFFFF | nil,
          records: [map()],
          payload: binary()
        }
end
