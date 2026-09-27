defmodule Wotex.Zigbee.FrameTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{Error, Frame}

  test "the pinned SYS_VERSION vector has exact bytes" do
    frame = %Frame{type: :sreq, subsystem: 1, id: 2, payload: <<>>}
    assert {:ok, <<0xFE, 0, 0x21, 2, 0x23>> = bytes} = Frame.encode(frame)
    assert {:ok, [^frame], <<>>, 0} = Frame.feed(<<>>, bytes)
  end

  test "fragmented and coalesced frames preserve order and incomplete tails" do
    first = %Frame{type: :srsp, subsystem: 1, id: 2, payload: <<2, 0, 3, 0, 0>>}
    second = %Frame{type: :areq, subsystem: 4, id: 0x80, payload: <<0, 1, 7>>}
    {:ok, first_bytes} = Frame.encode(first)
    {:ok, second_bytes} = Frame.encode(second)
    <<prefix::binary-size(3), tail::binary>> = first_bytes

    assert {:ok, [], ^prefix, 0} = Frame.feed(<<>>, prefix)

    assert {:ok, [^first, ^second], <<0xFE, 0>>, 0} =
             Frame.feed(prefix, tail <> second_bytes <> <<0xFE, 0>>)
  end

  test "garbage, invalid checksum and invalid type resynchronize" do
    valid = %Frame{type: :areq, subsystem: 4, id: 0x80, payload: <<0, 1, 7>>}
    {:ok, bytes} = Frame.encode(valid)
    bad_fcs = <<0xFE, 0, 0x21, 2, 0>>
    reserved_type = <<0xFE, 0, 0x81, 2, 0x83>>

    assert {:ok, [^valid], <<>>, faults} =
             Frame.feed(<<>>, <<0, 1>> <> bad_fcs <> reserved_type <> bytes)

    assert faults > 0
  end

  test "oversized inputs and malformed values fail with typed errors" do
    invalid = %Frame{type: :sreq, subsystem: 1, id: 2, payload: :binary.copy(<<0>>, 251)}
    assert {:error, %Error{kind: :invalid_frame}} = Frame.encode(invalid)
    assert {:error, %Error{kind: :overload}} = Frame.feed(<<0::40>>, <<1>>, 5)
    assert {:ok, [], <<0xFE, 0, 0x21>>, 0} = Frame.feed(<<>>, <<0xFE, 0, 0x21>>)

    assert {:ok, [], <<0xFE, 2, 0x21, 2, 0, 1>>, 0} =
             Frame.feed(<<>>, <<0xFE, 2, 0x21, 2, 0, 1>>)

    assert {:ok, [], <<>>, faults} = Frame.feed(<<>>, <<0xFE, 251, 0x21, 2, 0>>)
    assert faults > 0
  end
end
