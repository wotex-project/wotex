defmodule Wotex.Matter.NativeInputPressureInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.{Error, Native}

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 60_000

  test "WMA-C03 request and report ACK backpressure close the owned SDK process" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_INPUT_PRESSURE_FIXTURE")
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
      for mode <- [:request, :report_ack] do
        assert {:ok, handle} = Native.connect(options)
        assert {:ok, %{"status" => "ready"}} = Native.health(handle)
        delivery = if mode == :report_ack, do: initial_delivery(handle, path)
        port = :sys.get_state(handle.pid).port
        {:os_pid, child} = Port.info(port, :os_pid)
        monitor = Process.monitor(handle.pid)

        try do
          assert {_, 0} = System.cmd("/bin/kill", ["-STOP", to_string(child)])
          assert eventually(fn -> File.read!("/proc/#{child}/status") =~ ~r/State:\s+T/ end)
          assert {:busy, bytes} = fill_native_input(port, 128, 0)
          assert bytes > 0 and bytes <= 2_097_152
          started = System.monotonic_time(:millisecond)

          case mode do
            :request ->
              assert {:error, %Error{code: :transport_closed, effect: :none}} =
                       Native.health(handle, 100)

            :report_ack ->
              send(
                handle.pid,
                {:native_report_consumed, delivery.generation, delivery.reference,
                 delivery.sequence, delivery.token}
              )

              reference = delivery.reference

              assert_receive {:wotex_matter, ^reference, {:error, %Error{code: :transport_closed}}},
                             1_000
          end

          assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
          assert eventually(fn -> not File.exists?("/proc/#{child}") end)
          elapsed = System.monotonic_time(:millisecond) - started
          assert elapsed <= 1_000
          assert Port.info(port) == nil
          assert :ets.info(handle.admission) == :undefined
          refute_receive {:wotex_matter, _, _}, 20

          assert {:ok, reopened} = Native.connect(options)

          try do
            assert {:ok, %{"status" => "ready"}} = Native.health(reopened)
          after
            assert :ok = Native.disconnect(reopened)
          end

          %{
            mode: mode,
            injected_pipe_bytes: bytes,
            cleanup_ms: elapsed,
            durable_reopen: "passed",
            owned_processes_after_grace: 0
          }
        after
          if Port.info(port, :os_pid) == {:os_pid, child},
            do: System.cmd("/bin/kill", ["-KILL", to_string(child)], stderr_to_stdout: true)

          Native.disconnect(handle)
        end
      end

    File.write!(
      Map.fetch!(fixture, "result_path"),
      Jason.encode!(%{status: "passed", observations: observations}),
      [:exclusive]
    )
  end

  defp initial_delivery(handle, path) do
    request = %{
      kind: :attribute,
      paths: [path],
      min_interval_s: 0,
      max_interval_s: 10,
      queue_limit: 64,
      resubscribe: false
    }

    assert {:ok, _} = Native.subscribe_acknowledged(handle, request, self(), 10_000)
    assert_receive {:wotex_matter, _, %Native.Delivery{} = delivery}, 10_000
    delivery
  end

  defp fill_native_input(_, 0, _), do: :limit

  defp fill_native_input(port, remaining, bytes) do
    # The stopped process never parses these bounded fault-injection bytes.
    if Port.command(port, String.duplicate(" ", 16_384), [:nosuspend]),
      do: fill_native_input(port, remaining - 1, bytes + 16_384),
      else: {:busy, bytes}
  end

  defp eventually(function, attempts \\ 100)
  defp eventually(_, 0), do: false

  defp eventually(function, attempts) do
    if function.() do
      true
    else
      Process.sleep(5)
      eventually(function, attempts - 1)
    end
  end
end
