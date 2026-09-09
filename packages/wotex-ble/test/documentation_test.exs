defmodule Wotex.BLE.DocumentationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  doctest Wotex.BLE.Address
  doctest Wotex.BLE.ObjectPath
  doctest Wotex.BLE.Peer
  doctest Wotex.BLE.UUID
  doctest Wotex.BLE.Procedure
  doctest Wotex.BLE.BlueZ.Frame
  doctest Wotex.BLE.BlueZ.Options
  doctest Wotex.BLE.BlueZ.Stream
end
