defmodule Wotex.BLE.BlueZInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.BLE
  alias Wotex.BLE.{Address, Characteristic, Error, SoftwarePeer}
  @moduletag :interop

  setup do
    config = SoftwarePeer.command("reset")
    on_exit(fn -> SoftwarePeer.wait_until(&SoftwarePeer.released?/0, 1500) end)
    %{options: SoftwarePeer.options(config)}
  end

  test "WBL-N03 WBL-V03 V04 V05 public native GATT selects exact values and acknowledged writes", %{
    options: options
  } do
    session = connect(options)
    assert {:ok, page} = BLE.discover(session)
    assert page.cursor == nil
    selected = SoftwarePeer.selected(page, :value)
    assert %Characteristic{} = selected
    address = SoftwarePeer.target(selected)
    assert {:ok, <<0x34, 0x12>>} = BLE.read(session, address)
    assert {:ok, 4660} = BLE.read(session, address, value_type: :uint16)
    assert {:ok, :written} = BLE.write(session, address, 22_136, value_type: :uint16)
    assert {:ok, 22_136} = BLE.read(session, address, value_type: :uint16)
    assert SoftwarePeer.command("stats")["values"]["value"] == "7856"

    assert {:ok, ambiguous} =
             Address.new(%{
               service: SoftwarePeer.service(),
               characteristic: SoftwarePeer.uuid(:duplicate)
             })

    assert {:error, %Error{code: :ambiguous_characteristic}} = BLE.read(session, ambiguous)

    values =
      for item <- page.characteristics,
          item.characteristic_uuid == SoftwarePeer.uuid(:duplicate) do
        assert {:ok, value} = BLE.read(session, SoftwarePeer.target(item))
        value
      end

    assert Enum.sort(values) == [<<0xA1>>, <<0xB2>>]
    writes = SoftwarePeer.command("stats")["peer_calls"]["WriteValue"]

    assert {:error, %Error{code: :stale_discovery, effect: :none}} =
             BLE.write(session, %{address | generation: address.generation + 1}, <<0>>)

    assert SoftwarePeer.command("stats")["peer_calls"]["WriteValue"] == writes
    SoftwarePeer.command("deny", %{label: "value", denied: true})
    assert {:error, %Error{code: :not_permitted}} = BLE.read(session, address)

    assert {:error, %Error{code: :not_permitted, effect: :unknown}} =
             BLE.write(session, address, <<0>>)

    assert SoftwarePeer.command("stats")["values"]["value"] == "7856"
    assert :ok = BLE.disconnect(session)
  end

  test "WBL-N03 WBL-V07 V08 native equal notify and confirmed indicate reports preserve source", %{
    options: options
  } do
    session = connect(options)
    assert {:ok, page} = BLE.discover(session)

    for mode <- [:notify, :indicate] do
      characteristic = SoftwarePeer.selected(page, mode)
      address = SoftwarePeer.target(characteristic)

      assert {:ok, subscription} =
               BLE.subscribe(session, %{address: address, mode: mode, value_type: :uint8})

      reference = subscription.reference
      refute_receive {:wotex_ble, ^reference, _}, 50

      for _ <- 1..2 do
        SoftwarePeer.command("value", %{label: Atom.to_string(mode), hex: "01", emit: true})
        assert_receive {:wotex_ble, ^reference, {:ok, 1, metadata}}, 1000
        assert metadata.source == :bluez_value_change
        assert metadata.characteristic == characteristic
        assert metadata.requested_mode == mode
        assert metadata.effective_mode == mode
      end

      if mode == :indicate do
        SoftwarePeer.wait_until(fn -> SoftwarePeer.command("stats")["confirms"] == 2 end)
      end

      SoftwarePeer.command("value", %{label: Atom.to_string(mode), hex: "02", emit: false})
      assert {:ok, <<2>>} = BLE.read(session, address)
      assert_receive {:wotex_ble, ^reference, {:ok, 2, %{source: :bluez_value_change}}}, 1000
      assert :ok = BLE.unsubscribe(session, subscription)
      assert :ok = BLE.unsubscribe(session, subscription)
      SoftwarePeer.wait_until(fn -> SoftwarePeer.command("stats")["notifying"] == [] end)
    end

    assert :ok = BLE.disconnect(session)
  end

  test "WBL-N03 WBL-V09 first native sender cleanup preserves a second sender and its link", %{
    options: options
  } do
    first = connect(options)
    second = connect(options)
    assert {:ok, page} = BLE.discover(first)
    address = SoftwarePeer.target(SoftwarePeer.selected(page, :notify))
    assert {:ok, left} = BLE.subscribe(first, %{address: address})
    assert {:ok, right} = BLE.subscribe(second, %{address: address})
    left_ref = left.reference
    right_ref = right.reference
    SoftwarePeer.command("value", %{label: "notify", hex: "01", emit: true})

    for _ <- 1..2 do
      assert_receive {:wotex_ble, ^left_ref, {:ok, <<1>>, _}}, 1000
      assert_receive {:wotex_ble, ^right_ref, {:ok, <<1>>, _}}, 1000
    end

    assert :ok = BLE.disconnect(first)
    assert_receive {:wotex_ble, ^left_ref, {:error, %Error{code: :disconnected}}}, 1000
    assert {:ok, %{connected: true, services_resolved: true}} = BLE.health_check(second)
    SoftwarePeer.command("value", %{label: "notify", hex: "02", emit: true})
    assert_receive {:wotex_ble, ^right_ref, {:ok, <<2>>, _}}, 1000
    refute_receive {:wotex_ble, ^left_ref, _}, 50
    stats = SoftwarePeer.command("stats")
    assert length(stats["native_senders"]) == 1
    assert stats["notification_sessions"] == 1
    assert Map.get(stats["calls"], "Disconnect", 0) == 0
    assert :ok = BLE.unsubscribe(second, right)
    assert :ok = BLE.disconnect(second)
  end

  test "WBL-V09 receiver death releases the real CCC session without closing the native connection",
       %{
         options: options
       } do
    session = connect(options)
    assert {:ok, page} = BLE.discover(session)
    receiver = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> Process.exit(receiver, :kill) end)
    address = SoftwarePeer.target(SoftwarePeer.selected(page, :notify))
    assert {:ok, subscription} = BLE.subscribe(session, %{address: address, receiver: receiver})
    monitor = Process.monitor(subscription.pid)
    started = System.monotonic_time(:millisecond)
    Process.exit(receiver, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1000

    SoftwarePeer.wait_until(fn ->
      stats = SoftwarePeer.command("stats")
      stats["notification_sessions"] == 0 and stats["notifying"] == []
    end)

    assert System.monotonic_time(:millisecond) - started <= 1100
    assert {:ok, %{connected: true}} = BLE.health_check(session)
    assert :ok = BLE.disconnect(session)
  end

  test "WBL-N03 WBL-V06 public pairing uses exact peer callbacks and cleans accepted or rejected attempts",
       %{
         options: options
       } do
    for decision <- [:accept, :reject, :timeout] do
      SoftwarePeer.command("reset")
      session = connect(options)

      request = %{
        capability: :display_yes_no,
        agent: {__MODULE__, {self(), decision}},
        timeout: 1000
      }

      result = BLE.pair(session, request)
      assert_receive {:pair_challenge, challenge}, 1000
      assert challenge.peer == options[:peer]
      assert challenge.kind == :confirm_passkey
      assert challenge.value in 0..999_999

      case {decision, result} do
        {:accept, {:ok, %{paired: true}}} ->
          :ok

        {decision, {:error, %Error{code: :pairing_rejected}}}
        when decision in [:reject, :timeout] ->
          :ok

        {decision, {:error, %Error{code: :disconnected}}}
        when decision in [:reject, :timeout] ->
          assert SoftwarePeer.command("stats")["peer_connected"] == false

        unexpected ->
          flunk("Unexpected pairing outcome: #{inspect(unexpected)}")
      end

      assert :ok = BLE.disconnect(session)
      SoftwarePeer.wait_until(&SoftwarePeer.released?/0)
      stats = SoftwarePeer.command("stats")
      assert stats["calls"]["RegisterAgent"] == 1
      assert stats["calls"]["UnregisterAgent"] == 1
      assert Map.get(stats["calls"], "CancelPairing", 0) == 0
      assert Map.get(stats["calls"], "RemoveDevice", 0) == 0
      assert Map.get(stats["calls"], "RequestDefaultAgent", 0) == 0
    end
  end

  @spec decide(Wotex.BLE.Challenge.t(), {pid(), atom()}) :: atom()
  def decide(challenge, {receiver, decision}) do
    send(receiver, {:pair_challenge, challenge})
    if decision == :timeout, do: Process.sleep(60_000)
    decision
  end

  defp connect(options) do
    assert {:ok, session} = BLE.connect(options)
    on_exit(fn -> BLE.disconnect(session) end)
    session
  end
end
