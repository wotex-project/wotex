defmodule Wotex.Matter.NativePendingOwnerLossInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.{Error, Native}

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 30_000

  test "WMA-C03 abrupt owner loss reaps native code during an unresolved SDK read" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_PENDING_LOSS_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

    controller = Map.fetch!(fixture, "controller")

    options =
      [lifecycle: :persistent, storage_mode: :open_existing, authority: :stored, timeout: 10_000] ++
        Enum.map(
          [
            :executable,
            :storage_path,
            :vendor_id,
            :fabric_id,
            :controller_node_id,
            :paa_trust_store
          ],
          &{&1, Map.fetch!(controller, Atom.to_string(&1))}
        )

    assert {:ok, handle} = Native.connect(options)
    owner = handle.pid
    port = :sys.get_state(owner).port
    {:os_pid, child} = Port.info(port, :os_pid)
    child_identity = process_identity(child)
    assert {^child, ticks} = child_identity
    assert ticks =~ ~r/\A[0-9]+\z/
    monitor = Process.monitor(owner)

    request = %{
      type: :read,
      fabric_id: options[:fabric_id],
      node_id: Map.fetch!(fixture, "unreachable_node_id"),
      endpoint: 1,
      cluster: 6,
      member: 0
    }

    caller = Task.async(fn -> Native.request(handle, request, 5_000) end)

    try do
      assert Task.yield(caller, 250) == nil
      [{{_, token}, _, _}] = Native.Admission.reservations(handle.admission)
      assert :atomics.get(token, 1) == 1
      assert process_identity(child) == child_identity
      started = System.monotonic_time(:millisecond)
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}, 1_000
      assert {:error, %Error{code: :transport_closed, effect: :none}} = Task.await(caller, 1_000)
      assert child_stopped?(child, started + 1_000)
      assert Port.info(port) == nil
      assert :ets.info(handle.admission) == :undefined
      elapsed = System.monotonic_time(:millisecond) - started
      assert elapsed <= 1_000
      assert {:ok, reopened} = Native.connect(options)

      try do
        assert {:ok, %{"status" => "ready"}} = Native.health(reopened)
      after
        assert :ok = Native.disconnect(reopened)
      end

      File.write!(
        Map.fetch!(fixture, "result_path"),
        Jason.encode!(%{
          status: "passed",
          pending_native_requests: 1,
          cleanup_ms: elapsed,
          durable_reopen: "passed",
          owned_processes_after_grace: 0
        }),
        [:exclusive]
      )
    after
      Task.shutdown(caller, :brutal_kill)
      Native.disconnect(handle)

      unless child_stopped?(child, System.monotonic_time(:millisecond) + 6_000) do
        if process_identity(child) == child_identity,
          do:
            Wotex.Matter.Native.ProcessCommand.run("/bin/kill", ["-KILL", to_string(child)],
              stderr_to_stdout: true
            )

        assert child_stopped?(child, System.monotonic_time(:millisecond) + 1_000)
      end
    end
  end

  defp process_identity(pid) do
    case File.read("/proc/#{pid}/stat") do
      {:ok, contents} ->
        [_, fields] = String.split(contents, ") ", parts: 2)

        {pid,
         fields
         |> String.split()
         |> Enum.fetch!(19)}

      {:error, :enoent} ->
        nil
    end
  end

  defp child_stopped?(pid, deadline) do
    if File.exists?("/proc/#{pid}") do
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(5)
        child_stopped?(pid, deadline)
      else
        false
      end
    else
      true
    end
  end
end
