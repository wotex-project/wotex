Code.require_file("../../support/native_command.ex", __DIR__)

defmodule Wotex.BLE.CoreBluetoothClientTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.{BLE, ThingDescription}
  alias Wotex.BLE.{Address, CoreBluetooth, Error, NativeCommand, Procedure}
  alias Wotex.BLE.CoreBluetooth.{Characteristic, Options, Peer}
  alias Wotex.Runtime.{ConsumedThing, Context}

  @root Path.expand("../../..", __DIR__)
  @identifier "01234567-89ab-cdef-0123-456789abcdef"
  @unique %{service: "181a", characteristic: "2a19"}
  @accepted %{write_mode: :without_response, evidence: :native_queue_accepted}

  setup_all do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wotex-cb-client-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    cc = System.find_executable("cc") || flunk("cc required")
    cxx = System.find_executable("c++") || flunk("C++17 required")
    command = Path.join(directory, "command")
    guardian = Path.join(directory, "guardian")
    peer = Path.join(directory, "peer")

    assert {:ok, _, 0} =
             NativeCommand.bootstrap(
               cc,
               Path.join(@root, "priv/bluez/native/build_command.c"),
               command
             )

    assert {:ok, "", 0} =
             NativeCommand.run(
               command,
               cc,
               [
                 "-std=c11",
                 "-O1",
                 "-Wall",
                 "-Wextra",
                 "-Werror",
                 Path.join(@root, "priv/bluez/native/custody.c"),
                 "-o",
                 guardian
               ],
               cd: directory
             )

    assert {:ok, "", 0} =
             NativeCommand.run(
               command,
               cxx,
               [
                 "-std=c++17",
                 "-O1",
                 "-Wall",
                 "-Wextra",
                 "-Werror",
                 "-pedantic",
                 Path.join(@root, "test/native/corebluetooth_client_peer.cpp"),
                 "-o",
                 peer
               ],
               cd: directory,
               timeout: 15_000
             )

    host = Path.join(directory, "host")

    assert {:ok, "", 0} =
             NativeCommand.run(
               command,
               cxx,
               [
                 "-std=c++17",
                 "-O1",
                 "-Wall",
                 "-Wextra",
                 "-Werror",
                 "-pedantic",
                 Path.join(@root, "test/native/corebluetooth_host_peer.cpp"),
                 "-o",
                 host
               ],
               cd: directory,
               timeout: 15_000
             )

    {:ok, directory: directory, peer: peer, guardian: guardian, host: host}
  end

  test "the public client traverses the production native Host with all 256 routes", context do
    {options, _} = options(%{context | peer: context.host})
    assert {:ok, session} = BLE.connect([client: CoreBluetooth] ++ options)
    on_exit(fn -> BLE.disconnect(session) end)
    assert {:ok, %{characteristics: routes}} = BLE.discover(session)
    assert length(routes) == 256
    assert {:ok, address} = Characteristic.address(List.last(routes))
    assert {:ok, <<0, 255>>} = BLE.read(session, address)
    assert {:ok, :written} = BLE.write(session, address, <<0, 255>>)
    assert {:ok, @accepted} = BLE.write(session, address, <<0, 255>>, write_mode: :without_response)
    assert :ok = BLE.disconnect(session)
  end

  test "pure values and closed startup options reject malformed or forged selectors", context do
    assert {:ok, peer} = Peer.new(String.upcase(@identifier))
    assert peer.identifier == @identifier
    refute inspect(peer) =~ @identifier

    for value <- [nil, 7, "180f", @identifier <> "\n", Map.put(peer, :extra, true)] do
      assert {:error, %Error{code: :invalid_peer}} = Peer.new(value)
    end

    {options, path} = options(context)

    for change <- [
          pairing: :none,
          permission: :automatic,
          generation: 0,
          generation: 0x1_0000_0000_0000_0000,
          timeout: 0,
          unknown: true,
          owner: :invalid
        ] do
      assert {:error, %Error{code: :invalid_options}} =
               CoreBluetooth.connect([change | Keyword.delete(options, elem(change, 0))])
    end

    assert {:error, _} = CoreBluetooth.connect([{:generation, 7} | options])
    assert {:error, _} = Options.new([:invalid], self())
    refute File.exists?(path <> ".pid")
    assert {:ok, %{permission: :require_authorized}} = Options.new(options, self())
    assert {:ok, legacy} = Address.new(@unique)
    refute Map.has_key?(Address.fields(legacy), :native_route)

    value = %{
      service: "181a",
      characteristic: "2a19",
      generation: 7,
      route: 1,
      read: true,
      write: false,
      write_without_response: true,
      notify: false,
      indicate: false
    }

    assert {:ok, characteristic} = Characteristic.new(value)

    for changed <- [
          Map.delete(value, :read),
          Map.put(value, :read, "true"),
          Map.put(value, :generation, 0),
          Map.put(value, :route, 257),
          Map.put(value, :extra, true),
          Map.put(characteristic, :extra, true)
        ] do
      assert {:error, %Error{code: :invalid_characteristic}} = Characteristic.new(changed)
    end

    for route <- [nil, {:bluez, 1}, {:core_bluetooth, 0}, {:core_bluetooth, 257}] do
      if route != nil, do: assert({:error, _} = Address.new(Map.put(@unique, :native_route, route)))
    end
  end

  test "facade keeps exact duplicate routes, bytes, modes, default permission and private status",
       context do
    {session, path} = connected(context)
    assert {:ok, %{generation: 7, characteristics: [first, second, unique]}} = BLE.discover(session)
    assert first.characteristic == second.characteristic
    assert first.route != second.route
    assert {:ok, address} = Characteristic.address(second)
    assert {:ok, <<0, 255>>} = BLE.read(session, address)
    assert {:ok, 65_280} = BLE.read(session, @unique, value_type: :uint16)
    assert {:ok, :written} = BLE.write(session, address, <<0, 255>>)
    assert {:ok, @accepted} = BLE.write(session, address, <<0, 255>>, write_mode: :without_response)
    assert {:ok, %{connected: true, services_resolved: true}} = BLE.health_check(session)

    assert {:error, %Error{code: :ambiguous_characteristic}} =
             BLE.read(session, %{service: "181a", characteristic: "2a6e"})

    assert {:error, %Error{code: :stale_discovery, effect: :none}} =
             BLE.write(session, %{address | generation: 8}, <<0>>)

    assert {:error, %Error{code: :address_mismatch}} =
             BLE.read(session, %{address | characteristic: unique.characteristic})

    assert {:error, %Error{code: :not_supported}} =
             Procedure.parameters(Map.merge(Address.fields(address), %{type: :read}))

    assert {:error, %Error{}} = Address.new(%{address | handle: 1})
    status = inspect(:sys.get_status(session.handle.pid))
    refute status =~ @identifier
    refute status =~ path
    refute inspect(session) =~ @identifier
    assert :ok = BLE.disconnect(session)
    assert {:error, %Error{code: :disconnected}} = BLE.disconnect(session)
    calls = calls(path)
    assert hd(calls)["parameters"]["permission"] == "require_authorized"

    assert Enum.map(calls, & &1["operation"]) ==
             ~w(open discover discover read read write write_command health close)

    writes = Enum.filter(calls, &(&1["operation"] in ~w(write write_command)))
    assert Enum.all?(writes, &(&1["parameters"]["address"] == %{"generation" => 7, "route" => 2}))

    assert Enum.all?(
             writes,
             &(&1["parameters"]["value"] == %{"type" => "bytes", "base64" => "AP8="})
           )

    assert_retired(path)
  end

  test "independent instances and linked ownership never share routes or close another owner",
       context do
    {left, left_path} = connected(context)
    {options, right_path} = options(context, "normal", 9)
    assert {:ok, pid} = CoreBluetooth.start_link(options)
    assert {:ok, right} = CoreBluetooth.session(pid)
    assert right.generation == 9

    assert {:error, %Error{code: :invalid_handle}} =
             CoreBluetooth.health_check(%{right | reference: left.handle.reference}, 100)

    assert :ok = BLE.disconnect(left)
    assert_retired(left_path)
    assert {:ok, _} = CoreBluetooth.health_check(right, 500)
    assert :ok = CoreBluetooth.disconnect(right)
    assert_retired(right_path)
  end

  test "marker and result faults cannot fabricate write success or a known-unsent failure",
       context do
    for mode <- ~w(missing-marker double-marker foreign-marker wrong-mode lost-before-marker) do
      {session, path} = connected(context, mode)

      assert {:error, %Error{effect: :unknown, class: :permanent}} =
               BLE.write(session, @unique, <<0, 255>>, write_mode: :without_response, timeout: 500)

      assert Enum.count(calls(path), &(&1["operation"] == "write_command")) == 1
      assert_retired(path)
    end

    for {mode, effect} <- [{"refuse", :none}, {"post-error", :unknown}] do
      {session, _} = connected(context, mode)

      assert {:error, %Error{code: :not_permitted, effect: ^effect}} =
               BLE.write(session, @unique, <<0, 255>>)

      assert {:ok, _} = BLE.health_check(session)
      assert :ok = BLE.disconnect(session)
    end
  end

  test "discovery cannot change within one generation and unsupported properties never change modes",
       context do
    {session, path} = connected(context, "changed-discovery")
    assert {:error, %Error{code: :stale_discovery}} = BLE.discover(session)
    assert_retired(path)
    {session, path} = connected(context, "command-only")

    assert {:error, %Error{code: :not_supported, effect: :none}} =
             BLE.write(session, @unique, <<0, 255>>)

    assert {:error, %Error{code: :not_supported}} = BLE.read(session, @unique)
    assert {:ok, @accepted} = BLE.write(session, @unique, <<0, 255>>, write_mode: :without_response)
    assert Enum.count(calls(path), &(&1["operation"] in ~w(read write write_command))) == 1
    assert :ok = BLE.disconnect(session)
  end

  test "queued expiry and caller death remove unsent work while active loss retires the generation",
       context do
    {session, path} = connected(context, "hold")
    active = Task.async(fn -> BLE.write(session, @unique, <<0, 255>>, timeout: 400) end)
    eventually(fn -> Enum.any?(calls(path), &(&1["operation"] == "write")) end)
    queued = spawn(fn -> BLE.read(session, @unique, timeout: 1000) end)
    eventually(fn -> queue_size(session) == 1 end)
    Process.exit(queued, :kill)
    eventually(fn -> queue_size(session) == 0 end)

    assert {:error, %Error{code: :timeout, effect: :none}} =
             BLE.write(session, @unique, <<1>>, timeout: 20)

    assert {:error, %Error{code: :timeout, effect: :unknown}} = Task.await(active, 2000)
    assert Enum.count(calls(path), &(&1["operation"] in ~w(read write write_command))) == 1
    assert_retired(path)
  end

  test "saturation admits only 64 calls and close overtakes active and queued operations",
       context do
    {session, path} = connected(context, "hold")
    active = Task.async(fn -> BLE.read(session, @unique) end)
    eventually(fn -> Enum.any?(calls(path), &(&1["operation"] == "read")) end)
    queued = for _ <- 1..63, do: Task.async(fn -> BLE.read(session, @unique) end)
    eventually(fn -> queue_size(session) == 63 end)
    assert {:error, %Error{code: :busy}} = BLE.read(session, @unique)
    assert :ok = BLE.disconnect(session)

    for task <- [active | queued],
        do: assert({:error, %Error{code: :disconnected}} = Task.await(task, 2000))

    assert Enum.count(calls(path), &(&1["operation"] == "read")) == 1
    assert_retired(path)
  end

  test "owner and active caller loss join real native cleanup", context do
    {options, path} = options(context, "hold")
    parent = self()

    owner =
      spawn(fn ->
        {:ok, handle} = CoreBluetooth.connect(options |> Keyword.delete(:owner))
        send(parent, {:handle, handle})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:handle, handle}, 3000
    monitor = Process.monitor(handle.pid)
    send(owner, :stop)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 2000
    assert_retired(path)
    {session, path} = connected(context, "hold")
    caller = spawn(fn -> BLE.write(session, @unique, <<0, 255>>) end)
    eventually(fn -> Enum.any?(calls(path), &(&1["operation"] == "write")) end)
    monitor = Process.monitor(session.handle.pid)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 2000
    assert_retired(path)
  end

  test "abrupt connection death preserves mutation uncertainty and the guardian reaps its child",
       context do
    {session, path} = connected(context, "hold")
    active = Task.async(fn -> BLE.write(session, @unique, <<0, 255>>) end)
    eventually(fn -> Enum.any?(calls(path), &(&1["operation"] == "write")) end)
    Process.exit(session.handle.pid, :kill)
    assert {:error, %Error{effect: :unknown, class: :permanent}} = Task.await(active, 2000)
    assert_retired(path)
  end

  test "artifact mismatch and unsupported Runtime profiles acquire no native process", context do
    {options, path} = options(context)

    assert {:error, %Error{}} =
             CoreBluetooth.connect(
               Keyword.put(options, :executable_sha256, String.duplicate("0", 64))
             )

    refute File.exists?(path <> ".pid")
    {:ok, gatt} = BLE.profile(:gatt)
    consumed = consumer(options, %{}, gatt)

    assert {:error, %{details: %{cause: %{code: :unsupported_profile}}}} =
             ConsumedThing.read_property(consumed, "value", Context.new!(request_id: "unsupported"))

    refute File.exists?(path <> ".pid")
    consumed = consumer(options, %{})

    assert {:error, _} =
             ConsumedThing.read_property(
               consumed,
               "value",
               Context.new!(
                 request_id: "expired",
                 deadline: System.monotonic_time(:millisecond) - 1
               )
             )

    refute File.exists?(path <> ".pid")
  end

  test "startup and late replies preserve original deadlines and cleanup failure stays explicit",
       context do
    for mode <- ~w(bad-ready bad-discovery hold-start) do
      {options, path} = options(context, mode)
      assert {:error, %Error{}} = CoreBluetooth.connect(Keyword.put(options, :timeout, 80))
      assert_retired(path)
    end

    {session, path} = connected(context, "late")

    assert {:error, %Error{code: :timeout, effect: :unknown}} =
             BLE.write(session, @unique, <<0, 255>>, timeout: 20)

    assert_retired(path)
    {session, path} = connected(context, "unconfirmed-close")
    assert {:error, %Error{code: :cleanup_timeout}} = BLE.disconnect(session)
    assert_retired(path)
    {session, path} = connected(context, "hold-close")
    assert {:error, %Error{code: :cleanup_timeout}} = BLE.disconnect(session)
    assert_retired(path)
  end

  test "real Runtime point interactions preserve target binding, codecs, command evidence and cleanup",
       context do
    for {operation, selector, expected} <- [
          {:read, %{"wotex:bleValueType" => "uint16"}, 65_280},
          {:write, %{}, :written},
          {:write, %{"wotex:bleWriteMode" => "without_response"}, @accepted}
        ] do
      {options, path} = options(context)
      consumed = consumer(options, selector)

      context =
        Context.new!(
          request_id: "core-runtime",
          deadline: System.monotonic_time(:millisecond) + 2000
        )

      result =
        if operation == :read,
          do: ConsumedThing.read_property(consumed, "value", context),
          else: ConsumedThing.write_property(consumed, "value", <<0, 255>>, context)

      assert {:ok, %{payload: ^expected, status: status}} = result
      assert status == if(expected == @accepted, do: :accepted, else: :ok)
      assert List.last(calls(path))["operation"] == "close"
      assert_retired(path)
    end

    for change <- [[target: "other"], [security_mode: :authenticated]] do
      {options, path} = options(context)
      consumed = consumer(Keyword.merge(options, change), %{})

      assert {:error, _} =
               ConsumedThing.read_property(consumed, "value", Context.new!(request_id: "denied"))

      refute File.exists?(path <> ".pid")
    end
  end

  test "public notifications retain generation, decode equal updates and retire only the selected route",
       context do
    {session, path} = connected(context, "stream")
    assert {:ok, subscription} = BLE.subscribe(session, %{address: @unique, value_type: :uint16})
    assert subscription.generation == 7
    reference = subscription.reference

    for _ <- 1..3 do
      assert_receive {:wotex_ble, ^reference, {:ok, 65_280, metadata}}, 1000
      assert metadata.source == :corebluetooth_value_update
      assert metadata.characteristic.generation == 7
      assert metadata.characteristic.route == 3
      assert metadata.effective_mode == :notify
    end

    eventually(fn ->
      Enum.any?(calls(path), &(&1["event"] == "notification_ack" and &1["sequence"] == 3))
    end)

    for forged <- [
          %{subscription | generation: 8},
          %{subscription | session_reference: make_ref()},
          Map.put(subscription, :extra, true)
        ] do
      assert {:error, %Error{code: :invalid_subscription}} = BLE.unsubscribe(session, forged)
    end

    assert :ok = BLE.unsubscribe(session, subscription)
    assert :ok = BLE.unsubscribe(session, subscription)

    assert {:error, %Error{code: :invalid_subscription}} =
             BLE.unsubscribe(session, %{subscription | reference: make_ref()})

    assert {:error, %Error{code: :not_supported}} = BLE.read(session, @unique)
    assert {:error, %Error{code: :not_permitted}} = BLE.subscribe(session, %{address: @unique})
    assert {:ok, _} = BLE.health_check(session)
    assert :ok = BLE.disconnect(session)
    assert_retired(path)
  end

  test "the public receiver traverses concurrent production Host reports and point writes",
       context do
    {session, path} = connected(%{context | peer: context.host}, "notification-async")
    assert {:ok, %{characteristics: [first, second | _]}} = BLE.discover(session)
    assert {:ok, address} = Characteristic.address(first)
    assert {:ok, other} = Characteristic.address(second)
    parent = self()
    receiver = spawn(fn -> drain_reports(parent, true) end)
    on_exit(fn -> Process.exit(receiver, :kill) end)

    assert {:ok, subscription} =
             BLE.subscribe(session, %{address: address, receiver: receiver, max_queue_length: 64})

    assert_receive {:first_report, bytes, %{source: :corebluetooth_value_update}}, 1000

    assert bytes == :binary.copy(<<255>>, 512)
    assert {:ok, :written} = BLE.write(session, other, <<0, 255>>)
    assert :ok = BLE.unsubscribe(session, subscription)
    assert {:ok, _} = BLE.health_check(session)
    assert :ok = BLE.disconnect(session)
    assert_retired(path)
  end

  test "wrong bindings, early values and malformed reports end the exact native generation",
       context do
    for mode <-
          ~w(stream-bad-binding stream-early stream-gap stream-foreign stream-stale stream-oversize) do
      {session, path} = connected(context, mode)
      monitor = Process.monitor(session.handle.pid)

      case BLE.subscribe(session, %{address: @unique}) do
        {:error, %Error{code: :invalid_response}} ->
          :ok

        {:ok, subscription} ->
          reference = subscription.reference
          assert_receive {:wotex_ble, ^reference, {:error, %Error{code: :invalid_response}}}, 1000
      end

      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 2000
      assert_retired(path)
    end
  end

  test "missing or false retirement fences cannot return successful cancellation", context do
    for mode <- ~w(stream-no-retire stream-bad-retire stream-hold-stop) do
      {session, path} = connected(context, mode)
      assert {:ok, subscription} = BLE.subscribe(session, %{address: @unique})
      assert {:error, %Error{}} = BLE.unsubscribe(session, subscription)
      eventually(fn -> not Process.alive?(session.handle.pid) end)
      assert_retired(path)
    end
  end

  test "pending establishment expires and receiver loss joins native retirement", context do
    {session, path} = connected(context, "stream-hold")

    assert {:error, %Error{code: :timeout}} =
             BLE.subscribe(session, %{address: @unique, timeout: 20})

    assert_retired(path)
    {session, path} = connected(context, "stream-hold")
    receiver = spawn(fn -> receive do: (:stop -> :ok) end)
    task = Task.async(fn -> BLE.subscribe(session, %{address: @unique, receiver: receiver}) end)
    eventually(fn -> Enum.any?(calls(path), &(&1["operation"] == "subscribe")) end)
    Process.exit(receiver, :kill)
    assert {:error, %Error{code: :disconnected}} = Task.await(task)
    eventually(fn -> not Process.alive?(session.handle.pid) end)
    assert_retired(path)
  end

  test "cancellation during a submitted point write fences delivery and retains unknown effect",
       context do
    {session, path} = connected(context, "stream-point-hold")
    assert {:ok, subscription} = BLE.subscribe(session, %{address: @unique})
    task = Task.async(fn -> BLE.write(session, @unique, <<0, 255>>) end)
    eventually(fn -> match?(%{active: %{submitted: true}}, :sys.get_state(session.handle.pid)) end)
    assert :ok = BLE.unsubscribe(session, subscription)
    assert {:error, %Error{code: :disconnected, effect: :unknown}} = Task.await(task)
    assert_retired(path)
  end

  test "a queued stream deadline removes unsent custody while a point write remains active",
       context do
    {session, path} = connected(context, "stream-point-hold")
    task = Task.async(fn -> BLE.write(session, @unique, <<0, 255>>) end)
    eventually(fn -> match?(%{active: %{submitted: true}}, :sys.get_state(session.handle.pid)) end)

    assert {:error, %Error{code: :timeout}} =
             BLE.subscribe(session, %{address: @unique, timeout: 20})

    assert :sys.get_state(session.handle.pid).subscriptions == %{}
    refute Enum.any?(calls(path), &(&1["operation"] == "subscribe"))
    assert :ok = BLE.disconnect(session)
    assert {:error, %Error{effect: :unknown}} = Task.await(task)
    assert_retired(path)
  end

  test "a dead queued establishing caller releases unsent custody without retiring an unrelated write",
       context do
    {session, path} = connected(context, "stream-point-hold")
    task = Task.async(fn -> BLE.write(session, @unique, <<0, 255>>) end)
    eventually(fn -> match?(%{active: %{submitted: true}}, :sys.get_state(session.handle.pid)) end)
    caller = spawn(fn -> BLE.subscribe(session, %{address: @unique, receiver: self()}) end)
    eventually(fn -> queue_size(session) == 1 end)
    Process.exit(caller, :kill)
    eventually(fn -> :sys.get_state(session.handle.pid).subscriptions == %{} end)
    assert Process.alive?(session.handle.pid)
    assert :sys.get_state(session.handle.pid).active.kind == :write
    refute Enum.any?(calls(path), &(&1["operation"] == "subscribe"))
    assert :ok = BLE.disconnect(session)
    assert {:error, %Error{effect: :unknown}} = Task.await(task)
  end

  test "receiver overflow emits one terminal error and retires its stream without closing an idle session",
       context do
    {session, _} = connected(context, "stream")
    receiver = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> Process.exit(receiver, :kill) end)
    send(receiver, :occupied)

    assert {:ok, subscription} =
             BLE.subscribe(session, %{address: @unique, receiver: receiver, max_queue_length: 1})

    eventually(fn -> not Process.alive?(subscription.pid) end)
    assert {:messages, messages} = Process.info(receiver, :messages)
    assert [:occupied, {:wotex_ble, _, {:error, %Error{code: :receiver_overflow}}}] = messages
    assert {:ok, _} = BLE.health_check(session)
    assert :ok = BLE.disconnect(session)
  end

  test "real Runtime Property and Event streams decode CoreBluetooth metadata and join cleanup",
       context do
    for kind <- [:property, :event] do
      {options, path} = options(context, "stream")
      consumed = stream_consumer(Keyword.delete(options, :owner), kind)
      request_context = Context.new!(request_id: "core-stream")

      {:ok, spec} =
        if kind == :property,
          do:
            ConsumedThing.observation_child_spec(consumed, "value", request_context,
              id: make_ref(),
              receiver: self(),
              restart: :temporary
            ),
          else:
            ConsumedThing.event_subscription_child_spec(consumed, "value", request_context,
              id: make_ref(),
              receiver: self(),
              restart: :temporary
            )

      owner = start_supervised!(Map.put(spec, :id, make_ref()))

      for _ <- 1..3 do
        assert_receive {:wotex_runtime, _, {:ok, 65_280, metadata}}, 3000
        assert metadata.source == :corebluetooth_value_update
        assert metadata.characteristic.route == 3
      end

      assert :ok = Wotex.Runtime.Subscription.stop(owner)
      assert List.last(calls(path))["operation"] == "close"
      assert_retired(path)
    end
  end

  test "a one-frame public receiver does not count its own opening reply as a report", context do
    {session, _} = connected(context, "stream")
    assert {:ok, subscription} = BLE.subscribe(session, %{address: @unique, max_queue_length: 1})
    reference = subscription.reference
    assert_receive {:wotex_ble, ^reference, {:ok, <<0, 255>>, _}}, 1000
    refute_receive {:wotex_ble, ^reference, {:error, _}}, 20
    assert :ok = BLE.unsubscribe(session, subscription)
    assert :ok = BLE.disconnect(session)
  end

  test "public admission retains sixteen independent streams and their shared credit", context do
    {session, path} = connected(context, "stream-capacity")
    assert {:ok, %{characteristics: routes}} = BLE.discover(session)

    addresses =
      Enum.map(Enum.take(routes, 17), fn route ->
        {:ok, address} = Characteristic.address(route)
        address
      end)

    subscriptions =
      Enum.map(Enum.take(addresses, 16), fn address ->
        assert {:ok, subscription} =
                 BLE.subscribe(session, %{address: address, max_queue_length: 4})

        subscription
      end)

    assert {:error, %Error{code: :resource_limit}} =
             BLE.subscribe(session, %{address: List.last(addresses), max_queue_length: 4})

    assert :ok = BLE.unsubscribe(session, hd(subscriptions))

    assert {:ok, last} =
             BLE.subscribe(session, %{address: List.last(addresses), max_queue_length: 4})

    assert :ok = BLE.unsubscribe(session, last)
    assert :ok = BLE.disconnect(session)
    assert_retired(path)
    eventually(fn -> Enum.all?(subscriptions, &(not Process.alive?(&1.pid))) end)
  end

  defp drain_reports(parent, first) do
    receive do
      {:wotex_ble, _, {:ok, bytes, metadata}} ->
        if first, do: send(parent, {:first_report, bytes, metadata})
        drain_reports(parent, false)

      {:wotex_ble, _, {:error, error}} ->
        send(parent, {:receiver_error, error})
    end
  end

  test "a killed delivery owner joins the actual native generation before cancellation succeeds",
       context do
    {session, path} = connected(context, "stream-silent")
    assert {:ok, subscription} = BLE.subscribe(session, %{address: @unique})
    :sys.suspend(session.handle.pid)
    monitor = Process.monitor(subscription.pid)

    try do
      Process.exit(subscription.pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, _, :killed}, 1000
      task = Task.async(fn -> BLE.unsubscribe(session, subscription) end)

      eventually(fn ->
        match?(
          {:message_queue_len, length} when length >= 2,
          Process.info(session.handle.pid, :message_queue_len)
        )
      end)

      :sys.resume(session.handle.pid)
      assert :ok = Task.await(task)
      assert_retired(path)
    after
      if Process.alive?(session.handle.pid), do: :sys.resume(session.handle.pid)
    end
  end

  @tag capture_log: true
  test "Runtime owner death during native establishment closes the private CoreBluetooth session",
       context do
    {options, path} = options(context, "stream-hold")
    consumed = stream_consumer(Keyword.delete(options, :owner), :property)

    {:ok, spec} =
      ConsumedThing.observation_child_spec(
        consumed,
        "value",
        Context.new!(request_id: "core-owner-loss"),
        id: make_ref(),
        receiver: self(),
        restart: :temporary
      )

    owner = start_supervised!(spec)
    eventually(fn -> Enum.any?(calls(path), &(&1["operation"] == "subscribe")) end, 500)
    monitor = Process.monitor(owner)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}, 1000
    eventually(fn -> Enum.any?(calls(path), &(&1["operation"] == "close")) end, 500)
    assert_retired(path)
    refute_received {:wotex_runtime, _, {:ok, _, _}}
  end

  test "invalid public handles, deadlines and stream requests leave native custody intact",
       context do
    {session, _} = connected(context, "stream-silent")
    handle = session.handle
    forged = %{handle | reference: make_ref()}

    for invalid <- [nil, self(), Map.put(handle, :extra, true)] do
      assert {:error, %Error{code: :invalid_handle}} = CoreBluetooth.health_check(invalid, 100)
    end

    assert {:error, %Error{code: :invalid_handle}} = CoreBluetooth.session(nil)
    assert {:error, %Error{code: :invalid_options}} = CoreBluetooth.start_link(nil)

    for timeout <- [0, 60_001, :infinity] do
      assert {:error, %Error{code: :invalid_timeout}} = CoreBluetooth.health_check(handle, timeout)
    end

    assert {:error, %Error{code: :invalid_options}} = CoreBluetooth.subscribe(handle, nil, 100)
    assert {:error, %Error{code: :invalid_subscription}} = CoreBluetooth.unsubscribe(handle, nil)
    assert {:error, %Error{code: :invalid_handle}} = CoreBluetooth.disconnect(forged)

    assert {:error, %Error{code: :invalid_handle}} =
             CoreBluetooth.subscribe(forged, %{address: @unique}, 100)

    assert {:error, %Error{code: :invalid_request}} =
             GenServer.call(handle.pid, {:operation, handle, :unsupported, deadline(500)})

    assert {:error, %Error{code: :invalid_request}} = GenServer.call(handle.pid, :unsupported)
    GenServer.cast(handle.pid, :stale_control)
    send(handle.pid, {:subscription_claim_timeout, self()})
    send(handle.pid, {:ble_report_consumed, handle.reference, self(), 1, make_ref()})
    assert {:ok, %{connected: true}} = CoreBluetooth.health_check(handle, 500)
    assert :ok = BLE.disconnect(session)
  end

  test "closing generations refuse new work and bound simultaneous close waiters", context do
    {session, path} = connected(context, "hold-close")
    handle = session.handle
    first = Task.async(fn -> CoreBluetooth.disconnect(handle) end)
    eventually(fn -> :sys.get_state(handle.pid).phase == :closing end)
    forged = %{handle | reference: make_ref()}

    assert {:error, %Error{code: :disconnected}} = CoreBluetooth.session(handle.pid)
    assert {:error, %Error{code: :disconnected}} = CoreBluetooth.health_check(handle, 100)
    assert {:error, %Error{code: :invalid_handle}} = CoreBluetooth.health_check(forged, 100)

    assert {:error, %Error{code: :disconnected}} =
             CoreBluetooth.subscribe(handle, %{address: @unique}, 100)

    assert {:error, %Error{code: :invalid_handle}} =
             CoreBluetooth.subscribe(forged, %{address: @unique}, 100)

    rest = for _ <- 1..63, do: Task.async(fn -> CoreBluetooth.disconnect(handle) end)
    eventually(fn -> length(:sys.get_state(handle.pid).close_waiters) == 64 end)
    assert {:error, %Error{code: :busy}} = CoreBluetooth.disconnect(handle)

    for waiter <- [first | rest] do
      assert {:error, %Error{code: :cleanup_timeout}} = Task.await(waiter, 3000)
    end

    assert_retired(path)
  end

  test "malformed native lines, oversized frames and connection loss retire active writes",
       context do
    for {data, code} <- [
          {{:eol, "{"}, :invalid_response},
          {{:noeol, String.duplicate("x", 131_072)}, :response_limit},
          {{:eol,
            Jason.encode!(%{
              version: 1,
              generation: 7,
              event: "connection_lost",
              code: "not_authorized"
            })}, :not_authorized},
          {{:eol,
            Jason.encode!(%{version: 1, generation: 7, id: "foreign", ok: true, result: nil})},
           :invalid_response}
        ] do
      {session, path} = connected(context, "hold")
      task = Task.async(fn -> BLE.write(session, @unique, <<1>>, timeout: 1000) end)
      eventually(fn -> match?(%{submitted: true}, :sys.get_state(session.handle.pid).active) end)
      port = :sys.get_state(session.handle.pid).port
      send(session.handle.pid, {port, {:data, data}})
      assert {:error, %Error{code: ^code, effect: :unknown}} = Task.await(task, 3000)
      assert_retired(path)
    end
  end

  test "late native success and explicit refusal preserve different mutation evidence", context do
    for operation <- [:read, :write] do
      {session, path} = connected(context, "hold")

      task =
        Task.async(fn ->
          if operation == :read,
            do: BLE.read(session, @unique, timeout: 500),
            else: BLE.write(session, @unique, <<1>>, timeout: 500)
        end)

      eventually(fn ->
        active = :sys.get_state(session.handle.pid).active
        active != nil and (operation == :read or active.submitted)
      end)

      state = :sys.get_state(session.handle.pid)
      :ok = :sys.suspend(session.handle.pid)

      try do
        result =
          if operation == :read,
            do: %{
              ok: false,
              error: %{
                code: "not_permitted",
                cause: "not_permitted",
                submitted: false,
                cleanup_confirmed: true
              }
            },
            else: %{ok: true, result: nil}

        frame = Map.merge(result, %{version: 1, generation: 7, id: state.active.id})
        send(session.handle.pid, {state.port, {:data, {:eol, Jason.encode!(frame)}}})
        Process.sleep(530)
      after
        :sys.resume(session.handle.pid)
      end

      effect = if operation == :read, do: :none, else: :unknown
      assert {:error, %Error{code: :timeout, effect: ^effect}} = Task.await(task, 3000)
      assert_retired(path)
    end
  end

  test "request identity exhaustion closes without sending a reused native operation", context do
    {session, path} = connected(context)
    :sys.replace_state(session.handle.pid, &%{&1 | sequence: 0xFFFF_FFFF_FFFF_FFFF})
    assert {:error, %Error{code: :resource_limit}} = BLE.read(session, @unique)
    refute Enum.any?(calls(path), &(&1["operation"] == "read"))
    assert_retired(path)
  end

  test "receiver loss removes an unsent subscription without interrupting a submitted write",
       context do
    {session, path} = connected(context, "stream-point-hold")
    write = Task.async(fn -> BLE.write(session, @unique, <<1>>) end)
    eventually(fn -> match?(%{submitted: true}, :sys.get_state(session.handle.pid).active) end)
    receiver = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> Process.exit(receiver, :kill) end)

    opening = Task.async(fn -> BLE.subscribe(session, %{address: @unique, receiver: receiver}) end)
    eventually(fn -> queue_size(session) == 1 end)
    Process.exit(receiver, :kill)
    assert {:error, %Error{code: :disconnected}} = Task.await(opening)
    assert {:ok, handle} = CoreBluetooth.session(session.handle.pid)
    assert handle == session.handle
    assert :sys.get_state(handle.pid).subscriptions == %{}
    refute Enum.any?(calls(path), &(&1["operation"] == "subscribe"))
    assert :ok = BLE.disconnect(session)
    assert {:error, %Error{effect: :unknown}} = Task.await(write)
    assert_retired(path)
  end

  test "dispatch drops dead and expired queued callers before sending another native request",
       context do
    for abandoned <- [:dead, :expired] do
      {session, path} = connected(context, "hold")
      write = Task.async(fn -> BLE.write(session, @unique, <<1>>) end)
      eventually(fn -> match?(%{submitted: true}, :sys.get_state(session.handle.pid).active) end)
      parent = self()

      reader =
        spawn(fn ->
          send(parent, {:queued_result, BLE.read(session, @unique, timeout: 500)})
        end)

      monitor = Process.monitor(reader)
      eventually(fn -> queue_size(session) == 1 end)
      state = :sys.get_state(session.handle.pid)
      :ok = :sys.suspend(session.handle.pid)

      try do
        true = Port.command(state.port, ~s({"fixture":"release"}\n))
        eventually(fn -> queued_native_reply?(session.handle.pid, state.port, state.active.id) end)

        if abandoned == :dead do
          Process.exit(reader, :kill)
          assert_receive {:DOWN, ^monitor, :process, ^reader, :killed}, 1000
        else
          Process.sleep(530)
        end
      after
        :sys.resume(session.handle.pid)
      end

      assert {:ok, :written} = Task.await(write)

      if abandoned == :expired do
        assert_receive {:queued_result, {:error, %Error{code: :timeout}}}, 1000
        assert_receive {:DOWN, ^monitor, :process, ^reader, :normal}, 1000
      end

      assert {:ok, _} = BLE.health_check(session)
      refute Enum.any?(calls(path), &(&1["operation"] == "read"))
      assert :ok = BLE.disconnect(session)
      assert_retired(path)
    end
  end

  test "loss of an explicitly linked process joins native cleanup", context do
    {session, path} = connected(context)
    owner = self()

    linked =
      spawn(fn ->
        Process.link(session.handle.pid)
        send(owner, :linked)
        receive do: (:fail -> exit(:failed))
      end)

    assert_receive :linked
    monitor = Process.monitor(session.handle.pid)
    send(linked, :fail)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 3000
    assert_retired(path)
  end

  test "an unclaimed opening reply expires without publishing a usable stream", context do
    {session, path} = connected(context, "stream-silent")
    handle = session.handle
    monitor = Process.monitor(handle.pid)
    request = %{address: @unique, receiver: self(), timeout: 100}

    # Stop at the reply/claim handoff to model a caller that never completes it.
    assert {:ok, subscription} =
             GenServer.call(
               handle.pid,
               {:subscribe, handle, request, 100, deadline(100)},
               1000
             )

    assert_receive {:wotex_ble, _, {:error, %Error{code: :timeout}}}, 3000
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 3000
    refute Process.alive?(subscription.pid)
    refute_received {:wotex_ble, _, {:ok, _, _}}
    assert_retired(path)
  end

  test "the public call deadline remains bounded when its connection cannot schedule", context do
    {session, path} = connected(context)
    :ok = :sys.suspend(session.handle.pid)

    try do
      task = Task.async(fn -> BLE.write(session, @unique, <<1>>, timeout: 1) end)
      assert {:error, %Error{code: :timeout, effect: :unknown}} = Task.await(task, 3000)
    after
      :sys.resume(session.handle.pid)
    end

    assert {:ok, _} = BLE.health_check(session)
    refute Enum.any?(calls(path), &(&1["operation"] == "write"))
    assert :ok = BLE.disconnect(session)
  end

  test "forged lost-subscription handles cannot borrow another generation's cleanup", context do
    {session, _} = connected(context)
    dead = spawn(fn -> :ok end)
    monitor = Process.monitor(dead)
    assert_receive {:DOWN, ^monitor, :process, ^dead, _}, 1000
    forged = %{session.handle | reference: make_ref()}

    subscription = %Wotex.BLE.Subscription{
      pid: dead,
      reference: make_ref(),
      session_reference: forged.reference,
      generation: forged.generation
    }

    assert {:error, %Error{code: :invalid_subscription}} =
             CoreBluetooth.unsubscribe(forged, subscription)

    GenServer.cast(session.handle.pid, {:subscription_claimed, session.handle, subscription})
    assert {:ok, _} = BLE.health_check(session)
    assert :ok = BLE.disconnect(session)
  end

  defp deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  defp queued_native_reply?(pid, port, id) do
    {:messages, messages} = Process.info(pid, :messages)

    Enum.any?(messages, fn
      {^port, {:data, {:eol, line}}} -> Jason.decode!(line)["id"] == id
      _ -> false
    end)
  end

  defp stream_consumer(options, kind) do
    {key, start, stop} =
      if kind == :property,
        do: {"properties", "observeproperty", "unobserveproperty"},
        else: {"events", "subscribeevent", "unsubscribeevent"}

    affordance = %{
      "forms" => [
        %{
          "href" => "ble://route/181a/2a19",
          "op" => [start, stop],
          "wotex:bleValueType" => "uint16"
        }
      ]
    }

    affordance = if kind == :property, do: Map.put(affordance, "observable", true), else: affordance

    {:ok, td} =
      ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "CoreBluetooth stream fixture",
        "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
        "security" => ["none"],
        key => %{"value" => affordance}
      })

    {:ok, profile} = BLE.profile(:gatt)

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        credentials: {Wotex.BLE.RuntimeErrorPort, nil},
        transports: %{
          ble_gatt:
            {Wotex.BLE.Transport, Keyword.merge([client: CoreBluetooth, target: "route"], options)}
        }
      )

    consumed
  end

  defp options(context, mode \\ "normal", generation \\ 7) do
    path = Path.join(context.directory, "instance-#{System.unique_integer([:positive])}")
    File.cp!(context.peer, path)
    File.chmod!(path, 0o700)
    File.write!(path <> ".mode", mode)
    {:ok, peer} = Peer.new(@identifier)

    {[
       peer: peer,
       generation: generation,
       pairing: :system,
       owner: self(),
       timeout: 1000,
       executable: path,
       executable_sha256: digest(path),
       guardian: context.guardian,
       guardian_sha256: digest(context.guardian)
     ], path}
  end

  defp connected(context, mode \\ "normal") do
    {options, path} = options(context, mode)
    assert {:ok, session} = BLE.connect([client: CoreBluetooth] ++ options)
    on_exit(fn -> BLE.disconnect(session) end)
    {session, path}
  end

  defp digest(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  defp calls(path) do
    case File.read(path <> ".calls") do
      {:ok, value} ->
        value
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      _ ->
        []
    end
  end

  defp queue_size(session), do: length(:sys.get_state(session.handle.pid).queue)
  defp eventually(fun, attempts \\ 200)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, attempts) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(5)
          eventually(fun, attempts - 1)
        )
  end

  defp assert_retired(path) do
    if File.exists?(path <> ".pid") do
      pid = String.trim(File.read!(path <> ".pid"))

      eventually(fn ->
        match?(
          {_, 1},
          System.cmd("/bin/kill", ["-0", pid],
            stderr_to_stdout: true,
            env: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
          )
        )
      end)
    end
  end

  defp consumer(options, selector, profile \\ BLE.profile()) do
    {:ok, td} =
      ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "CoreBluetooth process fixture",
        "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
        "security" => ["none"],
        "properties" => %{
          "value" => %{"forms" => [Map.merge(%{"href" => "ble://route/181a/2a19"}, selector)]}
        }
      })

    config = Keyword.merge([client: CoreBluetooth, target: "route"], options)

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{profile.id => {Wotex.BLE.Transport, config}},
        credentials: {Wotex.BLE.RuntimeErrorPort, nil}
      )

    consumed
  end
end
