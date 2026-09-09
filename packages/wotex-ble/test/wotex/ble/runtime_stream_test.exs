defmodule Wotex.BLE.RuntimeStreamTest do
  @moduledoc false

  use ExUnit.Case, async: true
  import Wotex.BLE.NativeFixture

  alias Wotex.BLE
  alias Wotex.BLE.{BlueZ, Error}

  test "WBL-P06 WBL-I05 real Runtime Property and Event streams bind native signals then close once" do
    for kind <- [:property, :event] do
      {native, record} = options("stream_runtime")
      {consumed, context} = runtime_consumer(native, kind)
      spec = runtime_spec(consumed, context, kind, self())
      owner = start_supervised!(spec)
      assert_receive {:runtime_decode, ^owner, {:value, <<1, 0>>, metadata}, request}, 5000
      assert request.operation == if(kind == :property, do: :observeproperty, else: :subscribeevent)
      assert metadata.source == :bluez_value_change
      assert metadata.effective_mode == :notify
      assert metadata.requested_mode == :auto
      assert metadata.characteristic.object_path == "/another/characteristic0"
      refute is_struct(metadata.characteristic)
      assert_receive {:wotex_runtime, _, {:ok, 1, ^metadata}}, 5000
      refute_received {:wotex_ble, _, _}
      assert :ok = Wotex.Runtime.Subscription.stop(owner)
      eventually(fn -> Enum.any?(calls(record), &Map.has_key?(&1, "bus_closed")) end)
      trace = calls(record)
      assert Enum.count(trace, &(&1["method"] == "StartNotify")) == 1
      assert Enum.count(trace, &(&1["method"] == "StopNotify")) == 1
      assert Enum.any?(trace, &(&1 == %{"bus_closed" => true, "listeners" => 0, "sessions" => 0}))
      assert Enum.count(trace, &(&1["method"] == "Disconnect")) == 0
    end
  end

  test "WBL-I05 native establishment without Value does not invent an initial Runtime value" do
    {native, record} = options("stream_runtime_silent")
    {consumed, context} = runtime_consumer(native, :property)
    owner = start_supervised!(runtime_spec(consumed, context, :property, self()))

    eventually(
      fn -> File.exists?(record) and Enum.any?(calls(record), &(&1["method"] == "StartNotify")) end,
      500
    )

    refute_receive {:runtime_decode, ^owner, _, _}, 30
    refute_receive {:wotex_runtime, _, {:ok, _, _}}, 30
    assert :ok = Wotex.Runtime.Subscription.stop(owner)
    assert Enum.count(calls(record), &(&1["method"] == "StopNotify")) == 1
  end

  test "WBL-I05 equal fresh signals remain distinct Runtime deliveries" do
    {native, record} = options("stream_runtime_repeat")
    {consumed, context} = runtime_consumer(native, :property)
    owner = start_supervised!(runtime_spec(consumed, context, :property, self()))

    for _ <- 1..3 do
      assert_receive {:runtime_decode, ^owner, {:value, <<1, 0>>, _}, _}, 5000
      assert_receive {:wotex_runtime, _, {:ok, 1, _}}, 5000
    end

    assert :ok = Wotex.Runtime.Subscription.stop(owner)
    assert Enum.count(calls(record), &(&1["method"] == "StopNotify")) == 1
  end

  test "WBL-I05 final receiver death during pending StartNotify releases the complete native owner" do
    {native, record} = options("stream_runtime_pending")
    {consumed, context} = runtime_consumer(native, :property)
    receiver = spawn(fn -> receive do: (:never -> :ok) end)
    owner = start_supervised!(runtime_spec(consumed, context, :property, receiver))
    on_exit(fn -> Process.exit(receiver, :kill) end)

    eventually(
      fn -> File.exists?(record) and Enum.any?(calls(record), &(&1["method"] == "StartNotify")) end,
      500
    )

    monitor = Process.monitor(owner)
    started = System.monotonic_time(:millisecond)
    Process.exit(receiver, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, :receiver_down}}, 1000
    eventually(fn -> Enum.any?(calls(record), &Map.has_key?(&1, "bus_closed")) end)
    assert System.monotonic_time(:millisecond) - started < 1100

    assert Enum.any?(
             calls(record),
             &(&1 == %{"bus_closed" => true, "listeners" => 0, "sessions" => 0})
           )

    refute_received {:runtime_decode, ^owner, _, _}
  end

  test "WBL-I05 failed establishment and malformed stream bytes never become Runtime values" do
    for {mode, code} <- [
          {"stream_runtime_failed", :not_permitted},
          {"stream_runtime_invalid_value", :invalid_response}
        ] do
      {native, record} = options(mode)
      {consumed, context} = runtime_consumer(native, :property)
      owner = start_supervised!(runtime_spec(consumed, context, :property, self()))
      assert_receive {:wotex_runtime, _, {:error, %{details: %{cause: %{code: ^code}}}}}, 5000
      refute_received {:wotex_runtime, _, {:ok, _, _}}
      if mode == "stream_runtime_invalid_value", do: Wotex.Runtime.Subscription.stop(owner)
      eventually(fn -> Enum.any?(calls(record), &Map.has_key?(&1, "bus_closed")) end)

      assert Enum.any?(
               calls(record),
               &(&1 == %{"bus_closed" => true, "listeners" => 0, "sessions" => 0})
             )
    end
  end

  test "WBL-I05 stop uses owned relay identity after a changed Form and failed stop credentials" do
    {native, record} = options("stream_runtime")
    {consumed, context} = runtime_consumer(native, :property, %{}, stop_route: true)
    owner = start_supervised!(runtime_spec(consumed, context, :property, self()))
    assert_receive {:wotex_runtime, _, {:ok, 1, _}}, 5000
    assert {:error, %{phase: :credentials}} = Wotex.Runtime.Subscription.stop(owner)
    assert_receive {:runtime_unsubscribe, handle, request, true}
    assert request.resolved_href == "ble://other/180a/2a00"
    assert :ok = Wotex.BLE.RuntimeRelay.close(handle)
    assert Enum.count(calls(record), &(&1["method"] == "StopNotify")) == 1

    assert Enum.any?(
             calls(record),
             &(&1 == %{"bus_closed" => true, "listeners" => 0, "sessions" => 0})
           )
  end

  test "WBL-I05 forged relay handles and stale envelopes cannot alter a bound subscription" do
    {native, record} = options("stream_runtime")
    {consumed, context} = runtime_consumer(native, :property)
    owner = start_supervised!(runtime_spec(consumed, context, :property, self()))
    assert_receive {:wotex_runtime, _, {:ok, 1, _}}, 5000
    handle = :sys.get_state(owner).handle
    state = :sys.get_state(handle.pid)

    assert {:error, %Error{code: :invalid_subscription}} =
             Wotex.BLE.RuntimeRelay.close(%{handle | reference: make_ref()})

    for invalid <- [%{handle | generation: 2}, Map.put(handle, :extra, "PRIVATE_CANARY"), nil] do
      assert {:error, %Error{code: :invalid_subscription}} = Wotex.BLE.RuntimeRelay.close(invalid)
    end

    send(handle.pid, {:wotex_ble, make_ref(), {:ok, <<42>>, %{}}})
    send(handle.pid, {:open_deadline, make_ref()})
    send(handle.pid, {:DOWN, make_ref(), :process, self(), :stale})
    send(handle.pid, :unrelated)
    refute inspect(:sys.get_status(handle.pid)) =~ "PRIVATE_CANARY"
    assert Process.alive?(state.session.handle.pid)
    refute_receive {:wotex_runtime, _, {:ok, _, _}}, 20
    assert :ok = Wotex.Runtime.Subscription.stop(owner)
    assert :ok = Wotex.BLE.RuntimeRelay.close(handle)
    assert Enum.count(calls(record), &(&1["method"] == "StopNotify")) == 1
  end

  test "WBL-I05 native connection loss terminates Runtime and releases relay state" do
    {native, record} = options("stream_runtime")
    {consumed, context} = runtime_consumer(native, :property)
    owner = start_supervised!(runtime_spec(consumed, context, :property, self()))
    assert_receive {:wotex_runtime, _, {:ok, 1, _}}, 5000
    handle = :sys.get_state(owner).handle
    session = :sys.get_state(handle.pid).session
    assert :ok = BLE.disconnect(session)
    assert_receive {:wotex_runtime, _, {:error, _}}, 1000
    assert_receive {:wotex_runtime, _, {:status, :session_lost}}, 1000
    eventually(fn -> not Process.alive?(owner) and not Process.alive?(handle.pid) end)

    assert Enum.any?(
             calls(record),
             &(&1 == %{"bus_closed" => true, "listeners" => 0, "sessions" => 0})
           )
  end

  test "WBL-I05 relay opening admits at most 64 reports and excess cannot establish later" do
    {native, record} = options("stream_runtime_pending")
    {consumed, context} = runtime_consumer(native, :property)
    owner = start_supervised!(runtime_spec(consumed, context, :property, self()))

    eventually(
      fn -> File.exists?(record) and Enum.any?(calls(record), &(&1["method"] == "StartNotify")) end,
      500
    )

    opening = :sys.get_state(owner).opening
    callback = :sys.get_state(opening.pid).worker
    {:monitors, [{:process, relay}]} = Process.info(callback, :monitors)
    for _ <- 1..65, do: send(relay, {:wotex_ble, make_ref(), {:ok, <<1, 0>>, %{}}})

    assert_receive {:wotex_runtime, _, {:error, %{details: %{cause: %{code: :receiver_overflow}}}}},
                   1000

    eventually(fn -> not Process.alive?(owner) and not Process.alive?(relay) end)

    assert Enum.any?(
             calls(record),
             &(&1 == %{"bus_closed" => true, "listeners" => 0, "sessions" => 0})
           )

    refute_received {:wotex_runtime, _, {:ok, _, _}}
  end

  test "WBL-I05 relay protects the Runtime owner mailbox and releases its session on overflow" do
    {native, record} = options("stream_runtime")
    {consumed, context} = runtime_consumer([max_queue_length: 1] ++ native, :property)
    owner = start_supervised!(runtime_spec(consumed, context, :property, self()))
    assert_receive {:runtime_decode, ^owner, {:value, _, metadata}, _}, 5000
    assert_receive {:wotex_runtime, _, {:ok, 1, _}}, 5000
    relay = :sys.get_state(owner).handle.pid
    subscription = :sys.get_state(relay).subscription
    :sys.suspend(owner)
    for _ <- 1..3, do: send(relay, {:wotex_ble, subscription.reference, {:ok, <<1, 0>>, metadata}})
    eventually(fn -> not Process.alive?(relay) end)
    :sys.resume(owner)

    assert_receive {:wotex_runtime, _, {:error, %{details: %{cause: %{code: :receiver_overflow}}}}},
                   1000

    assert_receive {:wotex_runtime, _, {:status, :session_lost}}, 1000
    eventually(fn -> not Process.alive?(owner) end)
    assert Enum.count(calls(record), &(&1["method"] == "StopNotify")) == 1
  end

  @tag capture_log: true
  test "WBL-I05 forced Runtime owner death releases a bound relay and its borrowed notification session" do
    {native, record} = options("stream_runtime")
    {consumed, context} = runtime_consumer(native, :property)
    owner = start_supervised!(runtime_spec(consumed, context, :property, self()))
    assert_receive {:wotex_runtime, _, {:ok, 1, _}}, 5000
    relay = :sys.get_state(owner).handle.pid
    started = System.monotonic_time(:millisecond)
    Process.exit(owner, :kill)
    eventually(fn -> not Process.alive?(relay) end)
    assert System.monotonic_time(:millisecond) - started < 1100

    assert Enum.any?(
             calls(record),
             &(&1 == %{"bus_closed" => true, "listeners" => 0, "sessions" => 0})
           )

    assert Enum.count(calls(record), &(&1["method"] == "Disconnect")) == 0
  end

  test "WBL-I02 WBL-I03 GATT backend and queue policy are explicit before native acquisition" do
    for override <- [
          [client: Wotex.BLE.RuntimeClient],
          [lifecycle: :oneshot],
          [owner: self()],
          [max_queue_length: 0]
        ] do
      {native, record} = options("stream_runtime")
      {consumed, context} = runtime_consumer(native, :property, %{}, config_override: override)
      owner = start_supervised!(runtime_spec(consumed, context, :property, self()))
      assert_receive {:wotex_runtime, _, {:error, %{class: :permanent}}}, 1000
      eventually(fn -> not Process.alive?(owner) end)
      refute File.exists?(record)
    end
  end

  test "WBL-I02 admitted GATT profile includes validated native read and acknowledged write" do
    {:ok, profile} = BLE.profile(:gatt)
    assert profile.id == :ble_gatt
    assert profile.schemes == MapSet.new(["ble"])
    assert profile.media_types == MapSet.new()

    assert profile.operations ==
             MapSet.new([
               :readproperty,
               :writeproperty,
               :observeproperty,
               :unobserveproperty,
               :subscribeevent,
               :unsubscribeevent
             ])

    {native, record} = options("procedure_runtime")

    {consumed, context} =
      runtime_consumer(native, :property, %{"op" => ["readproperty", "writeproperty"]})

    assert {:ok, %{payload: 42, status: :ok}} =
             Wotex.Runtime.ConsumedThing.read_property(consumed, "reading", context)

    assert {:ok, %{payload: :written, status: :ok}} =
             Wotex.Runtime.ConsumedThing.write_property(consumed, "reading", 513, context)

    assert Enum.count(calls(record), &(&1["method"] == "ReadValue")) == 1
    assert Enum.count(calls(record), &(&1["method"] == "WriteValue")) == 1
    assert Enum.count(calls(record), &Map.has_key?(&1, "bus_closed")) == 2
  end

  test "WBL-I04 WBL-I05 a pending native stream cannot extend the interaction deadline" do
    {native, record} = options("stream_runtime_pending")
    {consumed, context} = runtime_consumer(Keyword.put(native, :timeout, 500), :property)
    started = System.monotonic_time(:millisecond)
    owner = start_supervised!(runtime_spec(consumed, context, :property, self()))
    assert_receive {:wotex_runtime, _, {:error, %{class: :timeout}}}, 1500
    eventually(fn -> not Process.alive?(owner) end)

    if File.exists?(record) do
      for %{"pid" => pid} <- calls(record), do: eventually(fn -> process_gone?(pid) end)
    end

    assert System.monotonic_time(:millisecond) - started < 1600
    refute_received {:wotex_runtime, _, {:ok, _, _}}
  end

  test "WBL-I05 stalled StopNotify releases the owned sender within cleanup grace" do
    {native, record} = options("stream_runtime_stop_blocked")
    {consumed, context} = runtime_consumer(native, :property)
    owner = start_supervised!(runtime_spec(consumed, context, :property, self()))
    assert_receive {:wotex_runtime, _, {:ok, 1, _}}, 5000
    started = System.monotonic_time(:millisecond)
    assert :ok = Wotex.Runtime.Subscription.stop(owner)
    assert System.monotonic_time(:millisecond) - started < 1100
    trace = calls(record)
    assert Enum.count(trace, &(&1["method"] == "StopNotify")) == 1
    assert Enum.any?(trace, &(&1 == %{"bus_closed" => true, "listeners" => 0, "sessions" => 0}))
    for %{"pid" => pid} <- trace, do: eventually(fn -> process_gone?(pid) end)
  end

  defp runtime_consumer(native, kind, fields \\ %{}, controls \\ []) do
    start = if kind == :property, do: "observeproperty", else: "subscribeevent"
    stop = if kind == :property, do: "unobserveproperty", else: "unsubscribeevent"

    form =
      Map.merge(
        %{
          "href" => "ble://peer/180f/2a19",
          "op" => [start, stop],
          "wotex:bleValueType" => "uint16"
        },
        fields
      )

    forms =
      if controls[:stop_route] do
        [%{form | "op" => start}, %{form | "op" => stop, "href" => "ble://other/180a/2a00"}]
      else
        [form]
      end

    affordance =
      if kind == :property,
        do: %{"observable" => true, "forms" => forms},
        else: %{"forms" => forms}

    key = if kind == :property, do: "properties", else: "events"

    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "Native Runtime stream fixture",
        "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
        "security" => ["none"],
        key => %{"reading" => affordance}
      })

    {:ok, profile} = BLE.profile(:gatt)

    {:ok, consumed} =
      Wotex.Runtime.ConsumedThing.new(td,
        profiles: [profile],
        credentials:
          {Wotex.BLE.RuntimeErrorPort, if(controls[:stop_route], do: :reject_stop, else: nil)},
        transports: %{
          ble_gatt:
            {Wotex.BLE.RuntimeRecordingTransport,
             Keyword.merge(
               [client: BlueZ, lifecycle: :persistent, target: "peer", test_pid: self()] ++ native,
               Keyword.get(controls, :config_override, [])
             )}
        }
      )

    {consumed, Wotex.Runtime.Context.new!(request_id: "native-stream")}
  end

  defp runtime_spec(consumed, context, kind, receiver) do
    options = [
      id: make_ref(),
      receiver: receiver,
      restart: :temporary,
      max_queue_length: 1000,
      overflow: :stop
    ]

    {:ok, spec} =
      if kind == :property,
        do:
          Wotex.Runtime.ConsumedThing.observation_child_spec(consumed, "reading", context, options),
        else:
          Wotex.Runtime.ConsumedThing.event_subscription_child_spec(
            consumed,
            "reading",
            context,
            options
          )

    spec
  end
end
