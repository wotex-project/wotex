defmodule CoreArchiveIdentityTest do
  @moduledoc false

  use ExUnit.Case, async: false

  test "public modules originate in the extracted consumer and passive loading starts nothing" do
    root = Path.join(File.cwd!(), "_build") <> "/"
    apps = Application.started_applications() |> Enum.map(&elem(&1, 0))
    ports = MapSet.new(Port.list())

    for module <- [
          Wotex.BLE,
          Wotex.BLE.CoreBluetooth,
          Wotex.BLE.CoreBluetooth.Peer,
          Wotex.BLE.CoreBluetooth.Characteristic,
          Wotex.BLE.CoreBluetooth.Build,
          Wotex.BLE.Transport,
          Wotex.Form,
          Wotex.ThingDescription,
          Wotex.Runtime.ConsumedThing,
          Wotex.Runtime.Context,
          Wotex.Runtime.Request
        ] do
      Code.ensure_loaded!(module)
      assert String.starts_with?(List.to_string(:code.which(module)), root)
    end

    for app <- [:wotex, :wotex_runtime, :wotex_ble] do
      assert Application.load(app) in [:ok, {:error, {:already_loaded, app}}]
      assert Application.spec(app, :mod) in [nil, []]
      refute app in apps
    end

    assert {:ok, peer} = Wotex.BLE.CoreBluetooth.Peer.new("01234567-89ab-cdef-0123-456789abcdef")
    refute inspect(peer) =~ "01234567-89ab-cdef-0123-456789abcdef"
    assert Application.started_applications() |> Enum.map(&elem(&1, 0)) == apps
    assert MapSet.new(Port.list()) == ports
    assert Path.wildcard("peer-instance-*") == []
  end
end
