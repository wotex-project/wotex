defmodule Wotex.BACnet.LifecycleStressTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.{CharacterString, IPv4}
  @moduletag :software
  @moduletag :capture_log
  @moduletag timeout: 120_000
  @cases Jason.decode!(File.read!(Path.expand("../fixtures/read_write_software_v1.json", __DIR__)))[
           "cases"
         ]
  @read %{type: :read_property, object_type: 1, instance: 1, property: 85}

  setup do
    port = System.fetch_env!("WOTEX_BACNET_INTEROP_PORT") |> String.to_integer()
    %{destination: {{127, 0, 0, 1}, port}}
  end

  test "WBA-S02 WBA-S03 WBA-V14 1000 sequential and32 concurrent independent C-stack reads", %{
    destination: destination
  } do
    row = Enum.find(@cases, &(&1["id"] == "WBA-ST01"))
    sequential = row["input"]["sequential_reads"]
    concurrent = row["input"]["concurrent_reads"]
    {:ok, handle} = connect(destination)
    on_exit(fn -> IPv4.disconnect(handle) end)
    resources = resources(handle)
    before = memory(resources)

    for _ <- 1..sequential do
      assert {:ok, %Encoding{type: :real}} = IPv4.request(handle, @read, 3000)
      assert_idle(handle, row["expected"])
    end

    tasks =
      for index <- 1..concurrent do
        property = if rem(index, 2) == 0, do: 85, else: 77
        {property, Task.async(fn -> IPv4.request(handle, %{@read | property: property}, 3000) end)}
      end

    for {property, task} <- tasks do
      if property == 85 do
        assert {:ok, %Encoding{type: :real}} = Task.await(task, 4000)
      else
        assert {:ok,
                %Encoding{
                  type: :character_string,
                  value: %CharacterString{character_set: 0, bytes: name}
                }} = Task.await(task, 4000)

        assert is_binary(name) and byte_size(name) > 0
      end
    end

    assert_idle(handle, row["expected"])
    after_memory = memory(resources)
    close_and_assert(handle, resources)

    assert Enum.count(resources.processes, &Process.alive?/1) ==
             row["expected"]["active_owned_resources"]

    report(
      "WBA-ST01",
      %{
        case: "WBA-ST01",
        sequential: sequential,
        concurrent: concurrent,
        tracked_process_bytes_before: before,
        tracked_process_bytes_after: after_memory,
        active_owned_resources: 0,
        subscription_cycles: "inapplicable_to_read_write_profile"
      }
    )
  end

  test "WBA-S03 WBA-V14 100 real stack lifecycles close all tracked processes and UDP ports", %{
    destination: destination
  } do
    row = Enum.find(@cases, &(&1["id"] == "WBA-ST02"))
    cycles = row["input"]["open_read_close_cycles"]

    for _ <- 1..cycles do
      {:ok, handle} = connect(destination)
      resources = resources(handle)
      assert {:ok, %Encoding{type: :real}} = IPv4.request(handle, @read, 3000)
      assert_idle(handle)
      close_and_assert(handle, resources)

      assert Enum.count(resources.processes, &Process.alive?/1) ==
               row["expected"]["active_owned_resources_after_each_cycle"]
    end

    report("WBA-ST02", %{case: "WBA-ST02", cycles: cycles, active_owned_resources: 0})
  end

  defp report(name, data) do
    directory = System.fetch_env!("WOTEX_BACNET_RESULTS_DIR")
    File.write!(Path.join(directory, name <> ".json"), Jason.encode!(data, pretty: true))
  end

  defp connect(destination),
    do: IPv4.connect(local_ip: :none, local_port: 55_822, destination: destination, timeout: 3000)

  defp resources(handle) do
    state = :sys.get_state(handle.owner)

    %{
      processes: [
        handle.owner,
        handle.stack.owner,
        state.client,
        state.transport,
        state.segmentator,
        state.segments_store
      ],
      socket: state.portal
    }
  end

  defp assert_idle(
         handle,
         expected \\ %{
           "pending_operations" => 0,
           "pending_apdus" => 0,
           "active_segment_sequences" => 0
         }
       ) do
    state = :sys.get_state(handle.owner)
    assert map_size(:sys.get_state(handle.stack.owner).pending) == expected["pending_operations"]
    assert map_size(:sys.get_state(state.client).apdu_timers) == expected["pending_apdus"]

    assert map_size(:sys.get_state(state.segments_store).sequences) ==
             expected["active_segment_sequences"]

    assert map_size(:sys.get_state(state.segmentator).sequences) ==
             expected["active_segment_sequences"]
  end

  defp close_and_assert(handle, resources) do
    monitors = Enum.map(resources.processes, &Process.monitor/1)
    assert :ok = IPv4.disconnect(handle)
    for reference <- monitors, do: assert_receive({:DOWN, ^reference, :process, _, _}, 1000)
    assert :erlang.port_info(resources.socket) == :undefined
    {:ok, rebound} = :gen_udp.open(55_822, [:binary])
    :gen_udp.close(rebound)
  end

  defp memory(resources),
    do: Enum.sum(Enum.map(resources.processes, fn pid -> elem(Process.info(pid, :memory), 1) end))
end
