defmodule Wotex.Zigbee.NetworkOwnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee

  alias Wotex.Zigbee.{
    Binding,
    Config,
    Error,
    Interview,
    Network,
    Owner,
    Routes,
    TestControlledSerial,
    TestSerialPeer
  }

  alias Wotex.Zigbee.Network.Snapshot

  @device <<0, 8, 7, 6, 5, 4, 3, 2, 1, 0::little-16, 7, 9, 2, 0x1234::little-16, 0x5678::little-16>>
  @network <<0::little-16, 9, 0x1234::little-16, 0::little-16, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6,
             0xA7, 0xA8, 8, 7, 6, 5, 4, 3, 2, 1, 15>>

  test "independent device/network replies produce ordered evidence while preserving indications" do
    {handle, peer} = open()
    call = Task.async(fn -> Zigbee.inspect_network(handle, 1_000) end)
    assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, 0x27>>}
    assert {:error, %Error{kind: :overload}} = Zigbee.inspect_network(handle, 1_000)
    assert {:error, %Error{kind: :overload}} = Zigbee.active_endpoints(handle, 0x1234, 1_000)

    {:ok, interview} =
      Interview.new(peer_ieee: <<1::64>>, route_address: 0x1234, source_endpoint: 1)

    assert {:error, %Error{kind: :overload}} = Zigbee.interview(handle, interview, 1_000)
    {:ok, routes} = Routes.new(handle.epoch)

    {:ok, bind} =
      Binding.new(
        operation: :bind,
        peer_ieee: <<1::64>>,
        route_address: 0x1234,
        source_endpoint: 1,
        cluster: 6,
        target: {:group, 1},
        correlation_id: "bind"
      )

    assert {:error, %Error{kind: :overload}} = Zigbee.change_binding(handle, routes, bind, 1_000)
    send(peer, {:inject, wire(0x45, 0xA1, <<0x1234::little-16, 0>>) <> wire(0x67, 0, @device)})
    assert_receive {:serial_write, <<0xFE, 0, 0x25, 0x50, 0x75>>}
    assert Task.yield(call, 10) == nil
    assert {:ok, %{events: [%{kind: :zdo_bind}]}} = Zigbee.drain_events(handle, 128)
    assert {:error, %Error{kind: :overload}} = Zigbee.active_endpoints(handle, 0x1234, 1_000)
    send(peer, {:inject, wire(0x65, 0x50, @network)})

    assert {:ok, %Snapshot{outcome: :observed, consistency: :matching} = snapshot} =
             Task.await(call)

    assert snapshot.owner_epoch == handle.epoch
    assert Snapshot.valid?(snapshot)
    [first, second] = snapshot.readings
    assert first.payload == @device
    assert first.value.associated_routes == [0x1234, 0x5678]
    assert second.payload == @network
    assert first.observed_at_ms <= second.observed_at_ms
    assert second.value.extended_pan_id == <<0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8>>
    refute Map.has_key?(second.value, :status)
    refute_receive {:serial_write, _}, 10
    assert :ok = Zigbee.close(handle)
  end

  test "changed and uninitialized network metadata stays visible without opening or resetting" do
    {handle, peer} = open()
    call = Task.async(fn -> Zigbee.inspect_network(handle, 1_000) end)
    assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}
    send(peer, {:inject, wire(0x67, 0, @device)})
    assert_receive {:serial_write, <<0xFE, 0, 0x25, 0x50, _>>}
    send(peer, {:inject, wire(0x65, 0x50, :binary.copy(<<255>>, 24))})
    assert {:ok, %Snapshot{outcome: :observed, consistency: :changed} = snapshot} = Task.await(call)
    assert List.last(snapshot.readings).value.channel == 255
    assert List.last(snapshot.readings).value.pan_id == 65_535
    assert {:ok, _} = Zigbee.handle(handle.owner)
    refute_receive {:serial_write, _}, 10
  end

  test "nonzero device status returns partial evidence without issuing network-info" do
    {handle, peer} = open()
    call = Task.async(fn -> Zigbee.inspect_network(handle, 1_000) end)
    assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}
    <<_, tail::binary>> = @device
    send(peer, {:inject, wire(0x67, 0, <<2, tail::binary>>)})

    assert {:ok, %Snapshot{outcome: :partial, issue: :status_failure, readings: [reading]}} =
             Task.await(call)

    assert reading.value.status == 2
    assert {:ok, _} = Zigbee.handle(handle.owner)
    refute_receive {:serial_write, _}, 10
  end

  test "ordinary raw query admission and malformed handles/timeouts fail before I/O" do
    {handle, _} = open()

    for phase <- [:device_info, :network_info] do
      {:ok, frame} = Network.frame(phase)
      assert {:error, %Error{kind: :invalid_command}} = Owner.call(handle, :command, [frame, 1_000])
    end

    for timeout <- [nil, 0, 1_001, "credential-canary"] do
      assert {:error, %Error{kind: :invalid_value} = error} =
               Zigbee.inspect_network(handle, timeout)

      refute inspect(error) =~ "credential-canary"
    end

    assert {:error, %Error{kind: :stale_handle}} = Zigbee.inspect_network(nil, 1_000)

    assert {:error, %Error{kind: :stale_handle}} =
             Zigbee.inspect_network(%{handle | epoch: make_ref()}, 1_000)

    assert {:ok, _} = Zigbee.handle(handle.owner)
    refute_receive {:serial_write, _}, 10
  end

  test "queued expiry before the first write preserves a usable owner" do
    {handle, _} = open()
    :ok = :sys.suspend(handle.owner)
    call = Task.async(fn -> Zigbee.inspect_network(handle, 20) end)

    wait_message(handle.owner, fn message ->
      match?({:"$gen_call", _, {:network, _, _}}, message)
    end)

    Process.sleep(25)
    :ok = :sys.resume(handle.owner)
    assert {:error, %Error{kind: :timeout}} = Task.await(call)
    assert {:ok, _} = Zigbee.handle(handle.owner)
    refute_receive {:serial_write, _}, 10
  end

  test "expiry or serial loss after either write retains only observed readings and closes" do
    for first_read <- [false, true], ending <- [:timeout, :disconnect] do
      {handle, peer} = open()
      monitor = Process.monitor(handle.owner)
      call = Task.async(fn -> Zigbee.inspect_network(handle, 80) end)
      assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}

      if first_read do
        send(peer, {:inject, wire(0x67, 0, @device)})
        assert_receive {:serial_write, <<0xFE, 0, 0x25, 0x50, _>>}
      end

      if ending == :disconnect, do: send(peer, {:disconnect, "credential-canary"})
      expected = if ending == :timeout, do: :timeout, else: :coordinator_lost
      assert {:ok, %Snapshot{outcome: :partial, issue: ^expected} = snapshot} = Task.await(call)
      assert length(snapshot.readings) == if(first_read, do: 1, else: 0)
      assert Snapshot.valid?(snapshot)
      refute inspect(snapshot) =~ "credential-canary"
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
    end
  end

  test "a valid network reply queued past the original deadline cannot finish inspection" do
    {handle, peer} = open()
    monitor = Process.monitor(handle.owner)
    call = Task.async(fn -> Zigbee.inspect_network(handle, 80) end)
    assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}
    send(peer, {:inject, wire(0x67, 0, @device)})
    assert_receive {:serial_write, <<0xFE, 0, 0x25, 0x50, _>>}
    deadline = :sys.get_state(handle.owner).network.deadline
    :ok = :sys.suspend(handle.owner)
    send(peer, {:inject, wire(0x65, 0x50, @network)})
    wait_message(handle.owner, fn message -> match?({:zigbee_serial, _, _}, message) end)
    Process.sleep(max(0, deadline - System.monotonic_time(:millisecond) + 5))
    :ok = :sys.resume(handle.owner)
    assert {:ok, %Snapshot{outcome: :partial, issue: :timeout, readings: [_]}} = Task.await(call)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
  end

  test "wrong and malformed replies terminate without matching a later request" do
    for stage <- [:device, :network], payload <- [<<>>, <<0>>, <<0, 0>>] do
      {handle, peer} = open()
      monitor = Process.monitor(handle.owner)
      call = Task.async(fn -> Zigbee.inspect_network(handle, 1_000) end)
      assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}

      if stage == :network do
        send(peer, {:inject, wire(0x67, 0, @device)})
        assert_receive {:serial_write, <<0xFE, 0, 0x25, 0x50, _>>}
      end

      command = if stage == :device, do: 0x67, else: 0x65
      id = if stage == :device, do: 0, else: 0x50
      send(peer, {:inject, wire(command, id, payload)})

      assert {:ok, %Snapshot{outcome: :partial, issue: :invalid_frame} = snapshot} =
               Task.await(call)

      assert length(snapshot.readings) == if(stage == :device, do: 0, else: 1)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
    end

    {handle, peer} = open()
    call = Task.async(fn -> Zigbee.inspect_network(handle, 1_000) end)
    assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}
    send(peer, {:inject, wire(0x65, 0x50, @network)})
    assert {:ok, %Snapshot{issue: :invalid_frame, readings: []}} = Task.await(call)
  end

  test "pending caller death after either query ends the owner" do
    for first_read <- [false, true] do
      {handle, peer} = open()
      monitor = Process.monitor(handle.owner)
      caller = spawn(fn -> Zigbee.inspect_network(handle, 1_000) end)
      assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}

      if first_read do
        send(peer, {:inject, wire(0x67, 0, @device)})
        assert_receive {:serial_write, <<0xFE, 0, 0x25, 0x50, _>>}
      end

      Process.exit(caller, :kill)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
    end
  end

  test "a queued reply cannot advance or finish inspection after its caller dies" do
    for final <- [false, true] do
      {handle, peer} = open()
      owner_monitor = Process.monitor(handle.owner)
      peer_monitor = Process.monitor(peer)
      caller = spawn(fn -> Zigbee.inspect_network(handle, 1_000) end)
      assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}

      if final do
        send(peer, {:inject, wire(0x67, 0, @device)})
        assert_receive {:serial_write, <<0xFE, 0, 0x25, 0x50, _>>}
      end

      :ok = :sys.suspend(handle.owner)
      response = if final, do: wire(0x65, 0x50, @network), else: wire(0x67, 0, @device)
      send(peer, {:inject, response})
      wait_message(handle.owner, fn message -> match?({:zigbee_serial, _, _}, message) end)
      caller_monitor = Process.monitor(caller)
      Process.exit(caller, :kill)
      assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :killed}
      :ok = :sys.resume(handle.owner)
      assert_receive {:DOWN, ^owner_monitor, :process, _, :normal}
      assert_receive {:DOWN, ^peer_monitor, :process, _, :normal}
      refute_receive {:serial_write, _}, 10
    end
  end

  test "write faults and explicit close return partial redacted observations" do
    for behavior <- [:raise, :throw, :exit, :malformed, :error, {:delay, 50}] do
      {handle, _} = open(serial: TestControlledSerial, write_behavior: behavior)
      monitor = Process.monitor(handle.owner)
      timeout = if is_tuple(behavior), do: 20, else: 1_000

      assert {:ok, %Snapshot{outcome: :partial, readings: []} = snapshot} =
               Zigbee.inspect_network(handle, timeout)

      assert snapshot.issue == if(is_tuple(behavior), do: :timeout, else: :serial)
      refute inspect(snapshot) =~ "credential-canary"
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
      if is_tuple(behavior), do: assert_receive({:serial_write, <<0xFE, 0, 0x27, 0, _>>})
    end

    {handle, peer} = open()
    call = Task.async(fn -> Zigbee.inspect_network(handle, 1_000) end)
    assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}
    send(peer, {:inject, wire(0x67, 0, @device)})
    assert_receive {:serial_write, <<0xFE, 0, 0x25, 0x50, _>>}
    assert :ok = Zigbee.close(handle)

    assert {:ok, %Snapshot{outcome: :partial, issue: :coordinator_lost, readings: [_]}} =
             Task.await(call)
  end

  defp open(options \\ []) do
    {:ok, config} =
      Config.new(
        serial: Keyword.get(options, :serial, TestSerialPeer),
        device_id: "simulated-coordinator",
        expected_version: {2, 0, 3, 2, 0},
        timeout_ms: 1_000,
        serial_options: [
          test_pid: self(),
          drop_reply: true,
          write_behavior: Keyword.get(options, :write_behavior, :ok)
        ]
      )

    {:ok, handle} = Zigbee.open(config)
    on_exit(fn -> Zigbee.close(handle) end)
    assert_receive {:serial_open, peer, _}
    assert_receive {:serial_write, <<0xFE, 0, 0x21, 2, _>>}
    {handle, peer}
  end

  defp wire(command, id, payload) do
    body = <<byte_size(payload), command, id, payload::binary>>
    checksum = Enum.reduce(:binary.bin_to_list(body), 0, &Bitwise.bxor/2)
    <<0xFE, body::binary, checksum>>
  end

  defp wait_message(owner, predicate, attempts \\ 200)

  defp wait_message(owner, predicate, attempts) when attempts > 0 do
    {:messages, messages} = Process.info(owner, :messages)

    if Enum.any?(messages, predicate) do
      :ok
    else
      Process.sleep(1)
      wait_message(owner, predicate, attempts - 1)
    end
  end

  defp wait_message(_, _, 0), do: flunk("network inspection message was not queued")
end
