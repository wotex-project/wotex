Code.require_file("../support/software/control_pump.exs", __DIR__)

defmodule Wotex.Matter.NativeControlPumpInteropTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Matter.SoftwareControlPump

  @moduletag :interop
  @moduletag :software
  @moduletag timeout: 60_000
  @generation "0123456789abcdef0123456789abcdef"

  test "WMA-B02 controls remain live during SDK read, subscription and window waits" do
    fixture =
      System.fetch_env!("WOTEX_MATTER_NATIVE_CONTROL_PUMP_FIXTURE")
      |> File.read!()
      |> Jason.decode!()

    controller = Map.fetch!(fixture, "controller")

    observations =
      for operation <- ["read", "subscribe", "open_window"] do
        port =
          Port.open(
            {:spawn_executable, String.to_charlist(controller["executable"])},
            [:binary, :exit_status, :use_stdio, {:line, 131_072}]
          )

        {:os_pid, child} = Port.info(port, :os_pid)

        try do
          assert {%{"event" => "ready"}, _} = frame(port, 1_000)
          send_frame(port, %{version: 1, event: "flow_open", session_generation: @generation})

          parameters =
            controller
            |> Map.take(~w(storage_path vendor_id fabric_id controller_node_id paa_trust_store))
            |> Map.merge(%{
              "lifecycle" => "persistent",
              "storage_mode" => "open_existing",
              "authority" => "stored"
            })

          request(port, "1", "open", parameters)
          assert {%{"id" => "1", "ok" => true}, _} = frame(port, 10_000)

          path = %{
            fabric_id: controller["fabric_id"],
            node_id: fixture["node_id"],
            endpoint: fixture["endpoint"],
            cluster: 6,
            member: 0
          }

          stream = subscription("1", path)
          request(port, "2", "subscribe", stream)
          assert {%{"id" => "2", "ok" => true, "result" => established}, _} = frame(port, 10_000)

          assert {%{"event" => "subscription_report", "report_sequence" => 1} = initial, bytes} =
                   frame(port, 10_000)

          probe =
            @generation
            |> SoftwareControlPump.new(established, path)
            |> SoftwareControlPump.report!(initial, bytes)

          unreachable = Map.put(path, :node_id, fixture["unreachable_node_id"])

          pending =
            case operation do
              "read" ->
                unreachable

              "subscribe" ->
                subscription("2", unreachable)

              "open_window" ->
                %{
                  node_id: unreachable.node_id,
                  timeout_s: 180,
                  iteration_count: 1000,
                  discriminator: 3840
                }
            end

          request(port, "3", operation, pending, 5_000)
          probe = SoftwareControlPump.pending!(port, probe, 250)
          started = System.monotonic_time(:millisecond)
          probe = SoftwareControlPump.acknowledge!(port, probe)

          request(port, "4", "unsubscribe", %{
            subscription_id: established["subscription_id"],
            generation: established["generation"]
          })

          probe = SoftwareControlPump.retired!(port, probe, 500)
          if probe.pending_frames > 0, do: SoftwareControlPump.acknowledge!(port, probe)
          assert {%{"id" => "4", "ok" => true, "result" => nil}, _} = frame(port, 500)
          request(port, "5", "health", %{})
          assert {%{"id" => "5", "ok" => true}, _} = frame(port, 500)
          controls_ms = System.monotonic_time(:millisecond) - started
          assert controls_ms <= 500

          close_started = System.monotonic_time(:millisecond)
          request(port, "close", "close", %{}, 1_000)
          assert {%{"id" => "close", "ok" => true, "result" => nil}, _} = frame(port, 1_000)
          assert_receive {^port, {:exit_status, 0}}, 1_000
          assert gone?(port, child, close_started + 1_000)
          cleanup_ms = System.monotonic_time(:millisecond) - close_started
          assert cleanup_ms <= 1_000
          refute_receive {^port, {:data, _}}, 20

          %{
            operation: operation,
            controls_ms: controls_ms,
            cleanup_ms: cleanup_ms,
            observed_reports: probe.sequence,
            acknowledged_report_bytes: probe.bytes,
            native_exit_status: 0,
            late_replies: 0
          }
        after
          try do
            Port.close(port)
          rescue
            ArgumentError -> :ok
          end

          assert gone?(port, child, System.monotonic_time(:millisecond) + 1_000)
        end
      end

    File.write!(
      fixture["result_path"],
      Jason.encode!(%{status: "passed", observations: observations}),
      [:exclusive]
    )
  end

  defp subscription(id, path) do
    %{
      subscription_id: String.pad_leading(id, 32, "0"),
      kind: "attribute",
      paths: [path],
      min_interval_s: 0,
      max_interval_s: 60,
      resubscribe: false,
      queue_limit: 64
    }
  end

  defp request(port, id, operation, parameters, timeout \\ 10_000) do
    send_frame(port, %{
      version: 1,
      id: id,
      operation: operation,
      parameters: parameters,
      timeout_ms: timeout
    })
  end

  defp send_frame(port, value),
    do: assert(Port.command(port, Jason.encode!(value) <> "\n", [:nosuspend]))

  defp frame(port, timeout) do
    assert_receive {^port, {:data, {:eol, bytes}}}, timeout
    {Jason.decode!(bytes), byte_size(bytes) + 1}
  end

  defp gone?(port, child, deadline) do
    if Port.info(port) == nil and not File.exists?("/proc/#{child}") do
      true
    else
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(1)
        gone?(port, child, deadline)
      else
        false
      end
    end
  end
end
