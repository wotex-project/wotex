defmodule Wotex.Thread.SdkBridgeTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.Thread.{Error, OpenThread, Session, State}
  alias Wotex.Thread.OpenThread.Connection

  @moduletag requirements: ["WTH-S03", "WTH-C03", "WTH-C07"], vectors: ["WTH-V04"]

  setup do
    directory =
      Path.join(System.tmp_dir!(), "wotex-thread-beam-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    executable = Path.join(directory, "bridge")
    source = File.read!(Path.expand("../../fixtures/sdk_bridge.py", __DIR__))

    python =
      System.find_executable("python3") || raise "Python3 is required for the injected native peer"

    File.write!(executable, String.replace(source, "#!/usr/bin/env python3", "#!" <> python))
    File.chmod!(executable, 0o700)
    File.write!(Path.join(directory, "mode"), "normal")
    on_exit(fn -> File.rm_rf!(directory) end)

    options = [
      executable: executable,
      radio_url: "spinel+hdlc+uart:///fixture/radio",
      interface: "wthfixture",
      storage_path: Path.join(directory, "private-canary-store"),
      storage_mode: :create_new,
      owner: self(),
      timeout: 5000
    ]

    %{directory: directory, options: options}
  end

  test "WTH-S03 native Client opens, inspects and closes a persistent generation", context do
    assert {:ok, session} = Wotex.Thread.connect([{:client, OpenThread} | context.options])
    handle = session.handle
    assert {:ok, %State{role: :disabled}} = Wotex.Thread.inspect_state(session, [])
    assert {:ok, %State{role: :disabled}} = Wotex.Thread.inspect_state(session, timeout: 1000)

    assert {:ok, %State{role: :disabled, generation: 1}} =
             OpenThread.request(handle, %{type: :inspect}, 1000)

    assert {:ok, "disabled"} = OpenThread.request(handle, %{type: :state}, 1000)
    assert {:ok, "fixture"} = OpenThread.request(handle, %{type: :version}, 1000)
    assert {:ok, nil} = OpenThread.request(handle, %{type: :network_name}, 1000)
    assert {:ok, nil} = OpenThread.request(handle, %{type: :rloc16}, 1000)
    assert :ok = OpenThread.disconnect(handle)
    assert :ok = OpenThread.disconnect(handle)
    refute Process.alive?(handle.pid)
    assert File.read!(Path.join(context.directory, "exited")) == "done"

    assert Enum.map(requests(context), & &1["operation"]) == [
             "open",
             "inspect",
             "inspect",
             "inspect",
             "state",
             "version",
             "network_name",
             "rloc16",
             "close"
           ]

    assert Enum.uniq(Enum.map(requests(context), & &1["id"])) ==
             Enum.map(requests(context), & &1["id"])
  end

  test "WTH-C03 supervision is explicit, temporary and returns an acquired Session", context do
    spec = OpenThread.child_spec(context.options)
    assert spec.restart == :temporary and spec.shutdown == 1000
    assert {:ok, supervisor} = Supervisor.start_link([spec], strategy: :one_for_one)
    [{OpenThread, pid, :worker, _}] = Supervisor.which_children(supervisor)
    assert {:ok, %Session{client: OpenThread, handle: handle}} = OpenThread.session(pid)
    assert :ok = OpenThread.disconnect(handle)
    assert Supervisor.which_children(supervisor) == []
    Supervisor.stop(supervisor)
  end

  test "WTH-C02 forged handles, invalid messages and options acquire no native request", context do
    assert {:error, %Error{code: :invalid_options}} =
             OpenThread.connect([{:unknown, true} | context.options])

    assert {:error, %Error{code: :transport_unavailable}} =
             OpenThread.connect(
               Keyword.put(context.options, :executable, "/missing/thread-executable")
             )

    assert {:ok, handle} = OpenThread.connect(context.options)

    for invalid <- [
          nil,
          Map.put(handle, :generation, 2),
          Map.put(handle, :extra, true),
          Map.put(handle, :pid, :bad),
          Map.put(handle, :reference, :bad),
          Map.put(handle, :reference, make_ref())
        ] do
      assert {:error, %Error{code: :invalid_handle}} =
               OpenThread.request(invalid, %{type: :state}, 1000)
    end

    assert {:error, %Error{code: :invalid_options}} = OpenThread.request(handle, %{type: :state}, 0)

    for request <- [
          nil,
          %{type: :inspect, extra: true},
          %{type: :state, extra: true},
          %{type: :set_enabled}
        ] do
      assert {:error, _} = OpenThread.request(handle, request, 1000)
    end

    assert {:error, _} = OpenThread.session(nil)
    assert {:error, _} = OpenThread.disconnect(nil)
    assert length(requests(context)) == 1
    refute inspect(handle) =~ "private-canary"
    refute inspect(:sys.get_status(handle.pid)) =~ "private-canary"
    assert :ok = OpenThread.disconnect(handle)
  end

  test "WTH-C03 unrelated processes never receive owner calls or cleanup", context do
    assert {:ok, handle} = OpenThread.connect(context.options)
    {:ok, unrelated} = Agent.start(fn -> :unrelated end)

    for pid <- [self(), unrelated] do
      forged = %{handle | pid: pid}
      assert {:error, %Error{code: :invalid_handle}} = OpenThread.session(pid)
      assert {:error, %Error{code: :invalid_handle}} = OpenThread.disconnect(forged)

      assert {:error, %Error{code: :invalid_handle}} =
               OpenThread.request(forged, %{type: :state}, 100)

      assert Process.alive?(pid)
    end

    assert Agent.get(unrelated, & &1) == :unrelated
    refute_received {:"$gen_call", _, _}
    Agent.stop(unrelated)
    assert :ok = OpenThread.disconnect(handle)
  end

  test "WTH-C03 expired startup and dead owners acquire no executable", context do
    {:ok, config} = Wotex.Thread.OpenThread.Config.new(context.options)

    assert {:error, %Error{code: :timeout}} =
             GenServer.start(Connection, {config, System.monotonic_time(:millisecond), self()})

    dead = spawn(fn -> :ok end)
    monitor = Process.monitor(dead)
    assert_receive {:DOWN, ^monitor, :process, ^dead, _}

    assert {:error, %Error{code: :owner_down}} =
             GenServer.start(
               Connection,
               {%{config | owner: dead}, System.monotonic_time(:millisecond) + 1000, self()}
             )

    refute File.exists?(Path.join(context.directory, "pid"))
  end

  test "WTH-C07 wrong reply IDs, duplicates, truncated output and line overflow close the generation",
       context do
    for mode <- ["wrong_id", "duplicate", "truncated", "large", "bad_json"] do
      File.write!(Path.join(context.directory, "mode"), mode)
      assert {:ok, handle} = OpenThread.connect(context.options)
      result = OpenThread.request(handle, %{type: :state}, 1000)

      if mode == "duplicate",
        do: assert(result == {:ok, "disabled"}),
        else: assert(match?({:error, %Error{}}, result))

      eventually(fn -> not Process.alive?(handle.pid) end)
    end
  end

  test "WTH-C03 startup deadlines and wrong backend identity fail without returning a Session",
       context do
    for mode <- ["startup_stall", "open_stall", "bad_ready", "open_bad", "open_error"] do
      File.write!(Path.join(context.directory, "mode"), mode)
      started = System.monotonic_time(:millisecond)

      assert {:error, %Error{code: code}} =
               OpenThread.connect(Keyword.put(context.options, :timeout, 100))

      assert code in [:timeout, :invalid_response, :storage_unavailable]
      assert System.monotonic_time(:millisecond) - started < 1100
    end
  end

  test "WTH-C03 queued deadlines and caller death never send cancelled requests", context do
    File.write!(Path.join(context.directory, "mode"), "wait")
    assert {:ok, handle} = OpenThread.connect(context.options)
    first = Task.async(fn -> OpenThread.request(handle, %{type: :state}, 2000) end)
    eventually(fn -> length(requests(context)) == 2 end)
    queued = Task.async(fn -> OpenThread.request(handle, %{type: :version}, 30) end)
    assert {:error, %Error{code: :timeout}} = Task.await(queued)
    dying = spawn(fn -> OpenThread.request(handle, %{type: :rloc16}, 2000) end)
    eventually(fn -> map_size(:sys.get_state(handle.pid).pending) == 2 end)
    Process.exit(dying, :kill)
    eventually(fn -> map_size(:sys.get_state(handle.pid).pending) == 1 end)
    File.write!(Path.join(context.directory, "release"), "yes")
    assert {:ok, "disabled"} = Task.await(first)
    assert :ok = OpenThread.disconnect(handle)
    assert Enum.map(requests(context), & &1["operation"]) == ["open", "state", "close"]
  end

  test "WTH-C03 all 64 admitted callers are bounded and the 65th is busy", context do
    File.write!(Path.join(context.directory, "mode"), "wait")
    assert {:ok, handle} = OpenThread.connect(context.options)

    tasks =
      for _ <- 1..64, do: Task.async(fn -> OpenThread.request(handle, %{type: :state}, 5000) end)

    eventually(fn -> map_size(:sys.get_state(handle.pid).pending) == 64 end)
    assert {:error, %Error{code: :busy}} = OpenThread.request(handle, %{type: :state}, 1000)
    assert length(requests(context)) == 2
    File.write!(Path.join(context.directory, "release"), "yes")
    for task <- tasks, do: assert(Task.await(task) == {:ok, "disabled"})
    assert :ok = OpenThread.disconnect(handle)
    assert length(requests(context)) == 66
  end

  test "WTH-C03 receiver and explicit owner death close their native generation", context do
    caller = self()

    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    assert {:ok, handle} = OpenThread.connect(Keyword.put(context.options, :owner, owner))
    monitor = Process.monitor(handle.pid)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1100
    File.write!(Path.join(context.directory, "mode"), "wait")
    assert {:ok, second} = OpenThread.connect(context.options)

    request =
      spawn(fn ->
        send(caller, :requesting)
        OpenThread.request(second, %{type: :state}, 5000)
      end)

    assert_receive :requesting
    eventually(fn -> length(requests(context)) >= 4 end)
    Process.exit(request, :kill)
    eventually(fn -> not Process.alive?(second.pid) end)
  end

  test "WTH-C03 concurrent close joins cleanup and a stuck bridge is killed before return",
       context do
    File.write!(Path.join(context.directory, "mode"), "close_stall")
    assert {:ok, handle} = OpenThread.connect(context.options)
    native_pid = File.read!(Path.join(context.directory, "pid")) |> String.to_integer()
    tasks = for _ <- 1..64, do: Task.async(fn -> OpenThread.disconnect(handle) end)
    eventually(fn -> length(:sys.get_state(handle.pid).close_waiters) == 64 end)
    assert {:error, %Error{code: :busy}} = OpenThread.disconnect(handle)

    assert {:error, %Error{code: :connection_closed}} =
             OpenThread.request(handle, %{type: :state}, 100)

    for task <- tasks, do: assert({:error, %Error{code: :cleanup_timeout}} = Task.await(task))
    refute Process.alive?(handle.pid)

    assert {_, exit_code} =
             System.cmd("/bin/kill", ["-0", Integer.to_string(native_pid)],
               stderr_to_stdout: true,
               env: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
             )

    assert exit_code != 0
    assert :ok = OpenThread.disconnect(handle)
    assert Enum.count(requests(context), &(&1["operation"] == "close")) == 1
  end

  test "WTH-C03 active deadlines terminate the generation and cancel queued work", context do
    File.write!(Path.join(context.directory, "mode"), "wait")
    assert {:ok, handle} = OpenThread.connect(context.options)
    active = Task.async(fn -> OpenThread.request(handle, %{type: :state}, 100) end)
    eventually(fn -> length(requests(context)) == 2 end)
    queued = Task.async(fn -> OpenThread.request(handle, %{type: :version}, 1000) end)
    assert {:error, %Error{code: :timeout}} = Task.await(active)
    assert {:error, %Error{code: :timeout}} = Task.await(queued)
    refute Process.alive?(handle.pid)
    assert Enum.map(requests(context), & &1["operation"]) == ["open", "state"]

    assert {:error, %Error{code: :connection_closed}} =
             OpenThread.request(handle, %{type: :state}, 100)
  end

  test "WTH-C07 unknown numeric SDK errors remain typed without closing a healthy generation",
       context do
    File.write!(Path.join(context.directory, "mode"), "error")
    assert {:ok, handle} = OpenThread.connect(context.options)

    assert {:error, %Error{code: :remote_error, details: %{status: 253}}} =
             OpenThread.request(handle, %{type: :inspect}, 1000)

    assert Process.alive?(handle.pid)
    assert :ok = OpenThread.disconnect(handle)
  end

  test "WTH-C03 startup waiter capacity and cancellation remain responsive", context do
    File.write!(Path.join(context.directory, "mode"), "startup_wait")
    assert {:ok, pid} = OpenThread.start_link(context.options)
    dying = spawn(fn -> OpenThread.session(pid) end)
    eventually(fn -> map_size(:sys.get_state(pid).waiters) == 1 end)
    Process.exit(dying, :kill)
    eventually(fn -> map_size(:sys.get_state(pid).waiters) == 0 end)
    tasks = for _ <- 1..64, do: Task.async(fn -> OpenThread.session(pid) end)
    eventually(fn -> map_size(:sys.get_state(pid).waiters) == 64 end)
    assert {:error, %Error{code: :busy}} = OpenThread.session(pid)
    File.write!(Path.join(context.directory, "release"), "yes")

    sessions =
      Enum.map(tasks, fn task ->
        assert {:ok, %Session{}} = result = Task.await(task)
        elem(result, 1)
      end)

    assert length(Enum.uniq(sessions)) == 1
    session = hd(sessions)
    assert {:ok, ^session} = OpenThread.session(pid)
    assert :ok = OpenThread.disconnect(session.handle)
  end

  test "WTH-C03 final owner admission rejects forged messages and expired work", context do
    assert {:ok, handle} = OpenThread.connect(context.options)
    deadline = System.monotonic_time(:millisecond) + 1000

    assert {:error, %Error{code: :invalid_message}} =
             GenServer.call(handle.pid, {handle.reference, :request, "unknown", deadline})

    assert {:error, %Error{code: :timeout}} =
             GenServer.call(handle.pid, {handle.reference, :request, "state", deadline - 1000})

    assert {:error, %Error{code: :invalid_handle}} = GenServer.call(handle.pid, :forged)
    send(handle.pid, {:deadline, "missing"})
    send(handle.pid, {:DOWN, make_ref(), :process, self(), :normal})
    send(handle.pid, :stale)
    assert {:ok, "disabled"} = OpenThread.request(handle, %{type: :state}, 1000)
    assert Enum.map(requests(context), & &1["operation"]) == ["open", "state"]
    assert :ok = OpenThread.disconnect(handle)
  end

  test "WTH-C03 malformed close acknowledgement does not become successful cleanup", context do
    File.write!(Path.join(context.directory, "mode"), "close_bad")
    assert {:ok, handle} = OpenThread.connect(context.options)
    assert {:error, %Error{code: :invalid_response}} = OpenThread.disconnect(handle)
    refute Process.alive?(handle.pid)
  end

  test "WTH-C03 status formatting redacts native configuration and queued requests" do
    redacted =
      Connection.format_status(%{
        state: %{status: :ready, pending: %{1 => :secret}},
        message: "secret-message",
        reason: "secret-reason",
        log: ["secret-log"],
        unrelated: :preserved
      })

    refute inspect(redacted) =~ "secret"
    assert redacted.state == %{status: :ready, pending: 1}
    assert redacted.unrelated == :preserved
  end

  defp requests(context) do
    case File.read(Path.join(context.directory, "requests")) do
      {:ok, bytes} ->
        bytes
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      {:error, :enoent} ->
        []
    end
  end

  defp eventually(predicate, remaining \\ 100)
  defp eventually(predicate, 0), do: assert(predicate.())

  defp eventually(predicate, remaining) do
    unless predicate.() do
      Process.sleep(10)
      eventually(predicate, remaining - 1)
    end
  end
end
