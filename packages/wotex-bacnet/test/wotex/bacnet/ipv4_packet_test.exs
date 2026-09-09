defmodule Wotex.BACnet.IPv4PacketTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias BACnet.Protocol.NPCI
  alias Wotex.BACnet.IPv4Packet

  test "WBA-S03a outgoing framing preserves unicast, broadcast, BVLC and header options" do
    assert {:ok, <<0x81, 10, 8::16, 1, 0, 16, 8>>} = IPv4Packet.encode([16, <<8>>], false)

    assert {:ok, <<0x81, 11, 12::16, 1, 0x20, 65_535::16, 0, 255, 16, 8>>} =
             IPv4Packet.encode(<<16, 8>>, true)

    assert {:ok, <<0x81, 10, 8::16, 1, 4, 0, 1>>} = IPv4Packet.encode(<<0, 1>>, false)
    assert {:error, :invalid_expects_reply_for_broadcast} = IPv4Packet.encode(<<0, 1>>, true)

    assert {:ok, <<0x81, 0, 6::16, 0, 0>>} =
             IPv4Packet.encode(<<>>, false, bvlc: <<0, 0, 0>>, npci: false)

    assert {:ok, <<0x81, 10, 4::16>>} =
             IPv4Packet.encode(<<0x81, 10, 4::16>>, false, skip_headers: true)

    assert {:ok, <<0x81, 11, 6::16, 16, 8>>} =
             IPv4Packet.encode(<<16, 8>>, false, is_broadcast: true, npci: false)
  end

  test "WBA-S03a outgoing datagram admission rejects exact boundary overflows and malformed codec inputs" do
    apdu = :binary.copy(<<16>>, 1476)
    assert {:ok, bytes} = IPv4Packet.encode(apdu, false)
    assert byte_size(bytes) == 1482
    assert {:error, :apdu_too_long} = IPv4Packet.encode(apdu <> <<0>>, false)
    assert {:error, :data_empty} = IPv4Packet.encode(<<>>, false)
    assert {:ok, bytes} = IPv4Packet.encode(apdu, false, bvlc: <<10, 0::432>>)
    assert byte_size(bytes) == 1536
    assert {:error, :oversize} = IPv4Packet.encode(apdu, false, bvlc: <<10, 0::440>>)

    for {data, broadcast, opts} <- [
          {nil, false, []},
          {<<16>>, :invalid, []},
          {<<16>>, false, nil},
          {<<16>>, false, [:invalid]},
          {<<16>>, false, [bvlc: <<>>]},
          {<<16>>, false, [bvlc: 10]},
          {<<16>>, false, [npci: :invalid]},
          {<<16>>, false, [source: :invalid]},
          {<<16>>, false, [is_broadcast: :invalid]},
          {[[256]], false, []},
          {%URI{}, false, []}
        ],
        do: assert({:error, :malformed} = IPv4Packet.encode(data, broadcast, opts))
  end

  test "WBA-S03a preserves exact APDU bytes through the public SDK codecs" do
    apdu = <<0x10, 0x08>>

    assert {:ok, {:apdu, _, %NPCI{source: nil}, ^apdu}} =
             IPv4Packet.decode(<<0x81, 0x0A, 8::16, 1, 0, apdu::binary>>)

    apdu = :binary.copy(<<0xFF>>, 1530)

    assert {:ok, {:apdu, _, %NPCI{}, ^apdu}} =
             IPv4Packet.decode(<<0x81, 0x0B, 1536::16, 1, 0, apdu::binary>>)
  end

  test "WBA-S03a validates the exact BVLL size and rejects unsupported packet encodings" do
    for packet <- [
          <<>>,
          <<0x81>>,
          <<0x81, 0x0A, 9::16, 1, 0, 0x10, 8>>,
          <<0x81, 0x0A, 7::16, 1, 0, 0x10, 8>>,
          <<0x82, 0x0A, 4::16>>,
          <<0x81, 0xFF, 4::16>>,
          <<0x81, 0x0A, 5::16, 1>>,
          <<0x81, 0x0A, 6::16, 2, 0>>,
          <<0x81, 0x0A, 9::16, 1, 0x20, 1, 2, 0>>,
          <<0x81, 0x0A, 12::16, 1, 0x20, 1::16, 1, 1, 0, 0>>
        ],
        do: assert({:error, :malformed} = IPv4Packet.decode(packet))
  end

  test "WBA-S03a retains bounded BVLC and network-layer messages without APDU reinterpretation" do
    assert {:ok, {:bvlc, _}} = IPv4Packet.decode(<<0x81, 0, 6::16, 0, 0>>)

    assert {:ok, {:network, _, %NPCI{}, _}} =
             IPv4Packet.decode(<<0x81, 0x0A, 7::16, 1, 0x80, 0>>)
  end

  property "WBA-S03a malformed datagrams never escape as codec exceptions" do
    check all(data <- binary(max_length: 1600)) do
      result = IPv4Packet.decode(data)
      assert match?({:ok, _}, result) or result in [{:error, :oversize}, {:error, :malformed}]
    end
  end
end
