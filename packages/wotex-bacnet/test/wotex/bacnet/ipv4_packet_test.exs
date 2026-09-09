defmodule Wotex.BACnet.IPv4PacketTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias BACnet.Protocol.NPCI
  alias Wotex.BACnet.IPv4Packet

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
