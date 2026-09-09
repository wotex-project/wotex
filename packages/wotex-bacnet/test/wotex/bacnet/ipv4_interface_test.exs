defmodule Wotex.BACnet.IPv4InterfaceTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.BACnet.IPv4Interface

  test "WBA-S03a configured IPv4 selection survives IPv6 and multiple interface addresses" do
    ip = {192, 0, 2, 7}
    mask = {255, 255, 255, 0}
    broadcast = {192, 0, 2, 255}

    interfaces = [
      {~c"fixture0",
       [
         flags: [:up],
         addr: {0, 0, 0, 0, 0, 0, 0, 1},
         netmask: {0, 0, 0, 0, 0, 0, 0, 1},
         addr: {198, 51, 100, 1},
         netmask: {255, 255, 0, 0},
         broadaddr: {198, 51, 255, 255},
         addr: ip,
         netmask: mask,
         broadaddr: broadcast
       ]}
    ]

    assert {:ok, interface} = IPv4Interface.select(ip, interfaces)
    assert interface == %{ip: ip, mask: mask, broadcast: broadcast}
    refute IPv4Interface.routed?(interface, {{192, 0, 2, 254}, 47_808})
    assert IPv4Interface.routed?(interface, {{192, 0, 3, 1}, 47_808})
    assert IPv4Interface.routed?(interface, {{:bad, 0, 2, 1}, 47_808})
    assert IPv4Interface.routed?(interface, :invalid)
  end

  test "WBA-S03a absent interface and loopback without broadcast never choose another address" do
    assert {:error, :invalid_interface} = IPv4Interface.resolve(:automatic)
    assert {:error, :invalid_interface} = IPv4Interface.resolve({192, 0, 2, 253})

    assert {:error, :invalid_interface} =
             IPv4Interface.select({127, 0, 0, 1}, [
               {~c"lo0", [addr: {127, 0, 0, 1}, netmask: {255, 0, 0, 0}]}
             ])

    assert {:ok, interface} = IPv4Interface.resolve(:none)
    assert interface.ip == {0, 0, 0, 0}
    assert IPv4Interface.routed?(interface, {{127, 0, 0, 1}, 47_808})
  end
end
