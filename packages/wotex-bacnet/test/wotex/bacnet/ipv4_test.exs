defmodule Wotex.BACnet.IPv4Test do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.BACnet.{IngressTransport, IPv4, IPv4Packet, StackOwner}
  @moduletag :capture_log

  test "WBA-N04 explicit UDP ports below 47808 carry a real Who-Is datagram" do
    {:ok, peer} = :gen_udp.open(33_021, [:binary, active: false, ip: {127, 0, 0, 1}])
    on_exit(fn -> :gen_udp.close(peer) end)
    destination = {{127, 0, 0, 1}, 33_021}

    assert {:ok, handle} =
             IPv4.connect(
               local_ip: :none,
               local_port: 33_022,
               destination: destination,
               discovery: %{destination: destination, timeout_ms: 20, max_devices: 1}
             )

    on_exit(fn -> IPv4.disconnect(handle) end)
    assert {:ok, []} = IPv4.who_is(handle, nil, nil, 200)
    assert {:ok, {{127, 0, 0, 1}, 33_022, bytes}} = :gen_udp.recv(peer, 0, 200)
    assert {:ok, {:apdu, _, _, <<0x10, 8>>}} = IPv4Packet.decode(bytes)
    assert :ok = IPv4.disconnect(handle)
    assert {:ok, socket} = :gen_udp.open(33_022, active: false)
    :gen_udp.close(socket)
  end

  test "WBA-N04 destination validation preserves explicit IPv4 and port boundaries" do
    for ip <- [{1, 0, 0, 0}, {192, 0, 2, 0}, {223, 255, 255, 255}, {255, 255, 255, 255}],
        port <- [1, 1024, 47_807, 47_808, 65_535],
        do: assert(IngressTransport.is_valid_destination({ip, port}))

    for destination <- [
          nil,
          {{127, 0, 0, 1}, 0},
          {{127, 0, 0, 1}, 65_536},
          {{127, 0, 0, 1}, 1024.0},
          {{127, 0, 0, 1.0}, 1024},
          {{0, 0, 0, 1}, 1024},
          {{224, 0, 0, 1}, 1024},
          {{255, 0, 0, 1}, 1024},
          {{192, 0, 256, 1}, 1024}
        ],
        do: refute(IngressTransport.is_valid_destination(destination))

    assert {:error, :invalid_transport} = IngressTransport.send(nil, nil, <<>>)
    {:ok, socket} = :gen_udp.open(0, active: false)

    assert {:error, :invalid_destination} =
             IngressTransport.send({socket, {255, 255, 255, 255}}, {{127, 0, 0, 1}, 0}, <<16, 8>>)

    :gen_udp.close(socket)

    assert {:error, :closed} =
             IngressTransport.send(
               {socket, {255, 255, 255, 255}},
               {{127, 0, 0, 1}, 1024},
               <<16, 8>>
             )
  end

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
          [local_ip: :none, destination: {{127, 0, 0, 1}, 0}],
          [local_ip: :none, destination: {{0, 0, 0, 0}, 55_809}],
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
