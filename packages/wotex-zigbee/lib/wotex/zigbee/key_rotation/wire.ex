defmodule Wotex.Zigbee.KeyRotation.Wire do
  @moduledoc false

  alias Wotex.Zigbee.{Frame, KeyRotation}

  @doc false
  @spec update(KeyRotation.t(), <<_::128>>) :: Frame.t()
  def update(request, key),
    do: %Frame{
      type: :sreq,
      subsystem: 5,
      id: 0x4E,
      payload: <<0xFFFD::little-16, request.next_sequence, key::binary-size(16)>>
    }

  @doc false
  @spec switch(KeyRotation.t()) :: Frame.t()
  def switch(request),
    do: %Frame{
      type: :sreq,
      subsystem: 5,
      id: 0x4F,
      payload: <<0xFFFD::little-16, request.next_sequence>>
    }
end
