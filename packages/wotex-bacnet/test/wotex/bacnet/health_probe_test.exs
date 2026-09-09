defmodule Wotex.BACnet.HealthProbeTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.BACnet
  alias Wotex.BACnet.{Error, IPv4, Tags, TestClient}
  @moduletag :capture_log
  @probe %{type: :read_property, object_type: 1, instance: 7, property: 85, array_index: 0}

  setup do
    {:ok, peer} = :gen_udp.open(55_830, [:binary, active: false, ip: {127, 0, 0, 1}])

    {:ok, session} =
      BACnet.connect(
        client: IPv4,
        local_ip: :none,
        local_port: 55_831,
        destination: {{127, 0, 0, 1}, 55_830},
        timeout: 500
      )

    on_exit(fn ->
      BACnet.disconnect(session)
      :gen_udp.close(peer)
    end)

    %{peer: peer, session: session}
  end

  test "WBA-S05 WBA-V12 explicit read probe retains address and accepts typed false/zero/null/empty",
       c do
    for encoded <- [<<0>>, <<0x10>>, <<0x21, 0>>, <<0x60>>, <<>>] do
      task = Task.async(fn -> BACnet.health_check(c.session, @probe) end)
      {invoke, tags} = request(c.peer)

      assert tags == [
               {:tagged, {0, <<1::10, 7::22>>, 4}},
               {:tagged, {1, <<85>>, 1}},
               {:tagged, {2, <<0>>, 1}}
             ]

      response(c.peer, invoke, 7, encoded)
      assert {:ok, :healthy} = Task.await(task)
    end
  end

  test "WBA-S05 WBA-V12 mismatched or malformed read responses cannot report healthy", c do
    for {instance, value} <- [{8, <<0>>}, {7, <<0x44, 0>>}] do
      task = Task.async(fn -> BACnet.health_check(c.session, @probe) end)
      {invoke, _} = request(c.peer)
      response(c.peer, invoke, instance, value)
      assert {:error, %Error{effect: :none}} = Task.await(task)
    end
  end

  test "WBA-S05 WBA-V12 absent probe, write probe, and malformed address emit no APDU", c do
    assert {:error, %Error{code: :probe_required}} = BACnet.health_check(c.session)

    assert {:error, %Error{code: :invalid_health_probe}} =
             BACnet.health_check(c.session, %{@probe | type: :write_property})

    assert {:error, %Error{code: :invalid_health_probe}} = BACnet.health_check(nil, @probe)

    assert {:error, %Error{code: :invalid_address}} =
             BACnet.health_check(c.session, %{@probe | instance: -1})

    assert {:error, %Error{code: :invalid_priority}} =
             BACnet.health_check(c.session, Map.put(@probe, :priority, 1))

    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
    {:ok, session} = BACnet.connect(client: TestClient)
    assert {:error, %Error{code: :invalid_value}} = BACnet.health_check(session, @probe)
    BACnet.disconnect(session)
  end

  test "WBA-S05 WBA-V12 missing response expires the original budget and closes owned work", c do
    task = Task.async(fn -> BACnet.health_check(%{c.session | timeout: 10}, @probe) end)
    {_, _} = request(c.peer)
    assert {:error, %Error{code: :deadline_exceeded}} = Task.await(task)
    assert :ok = BACnet.disconnect(c.session)
    refute Process.alive?(c.session.handle.stack.client)
  end

  test "WBA-S05 WBA-C03 late custom-client success cannot reset the health budget" do
    {:ok, session} = BACnet.connect(client: Wotex.BACnet.Test.HealthPort, timeout: 1)
    assert {:error, %Error{code: :deadline_exceeded}} = BACnet.health_check(session, @probe)
    BACnet.disconnect(session)
  end

  defp request(peer) do
    assert {:ok, {_, _, <<0x81, 0x0A, _::16, 1, 4, _, _, invoke, 12, bytes::binary>>}} =
             :gen_udp.recv(peer, 0, 1000)

    assert {:ok, tags} = Tags.decode(bytes)
    {invoke, tags}
  end

  defp response(peer, invoke, instance, value) do
    apdu =
      <<48, invoke, 12, 0x0C, 1::10, instance::22, 0x19, 85, 0x29, 0, 0x3E, value::binary, 0x3F>>

    :gen_udp.send(
      peer,
      {127, 0, 0, 1},
      55_831,
      <<0x81, 0x0A, byte_size(apdu) + 6::16, 1, 0, apdu::binary>>
    )
  end
end
