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
