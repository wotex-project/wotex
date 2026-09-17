defmodule Wotex.BLE.LifecycleStressTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.BLE
  alias Wotex.BLE.{Error, SoftwarePeer}
  @moduletag :software
  @moduletag timeout: 900_000

  # WBL-C09 software stress against the Mix-built native host, real BlueZ and
  # virtual controllers. Each lifecycle cycle returns to the recorded BEAM
  # process/port, native OS process and BlueZ ownership baseline.
  @grace 1100
  # The fixture monitor accepts 64 unique native senders between resets.
  @senders_per_reset 50

  setup do
    config = SoftwarePeer.command("reset")
    on_exit(fn -> SoftwarePeer.wait_until(&SoftwarePeer.released?/0, 3000) end)
    %{options: SoftwarePeer.options(config)}
  end

  test "WBL-C09 one thousand sequential native operations keep correlation and bounded memory", %{
    options: options
  } do
    session = connect(options)
    address = address(session, :value)
    host = host(session)
    before = SoftwarePeer.command("stats")["peer_calls"]
    samples = [sample(0, host)]

    samples =
      Enum.reduce(1..1000, samples, fn index, samples ->
        if rem(index, 2) == 1 do
          assert {:ok, :written} = BLE.write(session, address, index, value_type: :uint16)
        else
          assert {:ok, value} = BLE.read(session, address, value_type: :uint16)
          assert value == index - 1
        end

        if rem(index, 250) == 0, do: [sample(index, host) | samples], else: samples
      end)

    stats = SoftwarePeer.command("stats")

    for member <- ~w(ReadValue WriteValue),
        do: assert(stats["peer_calls"][member] - Map.get(before, member, 0) == 500)

    assert length(stats["native_senders"]) == 1
    assert :sys.get_state(session.handle.pid).pending == %{}
    report("sequential_operations", Enum.reverse(samples))
    assert :ok = BLE.disconnect(session)
    released()
  end

  test "WBL-C09 one hundred open and close cycles return to the ownership baseline", %{
    options: options
  } do
    baseline = baseline()

    samples =
      Enum.reduce(1..100, [], fn cycle, samples ->
        if cycle > 1 and rem(cycle - 1, @senders_per_reset) == 0,
          do: SoftwarePeer.command("reset")

        session = connect(options)
        monitor = Process.monitor(session.handle.pid)
        assert {:ok, %{connected: true, services_resolved: true}} = BLE.health_check(session)
        assert :ok = BLE.disconnect(session)
        assert_receive {:DOWN, ^monitor, :process, _, :normal}, @grace
        at_baseline(baseline)
        if rem(cycle, 25) == 0, do: [sample(cycle, nil) | samples], else: samples
      end)

    report("open_close_cycles", Enum.reverse(samples))
  end

  test "WBL-C09 one hundred receiver terminations release each real CCC session", %{
    options: options
  } do
    session = connect(options)
    address = address(session, :notify)
    host = host(session)

    samples =
      Enum.reduce(1..100, [sample(0, host)], fn cycle, samples ->
        parent = self()
        receiver = spawn(fn -> forward(parent) end)

        assert {:ok, subscription} =
                 BLE.subscribe(session, %{address: address, receiver: receiver})

        SoftwarePeer.command("value", %{label: "notify", hex: "01", emit: true})
        reference = subscription.reference
        assert_receive {:forwarded, {:wotex_ble, ^reference, {:ok, <<1>>, _}}}, 2000
        monitor = Process.monitor(subscription.pid)
        started = now()
        Process.exit(receiver, :kill)
        assert_receive {:DOWN, ^monitor, :process, _, :normal}, @grace

        SoftwarePeer.wait_until(
          fn ->
            stats = SoftwarePeer.command("stats", %{}, 1000)
            stats["notification_sessions"] == 0 and stats["notifying"] == []
          end,
          @grace
        )

        assert now() - started <= @grace
        state = :sys.get_state(session.handle.pid)
        assert state.subscriptions == %{} and state.pending == %{}
        assert state.report_flow.streams == %{} and state.report_flow.records == %{}
        if rem(cycle, 25) == 0, do: [sample(cycle, host) | samples], else: samples
      end)

    assert {:ok, %{connected: true}} = BLE.health_check(session)
    report("receiver_terminations", Enum.reverse(samples))
    assert :ok = BLE.disconnect(session)
    released()
  end

  test "WBL-C09 thirty-two concurrent callers correlate replies and share bounded admission", %{
    options: options
  } do
    session = connect(options)
    assert {:ok, page} = BLE.discover(session)

    targets =
      for item <- page.characteristics,
          item.service_uuid == SoftwarePeer.service(),
          do: SoftwarePeer.target(item)

    expected =
      Map.new(targets, fn address ->
        assert {:ok, value} = BLE.read(session, address)
        {address, value}
      end)

    results =
      1..32
      |> Enum.map(fn caller ->
        address = Enum.at(targets, rem(caller, length(targets)))

        Task.async(fn ->
          for _ <- 1..10, do: {address, BLE.read(session, address, timeout: 30_000)}
        end)
      end)
      |> Task.await_many(60_000)
      |> List.flatten()

    assert length(results) == 320
    assert Enum.all?(results, fn {address, result} -> result == {:ok, expected[address]} end)

    # While the owner is suspended, 65 callers enqueue before any dispatch.
    address = hd(targets)
    :ok = :sys.suspend(session.handle.pid)
    tasks = for _ <- 1..65, do: Task.async(fn -> BLE.read(session, address, timeout: 30_000) end)
    wait(fn -> mailbox(session.handle.pid) == 65 end)
    :ok = :sys.resume(session.handle.pid)
    outcomes = Task.await_many(tasks, 60_000)
    assert Enum.count(outcomes, &match?({:error, %Error{code: :busy}}, &1)) == 1
    assert Enum.count(outcomes, &(&1 == {:ok, expected[address]})) == 64
    assert :sys.get_state(session.handle.pid).pending == %{}
    assert :ok = BLE.disconnect(session)
    released()
  end

  test "WBL-C09 forced deadline, peer close, corrupt frame and host loss release ownership", %{
    options: options
  } do
    baseline = baseline()

    for fault <- [:deadline, :corrupt_frame, :host_loss, :peer_close] do
      session = connect(options)
      address = address(session, :value)
      monitor = Process.monitor(session.handle.pid)
      started = now()

      case fault do
        :deadline ->
          SoftwarePeer.command("delay", %{label: "value", milliseconds: 1500})
          assert {:error, %Error{code: :timeout}} = BLE.read(session, address, timeout: 200)
          SoftwarePeer.command("delay", %{label: "value", milliseconds: 0})

        :corrupt_frame ->
          state = :sys.get_state(session.handle.pid)
          send(session.handle.pid, {state.port, {:data, {:eol, "{\"version\":1"}}})

        :host_loss ->
          assert {_, 0} =
                   System.cmd("/bin/kill", ["-KILL", Integer.to_string(host(session))],
                     env: Enum.map(System.get_env(), fn {key, _} -> {key, nil} end)
                   )

        :peer_close ->
          SoftwarePeer.command("disconnect")
      end

      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 3000
      assert {:error, %Error{}} = BLE.read(session, address)
      at_baseline(baseline, 3000)
      report("fault_#{fault}", [%{"elapsed_ms" => now() - started}])
      if fault != :peer_close, do: assert(SoftwarePeer.command("stats")["peer_connected"])
    end
  end

  defp connect(options) do
    assert {:ok, session} = BLE.connect(options)
    on_exit(fn -> BLE.disconnect(session) end)
    session
  end

  defp address(session, label) do
    assert {:ok, page} = BLE.discover(session)
    SoftwarePeer.target(SoftwarePeer.selected(page, label))
  end

  defp forward(parent) do
    receive do
      message ->
        send(parent, {:forwarded, message})
        forward(parent)
    end
  end

  # The SDK host is the direct child of the runtime guardian Port process.
  defp host(session) do
    {:os_pid, guardian} = Port.info(:sys.get_state(session.handle.pid).port, :os_pid)
    [host] = children(guardian)
    host
  end

  defp baseline do
    released()

    %{
      processes: MapSet.new(Process.list()),
      ports: length(Port.list()),
      native: native_processes()
    }
  end

  defp at_baseline(baseline, timeout \\ @grace) do
    wait(
      fn ->
        MapSet.difference(MapSet.new(Process.list()), baseline.processes) == MapSet.new() and
          length(Port.list()) == baseline.ports and native_processes() == baseline.native
      end,
      timeout
    )

    SoftwarePeer.wait_until(&SoftwarePeer.released?/0, timeout)
  end

  defp released, do: SoftwarePeer.wait_until(&SoftwarePeer.released?/0, 3000)

  defp native_processes do
    for pid <- linux_processes(),
        {:ok, command} <- [File.read("/proc/#{pid}/cmdline")],
        String.contains?(command, ["wotex-ble-host", "wotex-ble-guardian"]),
        state(pid) not in [nil, "Z"],
        do: pid
  end

  defp children(parent) do
    for pid <- linux_processes(), parent(pid) == parent, state(pid) not in [nil, "Z"], do: pid
  end

  defp linux_processes do
    for name <- File.ls!("/proc"), {pid, ""} <- [Integer.parse(name)], do: pid
  end

  defp parent(pid) do
    case stat(pid) do
      [_, parent | _] -> String.to_integer(parent)
      _ -> nil
    end
  end

  defp state(pid) do
    case stat(pid) do
      [state | _] -> state
      _ -> nil
    end
  end

  defp stat(pid) do
    with {:ok, bytes} <- File.read("/proc/#{pid}/stat"),
         [_, fields] <- Regex.run(~r/\A.*\)\s(.*)\z/s, bytes) do
      String.split(fields)
    else
      _ -> nil
    end
  end

  defp sample(index, host) do
    rss =
      with pid when is_integer(pid) <- host,
           {:ok, status} <- File.read("/proc/#{pid}/status"),
           [_, kilobytes] <- Regex.run(~r/^VmRSS:\s+(\d+) kB$/m, status) do
        String.to_integer(kilobytes)
      else
        _ -> nil
      end

    %{"index" => index, "beam_total_bytes" => :erlang.memory(:total), "host_rss_kb" => rss}
  end

  # Memory trends are separate lane evidence; allocator caching is not a pass condition.
  defp report(name, samples) do
    path = System.fetch_env!("WOTEX_BLE_STRESS_REPORT")
    assert Path.type(path) == :absolute
    line = Jason.encode!(%{"case" => name, "samples" => samples}) <> "\n"
    assert :ok = File.write(path, line, [:append])
  end

  defp mailbox(pid) do
    {:message_queue_len, length} = Process.info(pid, :message_queue_len)
    length
  end

  defp wait(predicate, timeout \\ 5000), do: SoftwarePeer.wait_until(predicate, timeout)
  defp now, do: System.monotonic_time(:millisecond)
end
