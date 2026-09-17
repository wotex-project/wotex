defmodule Wotex.BLE.StreamBridgeTest do
  @moduledoc false
  use ExUnit.Case, async: true
  import Wotex.BLE.NativeFixture

  alias Wotex.BLE
  alias Wotex.BLE.{BlueZ, Error}

  defp connect(mode) do
    {options, record} = options(mode)
    assert {:ok, session} = BLE.connect([client: BlueZ, lifecycle: :persistent] ++ options)
    on_exit(fn -> BLE.disconnect(session) end)
    {session, record}
  end

  defp target,
    do: %{
      service: "180f",
      characteristic: "2a19",
      object_path: "/another/characteristic0",
      handle: 1,
      generation: 1
    }

  test "WBL-P05 C05 V07 native owners deliver typed reports and cancel the original sender" do
    for mode <- ["stream_notify", "stream_indicate"] do
      {session, record} = connect(mode)
      assert {:ok, handle} = BLE.subscribe(session, %{address: target(), value_type: :uint16})
      assert handle.pid != session.handle.pid
      assert handle.session_reference == session.handle.reference
      ref = handle.reference
      assert_receive {:wotex_ble, ^ref, {:ok, 1, metadata}}, 1000
      assert metadata.source == :bluez_value_change
      assert metadata.effective_mode == if(mode == "stream_notify", do: :notify, else: :indicate)
      assert metadata.characteristic.object_path == target().object_path
      assert {:ok, <<0x34, 0x12>>} = BLE.read(session, target())
      assert_receive {:wotex_ble, ^ref, {:ok, 4660, ^metadata}}, 1000
      assert_receive {:wotex_ble, ^ref, {:ok, 4660, ^metadata}}, 1000
      monitor = Process.monitor(handle.pid)
      assert :ok = BLE.unsubscribe(session, handle)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1000
      assert :ok = BLE.unsubscribe(session, handle)
      assert operations(record) == ["open", "subscribe", "read", "unsubscribe"]
      assert :sys.get_state(session.handle.pid).subscriptions == %{}
      refute_receive {:wotex_ble, ^ref, _}, 10
      assert :ok = BLE.disconnect(session)
      assert closed(record) == %{"closed" => true, "streams" => 0, "pending" => []}
    end
  end

  test "WBL-C05 foreign live and dead handles fail before native I/O" do
    {session, record} = connect("stream_notify")
    assert {:ok, handle} = BLE.subscribe(session, %{address: target()})
    before = calls(record)

    for forged <- [
          %{handle | reference: make_ref()},
          %{handle | pid: self(), reference: make_ref()},
          %{handle | session_reference: make_ref()},
          %{handle | generation: 1.0},
          Map.put(handle, :extra, true)
        ] do
      assert {:error, %Error{code: :invalid_subscription}} = BLE.unsubscribe(session, forged)
    end

    assert calls(record) == before
    assert :ok = BLE.unsubscribe(session, handle)

    assert {:error, %Error{code: :invalid_subscription}} =
             BLE.unsubscribe(session, %{handle | session_reference: make_ref()})

    assert :ok = BLE.unsubscribe(session, %{handle | reference: make_ref()})
  end

  test "WBL-C03 V09 receiver death preempts blocked data and bounds failed StopNotify" do
    for mode <- ["stream_blocked_read", "stream_blocked_stop"] do
      {session, record} = connect(mode)

      receiver =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      assert {:ok, handle} = BLE.subscribe(session, %{address: target(), receiver: receiver})
      monitor = Process.monitor(handle.pid)
      read = Task.async(fn -> BLE.read(session, target(), timeout: 60_000) end)
      eventually(fn -> count(record, "read") == 1 end)
      started = System.monotonic_time(:millisecond)
      Process.exit(receiver, :kill)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1000
      assert System.monotonic_time(:millisecond) - started < 1000
      assert count(record, "unsubscribe") == 1

      if mode == "stream_blocked_read" do
        assert Process.alive?(session.handle.pid)
        assert closed(record) == nil
        assert :ok = BLE.disconnect(session)
      else
        eventually(fn -> closed(record) != nil end)

        assert closed(record) == %{
                 "closed" => true,
                 "streams" => 1,
                 "pending" => ["read", "unsubscribe"]
               }
      end

      assert {:error, %Error{}} = Task.await(read, 2000)
    end
  end

  test "WBL-C05 V08 receiver overflow emits one terminal and releases native resources" do
    {session, record} = connect("stream_notify")

    receiver =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> Process.exit(receiver, :kill) end)

    assert {:ok, handle} =
             BLE.subscribe(session, %{address: target(), receiver: receiver, max_queue_length: 1})

    monitor = Process.monitor(handle.pid)
    eventually(fn -> elem(Process.info(receiver, :message_queue_len), 1) == 1 end)
    assert {:ok, _} = BLE.read(session, target())
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1000
    ref = handle.reference

    assert {:messages,
            [
              {:wotex_ble, ^ref, {:ok, <<1, 0>>, _}},
              {:wotex_ble, ^ref, {:error, %Error{code: :receiver_overflow}}}
            ]} = Process.info(receiver, :messages)

    assert count(record, "unsubscribe") == 1
    assert :ok = BLE.unsubscribe(session, handle)
  end

  test "WBL-V08 failed early establishment never returns a handle" do
    {session, record} = connect("stream_early_overflow")
    assert {:error, %Error{code: :response_limit}} = BLE.subscribe(session, %{address: target()})
    assert operations(record) == ["open", "subscribe"]
    assert :sys.get_state(session.handle.pid).subscriptions == %{}
    assert :sys.get_state(session.handle.pid).pending == %{}
    refute_receive {:wotex_ble, _, _}, 10
  end

  test "WBL-C05 one thousand BEAM lifetimes retain only active subscription records" do
    {session, record} = connect("stream_notify")

    for _ <- 1..1000 do
      assert {:ok, handle} = BLE.subscribe(session, %{address: target()})
      ref = handle.reference
      assert_receive {:wotex_ble, ^ref, {:ok, <<1, 0>>, _}}, 1000
      assert :ok = BLE.unsubscribe(session, handle)
      refute Process.alive?(handle.pid)
      state = :sys.get_state(session.handle.pid)
      assert state.subscriptions == %{} and state.pending == %{}
    end

    assert count(record, "subscribe") == 1000
    assert count(record, "unsubscribe") == 1000
  end

  test "WBL-C05 finite active subscription capacity and duplicate target are independent" do
    {session, record} = connect("stream_capacity")

    handles =
      for index <- 0..63 do
        address = %{target() | object_path: "/another/characteristic#{index}", handle: index + 1}
        assert {:ok, handle} = BLE.subscribe(session, %{address: address})
        ref = handle.reference
        assert_receive {:wotex_ble, ^ref, {:ok, <<1, 0>>, _}}, 1000
        handle
      end

    before = calls(record)
    address = %{target() | object_path: "/another/characteristic64", handle: 65}
    assert {:error, %Error{code: :busy}} = BLE.subscribe(session, %{address: address})
    assert calls(record) == before
    Enum.each(handles, fn handle -> assert :ok = BLE.unsubscribe(session, handle) end)
    assert :sys.get_state(session.handle.pid).subscriptions == %{}
    assert {:ok, handle} = BLE.subscribe(session, %{address: target()})

    assert {:error, %Error{code: :already_subscribed}} =
             BLE.subscribe(session, %{address: target()})

    assert :ok = BLE.unsubscribe(session, handle)
  end

  test "WBL-C03 concurrent cancellation waits for StopNotify and owned Port EXIT is only advisory" do
    {session, record} = connect("stream_slow_stop")
    assert {:ok, handle} = BLE.subscribe(session, %{address: target()})
    tasks = for _ <- 1..32, do: Task.async(fn -> BLE.unsubscribe(session, handle) end)
    eventually(fn -> count(record, "unsubscribe") == 1 end)
    state = :sys.get_state(session.handle.pid)
    send(session.handle.pid, {:EXIT, state.port, :normal})
    send(session.handle.pid, {:EXIT, state.port, :fixture_reason})
    assert :sys.get_state(session.handle.pid).status == :ready
    assert Enum.map(tasks, &Task.await(&1, 1500)) == List.duplicate(:ok, 32)
    assert count(record, "unsubscribe") == 1
    assert :sys.get_state(session.handle.pid).subscriptions == %{}
  end

  test "WBL-C07 bound stream metadata, generations and unknown IDs fail closed without delivery" do
    for mode <- [
          "stream_wrong_generation",
          "stream_wrong_metadata",
          "stream_extra_report",
          "stream_unknown_report"
        ] do
      {session, _} = connect(mode)
      monitor = Process.monitor(session.handle.pid)
      assert {:ok, handle} = BLE.subscribe(session, %{address: target()})
      ref = handle.reference
      assert_receive {:wotex_ble, ^ref, {:error, %Error{code: :invalid_response}}}, 1500
      refute_receive {:wotex_ble, ^ref, _}, 10
      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1100
      eventually(fn -> not Process.alive?(handle.pid) end)
    end
  end

  test "WBL-C03 death while StartNotify is pending closes the generation" do
    {session, record} = connect("stream_pending_start")

    receiver =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    task = Task.async(fn -> BLE.subscribe(session, %{address: target(), receiver: receiver}) end)
    eventually(fn -> count(record, "subscribe") == 1 end)
    started = System.monotonic_time(:millisecond)
    Process.exit(receiver, :kill)
    assert {:error, %Error{}} = Task.await(task, 1100)
    assert System.monotonic_time(:millisecond) - started < 1000
    eventually(fn -> closed(record) != nil end)
    assert closed(record) == %{"closed" => true, "streams" => 0, "pending" => ["subscribe"]}
  end

  test "WBL-C02 invalid facade inputs and dead or foreign sessions never acquire subscriptions" do
    assert {:error, %Error{code: :invalid_session}} = BLE.subscribe(nil, %{})
    assert {:error, %Error{code: :invalid_session}} = BLE.unsubscribe(nil, nil)
    assert {:error, %Error{code: :not_supported}} = BlueZ.subscribe(%{}, %{}, 5000)
    assert {:error, %Error{code: :not_supported}} = BlueZ.unsubscribe(%{}, nil)
    {session, record} = connect("stream_notify")
    before = calls(record)

    assert {:error, %Error{code: :invalid_handle}} =
             BlueZ.subscribe(Map.put(session.handle, :extra, true), %{address: target()}, 5000)

    assert {:error, %Error{code: :invalid_options}} =
             BLE.subscribe(session, %{address: target(), extra: true})

    assert {:error, %Error{code: :invalid_handle}} =
             BlueZ.subscribe(%{session.handle | reference: make_ref()}, %{address: target()}, 5000)

    assert calls(record) == before
    assert :ok = BLE.disconnect(session)
    assert {:error, %Error{code: :disconnected}} = BLE.subscribe(session, %{address: target()})
  end

  test "WBL-C03 C05 queued caller death releases admission without starting GATT" do
    {session, record} = connect("stream_blocked_read")
    read = Task.async(fn -> BLE.read(session, target(), timeout: 60_000) end)
    eventually(fn -> count(record, "read") == 1 end)
    caller = spawn(fn -> BLE.subscribe(session, %{address: target()}) end)
    eventually(fn -> map_size(:sys.get_state(session.handle.pid).pending) == 2 end)
    Process.exit(caller, :kill)
    eventually(fn -> map_size(:sys.get_state(session.handle.pid).pending) == 1 end)
    assert count(record, "subscribe") == 0
    assert Process.alive?(session.handle.pid)
    assert :ok = BLE.disconnect(session)
    assert {:error, %Error{}} = Task.await(read, 1500)
  end

  test "WBL-C03 C05 killed subscription owner triggers same-sender cancellation" do
    {session, record} = connect("stream_notify")
    assert {:ok, handle} = BLE.subscribe(session, %{address: target()})
    Process.exit(handle.pid, :kill)
    eventually(fn -> :sys.get_state(session.handle.pid).subscriptions == %{} end)
    assert count(record, "unsubscribe") == 1
    assert :ok = BLE.unsubscribe(session, handle)
  end

  test "WBL-C03 V09 uncertain cancellation releases the sender before returning failure" do
    for {mode, streams, pending} <- [
          {"stream_bad_stop_ack", 0, []},
          {"stream_lost_stop_ack", 0, ["unsubscribe"]},
          {"stream_stop_error", 1, []}
        ] do
      {session, record} = connect(mode)
      assert {:ok, handle} = BLE.subscribe(session, %{address: target()})
      assert {:error, %Error{}} = BLE.unsubscribe(session, handle)
      refute Process.alive?(handle.pid)
      eventually(fn -> closed(record) != nil end)
      assert closed(record) == %{"closed" => true, "streams" => streams, "pending" => pending}
      assert count(record, "unsubscribe") == 1
    end
  end

  test "WBL-C07 wrong establishment binding fails and a value codec error is terminal once" do
    {session, _} = connect("stream_wrong_binding")
    assert {:error, %Error{code: :invalid_response}} = BLE.subscribe(session, %{address: target()})
    {session, record} = connect("stream_notify")
    assert {:ok, handle} = BLE.subscribe(session, %{address: target(), value_type: :uint32})
    ref = handle.reference
    assert_receive {:wotex_ble, ^ref, {:error, %Error{code: :invalid_value}}}, 1000
    eventually(fn -> not Process.alive?(handle.pid) end)
    refute_receive {:wotex_ble, ^ref, _}, 10
    assert count(record, "unsubscribe") == 1
  end

  @spec subscription_event(list(), map(), map(), {pid(), reference()}) :: tuple()
  def subscription_event(event, measurements, metadata, {receiver, token}),
    do: send(receiver, {token, event, measurements, metadata})

  test "WBL-C08 stream diagnostics expose bounded counts and codes without identities or payloads" do
    token = make_ref()
    events = for phase <- [:open, :deliver, :close], do: [:wotex, :ble, :subscription, phase]

    assert :ok =
             :telemetry.attach_many(
               token,
               events,
               &__MODULE__.subscription_event/4,
               {self(), token}
             )

    on_exit(fn -> :telemetry.detach(token) end)
    {session, _} = connect("stream_canary")
    assert {:ok, handle} = BLE.subscribe(session, %{address: target()})
    ref = handle.reference
    assert_receive {:wotex_ble, ^ref, {:ok, "PRIVATE_STREAM_VALUE", _}}, 1000
    status = inspect(:sys.get_status(handle.pid))
    refute status =~ "PRIVATE_STREAM_VALUE"
    refute status =~ inspect(handle.reference)
    refute status =~ target().object_path
    assert :ok = BLE.unsubscribe(session, handle)

    for event <- events do
      assert_receive {^token, ^event, %{count: 1} = measurements, %{code: :ok} = metadata}, 1000
      assert map_size(measurements) == 1 and map_size(metadata) == 1
    end
  end

  test "WBL-C03 expired admission creates no owner or native GATT request" do
    {session, record} = connect("stream_notify")
    :ok = :sys.suspend(session.handle.pid)
    task = Task.async(fn -> BLE.subscribe(session, %{address: target(), timeout: 20}) end)
    Process.sleep(50)
    :ok = :sys.resume(session.handle.pid)
    assert {:error, %Error{code: :timeout}} = Task.await(task, 1000)
    assert :sys.get_state(session.handle.pid).subscriptions == %{}
    assert :sys.get_state(session.handle.pid).pending == %{}
    assert count(record, "subscribe") == 0
  end

  test "WBL-C05 C03 saturated data admission escalates receiver cleanup within ownership grace" do
    {session, record} = connect("stream_blocked_read")

    receiver =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    assert {:ok, handle} = BLE.subscribe(session, %{address: target(), receiver: receiver})
    readers = for _ <- 1..64, do: Task.async(fn -> BLE.read(session, target(), timeout: 60_000) end)
    eventually(fn -> map_size(:sys.get_state(session.handle.pid).pending) == 64 end)
    monitor = Process.monitor(handle.pid)
    Process.exit(receiver, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1000
    assert closed(record) == %{"closed" => true, "streams" => 1, "pending" => ["read"]}
    assert Enum.all?(readers, fn task -> match?({:error, %Error{}}, Task.await(task, 1500)) end)
  end

  test "WBL-C08 exception status redaction removes sensitive messages reasons and log data" do
    status = %{
      state: %{status: :closing},
      message: "PRIVATE_STREAM_VALUE",
      reason: {"PRIVATE_PEER", make_ref()},
      log: ["PRIVATE_CREDENTIAL"],
      other: :retained
    }

    assert %{
             state: %{status: :closing},
             message: :redacted,
             reason: :redacted,
             log: [],
             other: :retained
           } = Wotex.BLE.BlueZ.SubscriptionOwner.format_status(status)

    connection_status = put_in(status[:state][:pending], %{})

    expected = %{
      state: %{pending: 0, status: :closing},
      message: :redacted,
      reason: :redacted,
      log: [],
      other: :retained
    }

    assert Wotex.BLE.BlueZ.Connection.format_status(connection_status) == expected
  end

  test "WBL-C07 controls overtake queued data without rekeying deadlines or wire IDs" do
    {session, record} = connect("stream_dispatch_overtake")
    assert {:ok, handle} = BLE.subscribe(session, %{address: target()})
    first = Task.async(fn -> BLE.read(session, target()) end)
    eventually(fn -> count(record, "read") == 1 end)
    queued = Task.async(fn -> BLE.read(session, target()) end)
    eventually(fn -> map_size(:sys.get_state(session.handle.pid).pending) == 2 end)
    state = :sys.get_state(session.handle.pid)
    assert Enum.all?(Map.keys(state.pending), &is_reference/1)
    assert map_size(state.wires) == 1

    queued_entry =
      Enum.find_value(state.pending, fn {ref, pending} ->
        if is_nil(pending.wire_id), do: {ref, pending.timer}
      end)

    assert {reference, timer} = queued_entry
    assert is_reference(reference) and is_reference(timer)
    assert :ok = BLE.unsubscribe(session, handle)
    assert {:ok, <<0x34, 0x12>>} = Task.await(first, 1500)
    assert {:ok, <<0x34, 0x12>>} = Task.await(queued, 1500)

    assert Enum.map(
             Enum.filter(calls(record), &Map.has_key?(&1, "wire_id")),
             &{&1["wire_id"], &1["operation"]}
           ) ==
             [
               {"open", "open"},
               {"1", "subscribe"},
               {"2", "read"},
               {"3", "unsubscribe"},
               {"4", "read"}
             ]

    assert :sys.get_state(session.handle.pid).pending == %{}
    assert :sys.get_state(session.handle.pid).wires == %{}
    assert :queue.is_empty(:sys.get_state(session.handle.pid).queue)
  end

  test "WBL-C07 dispatch counter exhaustion closes without wrapping or sending a mutation" do
    {session, record} = connect("stream_notify")
    :sys.replace_state(session.handle.pid, &%{&1 | counter: 0xFFFF_FFFF_FFFF_FFFF})

    assert {:error, %Error{code: :request_id_exhausted, effect: :none}} =
             BLE.write(session, target(), <<1>>)

    assert :ok = BLE.disconnect(session)
    assert count(record, "write") == 0

    assert Enum.map(Enum.filter(calls(record), &Map.has_key?(&1, "wire_id")), & &1["wire_id"]) == [
             "open",
             "close"
           ]
  end
end
