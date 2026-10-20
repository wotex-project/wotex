Code.require_file("corebluetooth_support.exs", __DIR__)

defmodule CoreClientArchiveTest do
  @moduledoc false

  use ExUnit.Case, async: false
  import CoreArchiveSupport
  alias Wotex.BLE
  alias Wotex.BLE.{CoreBluetooth, Error}
  @address %{service: "181a", characteristic: "2a19"}
  @accepted %{write_mode: :without_response, evidence: :native_queue_accepted}

  test "literal point bytes, duplicate routes and both write modes survive archive extraction" do
    {session, path} = connect("normal")
    assert {:ok, %{generation: 7, characteristics: [first, second, _]}} = BLE.discover(session)
    assert first.characteristic == second.characteristic
    assert first.route != second.route
    assert {:ok, exact} = CoreBluetooth.Characteristic.address(second)
    assert {:ok, <<0, 255>>} = BLE.read(session, exact)
    assert {:ok, 65_280} = BLE.read(session, @address, value_type: :uint16)

    for bytes <- [<<>>, <<1, 2>>, :binary.copy(<<255>>, 512)] do
      assert {:ok, :written} = BLE.write(session, @address, bytes)
      assert {:ok, @accepted} = BLE.write(session, @address, bytes, write_mode: :without_response)
    end

    writes = Enum.filter(records(path), &(&1["operation"] in ["write", "write_command"]))

    assert Enum.map(writes, & &1["operation"]) ==
             List.flatten(List.duplicate(["write", "write_command"], 3))

    assert Enum.map(writes, & &1["parameters"]["value"]["base64"]) ==
             List.flatten(
               for value <- [<<>>, <<1, 2>>, :binary.copy(<<255>>, 512)],
                   do: List.duplicate(Base.encode64(value), 2)
             )

    assert :ok = BLE.disconnect(session)
    eventually(fn -> gone?(pid(path)) end)
  end

  test "invalid modes, addresses, sizes and artifact identities acquire no operation" do
    {session, path} = connect("normal")

    for options <- [
          [write_mode: :auto],
          [write_mode: nil],
          [write_mode: :without_response, write_mode: :without_response]
        ] do
      assert {:error, %Error{effect: :none}} = BLE.write(session, @address, <<1>>, options)
    end

    assert {:error, %Error{effect: :none}} = BLE.write(session, @address, :binary.copy(<<0>>, 513))

    assert {:error, %Error{code: :stale_discovery}} =
             BLE.write(session, Map.put(@address, :generation, 8), <<1>>)

    assert {:error, %Error{code: :ambiguous_characteristic}} =
             BLE.read(session, %{service: "181a", characteristic: "2a6e"})

    assert Enum.map(records(path), & &1["operation"]) |> Enum.reject(&is_nil/1) == [
             "open",
             "discover"
           ]

    {options, unstarted} = fixture("normal")

    assert {:error, %Error{}} =
             BLE.connect(
               [client: CoreBluetooth] ++
                 Keyword.put(options, :executable_sha256, String.duplicate("0", 64))
             )

    refute File.exists?(unstarted <> ".trace")
  end

  test "missing markers, fabricated acknowledgements and post-acceptance loss never become command success" do
    for mode <- ~w(command-ack missing-marker wrong-id post-error sleep-write) do
      {session, path} = connect(mode)

      assert {:error, %Error{effect: :unknown}} =
               BLE.write(session, @address, <<1, 2>>, write_mode: :without_response)

      assert Enum.count(records(path), &(&1["operation"] == "write_command")) == 1
      refute Enum.any?(records(path), &(&1["operation"] == "write"))
    end
  end

  test "public streams preserve repeated values, exact native metadata and ordered retirement" do
    {session, path} = connect("normal")
    assert {:ok, subscription} = BLE.subscribe(session, %{address: @address, value_type: :uint16})
    reference = subscription.reference

    for _ <- 1..3 do
      assert_receive {:wotex_ble, ^reference, {:ok, 65_280, metadata}}, 1500
      assert metadata.source == :corebluetooth_value_update
      assert metadata.requested_mode == :auto and metadata.effective_mode == :notify
      assert metadata.characteristic.generation == 7 and metadata.characteristic.route == 3
    end

    eventually(fn ->
      Enum.any?(records(path), &(&1["event"] == "notification_ack" and &1["sequence"] == 3))
    end)

    assert :ok = BLE.unsubscribe(session, subscription)
    assert :ok = BLE.unsubscribe(session, subscription)
    assert {:error, %Error{code: :not_permitted}} = BLE.subscribe(session, %{address: @address})
    assert {:error, %Error{code: :not_supported}} = BLE.read(session, @address)
    assert {:ok, %{connected: true}} = BLE.health_check(session)
  end

  test "codec refusal returns credit only after the native retirement fence" do
    {session, path} = connect("normal")
    assert {:ok, subscription} = BLE.subscribe(session, %{address: @address, value_type: :boolean})
    reference = subscription.reference
    assert_receive {:wotex_ble, ^reference, {:error, %Error{}}}, 1500
    refute_received {:wotex_ble, ^reference, {:ok, _, _}}

    eventually(fn ->
      Enum.any?(records(path), &(&1["event"] == "notification_ack" and &1["sequence"] == 3))
    end)

    trace = records(path)
    unsubscribe = Enum.find_index(trace, &(&1["operation"] == "unsubscribe"))
    credit = Enum.find_index(trace, &(&1["event"] == "notification_ack"))
    assert is_integer(unsubscribe) and is_integer(credit) and credit > unsubscribe
  end

  test "the original queued deadline sends nothing and a submitted timeout joins actual peer retirement" do
    {session, path} = connect("blocked")

    task =
      Task.async(fn ->
        BLE.write(session, @address, <<1>>, write_mode: :without_response, timeout: 400)
      end)

    eventually(fn -> Enum.any?(records(path), &(&1["operation"] in ["write", "write_command"])) end)

    assert {:error, %Error{code: :timeout, effect: :none}} =
             BLE.write(session, @address, <<2>>, write_mode: :without_response, timeout: 20)

    assert {:error, %Error{effect: :unknown}} = Task.await(task, 2500)
    assert Enum.count(records(path), &(&1["operation"] == "write_command")) == 1
    eventually(fn -> gone?(pid(path)) end)
  end

  test "independent owners, receiver loss and incompatible stream fences cannot leak or retarget a session" do
    {first, path} = connect("silent")
    {second, other} = connect("normal")
    receiver = spawn(fn -> receive do: (:finish -> :ok) end)
    assert {:ok, _} = BLE.subscribe(first, %{address: @address, receiver: receiver})
    Process.exit(receiver, :kill)
    eventually(fn -> Enum.any?(records(path), &(&1["operation"] == "unsubscribe")) end)
    assert {:ok, :written} = BLE.write(second, @address, <<1>>)
    assert :ok = BLE.disconnect(first)
    assert pid(path) != pid(other)
    assert {:ok, :written} = BLE.write(second, @address, <<2>>)
    {options, owned} = fixture("silent")
    parent = self()

    {owner, monitor} =
      spawn_monitor(fn ->
        {:ok, session} = BLE.connect([client: CoreBluetooth] ++ options)
        send(parent, {:owned_session, session})
        receive do: (:finish -> :ok)
      end)

    assert_receive {:owned_session, _}, 2000
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}, 1000
    eventually(fn -> gone?(pid(owned)) end)
    {bad, _} = connect("no-retire")
    assert {:ok, subscription} = BLE.subscribe(bad, %{address: @address})
    assert {:error, %Error{}} = BLE.unsubscribe(bad, subscription)
    {options, _} = fixture("bad-ready")
    assert {:error, %Error{}} = BLE.connect([client: CoreBluetooth] ++ options)

    for mode <- ~w(bad-binding bad-value) do
      {session, _} = connect(mode)

      case BLE.subscribe(session, %{address: @address}) do
        {:error, %Error{code: :invalid_response}} ->
          :ok

        {:ok, subscription} ->
          reference = subscription.reference
          assert_receive {:wotex_ble, ^reference, {:error, %Error{code: :invalid_response}}}, 1500
          refute_received {:wotex_ble, ^reference, {:ok, _, _}}
      end
    end
  end
end
