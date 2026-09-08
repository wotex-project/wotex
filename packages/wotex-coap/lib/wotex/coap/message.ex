defmodule Wotex.CoAP.Message do
  @moduledoc "Immutable RFC 7252 UDP message with numeric option identities and raw values."

  @enforce_keys [:type, :code, :message_id]
  defstruct [:type, :code, :message_id, token: <<>>, options: [], payload: <<>>]

  @type t :: %__MODULE__{
          type: :con | :non | :ack | :rst,
          code: 0..255,
          message_id: 0..65_535,
          token: binary(),
          options: [{non_neg_integer(), binary()}],
          payload: binary()
        }
end
