defmodule Wotex.Matter.NativePendingSubscriptionLossInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.{Error, Native}

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 30_000

  test "WMA-C03 receiver and stream-owner loss abandon pending SDK subscription registration" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_PENDING_SUBSCRIPTION_LOSS_FIXTURE")
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

    observations =
      for loss <- [:receiver, :stream_owner] do
        assert {:ok, handle} = Native.connect(options)
        owner = handle.pid
        port = :sys.get_state(owner).port
        {:os_pid, child} = Port.info(port, :os_pid)
        child_identity = process_identity(child)
        assert {^child, ticks} = child_identity
        assert ticks =~ ~r/\A[0-9]+\z/
        monitor = Process.monitor(owner)

        receiver = spawn(fn -> Process.sleep(:infinity) end)
        :erlang.trace(owner, true, [:procs])

        request = %{
          kind: :attribute,
          paths: [
            %{
              fabric_id: options[:fabric_id],
              node_id: Map.fetch!(fixture, "unreachable_node_id"),
              endpoint: 1,
              cluster: 6,
              member: 0
            }
          ],
          min_interval_s: 0,
          max_interval_s: 10,
          queue_limit: 64,
          resubscribe: false
        }

        caller = Task.async(fn -> Native.subscribe(handle, request, receiver, 5_000) end)

        try do
          assert_receive {:trace, ^owner, :spawn, stream_owner, _}, 1_000
          assert Task.yield(caller, 250) == nil
          :sys.suspend(stream_owner)
          [{{_, token}, _, _}] = Native.Admission.reservations(handle.admission)
          assert :atomics.get(token, 1) == 1
          assert process_identity(child) == child_identity
          started = System.monotonic_time(:millisecond)
          Process.exit(if(loss == :receiver, do: receiver, else: stream_owner), :kill)
          assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 1_000

          assert {:error, %Error{code: :transport_closed, effect: :none}} =
                   Task.await(caller, 1_000)

          assert child_stopped?(child, started + 1_000)
          refute Process.alive?(stream_owner)
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

          %{
            status: "passed",
            lost_owner: Atom.to_string(loss),
            pending_native_subscriptions: 1,
            cleanup_ms: elapsed,
            durable_reopen: "passed",
            owned_processes_after_grace: 0
          }
        after
          Process.exit(receiver, :kill)
          if Process.alive?(owner), do: :erlang.trace(owner, false, [:procs])
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

    File.write!(
      Map.fetch!(fixture, "result_path"),
      Jason.encode!(%{status: "passed", observations: observations}),
      [:exclusive]
    )
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
