defmodule Wotex.Zigbee.EventTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{Event, Frame}

  test "APS confirmation and incoming message retain independent correlation and source" do
    assert %Event{kind: :aps_confirm, status: 2, endpoint: 3, transaction: 4} =
             Event.from_frame(%Frame{type: :areq, subsystem: 4, id: 0x80, payload: <<2, 3, 4>>})

    payload =
      <<0::little-16, 6::little-16, 0x1234::little-16, 2, 1, 0, 180, 1, 123::little-32, 7, 2, 0xAA,
        0xBB>>

    assert %Event{
             kind: :af_incoming,
             source_address: 0x1234,
             source_endpoint: 2,
             endpoint: 1,
             cluster: 6,
             link_quality: 180,
             security_used: true,
             transaction: 7,
             payload: <<0xAA, 0xBB>>
           } = Event.from_frame(%Frame{type: :areq, subsystem: 4, id: 0x81, payload: payload})
  end

  test "malformed known indications and unknown commands remain observable" do
    assert %Event{kind: :malformed_indication} =
             Event.from_frame(%Frame{type: :areq, subsystem: 4, id: 0x81, payload: <<1>>})

    assert %Event{kind: :zdo_indication} =
             Event.from_frame(%Frame{type: :areq, subsystem: 5, id: 1, payload: <<>>})

    assert %Event{kind: :unknown_indication, payload: <<7>>} =
             Event.from_frame(%Frame{type: :areq, subsystem: 7, id: 1, payload: <<7>>})
  end
end
