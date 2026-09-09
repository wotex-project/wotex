defmodule Wotex.BLE.DBusBridgeTest do
  @moduledoc false

  @behaviour Wotex.BLE.Agent

  use ExUnit.Case, async: true

  alias Wotex.BLE
  alias Wotex.BLE.{BlueZ, Characteristic, Error, Peer, Session}
  alias Wotex.BLE.BlueZ.Connection

  @impl Wotex.BLE.Agent
  def decide(challenge, {receiver, action, _secret}) do
    send(receiver, {:challenge, challenge, self()})

    case action do
      :accept -> :accept
      :reject -> :reject
      :sleep -> Process.sleep(60_000)
      :raise -> raise "POLICY_SECRET_CANARY"
      :throw -> throw(:policy_failed)
      :exit -> exit(:policy_failed)
      :passkey -> {:passkey, 42}
      :pin -> {:pin, "000042"}
      :invalid -> :not_a_decision
    end
  end

  defp options(mode \\ "normal") do
    directory = Path.join(System.tmp_dir!(), "wbl-dbus-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    executable = Path.join(directory, "python-fixture")
    record = Path.join(directory, "calls.jsonl")
    script = Path.expand("../../support/bluez_process.py", __DIR__)

    python =
      System.find_executable("python3") || flunk("python3 is required for the native owner lane")

    File.write!(
      executable,
      "#!#{python}\nimport runpy,sys\nsys.dont_write_bytecode=True\nsys.argv=[#{Jason.encode!(script)},#{Jason.encode!(mode)},#{Jason.encode!(record)}]\nrunpy.run_path(#{Jason.encode!(script)},run_name='__main__')\n"
    )

    File.chmod!(executable, 0o700)

    on_exit(fn -> cleanup(directory, record) end)

    {:ok, peer} =
      Peer.new(%{adapter: "/org/bluez/hci0", address: "AA:BB:CC:DD:EE:FF", address_type: :random})

    {[peer: peer, executable: executable, bus_address: "unix:path=/tmp/test-bus", timeout: 2000],
     record}
  end

  defp cleanup(directory, record) do
    if File.exists?(record) do
      case Enum.find(calls(record), &Map.has_key?(&1, "pid")) do
        %{"pid" => pid} -> eventually(fn -> process_gone?(pid) end, 150)
        _ -> :ok
      end
    end

    File.rm_rf!(directory)
  end

  defp process_gone?(pid) do
    {_, status} =
      System.cmd("/bin/kill", ["-0", Integer.to_string(pid)],
        stderr_to_stdout: true,
        env: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
      )

    status != 0
  end

  defp connect(mode \\ "normal") do
    {options, record} = options(mode)
    assert {:ok, session} = BLE.connect([client: BlueZ, lifecycle: :persistent] ++ options)
    on_exit(fn -> BLE.disconnect(session) end)
    {session, record}
  end

  defp calls(path),
    do:
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

  defp eventually(function, remaining \\ 100) do
    if function.() do
      :ok
    else
      assert remaining > 0
      Process.sleep(10)
      eventually(function, remaining - 1)
    end
  end

  test "WBL-P02 WBL-V03 WBL-N01 real process returns typed duplicate UUID pages" do
    {session, record} = connect()

    assert {:ok, %{generation: 1, characteristics: [%Characteristic{} = first], cursor: cursor}} =
             BLE.discover(session, limit: 1)

    assert first.object_path == "/another/characteristic0"
    assert first.flags == ["read", "future-flag"]

    assert {:ok, %{generation: 1, characteristics: [second], cursor: nil}} =
             BLE.discover(session, cursor: cursor)

    assert second.characteristic_uuid == first.characteristic_uuid
    assert second.object_path == "/another/characteristic1"

    assert {:error, %Error{code: :invalid_cursor}} =
             BLE.discover(session, cursor: String.duplicate("0", 32))

    assert {:error, %Error{code: :invalid_options}} = BLE.discover(session, limit: 65)
    assert {:ok, ^session} = Connection.session(session.handle.pid)
    assert :ok = BLE.disconnect(session)
    assert :ok = BLE.disconnect(session)

    eventually(fn ->
      Enum.any?(calls(record), &(&1 == %{"bus_closed" => true, "listeners" => 0}))
    end)

    assert Enum.count(calls(record), &(&1["method"] == "Disconnect")) == 0
  end

  test "WBL-C03 start_link is explicit and fallible startup never kills caller" do
    {options, _} = options()
    assert {:ok, pid} = Connection.start_link(options)
    assert {:ok, session} = Connection.session(pid)
    assert :ok = BLE.disconnect(session)
    assert Connection.child_spec(options).start == {Connection, :start_link, [options]}
    assert {:error, %Error{code: :invalid_options}} = Connection.start_link([])

    assert {:error, %Error{code: :transport_unavailable}} =
             Connection.connect(Keyword.put(options, :executable, "/nonexistent/python"))

    assert {:error, %Error{code: :invalid_handle}} = Connection.session(nil)
    assert {:error, %Error{code: :invalid_handle}} = Connection.disconnect(%{})
    assert {:error, %Error{code: :invalid_handle}} = Connection.discover(%{}, [], 1)
    assert {:error, %Error{code: :invalid_session}} = BLE.discover(nil)

    assert {:error, %Error{code: :not_supported}} =
             BLE.discover(%Session{client: __MODULE__, handle: nil, timeout: 1})

    assert {:error, %Error{code: :not_supported}} = BlueZ.discover(%{}, [], 1)
  end

  test "WBL-C02 forged handles and ungraduated procedures acquire nothing" do
    {session, record} = connect()
    handle = %{session.handle | reference: make_ref()}
    assert {:error, %Error{code: :invalid_handle}} = Connection.discover(handle, [], 500)
    assert {:error, %Error{code: :invalid_handle}} = Connection.disconnect(handle)

    assert {:error, %Error{code: :not_supported}} =
             BlueZ.request(
               session.handle,
               %{type: :read, service: "180f", characteristic: "2a19"},
               500
             )

    assert {:error, %Error{code: :invalid_address}} =
             BlueZ.request(session.handle, %{type: :read}, 500)

    assert Enum.count(calls(record), &(&1["method"] == "GetManagedObjects")) == 1
  end

  test "WBL-C07 startup envelopes and process output fail closed" do
    for {mode, code} <- [
          {"wrong_ready", :invalid_response},
          {"startup_error", :disconnected},
          {"truncated", :disconnected},
          {"oversize", :response_limit},
          {"silent", :timeout}
        ] do
      {options, _} = options(mode)

      assert {:error, %Error{code: ^code}} =
               Connection.connect(
                 Keyword.put(options, :timeout, if(mode == "silent", do: 50, else: 2000))
               )
    end
  end

  test "WBL-C07 corrupt and wrong-ID responses close an established generation" do
    for mode <- ["invalid_frame", "wrong_id"] do
      {session, _} = connect(mode)
      monitor = Process.monitor(session.handle.pid)
      assert {:error, %Error{code: :invalid_response}} = BLE.discover(session)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1100
    end
  end

  test "WBL-V04 native failures preserve stable error codes" do
    {session, _} = connect("remote_error")
    assert {:error, %Error{code: :not_permitted}} = BLE.discover(session)
    assert Process.alive?(session.handle.pid)
    {session, _} = connect("timeout_error")
    assert {:error, %Error{code: :timeout}} = BLE.discover(session)
  end

  test "WBL-C03 absolute queue deadlines, admission bound and dead caller removal" do
    {session, record} = connect("blocked")
    parent = self()
    first = spawn(fn -> send(parent, {:first, Connection.discover(session.handle, [], 3000)}) end)
    eventually(fn -> map_size(:sys.get_state(session.handle.pid).pending) == 1 end)
    queued = for _ <- 1..63, do: spawn(fn -> Connection.discover(session.handle, [], 2000) end)
    eventually(fn -> map_size(:sys.get_state(session.handle.pid).pending) == 64 end)
    assert {:error, %Error{code: :busy}} = Connection.discover(session.handle, [], 100)
    Enum.each(queued, &Process.exit(&1, :kill))
    eventually(fn -> map_size(:sys.get_state(session.handle.pid).pending) == 1 end)
    assert {:error, %Error{code: :timeout}} = Connection.discover(session.handle, [], 20)
    assert :queue.len(:sys.get_state(session.handle.pid).queue) == 0
    assert Enum.count(calls(record), &(&1["method"] == "GetManagedObjects")) == 2
    Process.exit(first, :kill)
    eventually(fn -> not Process.alive?(session.handle.pid) end)
  end

  test "WBL-V04 owner death preempts blocked native discovery" do
    {options, record} = options("blocked")
    parent = self()

    owner =
      spawn(fn ->
        {:ok, handle} = Connection.connect(options)
        send(parent, {:handle, handle})
        Connection.discover(handle, [], 60_000)
      end)

    assert_receive {:handle, handle}, 2000
    eventually(fn -> Enum.count(calls(record), &(&1["method"] == "GetManagedObjects")) == 2 end)
    monitor = Process.monitor(handle.pid)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1000
    eventually(fn -> Enum.any?(calls(record), &(&1["bus_closed"] == true)) end)
  end

  test "WBL-C03 deadlines close active generation; queued success is serialized" do
    {session, _} = connect("blocked")
    monitor = Process.monitor(session.handle.pid)
    assert {:error, %Error{code: :timeout}} = Connection.discover(session.handle, [], 10)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1100
    {session, record} = connect("slow")
    tasks = for _ <- 1..3, do: Task.async(fn -> BLE.discover(session) end)
    assert Enum.all?(Task.await_many(tasks), &match?({:ok, _}, &1))
    assert Enum.count(calls(record), &(&1["method"] == "GetManagedObjects")) == 4
  end

  test "WBL-C03 an already queued native reply cannot cross the absolute deadline" do
    {session, record} = connect("slow")
    task = Task.async(fn -> Connection.discover(session.handle, [], 100) end)
    eventually(fn -> Enum.count(calls(record), &(&1["method"] == "GetManagedObjects")) == 2 end)
    :sys.suspend(session.handle.pid)
    Process.sleep(150)
    :sys.resume(session.handle.pid)
    assert {:error, %Error{code: :timeout}} = Task.await(task)
    eventually(fn -> not Process.alive?(session.handle.pid) end)
  end

  test "WBL-C07 uncooperative bridge is killed within cleanup grace" do
    {session, _} = connect("uncooperative")
    monitor = Process.monitor(session.handle.pid)
    assert {:error, %Error{code: :cleanup_timeout}} = BLE.disconnect(session)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 50
  end

  test "WBL-P03 WBL-V06 explicit policy completes first-party Agent exchange" do
    for {mode, action} <- [{"pair", :accept}, {"pair_pin", :pin}, {"pair_passkey", :passkey}] do
      {session, record} = connect(mode)

      assert {:ok, %{paired: true}} =
               BLE.pair(session, %{
                 capability: :display_yes_no,
                 agent: {__MODULE__, {self(), action, "POLICY_SECRET_CANARY"}}
               })

      assert_receive {:challenge, %Wotex.BLE.Challenge{} = challenge, worker}
      refute Process.alive?(worker)
      assert challenge.peer.address == "AA:BB:CC:DD:EE:FF"
      refute inspect(challenge) =~ "123456"
      refute File.read!(record) =~ "POLICY_SECRET_CANARY"
      assert Enum.count(calls(record), &(&1["method"] == "RegisterAgent")) == 1
      assert Enum.count(calls(record), &(&1["method"] == "UnregisterAgent")) == 1
      assert :ok = BLE.disconnect(session)
      assert %{"agents" => 0, "listeners" => 0, "bonds" => 1, "bus_closed" => true} in calls(record)
    end
  end

  test "WBL-V06 rejection, callback exceptions and invalid decisions fail without default acceptance" do
    for action <- [:reject, :raise, :throw, :exit, :invalid] do
      {session, record} = connect("pair")

      assert {:error, %Error{code: :pairing_rejected}} =
               BLE.pair(session, %{
                 capability: :no_input_no_output,
                 agent: {__MODULE__, {self(), action, "POLICY_SECRET_CANARY"}}
               })

      assert_receive {:challenge, _, worker}
      refute Process.alive?(worker)

      refute Enum.any?(
               calls(record),
               &(&1["method"] in ["CancelPairing", "RemoveDevice", "RequestDefaultAgent"])
             )

      BLE.disconnect(session)
    end
  end

  test "WBL-C03 policy timeout and owner loss release worker and Agent" do
    {session, record} = connect("pair")

    receiver = self()

    task =
      Task.async(fn ->
        BLE.pair(session, %{
          capability: :display_yes_no,
          timeout: 100,
          agent: {__MODULE__, {receiver, :sleep, "POLICY_SECRET_CANARY"}}
        })
      end)

    assert_receive {:challenge, _, worker}, 1000
    assert {:error, %Error{code: :pairing_rejected}} = Task.await(task)
    eventually(fn -> not Process.alive?(worker) end)
    BLE.disconnect(session)
    assert %{"agents" => 0, "listeners" => 0, "bonds" => 1, "bus_closed" => true} in calls(record)

    {options, record} = options("pair")
    receiver = self()

    owner =
      spawn(fn ->
        {:ok, handle} = Connection.connect(options)
        send(receiver, {:handle, handle})

        Connection.pair(
          handle,
          %{
            capability: :display_yes_no,
            agent: {__MODULE__, {receiver, :sleep, "POLICY_SECRET_CANARY"}}
          },
          60_000
        )
      end)

    assert_receive {:handle, handle}, 2000
    assert_receive {:challenge, _, worker}, 2000
    status = inspect(:sys.get_status(handle.pid))
    refute status =~ "POLICY_SECRET_CANARY"
    monitor = Process.monitor(handle.pid)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1100
    refute Process.alive?(worker)
    assert %{"agents" => 0, "listeners" => 0, "bonds" => 1, "bus_closed" => true} in calls(record)
  end

  test "WBL-C02 pairing unsupported and invalid policies acquire nothing" do
    assert {:error, %Error{code: :invalid_session}} = BLE.pair(nil, %{})

    assert {:error, %Error{code: :not_supported}} =
             BLE.pair(%Session{client: __MODULE__, handle: nil, timeout: 1}, %{})

    assert {:error, %Error{code: :invalid_handle}} = Connection.pair(nil, %{}, 1)
    assert {:error, %Error{code: :not_supported}} = BlueZ.pair(%{}, %{}, 1)
    {session, record} = connect("pair")

    assert {:error, %Error{code: :invalid_options}} =
             BLE.pair(session, %{capability: :display_yes_no, agent: {__MODULE__, nil}, timeout: 0})

    assert {:error, %Error{code: :invalid_options}} =
             BLE.pair(session, %{capability: :display_yes_no, agent: {:erlang, nil}})

    refute Enum.any?(calls(record), &(&1["method"] == "RegisterAgent"))
  end
end
