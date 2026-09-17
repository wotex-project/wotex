defmodule Wotex.Thread.LifecycleStressTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Thread
  alias Wotex.Thread.{Error, OpenThread, State}

  @moduletag :software
  @moduletag requirements: ["WTH-C03", "WTH-C05", "WTH-C09", "WTH-S03", "WTH-S06"],
             vectors: ["WTH-V13"]

  setup do
    assert match?({:unix, :linux}, :os.type())
    host = System.fetch_env!("WOTEX_THREAD_HOST")
    rcp = System.fetch_env!("WOTEX_THREAD_RCP")

    directory =
      Path.join(
        System.tmp_dir!(),
        "wth-stress-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{host: host, rcp: rcp, directory: directory}
  end

  @tag timeout: 600_000
  test "WTH-C09 1000 sequential operations return exact typed results within bounded resources",
       context do
    assert {:ok, session} = Thread.connect(options(context, "ops", 25))
    processes = native_processes(session)
    samples = [sample(session, processes, 0)]

    samples =
      Enum.reduce(1..1000, samples, fn index, samples ->
        case rem(index, 4) do
          0 ->
            assert {:ok, %State{role: :disabled, generation: 1}} = Thread.inspect_state(session, [])

          1 ->
            assert {:ok, "disabled"} = OpenThread.request(session.handle, %{type: :state}, 5000)

          2 ->
            assert {:ok, "OpenThread"} =
                     OpenThread.request(session.handle, %{type: :network_name}, 5000)

          3 ->
            assert {:ok, nil} = OpenThread.request(session.handle, %{type: :rloc16}, 5000)
        end

        if rem(index, 100) == 0, do: [sample(session, processes, index) | samples], else: samples
      end)

    assert_baseline(session.handle.pid)
    # Heap and RSS trends are reported, not asserted: allocator caching alone is not a leak.
    record("operations-trend", Enum.reverse(samples))
    assert :ok = Thread.disconnect(session)
    assert_released(session, processes)
  end

  @tag timeout: 600_000
  test "WTH-C09 WTH-C03 100 BEAM open and close cycles restore owned processes, ports and interfaces",
       context do
    ports = length(Port.list())
    beam_processes = length(Process.list())

    for cycle <- 1..100 do
      options = options(context, "cycle-#{cycle}", 26)
      assert {:ok, session} = Thread.connect(options)
      [guardian | _] = processes = native_processes(session)
      # The startup-deadline scan below compares these same executable links.
      assert File.read_link("/proc/#{guardian}/exe") == {:ok, context.host}
      assert Enum.any?(processes, &(File.read_link("/proc/#{&1}/exe") == {:ok, context.rcp}))
      assert File.exists?("/sys/class/net/wthstress26")
      assert {:ok, %State{}} = Thread.inspect_state(session, [])
      assert :ok = Thread.disconnect(session), "cycle #{cycle}"
      assert_released(session, processes)
      assert_eventually(fn -> length(Port.list()) == ports end)
      refute File.exists?("/sys/class/net/wthstress26")
    end

    assert_eventually(fn -> length(Process.list()) <= beam_processes end)
  end

  @tag timeout: 600_000
  test "WTH-C09 WTH-C05 100 receiver-death cycles release every native stream and owner", context do
    assert {:ok, session} = Thread.connect(options(context, "receivers", 27))
    connection = session.handle.pid
    processes = native_processes(session)

    # The native host admits at most 64 live streams, so every cycle past the 64th also
    # proves that each earlier native stream was retired rather than only forgotten here.
    for cycle <- 1..100 do
      parent = self()

      receiver =
        spawn(fn ->
          receive do
            {:wotex_thread, _, {:ok, %State{}, %{changed_flags: 0}}} = message ->
              send(parent, {:initial, message})
          end

          Process.sleep(:infinity)
        end)

      assert {:ok, subscription} = Thread.subscribe(session, %{type: :state, receiver: receiver})
      assert subscription.generation == cycle
      assert_receive {:initial, {:wotex_thread, _, _}}, 5000
      [record] = Map.values(:sys.get_state(connection).subscriptions)
      owner = Process.monitor(record.owner)
      Process.exit(receiver, :kill)
      assert_receive {:DOWN, ^owner, :process, _, _}, 2000
      assert_eventually(fn -> :sys.get_state(connection).subscriptions == %{} end)
      assert :ok = Thread.unsubscribe(session, subscription)
      # The retirement barrier precedes each cancellation reply, so wait for that reply too.
      assert_baseline(connection)
    end

    assert :ok = Thread.disconnect(session)
    assert_released(session, processes)
  end

  @tag timeout: 600_000
  test "WTH-C09 WTH-C03 32 concurrent callers correlate replies and return admission to zero",
       context do
    assert {:ok, session} = Thread.connect(options(context, "concurrent", 28))
    processes = native_processes(session)
    parent = self()

    callers =
      for caller <- 1..32 do
        spawn_link(fn ->
          results =
            for request <- 1..25 do
              type = if rem(caller + request, 2) == 0, do: :state, else: :version
              {type, OpenThread.request(session.handle, %{type: type}, 10_000)}
            end

          send(parent, {:caller, caller, results})
        end)
      end

    results =
      for caller <- 1..32 do
        assert_receive {:caller, ^caller, results}, 60_000
        results
      end

    assert length(callers) == 32

    for {type, result} <- List.flatten(results) do
      case type do
        :state ->
          assert {:ok, "disabled"} = result

        :version ->
          assert {:ok, version} = result
          assert version =~ "5c8c318627954c99cd1a957a290bbd4b1027d04b"
      end
    end

    assert_baseline(session.handle.pid)
    assert :ok = Thread.disconnect(session)
    assert_released(session, processes)
  end

  @tag timeout: 600_000
  test "WTH-C09 forced startup deadlines reap the native host that was starting", context do
    # The injected radio never completes Spinel startup, so each deadline expires
    # while the real host is blocked in SDK initialization.
    radio = Path.join(context.directory, "stubborn-radio")
    source = Path.expand("../fixtures/stubborn_radio.c", __DIR__)
    arguments = ["-std=c11", "-Wall", "-Wextra", "-Werror", source, "-o", radio]
    assert {_, 0} = System.cmd("/usr/bin/cc", arguments, env: command_env())

    for cycle <- 1..10 do
      options =
        context
        |> options("deadline-#{cycle}", 30)
        |> Keyword.merge(radio_url: "spinel+hdlc+forkpty://#{radio}?forkpty-arg=30", timeout: 200)

      started = System.monotonic_time(:millisecond)
      assert {:error, %Error{code: :timeout}} = Thread.connect(options)
      assert System.monotonic_time(:millisecond) - started < 1300

      assert_eventually(
        fn -> host_processes(context.host) == [] and host_processes(radio) == [] end,
        150
      )

      refute File.exists?("/sys/class/net/wthstress30")
    end
  end

  @tag timeout: 600_000
  test "WTH-C09 native peer loss fails pending use explicitly and releases resources", context do
    for cycle <- 1..10 do
      assert {:ok, session} = Thread.connect(options(context, "faults-#{cycle}", 29))
      handle = session.handle
      assert {:ok, "disabled"} = OpenThread.request(handle, %{type: :state}, 5000)
      [guardian, worker | _] = processes = native_processes(session)
      assert worker in children(guardian)
      monitor = Process.monitor(handle.pid)
      System.cmd("/bin/kill", ["-KILL", Integer.to_string(worker)], env: command_env())
      assert_receive {:DOWN, ^monitor, :process, _, _}, 2000

      assert {:error, %Error{code: code}} = OpenThread.request(handle, %{type: :state}, 1000)
      assert code in [:connection_closed, :invalid_handle]
      assert_released(session, processes)
      refute File.exists?("/sys/class/net/wthstress29")
    end
  end

  @tag timeout: 600_000
  test "WTH-C09 injected malformed replies close each generation without leaked owners", context do
    # The production host cannot be made to emit malformed frames; this cycle uses the
    # injected escript peer and is injected-contract evidence, not SDK interoperability.
    escript = System.find_executable("escript") || flunk("escript is required")
    source = File.read!(Path.expand("../fixtures/sdk_bridge.escript", __DIR__))

    header =
      case System.get_env("ERL_FLAGS") do
        flags when is_binary(flags) and flags != "" -> "#!" <> escript <> "\n%%! " <> flags
        _ -> "#!" <> escript
      end

    for cycle <- 1..30, mode = Enum.at(~w(bad_json truncated large), rem(cycle, 3)) do
      directory = Path.join(context.directory, "malformed-#{cycle}")
      File.mkdir_p!(directory)
      executable = Path.join(directory, "bridge")
      File.write!(executable, String.replace(source, "#!/usr/bin/env escript", header))
      File.chmod!(executable, 0o700)
      File.write!(Path.join(directory, "mode"), mode)

      options = [
        client: OpenThread,
        executable: executable,
        radio_url: "spinel+hdlc+uart:///fixture/radio",
        interface: "wthinjected",
        storage_path: Path.join(directory, "store"),
        storage_mode: :create_new,
        owner: self(),
        timeout: 10_000
      ]

      assert {:ok, session} = Thread.connect(options)

      assert {:error, %Error{code: code}} =
               OpenThread.request(session.handle, %{type: :state}, 5000)

      assert code in [:invalid_response, :response_limit, :connection_closed], mode
      pid = session.handle.pid
      assert_eventually(fn -> not Process.alive?(pid) end)
      peer = String.trim(File.read!(Path.join(directory, "pid")))
      assert_eventually(fn -> not File.exists?("/proc/#{peer}") end)
    end
  end

  defp command_env,
    do: Enum.map(System.get_env(), fn {key, value} -> {key, if(key == "PATH", do: value)} end)

  defp options(context, name, node) do
    [
      client: OpenThread,
      executable: context.host,
      radio_url: "spinel+hdlc+forkpty://#{context.rcp}?forkpty-arg=#{node}",
      interface: "wthstress#{node}",
      storage_path: Path.join(context.directory, name),
      storage_mode: :create_new,
      owner: self(),
      timeout: 10_000
    ]
  end

  # The Port's guardian, its SDK worker and the simulated radio the worker started.
  defp native_processes(session) do
    %{port: port} = :sys.get_state(session.handle.pid)
    {:os_pid, guardian} = Port.info(port, :os_pid)
    processes = [guardian | descendants(guardian)]
    assert length(processes) >= 3
    processes
  end

  defp assert_baseline(connection) do
    assert_eventually(fn ->
      state = :sys.get_state(connection)

      state.pending == %{} and state.waiters == %{} and state.subscriptions == %{} and
        state.streams == %{} and state.reports == %{} and state.monitors == %{} and
        ledger_released?(state.ledger) and :queue.is_empty(state.queue) and
        :queue.is_empty(state.controls) and state.active == nil and state.control == nil
    end)

    assert {:message_queue_len, 0} = Process.info(connection, :message_queue_len)
  end

  # Every assigned report was acknowledged and no stream or retained byte remains.
  defp ledger_released?(ledger) do
    ledger.pending == %{} and ledger.streams == %{} and ledger.retained_bytes == 0 and
      ledger.acknowledged_sequence == ledger.next_sequence - 1
  end

  defp assert_released(session, processes) do
    pid = session.handle.pid
    assert_eventually(fn -> not Process.alive?(pid) end)
    assert_eventually(fn -> Enum.all?(processes, &(not File.exists?("/proc/#{&1}"))) end)
  end

  defp sample(session, processes, operations) do
    {:memory, connection} = Process.info(session.handle.pid, :memory)

    %{
      "operations" => operations,
      "native_rss_kib" => Enum.sum(Enum.map(processes, &rss/1)),
      "connection_memory_bytes" => connection,
      "beam_total_bytes" => :erlang.memory(:total)
    }
  end

  defp host_processes(executable) do
    for entry <- File.ls!("/proc"),
        entry =~ ~r/\A\d+\z/,
        {:ok, target} <- [File.read_link("/proc/#{entry}/exe")],
        target == executable,
        do: String.to_integer(entry)
  end

  defp descendants(pid) do
    direct = children(pid)
    direct ++ Enum.flat_map(direct, &descendants/1)
  end

  defp children(pid) do
    case File.read("/proc/#{pid}/task/#{pid}/children") do
      {:ok, text} -> Enum.map(String.split(text), &String.to_integer/1)
      {:error, _} -> []
    end
  end

  defp rss(process) do
    with {:ok, status} <- File.read("/proc/#{process}/status"),
         [_, kib] <- Regex.run(~r/VmRSS:\s+(\d+) kB/, status) do
      String.to_integer(kib)
    else
      _ -> flunk("native process #{process} exited during sampling")
    end
  end

  # Each lane writes its own trend beside its case results.
  defp record(name, value) do
    case System.get_env("WOTEX_THREAD_CASE_RESULTS") do
      nil ->
        :ok

      path ->
        lane = Path.basename(path, "-cases.jsonl")
        output = Path.join(Path.dirname(path), "stress-#{lane}-#{name}.json")
        File.write!(output, Jason.encode!(value))
    end
  end

  defp assert_eventually(condition, remaining \\ 300)
  defp assert_eventually(condition, 0), do: assert(condition.())

  defp assert_eventually(condition, remaining) do
    unless condition.() do
      Process.sleep(10)
      assert_eventually(condition, remaining - 1)
    end
  end
end
