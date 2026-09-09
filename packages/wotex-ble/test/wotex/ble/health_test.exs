defmodule Wotex.BLE.HealthTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.BLE
  alias Wotex.BLE.BlueZ.Response
  alias Wotex.BLE.Error

  test "WBL-P06 WBL-S05 profile capabilities declare only implemented local operations" do
    assert {:ok, baseline} = BLE.capabilities(:oneshot)
    assert baseline == BLE.capabilities()
    assert {:ok, gatt} = BLE.capabilities(:gatt)

    assert gatt ==
             Map.merge(baseline, %{
               operations: [
                 :read,
                 :write,
                 :discover,
                 :pair,
                 :subscribe,
                 :unsubscribe,
                 :health_check
               ],
               transport: :bluez_dbus,
               supports_streaming: true,
               discovery_capable: true
             })

    assert gatt.max_payload_size == 512
    assert {gatt.reliable, gatt.ordered, gatt.qos_levels} == {false, false, []}

    for mode <- [nil, "gatt", :secure, %{}, []] do
      assert {:error, %Error{code: :unsupported_profile}} = BLE.capabilities(mode)
    end
  end

  test "WBL-C07 health projection rejects unknown fields and any fabricated state" do
    result = %{"connected" => true, "services_resolved" => true}
    frame = %{"version" => 1, "id" => "1", "ok" => true, "result" => result}
    assert {:ok, %{connected: true, services_resolved: true}} = Response.parse(frame, "health")

    for value <- [
          nil,
          %{},
          [],
          Map.put(result, "paired", true),
          %{result | "connected" => false},
          %{result | "connected" => 1},
          %{result | "services_resolved" => false},
          %{result | "services_resolved" => "true"}
        ] do
      assert :invalid = Response.parse(%{frame | "result" => value}, "health")
    end

    assert :invalid = Response.parse(frame, "discover")
  end
end
