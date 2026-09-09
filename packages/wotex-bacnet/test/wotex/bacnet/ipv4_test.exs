defmodule Wotex.BACnet.IPv4Test do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.BACnet.{IPv4, StackOwner}
  @moduletag :capture_log

  test "owned process group starts with no retries, forwards frames and cleans up on disconnect" do
    opts = [local_ip: :none, local_port: 55_808, destination: {{127, 0, 0, 1}, 55_809}, timeout: 20]
    assert {:ok, handle} = IPv4.connect(opts)
    assert {:ok, client} = StackOwner.client(handle.owner)
    state = :sys.get_state(client).sdk
    assert state.opts.apdu_retries == 0

    send(handle.owner, :unrelated)
    owner_state = :sys.get_state(handle.owner)

    refs =
      for key <- [:client, :transport, :segmentator, :segments_store],
          do: Process.monitor(Map.fetch!(owner_state, key))

    assert {:error, _} = IPv4.connect(opts)

    assert {:error, _} =
             IPv4.request(
               handle,
               %{
                 type: :read_property,
                 object_type: :analog_value,
                 instance: 0,
                 property: :present_value
               },
               10
             )

    assert :ok = IPv4.disconnect(handle)
    for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _, _})
    assert :ok = IPv4.disconnect(handle)
    assert {:error, _} = StackOwner.client(handle.owner)
  end

  test "consumer exit and child exit stop the entire group" do
    parent = self()

    task =
      Task.async(fn ->
        {:ok, handle} =
          IPv4.connect(local_ip: :none, local_port: 55_810, destination: {{127, 0, 0, 1}, 55_809})

        send(parent, {:handle, handle})

        receive do
          :done -> :ok
        end
      end)

    assert_receive {:handle, handle}, 1000
    ref = Process.monitor(handle.owner)
    send(task.pid, :done)
    Task.await(task)
    assert_receive {:DOWN, ^ref, :process, _, :normal}

    {:ok, handle} =
      IPv4.connect(local_ip: :none, local_port: 55_810, destination: {{127, 0, 0, 1}, 55_809})

    ref = Process.monitor(handle.owner)
    GenServer.stop(handle.stack.client)
    assert_receive {:DOWN, ^ref, :process, _, :normal}

    for opts <- [
          [],
          [:invalid],
          [local_ip: :none, local_port: 1],
          [local_ip: {999, 0, 0, 1}],
          [local_ip: :none, destination: nil],
          [local_ip: :none, destination: {{127, 0, 0, 1}, 1024}],
          [local_ip: :none, destination: {{127, 0, 0, 0}, 55_809}],
          [
            local_ip: :none,
            local_port: 55_810,
            destination: {{127, 0, 0, 1}, 55_809},
            security_mode: :bacnet_sc
          ],
          [
            local_ip: :none,
            local_port: 55_810,
            destination: {{127, 0, 0, 1}, 55_809},
            destination: {{127, 0, 0, 1}, 55_808}
          ]
        ],
        do: assert(match?({:error, _}, IPv4.connect(opts)))

    assert {:error, _} = IPv4.connect(nil)
  end
end
