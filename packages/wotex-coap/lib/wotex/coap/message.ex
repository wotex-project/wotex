defmodule Wotex.CoAP.Message do
  @moduledoc """
  Represents an immutable RFC 7252 message for the package's UDP profile.

  The required fields identify the message type, numeric code, and 16-bit
  Message ID. A message also carries a token, an ordered list of numeric option
  identities with raw binary values, and an application payload. Retaining raw
  option values lets `Wotex.CoAP.Codec` preserve options it does not interpret.

  The struct is a value, not a live request. Construction through
  `Wotex.CoAP.message/1` or decoding through `Wotex.CoAP.Codec.decode/1`
  establishes structural validity under the package limits. It does not grant
  authorization, reserve a Message ID, or transmit a datagram. Correlation and
  retransmission are owned by `Wotex.CoAP.Connection`; application-content
  interpretation belongs to `Wotex.CoAP.Mapping`.
  """

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
