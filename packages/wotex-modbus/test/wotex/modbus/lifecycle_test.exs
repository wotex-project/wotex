defmodule Wotex.Modbus.LifecycleTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Modbus
  alias Wotex.Modbus.{Command, Connection, Error, SessionTrace, TestPeer}

  test "WMB-S03 WMB-V07 capacity includes the active caller; canceled work consumes no wire IDs" do
    {peer, port} = controlled_peer()
    {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port, transaction_id: 65_535)
    first = Task.async(fn -> Modbus.read_holding_registers(session, 0, 1) end)
    assert_receive {:wire, 65_535, 1, <<3, 0, 0, 0, 1>>}
    queued = for n <- 1..63, do: Task.async(fn -> Modbus.write_holding_register(session, n, n) end)
    await_calls(session.pid, 64)
    assert {:error, %Error{code: :busy, effect: :none}} = Modbus.write_coil(session, 0, true)
    assert :queue.len(:sys.get_state(session.pid).queue) == 63
    assert :sys.get_state(session.pid).transaction == 0
    Enum.each(queued, &Task.shutdown(&1, :brutal_kill))
    await_calls(session.pid, 1)
    send(peer.pid, {:reply, <<3, 2, 0, 42>>})
    assert {:ok, [42]} = Task.await(first)
    second = Task.async(fn -> Modbus.read_holding_registers(session, 0, 1) end)
    assert_receive {:wire, 0, 1, <<3, 0, 0, 0, 1>>}
    send(peer.pid, {:reply, <<3, 2, 0, 43>>})
    assert {:ok, [43]} = Task.await(second)
    assert :ok = Modbus.disconnect(session)
    assert :ok = Task.await(peer)
    refute_received {:wire, _, _, _}
  end

  test "WMB-S03 WMB-V07 queued deadlines and canceled timers cannot affect the next request" do
    {peer, port} = controlled_peer()
    {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port)
    first = Task.async(fn -> Modbus.read_holding_registers(session, 0, 1) end)
    assert_receive {:wire, 0, 1, _}
    {:ok, command} = Command.new(:write_holding_register, 1, 42)
    queued = Task.async(fn -> Connection.request(session.pid, command, 50) end)
    state = await_calls(session.pid, 2)
    [queued_ref] = :queue.to_list(state.queue)
    assert {:error, %Error{code: :deadline_exceeded, effect: :none}} = Task.await(queued)
    assert :sys.get_state(session.pid).transaction == 1
    send(session.pid, {:deadline, queued_ref})
    send(session.pid, {:sent, queued_ref, {:error, :closed}})
    send(session.pid, {:DOWN, make_ref(), :process, self(), :normal})
    send(peer.pid, {:reply, <<3, 2, 0, 42>>})
    assert {:ok, [42]} = Task.await(first)
    assert :ok = Modbus.disconnect(session)
    assert :ok = Task.await(peer)
    refute_received {:wire, _, _, _}
  end

  test "WMB-C03 WMB-S03 WMB-V08 owner death closes a blocked receive within cleanup bounds" do
    {peer, port} = controlled_peer()

    owner =
      spawn(fn ->
        receive do
          :finish -> :ok
        end
      end)

    {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port, owner: owner, timeout: 60_000)
    call = Task.async(fn -> Modbus.write_holding_register(session, 0, 42) end)
    assert_receive {:wire, _, _, _}
    state = :sys.get_state(session.pid)
    monitor = Process.monitor(session.pid)
    started = System.monotonic_time(:millisecond)
    send(owner, :finish)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 100
    assert System.monotonic_time(:millisecond) - started < 1000
    assert {:error, %Error{code: :connection_closed, effect: :unknown}} = Task.await(call)
    assert :erlang.port_info(state.socket) == :undefined
    assert Enum.all?(state.calls, fn {_ref, entry} -> Process.read_timer(entry.timer) == false end)
    send(peer.pid, :close)
    assert :ok = Task.await(peer)
    assert :ok = Modbus.disconnect(session)
  end

  test "WMB-S03 WMB-V07 active caller death closes the generation and rejects queued writes" do
    for operation <- [:read_holding_registers, :write_holding_register] do
      {peer, port} = controlled_peer()
      {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port)
      call = Task.async(fn -> apply(Modbus, operation, [session, 0, 1]) end)
      assert_receive {:wire, _, _, _}
      queued = Task.async(fn -> Modbus.write_holding_register(session, 1, 42) end)
      state = await_calls(session.pid, 2)
      monitor = Process.monitor(session.pid)
      Task.shutdown(call, :brutal_kill)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 100
      assert {:error, %Error{code: :connection_closed, effect: :none}} = Task.await(queued)
      assert :erlang.port_info(state.socket) == :undefined

      assert Enum.all?(state.calls, fn {_ref, entry} -> Process.read_timer(entry.timer) == false end)

      send(peer.pid, :close)
      assert :ok = Task.await(peer)
      refute_received {:wire, _, _, _}
    end
  end

  test "WMB-C03 WMB-V08 acquisition failure is caller-safe and child policy remains consumer-owned" do
    {:ok, listener} = :gen_tcp.listen(0, active: false, ip: {127, 0, 0, 1})
    {:ok, {_, port}} = :inet.sockname(listener)
    :gen_tcp.close(listener)
    before_links = Process.info(self(), :links)

    for _ <- 1..20 do
      assert {:error, %Error{code: :connect_failed, details: %{reason: :econnrefused}}} =
               Connection.start_link(host: "127.0.0.1", port: port)
    end

    assert before_links == Process.info(self(), :links)
    spec = Supervisor.child_spec({Connection, [host: "127.0.0.1"]}, restart: :temporary)
    assert spec.restart == :temporary
    assert spec.start == {Connection, :start_link, [[host: "127.0.0.1"]]}
  end

  test "WMB-S02 WMB-S03 unsolicited trailing responses never seed a later wire request" do
    for response <- [
          <<0::16, 0::16, 5::16, 1, 3, 2, 0, 42, 1::16, 0::16, 5::16, 1, 3, 2, 0, 99>>,
          :binary.copy(<<0>>, 261)
        ] do
      {peer, port} = TestPeer.start(fn _, _, _ -> {:raw, response} end)
      {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port)
      monitor = Process.monitor(session.pid)
      assert {:error, %Error{}} = Modbus.read_holding_registers(session, 0, 1)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
      assert :ok = Task.await(peer)
    end
  end

  test "WMB-C03 admission rejects elapsed deadlines before allocating a transaction" do
    {peer, port} = controlled_peer()
    {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port)
    :ok = :sys.suspend(session.pid)
    {:ok, command} = Command.new(:write_holding_register, 0, 1)
    call = Task.async(fn -> Connection.request(session.pid, command, 10) end)

    receive do
    after
      25 -> :ok
    end

    :ok = :sys.resume(session.pid)
    assert {:error, %Error{code: :deadline_exceeded, effect: :none}} = Task.await(call)
    assert :sys.get_state(session.pid).transaction == 0
    :ok = Modbus.disconnect(session)
    assert :ok = Task.await(peer)
    refute_received {:wire, _, _, _}
  end

  test "WMB-C03 WMB-V08 dead owner at startup never leaves a linked socket generation" do
    for _ <- 1..20 do
      {peer, port} = controlled_peer()
      owner = spawn(fn -> :ok end)
      monitor = Process.monitor(owner)
      assert_receive {:DOWN, ^monitor, :process, _, _}

      case Modbus.connect(host: "127.0.0.1", port: port, owner: owner) do
        {:error, %Error{code: :connect_failed}} ->
          :ok

        {:ok, session} ->
          monitor = Process.monitor(session.pid)
          assert_receive {:DOWN, ^monitor, :process, _, _}, 100
          :ok = Modbus.disconnect(session)
      end

      Task.shutdown(peer, :brutal_kill)
    end
  end

  test "WMB-S03 an idle peer close releases the owner without a request" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)

    peer =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)

        receive do
          :close -> :gen_tcp.close(socket)
        end
      end)

    {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port)
    monitor = Process.monitor(session.pid)
    send(peer.pid, :close)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    assert :ok = Task.await(peer)
    assert :ok = :gen_tcp.close(listener)
  end

  test "WMB-C03 graceful cleanup timeout force-closes its owned socket without claiming success" do
    {peer, port} = controlled_peer()
    {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port)
    socket = :sys.get_state(session.pid).socket
    true = :erlang.suspend_process(session.pid)
    assert {:error, %Error{code: :cleanup_timeout}} = Modbus.disconnect(session)
    refute Process.alive?(session.pid)
    assert :erlang.port_info(socket) == :undefined
    assert :ok = Modbus.disconnect(session)
    assert :ok = Task.await(peer)
  end

  test "WMB-C03 WMB-V08 startup completion may precede its readiness caller without losing errors" do
    {peer, port} = controlled_peer()
    {:ok, config} = Connection.config(host: "127.0.0.1", port: port)
    {:ok, pid} = GenServer.start(Connection, Map.put(config, :creator, self()))
    assert await_startup(pid).phase == :ready
    assert :ok = GenServer.call(pid, :ready)
    assert :ok = Connection.close(pid)
    assert :ok = Task.await(peer)

    {:ok, pid} = GenServer.start(Connection, Map.put(config, :creator, self()))
    assert {:failed, %Error{code: :connect_failed}} = await_startup(pid).phase
    monitor = Process.monitor(pid)
    assert {:error, %Error{code: :connect_failed}} = GenServer.call(pid, :ready)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    refute pid in elem(Process.info(self(), :links), 1)
  end

  test "WMB-S03 an ordered admission receipt distinguishes normal-close failure effects" do
    {:ok, write} = Command.new(:write_holding_register, 0, 42)

    for {admitted, effect} <- [{false, :none}, {true, :unknown}] do
      closing =
        spawn(fn ->
          receive do
            {:"$gen_call", {caller, _}, {:request, ^write, _deadline, admission}} ->
              if admitted, do: send(caller, {:wotex_modbus_admitted, admission})
          end
        end)

      assert {:error, %Error{code: :connection_closed, effect: ^effect}} =
               Connection.request(closing, write, 100)

      refute_received {:wotex_modbus_admitted, _}
    end
  end

  test "WMB-S03 a transmitted mutation closed normally stays unknown and is never retried" do
    {peer, port} = controlled_peer()
    {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port)
    call = Task.async(fn -> Modbus.write_holding_register(session, 0, 42) end)
    assert_receive {:wire, 0, 1, <<6, 0, 0, 0, 42>>}
    :ok = GenServer.stop(session.pid, :normal)

    assert {:error, %Error{code: :connection_closed, effect: :unknown, class: :permanent}} =
             Task.await(call)

    assert {:error, %Error{code: :connection_closed, effect: :none}} =
             Modbus.write_holding_register(session, 0, 43)

    send(peer.pid, :close)
    assert :ok = Task.await(peer)
    refute_received {:wire, _, _, _}
    refute_received {:wotex_modbus_admitted, _}
  end

  @tag requirements: ["WMB-S03", "WMB-D03", "WMB-D04"], scenarios: ["WMB-V08"]
  test "WMB-F-WRITE-UNCERTAINTY uses the virtual event clock and actual TCP observations" do
    path = Path.expand("../../../docs/specs/fixtures/contract-v1.json", __DIR__)

    fixture =
      Jason.decode!(File.read!(path))["cases"]
      |> Enum.find(&(&1["id"] == "WMB-F-WRITE-UNCERTAINTY"))

    assert fixture["tier"] == "lifecycle_contract"
    clock = :atomics.new(1, signed: false)

    advance = fn at_ms ->
      assert at_ms >= :atomics.get(clock, 1)
      :atomics.put(clock, 1, at_ms)
    end

    actual = SessionTrace.run(fixture["input"], advance)
    assert actual == fixture["expectation"]["value"]
    assert :atomics.get(clock, 1) == 3
  end

  defp controlled_peer do
    test = self()

    TestPeer.start(fn tid, unit, pdu ->
      send(test, {:wire, tid, unit, pdu})

      receive do
        {:reply, reply} -> reply
        :close -> :close
      after
        2000 -> raise "test did not release the controlled peer"
      end
    end)
  end

  defp await_startup(pid) do
    await_state(pid, &(&1.phase != :connecting), System.monotonic_time(:millisecond) + 1000)
  end

  defp await_state(pid, predicate, deadline) do
    state = :sys.get_state(pid)

    if predicate.(state) do
      state
    else
      assert System.monotonic_time(:millisecond) < deadline

      receive do
      after
        1 -> await_state(pid, predicate, deadline)
      end
    end
  end

  defp await_calls(pid, count),
    do: await_calls(pid, count, System.monotonic_time(:millisecond) + 1000)

  defp await_calls(pid, count, deadline) do
    state = :sys.get_state(pid)

    if map_size(state.calls) == count do
      state
    else
      assert System.monotonic_time(:millisecond) < deadline

      receive do
      after
        1 -> await_calls(pid, count, deadline)
      end
    end
  end
end
