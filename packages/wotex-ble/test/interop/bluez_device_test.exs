defmodule Wotex.BLE.BlueZDeviceTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.BLE
  alias Wotex.BLE.BlueZ
  @moduletag :hardware

  test "a selected BlueZ Battery Service characteristic yields a valid battery level" do
    opts = [
      client: BlueZ,
      executable: System.fetch_env!("WOTEX_BLE_BUSCTL"),
      object_path: System.fetch_env!("WOTEX_BLE_CHARACTERISTIC_PATH"),
      service: 0x180F,
      characteristic: 0x2A19,
      timeout: 5000
    ]

    assert {:ok, session} = BLE.connect(opts)

    try do
      assert {:ok, <<level>>} =
               BLE.send(session, %{type: :read, service: 0x180F, characteristic: 0x2A19})

      assert level in 0..100
    after
      BLE.disconnect(session)
    end
  end
end
