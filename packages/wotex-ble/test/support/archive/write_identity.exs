defmodule WriteArchiveIdentityTest do
  @moduledoc false

  use ExUnit.Case, async: false

  test "public modules load only from this extracted build without library startup" do
    root = Path.join(File.cwd!(), "_build") <> "/"

    for module <- [
          Wotex.BLE,
          Wotex.BLE.BlueZ,
          Wotex.BLE.Peer,
          Wotex.BLE.Error,
          Wotex.BLE.Transport,
          Wotex.Form,
          Wotex.ThingDescription,
          Wotex.Runtime.ConsumedThing,
          Wotex.Runtime.Context,
          Wotex.Runtime.Result
        ] do
      Code.ensure_loaded!(module)
      assert String.starts_with?(List.to_string(:code.which(module)), root)
    end

    running = Application.started_applications() |> Enum.map(&elem(&1, 0))

    for app <- [:wotex, :wotex_runtime, :wotex_ble] do
      assert Application.load(app) in [:ok, {:error, {:already_loaded, app}}]
      assert Application.spec(app, :mod) in [nil, []]
      refute app in running
    end

    assert {:ok, _} =
             Wotex.BLE.Peer.new(%{
               adapter: "/org/bluez/hci0",
               address: "AA:BB:CC:DD:EE:FF",
               address_type: :random
             })

    assert Application.started_applications() |> Enum.map(&elem(&1, 0)) == running
  end
end
