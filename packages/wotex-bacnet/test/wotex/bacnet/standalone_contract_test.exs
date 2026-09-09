defmodule Wotex.BACnet.StandaloneContractTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet
  alias Wotex.BACnet.{BACstack, Error, IPv4, Tags}
  @moduletag :capture_log

  setup do
    {:ok, peer} = :gen_udp.open(55_836, [:binary, active: false, ip: {127, 0, 0, 1}])

    {:ok, session} =
      BACnet.connect(
        client: IPv4,
        local_ip: :none,
        local_port: 55_837,
        destination: {{127, 0, 0, 1}, 55_836},
        timeout: 100
      )

    on_exit(fn ->
      BACnet.disconnect(session)
      :gen_udp.close(peer)
    end)

    %{peer: peer, session: session, owner: session.handle.stack.owner}
  end

  test "WBA-C02 WBA-C03 native deadline entry points reject forged and expired requests without I/O",
       c do
    {:ok, [request] = requests} = Wotex.BACnet.Batch.new(1, 0, [85])
    expired = System.monotonic_time(:millisecond) - 1

    for {client, handle} <- [{IPv4, c.session.handle}, {BACstack, c.session.handle.stack}] do
      assert {:error, %Error{code: :deadline_exceeded, effect: :none}} =
               client.request_deadline(handle, request, expired)

      assert {:error,
              %Error{
                code: :deadline_exceeded,
                details: %{batch_index: 0, completed_count: 0, property: 85}
              }} =
               client.read_properties_deadline(handle, requests, expired)

      assert {:error, %Error{code: :invalid_request}} =
               client.request_deadline(nil, request, expired)

      assert {:error, %Error{code: :invalid_properties}} =
               client.read_properties_deadline(nil, requests, expired)

      assert {:error, %Error{code: :invalid_properties}} =
               client.read_properties(handle, requests, 0)
    end

    assert {:error, %Error{code: :invalid_request}} =
             BACstack.request(c.session.handle.stack, request, 60_001)

    assert map_size(:sys.get_state(c.owner).pending) == 0
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
  end

  test "WBA-N03 optional client callback retains sequential read ownership", c do
    {:ok, requests} = Wotex.BACnet.Batch.new(1, 0, [85])
    call = Task.async(fn -> IPv4.read_properties(c.session.handle, requests, 100) end)
    {invoke, 12, _} = service(c.peer)
    respond(c.peer, invoke, 85, <<0x21, 0>>)
    assert {:ok, %{85 => %Encoding{type: :unsigned_integer, value: 0}}} = Task.await(call)
    assert map_size(:sys.get_state(c.owner).pending) == 0
  end

  test "WBA-N01 WBA-N02 named read and acknowledged write use the original native session", c do
    read = Task.async(fn -> BACnet.read_property(c.session, :analog_output, 0, :present_value) end)
    {invoke, 12, tags} = service(c.peer)
    assert tags == [{:tagged, {0, <<1::10, 0::22>>, 4}}, {:tagged, {1, <<85>>, 1}}]
    respond(c.peer, invoke, 85, <<0x44, 25.5::float-32>>)
    assert {:ok, %Encoding{type: :real, value: 25.5}} = Task.await(read)

    {:ok, value} = Encoding.create({:null, nil})
    write = Task.async(fn -> BACnet.write_property(c.session, 1, 0, 85, value) end)
    {invoke, 15, tags} = service(c.peer)

    assert tags == [
             {:tagged, {0, <<1::10, 0::22>>, 4}},
             {:tagged, {1, <<85>>, 1}},
             {:constructed, {3, {:null, nil}, 0}}
           ]

    send_apdu(c.peer, <<0x20, invoke, 15>>)
    assert :ok = Task.await(write)
    assert Process.alive?(c.owner)
    assert map_size(:sys.get_state(c.owner).pending) == 0
  end

  test "WBA-N03 ordered batch retains one admission reference and one absolute deadline", c do
    batch =
      Task.async(fn ->
        BACnet.read_properties(c.session, 1, 0, [:present_value, :object_name, :units])
      end)

    {first, 12, _} = service(c.peer)
    [{reference, initial}] = Map.to_list(:sys.get_state(c.owner).pending)
    respond(c.peer, first, 85, <<0x10>>)
    {second, 12, tags} = service(c.peer)
    assert List.last(tags) == {:tagged, {1, <<77>>, 1}}
    assert [{^reference, ongoing}] = Map.to_list(:sys.get_state(c.owner).pending)
    assert ongoing.deadline == initial.deadline
    assert ongoing.batch.index == 1
    respond(c.peer, second, 77, <<0x00>>)
    {third, 12, tags} = service(c.peer)
    assert List.last(tags) == {:tagged, {1, <<117>>, 1}}
    assert [{^reference, final}] = Map.to_list(:sys.get_state(c.owner).pending)
    assert final.deadline == initial.deadline
    respond(c.peer, third, 117, <<0x60>>)

    assert {:ok,
            %{
              85 => %Encoding{type: :boolean, value: false},
              77 => %Encoding{type: :null, value: nil},
              117 => %Encoding{type: :octet_string, value: ""}
            }} = Task.await(batch)

    assert map_size(:sys.get_state(c.owner).pending) == 0
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
  end

  test "WBA-N03 WBA-F09 native negative ACK preserves status and never sends the third read", c do
    batch = Task.async(fn -> BACnet.read_properties(c.session, 1, 0, [85, 77, 117]) end)
    {first, 12, _} = service(c.peer)
    respond(c.peer, first, 85, <<0x44, 25.5::float-32>>)
    {second, 12, _} = service(c.peer)
    send_apdu(c.peer, <<0x50, second, 12, 0x91, 2, 0x91, 32>>)

    assert {:error,
            %Error{
              code: :remote_error,
              effect: :none,
              details: %{class: 2, code: 32, batch_index: 1, property: 77, completed_count: 1}
            }} = Task.await(batch)

    assert map_size(:sys.get_state(c.owner).pending) == 0
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 20)
  end

  test "WBA-N03 missing second response expires the batch without requesting later properties", c do
    batch = Task.async(fn -> BACnet.read_properties(c.session, 1, 0, [85, 77, 117]) end)
    {first, 12, _} = service(c.peer)
    respond(c.peer, first, 85, <<0x21, 0>>)
    {_, 12, _} = service(c.peer)

    assert {:error,
            %Error{
              code: :deadline_exceeded,
              effect: :none,
              details: %{batch_index: 1, property: 77, completed_count: 1}
            }} = Task.await(batch)

    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 20)
  end

  test "WBA-N02 WBA-N03 WBA-F08 whole-batch validation and forged adapter inputs acquire nothing",
       c do
    assert {:error, %Error{code: :duplicate_property}} =
             BACnet.read_properties(c.session, 1, 0, [:present_value, 85])

    assert {:error, %Error{code: :invalid_address}} =
             BACnet.read_properties(c.session, 1, 0, [85, -1])

    assert {:error, %Error{code: :invalid_session}} =
             BACnet.read_property(%{c.session | timeout: 0}, 1, 0, 85)

    assert {:error, %Error{code: :invalid_value}} = BACnet.write_property(c.session, 1, 0, 85, 1.5)

    assert {:error, %Error{}} =
             BACstack.read_properties(c.session.handle.stack, [%{property: 85}], 100)

    assert {:error, %Error{}} = BACstack.read_properties(nil, [], 0)
    assert {:error, %Error{}} = IPv4.read_properties(nil, [], 100)
    assert map_size(:sys.get_state(c.owner).pending) == 0
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
  end

  test "WBA-N01 WBA-N03 borrowed client survives an ordered native batch", c do
    client = c.session.handle.stack.client

    {:ok, borrowed} =
      BACnet.connect(
        client: BACstack,
        stack_client: client,
        destination: {{127, 0, 0, 1}, 55_836},
        timeout: 100
      )

    batch = Task.async(fn -> BACnet.read_properties(borrowed, 1, 0, [85, 77]) end)
    {first, 12, _} = service(c.peer)
    respond(c.peer, first, 85, <<0x00>>)
    {second, 12, _} = service(c.peer)
    respond(c.peer, second, 77, <<0x21, 0>>)
    assert {:ok, %{85 => %Encoding{value: nil}, 77 => %Encoding{value: 0}}} = Task.await(batch)
    assert :ok = BACnet.disconnect(borrowed)
    assert Process.alive?(client)
  end

  test "WBA-C03 WBA-N03 caller death during the second read releases the batch and owned stack",
       c do
    batch = Task.async(fn -> BACnet.read_properties(c.session, 1, 0, [85, 77, 117]) end)
    {first, 12, _} = service(c.peer)
    respond(c.peer, first, 85, <<0x00>>)
    {_, 12, _} = service(c.peer)
    [operation] = Map.values(:sys.get_state(c.owner).pending)
    worker = operation.worker
    monitor = Process.monitor(worker)
    stack_monitor = Process.monitor(c.session.handle.owner)
    Process.unlink(batch.pid)
    Process.exit(batch.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1100
    assert_receive {:DOWN, ^stack_monitor, :process, _, _}, 1100
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
  end

  test "WBA-C03 WBA-N03 sixty-four batches own sixty-four slots across their next reads", c do
    session = %{c.session | timeout: 2000}

    batches =
      for _ <- 1..64, do: Task.async(fn -> BACnet.read_properties(session, 1, 0, [85, 77]) end)

    first = for _ <- 1..64, do: service(c.peer)
    assert map_size(:sys.get_state(c.owner).pending) == 64

    assert {:error,
            %Error{
              code: :busy,
              effect: :none,
              details: %{batch_index: 0, completed_count: 0, property: 85}
            }} =
             BACnet.read_properties(session, 1, 0, [85, 77])

    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
    for {invoke, 12, _} <- first, do: respond(c.peer, invoke, 85, <<0x00>>)
    second = for _ <- 1..64, do: service(c.peer)
    assert map_size(:sys.get_state(c.owner).pending) == 64
    for {invoke, 12, _} <- second, do: respond(c.peer, invoke, 77, <<0x10>>)

    for batch <- batches,
        do:
          assert(
            {:ok, %{85 => %Encoding{value: nil}, 77 => %Encoding{value: false}}} = Task.await(batch)
          )

    assert map_size(:sys.get_state(c.owner).pending) == 0
  end

  defp service(peer) do
    assert {:ok, {_, _, <<0x81, 0x0A, _::16, 1, 4, _, _, invoke, service, bytes::binary>>}} =
             :gen_udp.recv(peer, 0, 1000)

    assert {:ok, tags} = Tags.decode(bytes)
    {invoke, service, tags}
  end

  defp respond(peer, invoke, property, value),
    do:
      send_apdu(
        peer,
        <<0x30, invoke, 12, 0x0C, 1::10, 0::22, 0x19, property, 0x3E, value::binary, 0x3F>>
      )

  defp send_apdu(peer, apdu),
    do:
      :gen_udp.send(
        peer,
        {127, 0, 0, 1},
        55_837,
        <<0x81, 0x0A, byte_size(apdu) + 6::16, 1, 4, apdu::binary>>
      )
end
