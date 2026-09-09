defmodule Wotex.Modbus.SoftwareLifecycleStressTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Modbus
  alias Wotex.Modbus.{Error, TestPeer}
  @moduletag :software
  @moduletag timeout: 180_000

  test "WMB-C09 WMB-S01 WMB-S02 WMB-V11 WMB-V12 1000 sequential independent-peer operations" do
    {:ok, session} = Modbus.connect(options())
    resources = owned(session)

    samples =
      Enum.reduce(1..500, [], fn value, samples ->
        assert :ok = Modbus.write_holding_register(session, 100, value)
        assert {:ok, [^value]} = Modbus.read_holding_registers(session, 100, 1)
        assert_idle(session)
        if rem(value, 50) == 0, do: [sample(session, value * 2) | samples], else: samples
      end)

    close_and_assert(session, resources)

    record("sequential", %{
      requirements: ["WMB-C09", "WMB-S01", "WMB-S02", "WMB-V11", "WMB-V12"],
      peer: "independent-libmodbus",
      operations: 1000,
      owned_resources_after: 0,
      samples: Enum.reverse(samples),
      allocator_claim: "Heap/RSS observations; allocator caching is not classified as a leak."
    })
  end

  test "WMB-C03 WMB-C09 WMB-S03 WMB-V08 WMB-V12 100 independent-peer open and close cycles" do
    samples =
      for cycle <- 1..100 do
        {:ok, session} = Modbus.connect(options())
        resources = owned(session)
        assert {:ok, [42]} = Modbus.read_holding_registers(session, 0, 1)
        assert_idle(session)
        measurement = sample(session, cycle)
        close_and_assert(session, resources)
        measurement
      end

    record("cycles", %{
      requirements: ["WMB-C03", "WMB-C09", "WMB-S03", "WMB-V08", "WMB-V12"],
      peer: "independent-libmodbus",
      cycles: 100,
      owned_resources_after_each_cycle: 0,
      samples: samples
    })
  end

  test "WMB-C09 WMB-S03 WMB-V07 WMB-V12 32 concurrent callers keep distinct register results correlated" do
    {:ok, session} = Modbus.connect(options())
    resources = owned(session)
    parent = self()

    callers =
      for number <- 1..32 do
        Task.async(fn ->
          send(parent, {:admission_ready, self()})

          receive do
            :go ->
              value = 1000 + number
              assert :ok = Modbus.write_holding_register(session, number, value)
              assert {:ok, [^value]} = Modbus.read_holding_registers(session, number, 1)
              {number, value}
          after
            1000 -> flunk("caller barrier did not release")
          end
        end)
      end

    for _ <- callers, do: assert_receive({:admission_ready, _}, 1000)
    Enum.each(callers, &send(&1.pid, :go))
    expected = for number <- 1..32, do: {number, 1000 + number}
    assert Enum.map(callers, &Task.await(&1, 30_000)) == expected
    assert_idle(session)
    close_and_assert(session, resources)

    record("concurrency", %{
      requirements: ["WMB-C09", "WMB-S03", "WMB-V07", "WMB-V12"],
      peer: "independent-libmodbus",
      simultaneous_callers: 32,
      operations: 64,
      owned_resources_after: 0
    })
  end

  test "WMB-C09 WMB-S02 WMB-S03 WMB-V04 WMB-V08 WMB-V12 repeated failure cleanup uses a separate malformed peer" do
    for failure <- [:deadline, :peer_close, :malformed], _ <- 1..10 do
      {peer, port} =
        TestPeer.start(fn tid, unit, _ ->
          case failure do
            :deadline ->
              receive do
              after
                40 -> :close
              end

            :peer_close ->
              :close

            :malformed ->
              {:raw, <<rem(tid + 1, 65_536)::16, 0::16, 6::16, unit, 6, 0, 0, 0, 42>>}
          end
        end)

      {:ok, session} = Modbus.connect(host: "127.0.0.1", port: port, timeout: 20)
      resources = owned(session)

      assert {:error, %Error{effect: :unknown, class: :permanent, retryable: false}} =
               Modbus.write_holding_register(session, 0, 42)

      assert {:error, %Error{code: :connection_closed, effect: :none}} =
               Modbus.write_holding_register(session, 0, 43)

      close_and_assert(session, resources)
      assert :ok = Task.await(peer)
    end

    record("failures", %{
      requirements: ["WMB-C09", "WMB-S02", "WMB-S03", "WMB-V04", "WMB-V08", "WMB-V12"],
      peer: "separate-malformed-peer",
      failures: %{deadline: 10, peer_close: 10, malformed: 10},
      owned_resources_after_each_cycle: 0
    })
  end

  defp options do
    [
      host: System.fetch_env!("WOTEX_MODBUS_INTEROP_HOST"),
      port: String.to_integer(System.fetch_env!("WOTEX_MODBUS_INTEROP_PORT")),
      timeout: 5000
    ]
  end

  defp owned(session) do
    state = :sys.get_state(session.pid)

    %{
      pid: session.pid,
      socket: state.socket,
      monitor: Process.monitor(session.pid),
      startup_timer: state.connect_timer
    }
  end

  defp assert_idle(session) do
    state = :sys.get_state(session.pid)
    assert state.active == nil
    assert state.calls == %{}
    assert :queue.is_empty(state.queue)
    assert Process.read_timer(state.connect_timer) == false
  end

  defp close_and_assert(session, resources) do
    :ok = Modbus.disconnect(session)
    monitor = resources.monitor
    pid = resources.pid
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 1000
    refute Process.alive?(resources.pid)
    assert :erlang.port_info(resources.socket) == :undefined
    assert Process.read_timer(resources.startup_timer) == false
    :ok = Modbus.disconnect(session)
  end

  defp sample(session, completed) do
    {:memory, memory} = Process.info(session.pid, :memory)

    {rss, 0} =
      System.cmd("ps", ["-o", "rss=", "-p", System.pid()],
        env: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
      )

    %{
      completed: completed,
      owner_heap_bytes: memory,
      beam_rss_kib: String.to_integer(String.trim(rss))
    }
  end

  defp record(name, evidence) do
    root = System.fetch_env!("WOTEX_MODBUS_SOFTWARE_EVIDENCE")
    File.write!(Path.join(root, name <> ".json"), Jason.encode!(evidence, pretty: true))
  end
end
