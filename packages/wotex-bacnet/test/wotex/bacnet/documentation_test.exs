defmodule Wotex.BACnet.DocumentationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  doctest Wotex.BACnet.Address
  doctest Wotex.BACnet.Device
  doctest Wotex.BACnet.CharacterString
  doctest Wotex.BACnet.Tags
  doctest Wotex.BACnet.COVCache
end
