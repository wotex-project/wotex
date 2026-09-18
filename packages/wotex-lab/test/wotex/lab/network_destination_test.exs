defmodule Wotex.Lab.NetworkDestinationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Network.Destination

  test "every address in fc00::/7 is refused as unique local" do
    for first <- [0xFC00, 0xFCFF, 0xFD00, 0xFDFF] do
      refute Destination.public_address?(low(first))
      refute Destination.public_address?(high(first))
    end
  end

  test "every address in fe00::/8 is refused as reserved, link-local or site-local" do
    # fe00::/9 is IETF-reserved, fe80::/10 link-local and fec0::/10 site-local.
    for first <- [0xFE00, 0xFE7F, 0xFE80, 0xFEBF, 0xFEC0, 0xFEFF] do
      refute Destination.public_address?(low(first))
      refute Destination.public_address?(high(first))
    end
  end

  test "every address in ff00::/8 is refused as multicast" do
    for first <- [0xFF00, 0xFF01, 0xFF02, 0xFF05, 0xFF0E, 0xFF3E, 0xFFFF] do
      refute Destination.public_address?(low(first))
      refute Destination.public_address?(high(first))
    end
  end

  test "global unicast addresses outside the reserved ranges stay public" do
    for address <- [
          {0x2001, 0x4860, 0x4860, 0, 0, 0, 0, 0x8888},
          {0x2606, 0x4700, 0x4700, 0, 0, 0, 0, 0x1111},
          {0x2A00, 0x1450, 0x4001, 0x082E, 0, 0, 0, 0x200E}
        ] do
      assert Destination.public_address?(address)
    end
  end

  test "a malformed eight-tuple is refused rather than matched by range" do
    for address <- [
          {0x10000, 0, 0, 0, 0, 0, 0, 1},
          {0x1FE80, 0, 0, 0, 0, 0, 0, 1},
          {-1, 0, 0, 0, 0, 0, 0, 1},
          {"fe80", 0, 0, 0, 0, 0, 0, 1}
        ] do
      refute Destination.public_address?(address)
    end
  end

  defp low(first), do: {first, 0, 0, 0, 0, 0, 0, 1}
  defp high(first), do: {first, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF}
end
