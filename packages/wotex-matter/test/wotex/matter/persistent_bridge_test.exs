defmodule Wotex.Matter.PersistentBridgeTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter
  alias Wotex.Matter.{Error, Native}

  @read %{
    type: :read,
    fabric_id: 1,
    node_id: 2,
    endpoint: 1,
    cluster: 513,
    member: 0
  }

  @write Map.merge(@read, %{
           type: :write,
           member: 18,
           value: %{tag: :anonymous, type: :i16, value: 2000}
         })

  test "WMA-C03 native request admission stops at 64 before the owner mailbox" do
    audit = temporary_path("admission")
    assert {:ok, handle} = Native.connect(options(fixture("valid", audit)))
    initial = File.read!(audit)
    :sys.suspend(handle.pid)
    callers = for _ <- 1..64, do: Task.async(fn -> Native.health(handle, 5_000) end)

    try do
      assert mailbox_reaches?(handle.pid, 64, 100)
      assert File.read!(audit) == initial
      assert {:error, %Error{code: :busy, effect: :none}} = Native.health(handle, 25)
      assert mailbox_requests(handle.pid) == 64
      assert {:message_queue_len, total} = Process.info(handle.pid, :message_queue_len)
      assert total <= 65
    after
      :sys.resume(handle.pid)
      for caller <- callers, do: assert({:ok, %{"status" => "ready"}} = Task.await(caller, 6_000))
      assert :ok = Native.disconnect(handle)
    end
  end

  test "WMA-C03 timed-out queued callers retain admission until the owner consumes them" do
    audit = temporary_path("admission-expiry")
    assert {:ok, handle} = Native.connect(options(fixture("valid", audit)))
    initial = File.read!(audit)
    :sys.suspend(handle.pid)
    callers = for _ <- 1..64, do: Task.async(fn -> Native.health(handle, 25) end)

    try do
      for caller <- callers do
        assert {:error, %Error{code: :timeout}} = Task.await(caller, 1_000)
      end

      assert mailbox_requests(handle.pid) == 64
      assert {:message_queue_len, total} = Process.info(handle.pid, :message_queue_len)
      assert total <= 65
      assert {:error, %Error{code: :busy, effect: :none}} = Native.health(handle, 25)
      assert File.read!(audit) == initial
    after
      :sys.resume(handle.pid)
    end

    :sys.get_state(handle.pid)
    assert :ets.info(handle.admission, :size) == 1
    assert File.read!(audit) == initial
    assert {:ok, %{"status" => "ready"}} = Native.health(handle)
    assert :ok = Native.disconnect(handle)
    assert :ets.info(handle.admission) == :undefined
    assert {:error, %Error{code: :transport_closed}} = Native.health(handle)
  end

  test "WMA-C03 admission capabilities are bound to the connection and generation" do
    audit = temporary_path("admission-identity")
    assert {:ok, handle} = Native.connect(options(fixture("valid", audit)))
    assert {:ok, other} = Native.connect(options(fixture("valid")))
    initial = File.read!(audit)

    try do
      for invalid <- [
            %{handle | admission: nil},
            %{handle | admission: other.admission},
            %{handle | generation: String.duplicate("f", 32)}
          ] do
        assert {:error, %Error{code: :invalid_handle, effect: :none}} = Native.health(invalid)
      end

      assert :ets.info(handle.admission, :size) == 1
      assert :ets.info(other.admission, :size) == 1
      assert File.read!(audit) == initial
      refute inspect(handle) =~ inspect(handle.admission)
    after
      assert :ok = Native.disconnect(handle)
      assert :ok = Native.disconnect(other)
    end
  end

  @tag :caller_control
  test "WMA-C03 dead queued callers release admission during blocked native I/O" do
    audit = temporary_path("dead-queued-caller")
    assert {:ok, handle} = Native.connect(options(fixture("silent_request", audit)))
    active = spawn(fn -> Native.health(handle, 10_000) end)
    assert request_recorded?(audit, 100)
    queued = spawn(fn -> Native.request(handle, @write, 10_000) end)

    try do
      assert admission_reaches?(handle, 2, 100)
      monitor = Process.monitor(queued)
      Process.exit(queued, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^queued, :killed}, 100
      assert admission_reaches?(handle, 1, 20)
      assert {:error, %Error{code: :timeout, effect: :none}} = Native.request(handle, @write, 25)
      assert admission_reaches?(handle, 1, 20)
      refute File.read!(audit) =~ ~s("operation":"write")
      assert Process.alive?(handle.pid)
    after
      Process.exit(active, :kill)
      Process.exit(queued, :kill)
      Native.disconnect(handle)
    end
  end

  @tag :caller_control
  test "WMA-C03 active caller death closes native I/O and fails queued mutations without effects" do
    audit = temporary_path("dead-active-caller")
    assert {:ok, handle} = Native.connect(options(fixture("silent_request", audit)))
    owner_monitor = Process.monitor(handle.pid)
    {:links, links} = Process.info(handle.pid, :links)
    [port] = Enum.filter(links, &is_port/1)
    {:os_pid, child} = Port.info(port, :os_pid)
    active = spawn(fn -> Native.health(handle, 10_000) end)
    assert request_recorded?(audit, 100)
    queued = Task.async(fn -> Native.request(handle, @write, 5_000) end)

    try do
      assert admission_reaches?(handle, 2, 100)
      Process.exit(active, :kill)
      assert_receive {:DOWN, ^owner_monitor, :process, _, :normal}, 1_000
      assert {:error, %Error{code: :transport_closed, effect: :none}} = Task.await(queued, 1_000)
      assert child_stopped?(child, 100)
      refute File.read!(audit) =~ ~s("operation":"write")
      assert :ets.info(handle.admission) == :undefined
    after
      Process.exit(active, :kill)
      Task.shutdown(queued, :brutal_kill)
      Native.disconnect(handle)
    end
  end

  @tag :close_control
  test "WMA-C03 disconnect bypasses full ordinary admission and blocked native I/O" do
    audit = temporary_path("close-full-admission")
    assert {:ok, handle} = Native.connect(options(fixture("silent_request", audit)))
    owner_monitor = Process.monitor(handle.pid)
    {:links, links} = Process.info(handle.pid, :links)
    [port] = Enum.filter(links, &is_port/1)
    {:os_pid, child} = Port.info(port, :os_pid)
    active = Task.async(fn -> Native.health(handle, 10_000) end)
    assert request_recorded?(audit, 100)
    mutation = Task.async(fn -> Native.request(handle, @write, 10_000) end)
    queued = for _ <- 1..62, do: Task.async(fn -> Native.health(handle, 10_000) end)

    try do
      assert admission_reaches?(handle, 64, 100)
      assert {:error, %Error{code: :busy}} = Native.health(handle, 25)
      started = System.monotonic_time(:millisecond)
      assert :ok = Native.disconnect(handle)
      assert_receive {:DOWN, ^owner_monitor, :process, _, :normal}, 1_000
      assert child_stopped?(child, 100)
      assert System.monotonic_time(:millisecond) - started <= 1_000

      for caller <- [active, mutation | queued] do
        assert {:error, %Error{code: :transport_closed, effect: :none}} = Task.await(caller, 1_000)
      end

      refute File.read!(audit) =~ ~s("operation":"write")
      assert :ets.info(handle.admission) == :undefined
      assert :ok = Native.disconnect(handle)
    after
      for caller <- [active, mutation | queued], do: Task.shutdown(caller, :brutal_kill)
      Native.disconnect(handle)
    end
  end

  @tag :orphan_admission
  test "WMA-C03 reservations abandoned before message submission are reclaimed during I/O" do
    audit = temporary_path("orphan-admission")
    assert {:ok, handle} = Native.connect(options(fixture("silent_request", audit)))
    active = spawn(fn -> Native.health(handle, 10_000) end)
    assert request_recorded?(audit, 100)
    parent = self()

    orphan =
      spawn(fn ->
        result =
          Native.Admission.acquire(
            handle.admission,
            handle.pid,
            handle.generation,
            System.monotonic_time(:millisecond) + 5_000
          )

        send(parent, {:reserved, result})
        Process.sleep(:infinity)
      end)

    try do
      assert_receive {:reserved, {:ok, _}}, 1_000
      assert admission_reaches?(handle, 2, 100)
      Process.exit(orphan, :kill)
      assert admission_reaches?(handle, 1, 20)
      assert Process.alive?(handle.pid)
    after
      Process.exit(orphan, :kill)
      Process.exit(active, :kill)
      Native.disconnect(handle)
    end
  end

  @tag :orphan_admission
  test "WMA-C03 a caller lost before submitting its reserved close cannot strand the generation" do
    assert {:ok, handle} = Native.connect(options(fixture("valid")))
    owner_monitor = Process.monitor(handle.pid)
    parent = self()

    orphan =
      spawn(fn ->
        send(
          parent,
          {:closing,
           Native.Admission.begin_close(
             handle.admission,
             handle.pid,
             handle.generation,
             System.monotonic_time(:millisecond) + 5_000
           )}
        )

        Process.sleep(:infinity)
      end)

    try do
      assert_receive {:closing, {:first, _}}, 1_000
      Process.exit(orphan, :kill)
      assert_receive {:DOWN, ^owner_monitor, :process, _, :normal}, 1_000
      assert :ets.info(handle.admission) == :undefined
    after
      Process.exit(orphan, :kill)
      Native.disconnect(handle)
    end
  end

  @tag :orphan_admission
  test "WMA-C03 an expired unsubmitted reservation rejects late messages without native I/O" do
    audit = temporary_path("orphan-expiry")
    assert {:ok, handle} = Native.connect(options(fixture("valid", audit)))
    initial = File.read!(audit)
    deadline = System.monotonic_time(:millisecond) + 25

    assert {:ok, lease} =
             Native.Admission.acquire(handle.admission, handle.pid, handle.generation, deadline)

    try do
      assert admission_reaches?(handle, 0, 20)

      assert {:error, %Error{code: :timeout, effect: :none}} =
               GenServer.call(
                 handle.pid,
                 {:bounded, {:request, handle.generation, @write, 25}, deadline, lease}
               )

      assert File.read!(audit) == initial
      assert {:ok, %{"status" => "ready"}} = Native.health(handle)
    after
      Native.disconnect(handle)
    end
  end

  @tag :orphan_admission
  test "WMA-C03 an unsubmitted close cannot outlive its deadline even with a live caller" do
    assert {:ok, handle} = Native.connect(options(fixture("valid")))
    monitor = Process.monitor(handle.pid)

    assert {:first, _} =
             Native.Admission.begin_close(
               handle.admission,
               handle.pid,
               handle.generation,
               System.monotonic_time(:millisecond) + 25
             )

    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
    assert :ets.info(handle.admission) == :undefined
    assert :ok = Native.disconnect(handle)
  end

  @tag :native_input_pressure
  test "WMA-C03 native stdin backpressure cannot suspend the owner past cleanup" do
    assert {:ok, handle} = Native.connect(options(fixture("valid")))
    monitor = Process.monitor(handle.pid)
    port = :sys.get_state(handle.pid).port
    {:os_pid, child} = Port.info(port, :os_pid)

    try do
      assert {_, 0} = System.cmd("/bin/kill", ["-STOP", to_string(child)])
      assert fill_native_input(port, 128) == :busy
      started = System.monotonic_time(:millisecond)
      assert {:error, %Error{code: :transport_closed, effect: :none}} = Native.health(handle, 100)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
      assert child_stopped?(child, 100)
      assert System.monotonic_time(:millisecond) - started <= 1_000
    after
      if Port.info(port, :os_pid) == {:os_pid, child},
        do: System.cmd("/bin/kill", ["-KILL", to_string(child)], stderr_to_stdout: true)

      Native.disconnect(handle)
    end
  end

  @tag :request_bounds
  test "WMA-C02 malformed and oversized terms fail before entering the native owner mailbox" do
    audit = temporary_path("request-bounds")
    assert {:ok, handle} = Native.connect(options(fixture("valid", audit)))
    initial = File.read!(audit)
    nested = Enum.reduce(1..24, nil, fn _, child -> %{value: child} end)
    :sys.suspend(handle.pid)

    try do
      for value <- [
            String.duplicate("x", 131_072),
            String.duplicate(<<0>>, 22_000),
            List.duplicate(nil, 1025),
            List.duplicate(List.duplicate(nil, 1024), 4),
            nested,
            0x1_0000000000000000,
            <<255>>,
            %{"value" => 1, value: 2},
            %Wotex.Matter.Address{fabric_id: 1, node_id: 2, endpoint: 1, cluster: 6, member: 0},
            fn -> :invalid end
          ] do
        assert {:error, %Error{code: :invalid_request, effect: :none}} =
                 Native.request(handle, %{@write | value: value}, 25)
      end

      assert mailbox_requests(handle.pid) == 0
      assert :ets.info(handle.admission, :size) == 1
      assert File.read!(audit) == initial
    after
      :sys.resume(handle.pid)
      Native.disconnect(handle)
    end
  end

  test "native one-shot handles acquire one existing-store owner per concrete request" do
    audit = temporary_path("oneshot-audit")
    executable = fixture("typed_read", audit)

    config =
      options(executable)
      |> Keyword.merge(lifecycle: :oneshot, storage_mode: :open_existing, authority: :stored)

    assert owned_ports(executable) == []
    assert {:ok, handle} = Native.connect(config)
    assert owned_ports(executable) == []
    refute File.exists?(audit)
    refute inspect(handle) =~ executable

    for _ <- 1..2 do
      assert {:ok, %{value: %{type: :i16, value: 2150}}} = Native.request(handle, @read, 3_000)
      assert owned_ports(executable) == []
    end

    frames = audit |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    assert Enum.map(frames, & &1["operation"]) ==
             [nil, "open", "read", "close", nil, "open", "read", "close"]

    assert length(
             Enum.uniq(
               Enum.map(
                 Enum.filter(frames, &(&1["event"] == "flow_open")),
                 & &1["session_generation"]
               )
             )
           ) == 2

    for frame <- Enum.filter(frames, &(&1["operation"] == "open")) do
      assert frame["parameters"]["storage_mode"] == "open_existing"
      assert frame["parameters"]["authority"] == "stored"
    end

    assert :ok = Native.disconnect(handle)
  end

  test "native one-shot rejects unsupported operations and schemas before acquisition" do
    audit = temporary_path("oneshot-rejections")

    config =
      options(fixture("valid", audit))
      |> Keyword.merge(lifecycle: :oneshot, storage_mode: :open_existing, authority: :stored)

    assert {:ok, handle} = Native.connect(config)

    for operation <- [:read_paths, :read_events, :commission_on_network, :open_window] do
      assert {:error, %Error{code: :not_supported}} =
               Native.request(handle, %{type: operation}, 100)
    end

    assert {:error, %Error{code: :not_supported}} = Native.health(handle)
    assert {:error, %Error{code: :not_supported}} = Native.subscribe(handle, %{}, self(), 100)

    assert {:error, %Error{code: :unsupported_schema}} =
             Native.request(handle, %{@read | cluster: 7}, 100)

    assert {:error, %Error{code: :fabric_mismatch}} =
             Native.request(handle, %{@read | fabric_id: 2}, 100)

    assert {:error, %Error{code: :invalid_handle}} =
             Native.request(%{handle | fabric_id: 2}, @read, 100)

    assert {:error, %Error{}} = Native.request(handle, Map.put(@read, :type, :write), 100)
    refute File.exists?(audit)
  end

  test "native one-shot Runtime keeps scalar zero and null and rejects a mismatched lifecycle" do
    for {mode, expected} <- [{"typed_read", 2150}, {"typed_zero", 0}, {"typed_null", nil}] do
      config =
        options(fixture(mode))
        |> Keyword.merge(
          client: Native,
          lifecycle: :oneshot,
          storage_mode: :open_existing,
          authority: :stored
        )

      consumed = oneshot_consumed(config)

      assert {:ok, context} =
               Wotex.Runtime.Context.new(
                 request_id: "oneshot-scalar",
                 deadline: System.monotonic_time(:millisecond) + 5_000
               )

      assert {:ok, %Wotex.Runtime.Result{payload: ^expected, metadata: metadata}} =
               Wotex.Runtime.ConsumedThing.read_property(consumed, "temperature", context)

      assert metadata == %{}
    end

    audit = temporary_path("oneshot-mode")
    config = options(fixture("valid", audit)) |> Keyword.put(:client, Native)
    assert {:ok, context} = Wotex.Runtime.Context.new(request_id: "wrong-lifecycle")

    assert {:error, %Wotex.Runtime.Error{details: %{cause: %{code: :invalid_options}}}} =
             Wotex.Runtime.ConsumedThing.read_property(
               oneshot_consumed(config),
               "temperature",
               context
             )

    refute File.exists?(audit)
  end

  test "native one-shot startup expiry and close failures cannot return successful operations" do
    config =
      options(startup_fixture())
      |> Keyword.merge(lifecycle: :oneshot, storage_mode: :open_existing, authority: :stored)

    assert {:ok, handle} = Native.connect(config)
    assert {:error, %Error{code: :timeout, effect: :none}} = Native.request(handle, @read, 1_100)

    audit = temporary_path("oneshot-close")

    config =
      options(fixture("bad_close", audit))
      |> Keyword.merge(lifecycle: :oneshot, storage_mode: :open_existing, authority: :stored)

    assert {:ok, handle} = Native.connect(config)
    assert {:error, %Error{code: :invalid_frame}} = Native.request(handle, @read, 3_000)
    assert File.read!(audit) =~ ~s("operation":"close")
  end

  test "WMA-C03 native ready and controller open share one startup deadline" do
    executable = startup_fixture()

    assert {:error, %Error{code: :timeout}} =
             Native.connect(Keyword.put(options(executable), :timeout, 1_100))
  end

  test "WMA-C03 cooperative close waits for successful native process exit" do
    audit = temporary_path("close-exit")
    assert {:ok, handle} = Native.connect(options(fixture("delayed_close_exit", audit)))
    assert :ok = Native.disconnect(handle)
    assert File.read!(audit) =~ "native-exit-completed"
  end

  test "WMA-C03 close rejects malformed results, nonzero exits and stalled shutdown" do
    for {mode, code} <- [
          {"nonnull_close", :invalid_frame},
          {"failed_close_exit", :invalid_transport_return},
          {"stalled_close_exit", :timeout}
        ] do
      assert {:ok, handle} = Native.connect(options(fixture(mode)))
      monitor = Process.monitor(handle.pid)
      {:links, links} = Process.info(handle.pid, :links)
      [port] = Enum.filter(links, &is_port/1)
      {:os_pid, child} = Port.info(port, :os_pid)
      assert {:error, %Error{code: ^code}} = Native.disconnect(handle)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
      assert child_stopped?(child, 100)
      assert :ok = Native.disconnect(handle)
    end
  end

  test "WMA-C03 a stalled child is reaped after its request deadline" do
    assert {:ok, handle} = Native.connect(options(fixture("ignore_eof")))
    monitor = Process.monitor(handle.pid)
    {:links, links} = Process.info(handle.pid, :links)
    [port] = Enum.filter(links, &is_port/1)
    {:os_pid, child} = Port.info(port, :os_pid)

    try do
      assert {:error, %Error{code: :timeout}} = Native.health(handle, 20)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
      assert child_stopped?(child, 100)
    after
      Native.disconnect(handle)
      System.cmd("kill", ["-KILL", Integer.to_string(child)], stderr_to_stdout: true)
    end
  end

  test "persistent owner validates native identity, correlates calls and closes explicitly" do
    fixture = fixture("valid")
    options = options(fixture)

    assert {:ok, session} = Matter.connect([client: Native] ++ options)
    refute inspect(session) =~ "session_generation"
    refute inspect(session.handle) =~ inspect(session.handle.pid)

    assert {:ok, %{"status" => "ready", "fabric_id" => 1}} =
             Native.health(session.handle)

    assert {:error, %Error{code: :not_supported, effect: :none}} =
             Matter.send(session, @read)

    assert :ok = Matter.disconnect(session)
    refute Process.alive?(session.handle.pid)
    assert :ok = Matter.disconnect(session)
  end

  test "wrong fabric is rejected before the native request boundary" do
    audit = temporary_path("requests")
    fixture = fixture("valid", audit)
    assert {:ok, handle} = Native.connect(options(fixture))
    initial = File.read!(audit)

    assert {:error, %Error{code: :fabric_mismatch, effect: :none}} =
             Native.request(handle, %{@read | fabric_id: 2}, 1_000)

    assert File.read!(audit) == initial
    assert :ok = Native.disconnect(handle)
  end

  test "malformed operation types fail before native serialization" do
    audit = temporary_path("malformed-requests")
    fixture = fixture("valid", audit)
    assert {:ok, handle} = Native.connect(options(fixture))
    initial = File.read!(audit)

    assert {:error, %Error{code: :invalid_request, effect: :none}} =
             Native.request(handle, %{type: "read", fabric_id: 1}, 1_000)

    assert {:error, %Error{code: :invalid_request, effect: :none}} =
             Native.request(handle, %{fabric_id: 1}, 1_000)

    assert {:error, %Error{code: :invalid_request, effect: :none}} =
             Native.request(handle, %{"node_id" => 2, type: :read, fabric_id: 1}, 1_000)

    assert {:error, %Error{code: :invalid_request, effect: :none}} =
             Native.request(handle, :not_a_map, 1_000)

    for message <- [
          %{type: :read},
          %{type: :read_paths, paths: []},
          %{type: :read_paths, paths: [false]},
          %{type: :read_paths, paths: [%{fabric_id: 1}, %{fabric_id: 2}]}
        ] do
      assert {:error, %Error{code: :invalid_request, effect: :none}} =
               Native.request(handle, message, 1_000)
    end

    for timeout <- [0, 60_001, :infinity] do
      assert {:error, %Error{code: :invalid_handle}} = Native.request(handle, @read, timeout)
      assert {:error, %Error{code: :invalid_handle}} = Native.health(handle, timeout)
    end

    assert {:error, %Error{code: :invalid_handle}} = Native.unsubscribe(handle, nil, 1_000)
    assert {:error, %Error{code: :invalid_handle}} = Native.subscribe(handle, %{}, nil, 1_000)

    assert File.read!(audit) == initial
    assert :ok = Native.disconnect(handle)
  end

  test "WMA-C03 a foreign generation cannot use or close the live controller" do
    audit = temporary_path("generation-requests")
    assert {:ok, handle} = Native.connect(options(fixture("valid", audit)))
    foreign = %{handle | generation: String.duplicate("0", 32)}
    initial = File.read!(audit)

    assert {:error, %Error{code: :invalid_handle}} = Native.request(foreign, @read, 1_000)
    assert {:error, %Error{code: :invalid_handle}} = Native.health(foreign)
    assert {:error, %Error{code: :invalid_handle}} = Native.disconnect(foreign)

    assert {:error, %Error{code: :invalid_handle}} =
             Native.Connection.invalidate(foreign.pid, foreign.generation, foreign.admission)

    assert File.read!(audit) == initial
    assert Process.alive?(handle.pid)
    assert {:ok, %{"status" => "ready"}} = Native.health(handle)
    assert :ok = Native.disconnect(handle)

    for invalid <- [nil, false, %{}, %{handle | pid: nil}] do
      assert {:error, %Error{code: :invalid_handle}} = Native.health(invalid)
      assert {:error, %Error{code: :invalid_handle}} = Native.request(invalid, @read, 1_000)
      assert :ok = Native.disconnect(invalid)
    end
  end

  test "WMA-C05 native subscription admission rejects invalid fields without opening a stream" do
    audit = temporary_path("subscription-admission")
    assert {:ok, handle} = Native.connect(options(fixture("valid", audit)))
    initial = File.read!(audit)
    path = Map.delete(@read, :type)

    request = %{
      kind: :attribute,
      paths: [path],
      min_interval_s: 0,
      max_interval_s: 1,
      resubscribe: false,
      queue_limit: 1
    }

    for {key, value} <- [
          {:kind, :unknown},
          {:paths, []},
          {:paths, [path, path]},
          {:paths, [nil]},
          {:paths, [%{path | node_id: 0}]},
          {:paths, [%{path | fabric_id: 2}]},
          {:paths, [%{path | cluster: 0x7FFF}]},
          {:min_interval_s, -1},
          {:max_interval_s, 0},
          {:resubscribe, 0},
          {:queue_limit, 0},
          {:queue_limit, 10_001},
          {:extra, true}
        ] do
      assert {:error, %Error{effect: :none}} =
               Native.subscribe(handle, Map.put(request, key, value), self(), 1_000)
    end

    assert File.read!(audit) == initial
    assert :ok = Native.disconnect(handle)
  end

  test "invalid options and startup frames fail without returning a handle" do
    valid = options(fixture("valid"))

    for options <- [
          :invalid,
          [],
          Keyword.put(valid, :lifecycle, :oneshot),
          Keyword.put(valid, :storage_path, "relative"),
          Keyword.put(valid, :storage_path, nil),
          Keyword.put(valid, :storage_mode, :unknown),
          Keyword.put(valid, :authority, :external),
          Keyword.put(valid, :vendor_id, 0),
          Keyword.put(valid, :fabric_id, 0),
          Keyword.put(valid, :controller_node_id, 0),
          Keyword.put(valid, :paa_trust_store, temporary_path("missing-paa")),
          Keyword.put(valid, :executable, temporary_path("missing-host")),
          [{:vendor_id, 1} | valid]
        ] do
      assert {:error, %Error{}} = Native.connect(options)
    end

    for mode <- ["bad_ready", "duplicate_ready", "foreign_id", "stdout_log"] do
      assert {:error, %Error{}} = Native.connect(options(fixture(mode)))
    end

    assert {:ok, handle} = Native.connect(options(fixture("noisy_stderr")))
    assert :ok = Native.disconnect(handle)
  end

  test "the creating process owns connection and native process lifetime" do
    fixture = fixture("valid")
    parent = self()

    owner =
      spawn(fn ->
        {:ok, handle} = Native.connect(options(fixture))
        send(parent, {:handle, handle})
        Process.sleep(:infinity)
      end)

    assert_receive {:handle, handle}, 2_000
    monitor = Process.monitor(handle.pid)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, _pid, _reason}, 2_000
  end

  test "WMA-C07 an open reply must match the explicitly requested controller identity" do
    for mode <- [
          "wrong_open_fabric",
          "wrong_open_node",
          "wrong_open_vendor",
          "wrong_open_lifecycle",
          "extra_open_field",
          "null_open"
        ] do
      assert {:error, %Error{code: :invalid_controller_identity}} =
               Native.connect(options(fixture(mode)))
    end
  end

  test "WMA-C07 malformed replies retire the controller generation" do
    for {mode, code} <- [
          {"malformed_reply", :invalid_frame},
          {"oversized_reply", :response_limit},
          {"request_eof", :transport_closed}
        ] do
      assert {:ok, handle} = Native.connect(options(fixture(mode)))
      monitor = Process.monitor(handle.pid)
      assert {:error, %Error{code: ^code}} = Native.health(handle)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
      assert {:error, %Error{code: :transport_closed}} = Native.health(handle)
    end
  end

  test "WMA-C03 owner death interrupts an in-flight native request" do
    audit = temporary_path("inflight-owner")
    executable = fixture("silent_request", audit)
    parent = self()

    owner =
      spawn(fn ->
        {:ok, handle} = Native.connect(options(executable))
        send(parent, {:handle, handle})
        send(parent, {:late_response, Native.health(handle, 60_000)})
      end)

    assert_receive {:handle, handle}, 2_000
    assert request_recorded?(audit, 100)
    monitor = Process.monitor(handle.pid)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
    refute_receive {:late_response, _}
  end

  test "WMA-C04 a broken reply after mutation submission has unknown effect" do
    for message <- [
          Map.merge(@read, %{
            type: :write,
            member: 18,
            value: %{tag: :anonymous, type: :i16, value: 2000}
          }),
          Map.merge(@read, %{
            type: :invoke,
            cluster: 6,
            member: 1,
            value: %{tag: :anonymous, type: :structure, value: []}
          })
        ] do
      assert {:ok, handle} = Native.connect(options(fixture("malformed_reply")))

      assert {:error,
              %Error{code: :invalid_frame, effect: :unknown, class: :permanent, retryable: false}} =
               Native.request(handle, message, 1_000)

      assert :ok = Native.disconnect(handle)

      assert {:ok, malformed} = Native.connect(options(fixture("malformed_result")))
      monitor = Process.monitor(malformed.pid)

      assert {:error,
              %Error{code: :invalid_frame, effect: :unknown, class: :permanent, retryable: false}} =
               Native.request(malformed, message, 1_000)

      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000

      assert {:ok, refused} = Native.connect(options(fixture("native_timeout")))

      assert {:error, %Error{code: :timeout, effect: :none}} =
               Native.request(refused, message, 1_000)

      assert :ok = Native.disconnect(refused)
    end
  end

  test "WMA-C03 an expired queued mutation never reaches the native process" do
    audit = temporary_path("queued-deadline")
    assert {:ok, handle} = Native.connect(options(fixture("slow_first", audit)))
    first = Task.async(fn -> Native.health(handle, 1_000) end)
    assert request_recorded?(audit, 100)

    mutation =
      Map.merge(@read, %{
        type: :write,
        member: 18,
        value: %{tag: :anonymous, type: :i16, value: 2000}
      })

    assert {:error, %Error{code: :timeout, effect: :none}} = Native.request(handle, mutation, 10)
    assert {:ok, %{"status" => "ready"}} = Task.await(first)
    assert {:ok, %{"status" => "ready"}} = Native.health(handle)
    refute File.read!(audit) =~ ~s("operation":"write")
    assert :ok = Native.disconnect(handle)
  end

  test "WMA-C03 successful replies after the request deadline cannot become success" do
    for {mode, message, effect} <- [
          {"late_read", @read, :none},
          {"late_write",
           Map.merge(@read, %{
             type: :write,
             member: 18,
             value: %{tag: :anonymous, type: :i16, value: 2000}
           }), :unknown}
        ] do
      assert {:ok, handle} = Native.connect(options(fixture(mode)))
      assert {:error, %Error{code: :timeout, effect: ^effect}} = Native.request(handle, message, 10)
      assert :ok = Native.disconnect(handle)
    end
  end

  test "WMA-C03 concurrent disconnect is idempotent and emits one native close" do
    audit = temporary_path("concurrent-close")
    assert {:ok, handle} = Native.connect(options(fixture("valid", audit)))

    results =
      Task.async_stream(1..32, fn _ -> Native.disconnect(handle) end, max_concurrency: 32)
      |> Enum.to_list()

    assert Enum.all?(results, &(&1 == {:ok, :ok}))
    assert length(Regex.scan(~r/"operation":"close"/, File.read!(audit))) == 1
  end

  defp owned_ports(executable) do
    Enum.filter(Port.list(), &(Port.info(&1, :name) == {:name, String.to_charlist(executable)}))
  end

  defp oneshot_consumed(config) do
    assert {:ok, td} =
             Wotex.ThingDescription.from_map(%{
               "@context" => "https://www.w3.org/2022/wot/td/v1.1",
               "id" => "urn:example:matter:oneshot-boundary",
               "title" => "Native one-shot boundary",
               "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
               "security" => ["none"],
               "properties" => %{
                 "temperature" => %{
                   "readOnly" => true,
                   "forms" => [%{"href" => "matter://1/2/1/513/0", "op" => "readproperty"}]
                 }
               }
             })

    assert {:ok, consumed} =
             Wotex.Runtime.ConsumedThing.new(td,
               profiles: [Matter.profile()],
               transports: %{matter: {Wotex.Matter.Transport, Keyword.put(config, :target, "1")}},
               credentials: {Wotex.Matter.RuntimeCredentials, %{test_pid: self()}}
             )

    consumed
  end

  defp options(executable) do
    paa = temporary_path("paa")
    File.mkdir_p!(paa)

    [
      executable: executable,
      lifecycle: :persistent,
      storage_path: temporary_path("store"),
      storage_mode: :create_new,
      authority: :generate_root,
      vendor_id: 65_521,
      fabric_id: 1,
      controller_node_id: 2,
      paa_trust_store: paa,
      timeout: 3_000
    ]
  end

  defp startup_fixture do
    path = temporary_path("startup-budget-host")

    File.write!(path, """
    #!/bin/sh
    sleep 0.6
    printf '%s\\n' '{"version":1,"event":"ready","backend":"matter-native","revision":"250a9e6c50ee2068107f3c4808b680f5f2925415"}'
    IFS= read -r flow
    IFS= read -r open
    sleep 0.6
    printf '%s\\n' '{"version":1,"id":"1","ok":true,"result":{"lifecycle":"persistent","fabric_id":1,"controller_node_id":2,"vendor_id":65521}}'
    IFS= read -r close
    """)

    File.chmod!(path, 0o700)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp fixture(mode, audit \\ nil) do
    path = temporary_path("#{mode}-host")
    audit = audit || temporary_path("#{mode}-audit")

    script = """
    #!/usr/bin/env elixir
    mode = #{inspect(mode)}
    audit = #{inspect(audit)}
    record = fn line -> File.write!(audit, line, [:append]) end
    read = fn ->
      case IO.read(:stdio, :line) do
        :eof -> System.halt(0)
        {:error, _} -> System.halt(1)
        line -> record.(line); line
      end
    end

    if mode == "stdout_log" do
      IO.puts("unframed log")
      System.halt(0)
    end

    if mode == "noisy_stderr", do: IO.puts(:stderr, "native-log")

    ready =
      case mode do
        "bad_ready" ->
          ~s({"version":1,"event":"ready","backend":"matter-native","revision":"wrong"})
        "duplicate_ready" ->
          ~s({"version":99,"version":1,"event":"ready","backend":"matter-native","revision":"250a9e6c50ee2068107f3c4808b680f5f2925415"})
        _ ->
          ~s({"version":1,"event":"ready","backend":"matter-native","revision":"250a9e6c50ee2068107f3c4808b680f5f2925415"})
      end

    IO.puts(ready)
    read.()
    read.()

    open_id = if mode == "foreign_id", do: "99", else: "1"
    open_result = ~s({"lifecycle":"persistent","fabric_id":1,"controller_node_id":2,"vendor_id":65521})
    open_result = case mode do
      "wrong_open_fabric" -> String.replace(open_result, ~s("fabric_id":1), ~s("fabric_id":2))
      "wrong_open_node" -> String.replace(open_result, ~s("controller_node_id":2), ~s("controller_node_id":3))
      "wrong_open_vendor" -> String.replace(open_result, ~s("vendor_id":65521), ~s("vendor_id":65522))
      "wrong_open_lifecycle" -> String.replace(open_result, "persistent", "oneshot")
      "extra_open_field" -> String.replace(open_result, "}", ~s(,"extra":true}))
      "null_open" -> "null"
      _ -> open_result
    end
    IO.puts(~s({"version":1,"id":"\#{open_id}","ok":true,"result":\#{open_result}}))

    loop = fn loop ->
      line = read.()
      [_, id] = Regex.run(~r/"id":"([1-9][0-9]*)"/, line)

      cond do
        mode == "ignore_eof" ->
          Process.sleep(:infinity)

        mode == "malformed_reply" ->
          IO.puts(~s({"version":1,"id":"\#{id}","ok":true,"result":null,"result":42}))
          loop.(loop)

        mode == "oversized_reply" ->
          IO.puts(String.duplicate("x", 131072))
          loop.(loop)

        mode == "request_eof" ->
          System.halt(78)

        mode == "silent_request" ->
          loop.(loop)

        mode == "native_timeout" ->
          IO.puts(~s({"version":1,"id":"\#{id}","ok":false,"error":{"code":"interaction_timeout","effect":"none"}}))
          loop.(loop)

        mode == "malformed_result" ->
          IO.puts(~s({"version":1,"id":"\#{id}","ok":true,"result":false}))
          loop.(loop)

        mode in ["late_read", "late_write"] ->
          Process.sleep(30)
          result = if mode == "late_read" do
            ~s({"path":{"fabric_id":1,"node_id":2,"endpoint":1,"cluster":513,"member":0},"value":{"tag":"anonymous","type":"i16","value":2150},"data_version":0})
          else
            ~s({"path":{"fabric_id":1,"node_id":2,"endpoint":1,"cluster":513,"member":18},"status":0})
          end
          IO.puts(~s({"version":1,"id":"\#{id}","ok":true,"result":\#{result}}))
          loop.(loop)

        mode in ["typed_read", "typed_zero", "typed_null", "bad_close"] and String.contains?(line, ~s("operation":"read")) ->
          result = ~s({"path":{"fabric_id":1,"node_id":2,"endpoint":1,"cluster":513,"member":0},"value":{"tag":"anonymous","type":"i16","value":2150},"data_version":0})
          result = case mode do
            "typed_zero" -> String.replace(result, "2150", "0")
            "typed_null" -> result |> String.replace(~s("type":"i16"), ~s("type":"null")) |> String.replace("2150", "null")
            _ -> result
          end
          IO.puts(~s({"version":1,"id":"\#{id}","ok":true,"result":\#{result}}))
          loop.(loop)

        mode == "bad_close" and String.contains?(line, ~s("operation":"close")) ->
          IO.puts(~s({"version":1,"id":"999","ok":true,"result":null}))
          loop.(loop)

        String.contains?(line, ~s("operation":"close")) ->
          result = if mode == "nonnull_close", do: "42", else: "null"
          IO.puts(~s({"version":1,"id":"\#{id}","ok":true,"result":\#{result}}))
          case mode do
            "delayed_close_exit" ->
              Process.sleep(200)
              File.write!(audit, "native-exit-completed", [:append])
            "failed_close_exit" ->
              System.halt(42)
            "stalled_close_exit" ->
              Process.sleep(:infinity)
            _ -> :ok
          end

        String.contains?(line, ~s("operation":"health")) ->
          count = Process.get(:health_count, 0) + 1
          Process.put(:health_count, count)
          if mode == "slow_first" and count == 1, do: Process.sleep(200)
          IO.puts(~s({"version":1,"id":"\#{id}","ok":true,"result":{"status":"ready","fabric_id":1}}))
          loop.(loop)

        true ->
          IO.puts(~s({"version":1,"id":"\#{id}","ok":false,"error":{"code":"not_supported"}}))
          loop.(loop)
      end
    end

    loop.(loop)
    """

    File.write!(path, script)
    File.chmod!(path, 0o700)

    on_exit(fn ->
      File.rm(path)
      File.rm(audit)
    end)

    path
  end

  defp fill_native_input(_, 0), do: :limit

  defp fill_native_input(port, remaining) do
    # Bounded transport fault injection into the stopped child's pipe, not an
    # application request. Never resume it to parse these setup bytes.
    if Port.command(port, String.duplicate(" ", 16_384), [:nosuspend]),
      do: fill_native_input(port, remaining - 1),
      else: :busy
  end

  defp mailbox_requests(pid) do
    {:messages, messages} = Process.info(pid, :messages)
    Enum.count(messages, &match?({:"$gen_call", _, {:bounded, _, _, _}}, &1))
  end

  defp mailbox_reaches?(_, _, 0), do: false

  defp mailbox_reaches?(pid, count, attempts) do
    if mailbox_requests(pid) == count do
      true
    else
      Process.sleep(5)
      mailbox_reaches?(pid, count, attempts - 1)
    end
  end

  defp admission_reaches?(_, _, 0), do: false

  defp admission_reaches?(handle, count, attempts) do
    if :ets.info(handle.admission, :size) == count + 1 do
      true
    else
      Process.sleep(5)
      admission_reaches?(handle, count, attempts - 1)
    end
  end

  defp request_recorded?(_, 0), do: false

  defp request_recorded?(audit, attempts) do
    if File.read!(audit) =~ ~s("operation":"health") do
      true
    else
      Process.sleep(10)
      request_recorded?(audit, attempts - 1)
    end
  end

  defp child_stopped?(_, 0), do: false

  defp child_stopped?(pid, attempts) do
    case System.cmd("kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_, 0} ->
        Process.sleep(10)
        child_stopped?(pid, attempts - 1)

      _ ->
        true
    end
  end

  defp temporary_path(suffix) do
    Path.join(
      System.tmp_dir!(),
      "wotex-matter-p03-#{System.unique_integer([:positive])}-#{suffix}"
    )
  end
end
