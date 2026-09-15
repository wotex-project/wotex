defmodule Wotex.Matter.NativeRequestIdInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.{Error, Native}

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 60_000

  test "WMA-B02 ordinary and cancellation ID exhaustion close the real SDK controller" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_REQUEST_ID_FIXTURE")
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

    path = %{
      fabric_id: options[:fabric_id],
      node_id: Map.fetch!(fixture, "node_id"),
      endpoint: Map.fetch!(fixture, "endpoint"),
      cluster: 6,
      member: 0
    }

    observations =
      for mode <- [:request, :receiver_death] do
        assert {:ok, handle} = Native.connect(options)
        owner = handle.pid
        port = :sys.get_state(owner).port
        {:os_pid, child} = Port.info(port, :os_pid)
        monitor = Process.monitor(owner)
        receiver = if mode == :receiver_death, do: subscribed_receiver(handle, path)

        try do
          :sys.replace_state(owner, &%{&1 | next_id: 0xFFFFFFFFFFFFFFFF})
          assert :erlang.trace(owner, true, [:receive]) == 1
          started = System.monotonic_time(:millisecond)

          case mode do
            :request -> assert {:ok, %{"status" => "ready"}} = Native.health(handle)
            :receiver_death -> Process.exit(receiver, :kill)
          end

          assert reserved_close_reply?(owner, port, started + 1_000)
          assert_receive {:trace, ^owner, :receive, {^port, {:exit_status, 0}}}, 1_000
          assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 1_000
          assert child_stopped?(child, started + 1_000)
          elapsed = System.monotonic_time(:millisecond) - started
          assert elapsed <= 1_000
          assert Port.info(port) == nil
          assert :ets.info(handle.admission) == :undefined
          assert {:error, %Error{code: :transport_closed, effect: :none}} = Native.health(handle)

          %{
            mode: mode,
            final_request_id: "18446744073709551615",
            reserved_close_result: "null",
            native_exit_status: 0,
            cleanup_ms: elapsed,
            owned_processes_after_grace: 0
          }
        after
          if receiver && Process.alive?(receiver), do: Process.exit(receiver, :kill)
          if Process.alive?(owner), do: :erlang.trace(owner, false, [:receive])
          Native.disconnect(handle)
        end
      end

    File.write!(
      Map.fetch!(fixture, "result_path"),
      Jason.encode!(%{status: "passed", observations: observations}),
      [:exclusive]
    )
  end

  defp subscribed_receiver(handle, path) do
    parent = self()

    receiver =
      spawn(fn ->
        receive do
          report -> send(parent, {:initial_report, report})
        end

        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn ->
      if Process.alive?(receiver), do: Process.exit(receiver, :kill)
    end)

    request = %{
      kind: :attribute,
      paths: [path],
      min_interval_s: 0,
      max_interval_s: 10,
      queue_limit: 64,
      resubscribe: false
    }

    assert {:ok, _} = Native.subscribe_acknowledged(handle, request, receiver, 10_000)
    assert_receive {:initial_report, {:wotex_matter, _, %Native.Delivery{}}}, 10_000
    receiver
  end

  defp reserved_close_reply?(owner, port, deadline) do
    receive do
      {:trace, ^owner, :receive, {^port, {:data, {:eol, line}}}} ->
        if Jason.decode!(line) == %{"version" => 1, "id" => "close", "ok" => true, "result" => nil},
          do: true,
          else: reserved_close_reply?(owner, port, deadline)
    after
      max(0, deadline - System.monotonic_time(:millisecond)) -> false
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
