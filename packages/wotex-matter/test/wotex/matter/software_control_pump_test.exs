Code.require_file("../../support/software/control_pump.exs", __DIR__)

defmodule Wotex.Matter.SoftwareControlPumpTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Matter.SoftwareControlPump

  @generation "0123456789abcdef0123456789abcdef"
  @subscription String.duplicate("1", 32)
  @path %{fabric_id: 1, node_id: 99, endpoint: 1, cluster: 6, member: 0}
  @established %{
    "subscription_id" => @subscription,
    "generation" => 1,
    "sdk_subscription_id" => 17,
    "min_interval_s" => 0,
    "max_interval_s" => 60
  }

  test "pending controls accept bound reports and acknowledge their exact cumulative bytes" do
    with_port(fn port ->
      first = encode(report(1)) <> encode(report(2))
      assert Port.command(port, first)
      started = System.monotonic_time(:millisecond)
      probe = SoftwareControlPump.pending!(port, probe(), 30)
      assert (System.monotonic_time(:millisecond) - started) in 30..1_000
      assert probe.sequence == 2 and probe.bytes == byte_size(first)
      probe = SoftwareControlPump.acknowledge!(port, probe)
      assert read_frame(port) == acknowledgement(2, byte_size(first))

      last = encode(report(3))

      assert Port.command(
               port,
               last <> encode(retirement(3)) <> encode(%{version: 1, id: "4", ok: true})
             )

      probe = SoftwareControlPump.retired!(port, probe, 1_000)
      assert probe.sequence == 3 and probe.bytes == byte_size(first) + byte_size(last)
      assert read_frame(port) == %{"version" => 1, "id" => "4", "ok" => true}
      SoftwareControlPump.acknowledge!(port, probe)
      assert read_frame(port) == acknowledgement(3, probe.bytes)
    end)
  end

  test "early operation replies and foreign, malformed or replayed reports fail the control probe" do
    for frame <- [
          %{"version" => 1, "id" => "3", "ok" => true},
          report(2),
          Map.put(report(1), "session_generation", String.duplicate("2", 32)),
          Map.put(report(1), "generation", 2),
          put_in(report(1), ["metadata", "path", "node_id"], 100),
          put_in(report(1), ["metadata", "sdk_subscription_id"], 18),
          put_in(report(1), ["value", "type"], "u8")
        ] do
      with_port(fn port ->
        assert Port.command(port, encode(frame))

        assert_raise ExUnit.AssertionError, fn ->
          SoftwareControlPump.pending!(port, probe(), 1_000)
        end
      end)
    end
  end

  test "excess unacknowledged reports and a forged retirement cutoff cannot satisfy control liveness" do
    with_port(fn port ->
      assert Port.command(port, Enum.map(1..65, &encode(report(&1))))

      assert_raise ExUnit.AssertionError, fn ->
        SoftwareControlPump.pending!(port, probe(), 1_000)
      end
    end)

    with_port(fn port ->
      assert Port.command(port, encode(report(1)) <> encode(retirement(2)))

      assert_raise ExUnit.AssertionError, fn ->
        SoftwareControlPump.retired!(port, probe(), 1_000)
      end
    end)
  end

  defp probe, do: SoftwareControlPump.new(@generation, @established, @path)

  defp report(sequence) do
    %{
      "version" => 1,
      "event" => "subscription_report",
      "session_generation" => @generation,
      "subscription_id" => @subscription,
      "generation" => 1,
      "report_sequence" => sequence,
      "kind" => "attribute",
      "value" => %{"tag" => "anonymous", "type" => "boolean", "value" => sequence != 1},
      "metadata" => %{
        "path" => Map.new(@path, fn {key, value} -> {Atom.to_string(key), value} end),
        "data_version" => sequence,
        "report_id" => sequence,
        "initial" => sequence == 1,
        "min_interval_s" => 0,
        "max_interval_s" => 60,
        "sdk_subscription_id" => 17
      }
    }
  end

  defp retirement(sequence),
    do: %{
      version: 1,
      event: "stream_retired",
      session_generation: @generation,
      subscription_id: @subscription,
      generation: 1,
      last_report_sequence: sequence
    }

  defp acknowledgement(sequence, bytes),
    do: %{
      "version" => 1,
      "event" => "report_ack",
      "session_generation" => @generation,
      "report_sequence" => sequence,
      "acknowledged_bytes" => bytes
    }

  defp encode(frame), do: Jason.encode!(frame) <> "\n"

  defp read_frame(port) do
    assert_receive {^port, {:data, {:eol, bytes}}}, 1_000
    Jason.decode!(bytes)
  end

  defp with_port(operation) do
    port = Port.open({:spawn_executable, ~c"/bin/cat"}, [:binary, :use_stdio, {:line, 131_072}])

    try do
      operation.(port)
    after
      try do
        Port.close(port)
      rescue
        ArgumentError -> :ok
      end
    end
  end
end
