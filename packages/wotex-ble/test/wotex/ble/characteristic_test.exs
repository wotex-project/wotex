defmodule Wotex.BLE.CharacteristicTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Wotex.BLE.{Address, Characteristic, Error}

  @characteristic %{
    service_uuid: "180f",
    characteristic_uuid: "2a19",
    service_path: "/org/bluez/hci0/dev_00_11_22_33_44_55/service001",
    object_path: "/org/bluez/hci0/dev_00_11_22_33_44_55/service001/char002",
    flags: ["read", "notify", "extension-future"],
    generation: 1,
    handle: 37
  }

  test "WBL-P02 WBL-S01 WBL-N01 discovery values preserve exact identity and unknown flags" do
    assert {:ok, characteristic} = Characteristic.new(@characteristic)
    assert characteristic.service_uuid == "0000180f-0000-1000-8000-00805f9b34fb"
    assert characteristic.flags == @characteristic.flags
    assert {:ok, ^characteristic} = Characteristic.new(characteristic)

    assert {:ok, %Address{handle: 37, generation: 1} = address} =
             Characteristic.address(characteristic)

    assert address.service == characteristic.service_uuid
    assert address.characteristic == characteristic.characteristic_uuid
    assert address.object_path == @characteristic.object_path
    assert {:ok, %{handle: nil}} = Characteristic.new(Map.delete(@characteristic, :handle))
    assert {:ok, %{flags: []}} = Characteristic.new(%{@characteristic | flags: []})
  end

  test "WBL-S01 WBL-V03 forged discovery fields never produce a usable address" do
    assert {:ok, characteristic} = Characteristic.new(@characteristic)

    for forged <- [
          nil,
          %{},
          Map.delete(@characteristic, :generation),
          %{characteristic | service_uuid: nil},
          %{characteristic | characteristic_uuid: "bad"},
          %{characteristic | service_path: "relative"},
          %{characteristic | object_path: nil},
          %{characteristic | generation: nil},
          %{characteristic | generation: -1},
          %{characteristic | handle: 0},
          %{characteristic | flags: [:read]},
          %{characteristic | flags: ["read", "read"]},
          %{characteristic | flags: ["read" | :invalid]},
          %{characteristic | flags: [<<255>>]},
          %{characteristic | flags: [""]},
          %{characteristic | flags: [String.duplicate("x", 65)]},
          %{characteristic | flags: Enum.map(1..65, &"flag-#{&1}")}
        ] do
      assert {:error, %Error{code: :invalid_characteristic, effect: :none}} =
               Characteristic.new(forged)

      assert {:error, %{code: :invalid_characteristic}} = Characteristic.address(forged)
    end

    assert {:ok, _} =
             Characteristic.new(%{
               @characteristic
               | flags: Enum.map(1..64, &String.pad_trailing("flag-#{&1}", 64, "x"))
             })
  end

  property "WBL-C02 arbitrary discovery flag bytes return bounded failures or preserved values" do
    check all(flag <- binary(max_length: 80)) do
      case Characteristic.new(%{@characteristic | flags: [flag]}) do
        {:ok, result} -> assert result.flags == [flag]
        {:error, %Error{code: :invalid_characteristic}} -> :ok
      end
    end
  end
end
