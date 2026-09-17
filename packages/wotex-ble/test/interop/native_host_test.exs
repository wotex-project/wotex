defmodule Wotex.BLE.NativeHostTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.BLE.BlueZ.Artifacts
  alias Wotex.BLE.NativeProcesses

  @moduletag :interop
  @root Path.expand("../..", __DIR__)
  @grace 1000
  @cases @root
         |> Path.join("priv/fixtures/native-port-v1.json")
         |> File.read!()
         |> Jason.decode!()
         |> Map.fetch!("cases")
         |> Map.new(&{&1["id"], &1})

  setup_all do
    workspace = System.get_env("WOTEX_BLE_NATIVE_WORKSPACE")

    assert is_binary(workspace) and Path.type(workspace) == :absolute and File.dir?(workspace),
           "selected native host lane requires WOTEX_BLE_NATIVE_WORKSPACE"

    manifest = Jason.decode!(File.read!(Path.join(workspace, "native-manifest.json")))
    assert manifest["schema"] == "wotex.native-build" and manifest["package"] == "wotex_ble"
    binaries = Map.new(manifest["binaries"], &{&1["purpose"], &1})
    host = Path.join(workspace, binaries["sdk_host"]["path"])
    guardian = Path.join(workspace, binaries["runtime_guardian"]["path"])

    assert {:ok, _} =
             Artifacts.verify(
               [
                 executable: host,
                 executable_sha256: binaries["sdk_host"]["sha256"],
                 guardian: guardian,
                 guardian_sha256: binaries["runtime_guardian"]["sha256"]
               ],
               System.monotonic_time(:millisecond) + 5000
             )

    {:ok, host: host, guardian: guardian}
  end

  test "WBL-B-F06 the built host emits its ready frame and releases owned processes", context do
    fixture = @cases["WBL-B-F06"]
    assert fixture["input"] == %{"stdin" => "close_after_ready"}
    session = start(context)
    assert [frame] = session.frames
    owned = [session.guardian | NativeProcesses.children(session.guardian)]
    assert length(owned) == 2
    Port.close(session.port)

    projection = %{
      "frame" => Jason.decode!(frame),
      "owned_processes_after_grace" => survivors(owned)
    }

    assert projection == fixture["expectation"]["value"]
  end

  test "WBL-B02 every byte split of initialization and open yields the coalesced result",
       context do
    stream = initialization("unix:path=/nonexistent/wotex-ble-private-bus")
    baseline = exchange(context, [stream])
    assert {[reply], 1, 0} = baseline

    assert Jason.decode!(reply) == %{
             "version" => 1,
             "id" => "open",
             "ok" => false,
             "error" => %{"code" => "transport_unavailable"}
           }

    for split <- 1..(byte_size(stream) - 1) do
      first = binary_part(stream, 0, split)
      second = binary_part(stream, split, byte_size(stream) - split)
      assert exchange(context, [first, second]) == baseline, "split at byte #{split}"
    end
  end

  test "WBL-B02 malformed, oversized, replayed and truncated input closes the generation",
       context do
    flow = frame(%{"version" => 1, "event" => "flow_open", "session_generation" => generation()})

    assert {[], 1, 0} = exchange(context, [~s({"version":1,\n)])
    assert {[], 1, 0} = exchange(context, [:binary.copy("a", 131_073)])
    assert {[], 1, 0} = exchange(context, [flow, flow])

    assert {[], 1, 0} =
             exchange(context, [flow, frame(request("1", "discover", %{}))])

    assert {[], 1, 0} =
             exchange(context, [flow <> ~s({"version":1,"version":1,"id":"open"}\n)])

    session = start(context)
    owned = [session.guardian | NativeProcesses.children(session.guardian)]
    Port.command(session.port, flow <> binary_part(initialization("unix:path=/x"), 0, 40))
    Port.close(session.port)
    assert survivors(owned) == 0
  end

  defp exchange(context, writes) do
    session = start(context)
    owned = [session.guardian | NativeProcesses.children(session.guardian)]

    Enum.each(writes, fn bytes ->
      Port.command(session.port, bytes)
      Process.sleep(2)
    end)

    {frames, status} = finish(session.port, "", [], deadline(5000))
    {frames, status, survivors(owned)}
  end

  defp start(context) do
    port =
      Port.open({:spawn_executable, context.guardian}, [
        :binary,
        :exit_status,
        args: ["500", "131072", "65536", Path.dirname(context.host), context.host],
        env: Enum.map(System.get_env(), fn {key, _} -> {String.to_charlist(key), false} end)
      ])

    {:os_pid, guardian} = Port.info(port, :os_pid)
    {[ready], rest} = lines(port, "", 1, deadline(5000))
    %{port: port, guardian: guardian, frames: [ready], buffer: rest}
  end

  defp lines(_, buffer, 0, _), do: {[], buffer}

  defp lines(port, buffer, count, deadline) do
    case String.split(buffer, "\n", parts: 2) do
      [line, rest] ->
        {found, remaining} = lines(port, rest, count - 1, deadline)
        {[line | found], remaining}

      [_] ->
        receive do
          {^port, {:data, bytes}} -> lines(port, buffer <> bytes, count, deadline)
        after
          remaining(deadline) -> flunk("native host did not emit #{count} frame(s)")
        end
    end
  end

  defp finish(port, buffer, frames, deadline) do
    receive do
      {^port, {:data, bytes}} ->
        {complete, rest} = split(buffer <> bytes)
        finish(port, rest, frames ++ complete, deadline)

      {^port, {:exit_status, status}} ->
        assert buffer == ""
        {frames, status}
    after
      remaining(deadline) -> flunk("native host did not exit")
    end
  end

  defp split(bytes) do
    parts = String.split(bytes, "\n")
    {Enum.drop(parts, -1), List.last(parts)}
  end

  defp survivors(pids) do
    stop = deadline(@grace)
    wait_gone(pids, stop)
    Enum.count(pids, &NativeProcesses.alive?/1)
  end

  defp wait_gone(pids, stop) do
    if Enum.any?(pids, &NativeProcesses.alive?/1) and remaining(stop) > 0 do
      Process.sleep(10)
      wait_gone(pids, stop)
    end
  end

  defp initialization(bus_address) do
    frame(%{"version" => 1, "event" => "flow_open", "session_generation" => generation()}) <>
      frame(
        request("open", "open", %{
          "peer" => %{
            "adapter" => "/org/bluez/hci0",
            "address" => "AA:BB:CC:DD:EE:FF",
            "address_type" => "random"
          },
          "connection" => "borrowed",
          "bus_address" => bus_address
        })
      )
  end

  defp request(id, operation, parameters) do
    %{
      "version" => 1,
      "id" => id,
      "operation" => operation,
      "parameters" => parameters,
      "timeout_ms" => 2000
    }
  end

  defp frame(value), do: Jason.encode!(value) <> "\n"
  defp generation, do: "0123456789abcdef0123456789abcdef"
  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
