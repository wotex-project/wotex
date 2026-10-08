defmodule Wotex.Zigbee.OwnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee
  alias Wotex.Zigbee.{Command, Config, Error, Event, Frame, Handle, Owner, Reply, TestSerialPeer}

  test "startup checks the exact firmware version and selected serial identity" do
    {:ok, config} = config()
    assert {:ok, %Handle{} = handle} = Zigbee.open(config)
    assert_receive {:serial_open, peer, options}
    assert Keyword.fetch!(options, :baud_rate) == 115_200
    assert Keyword.fetch!(options, :flow_control) == :none
    assert_receive {:serial_write, <<0xFE, 0, 0x21, 2, 0x23>>}
    assert is_pid(peer)
    assert :ok = Zigbee.close(handle)
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.drain_events(handle, 1)

    {:ok, wrong_version} = config(serial_options: [test_pid: self(), version: {2, 0, 2, 0, 0}])
    assert {:error, %Error{kind: :version_mismatch}} = Zigbee.open(wrong_version)

    {:ok, wrong_identity} = config(device_id: "other-coordinator")
    assert {:error, %Error{kind: :serial}} = Zigbee.open(wrong_identity)
  end

  test "ZDO request acceptance and later APS confirmation remain distinct" do
    {:ok, handle} = open()
    on_exit(fn -> Zigbee.close(handle) end)

    assert {:ok, %Reply{subsystem: 5, id: 5, status: 0}} =
             Zigbee.active_endpoints(handle, 0x1234, 100)

    assert {:ok, %Reply{subsystem: 5, id: 4, status: 0}} =
             Zigbee.simple_descriptor(handle, 0x1234, 1, 100)

    assert {:ok, %Reply{subsystem: 4, id: 1, status: 0}} =
             Zigbee.send_data(handle, 0x1234, 2, 1, 0x0006, 7, <<1, 2>>, 100)

    assert_event_count(handle, 1)

    assert {:ok, %{events: [%Event{kind: :aps_confirm, transaction: 7, status: 0}], dropped: 0}} =
             Zigbee.drain_events(handle, 8)
  end

  test "serial fragments, checksum faults and queue overflow are observable" do
    {:ok, handle} = open(max_events: 2)
    on_exit(fn -> Zigbee.close(handle) end)
    assert_receive {:serial_open, peer, _}

    {:ok, event} =
      Frame.encode(%Frame{
        type: :areq,
        subsystem: 5,
        id: 0x85,
        payload: <<0x1234::little-16, 0, 0x1234::little-16, 1, 2>>
      })

    send(peer, {:inject, <<0, 1, 2, 0xFE, 0, 0x45, 0x85, 0>>})
    send(peer, {:inject, event <> event <> event})

    assert_event_count(handle, 2)

    assert {:ok, %{events: events, dropped: 1, framing_faults: faults}} =
             Zigbee.drain_events(handle, 2)

    assert Enum.all?(events, &match?(%Event{kind: :zdo_active_endpoints}, &1))
    assert faults > 0
    assert {:ok, %{events: [], dropped: 0}} = Zigbee.drain_events(handle, 2)
  end

  test "command timeout ends the epoch instead of reusing an uncorrelated SRSP" do
    {:ok, handle} = open(serial_options: [test_pid: self(), drop_reply: true])
    assert {:error, %Error{kind: :timeout}} = Zigbee.active_endpoints(handle, 0x1234, 20)

    assert {:error, %Error{kind: :coordinator_lost}} =
             Zigbee.simple_descriptor(handle, 0x1234, 1, 20)
  end

  test "unsupported values and raw administration are rejected before serial I/O" do
    assert {:error, %Error{kind: :invalid_config}} = Config.new(serial: TestSerialPeer)
    assert {:error, %Error{kind: :invalid_command}} = Command.active_endpoints(0xFFFF)
    assert {:error, %Error{kind: :invalid_command}} = Command.simple_descriptor(1, 0)

    assert {:error, %Error{kind: :invalid_command}} =
             Command.data_request(1, 1, 1, 6, 1, :binary.copy(<<0>>, 129))

    assert {:error, %Error{kind: :invalid_command}} =
             Command.data_request(1, 1, 1, 6, 1, <<>>, radius: 1, radius: 2)

    {:ok, handle} = open()
    on_exit(fn -> Zigbee.close(handle) end)
    assert {:error, %Error{kind: :invalid_command}} = Zigbee.active_endpoints(handle, -1, 100)
    assert {:error, %Error{kind: :invalid_value}} = Zigbee.drain_events(handle, 0)
    assert {:error, %Error{kind: :invalid_value}} = Zigbee.active_endpoints(handle, 1, 0)
  end

  test "supervised startup, handle retrieval and explicit close use the same epoch" do
    {:ok, config} = config()

    assert %{start: {Owner, :start_link, [^config]}, restart: :transient} =
             Zigbee.child_spec(config)

    owner = start_supervised!(Zigbee.child_spec(config, restart: :temporary))
    assert_receive {:serial_open, _peer, _}
    assert {:ok, %Handle{owner: ^owner} = handle} = eventually_handle(owner)
    assert {:ok, %Handle{epoch: epoch}} = Zigbee.handle(owner)
    assert epoch == handle.epoch
    assert :ok = Zigbee.close(handle)
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.handle(owner)
  end

  test "version silence, serial removal and serial buffer exhaustion end ownership" do
    {:ok, silent} = config(timeout_ms: 20, serial_options: [test_pid: self(), drop_version: true])
    assert {:error, %Error{kind: :timeout}} = Zigbee.open(silent)
    assert_receive {:serial_open, _silent_peer, _}

    {:ok, %Handle{} = handle} = open()
    assert_receive {:serial_open, peer, _}
    owner = handle.owner
    monitor = Process.monitor(owner)
    send(peer, {:disconnect, :removed})
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.drain_events(handle, 1)

    {:ok, limited} = open(max_buffer_bytes: 10)
    assert_receive {:serial_open, peer2, _}
    monitor2 = Process.monitor(limited.owner)
    send(peer2, {:inject, :binary.copy(<<0xAA>>, 11)})
    assert_receive {:DOWN, ^monitor2, :process, _, :normal}
  end

  test "one pending request rejects concurrent work and a mismatched SRSP kills the epoch" do
    {:ok, handle} = open(serial_options: [test_pid: self(), drop_reply: true])
    assert_receive {:serial_open, peer, _}
    pending = Task.async(fn -> Zigbee.active_endpoints(handle, 0x1234, 100) end)
    assert_receive {:serial_write, <<0xFE, 4, 0x25, 5, _::binary>>}
    assert {:error, %Error{kind: :overload}} = Zigbee.simple_descriptor(handle, 1, 1, 100)
    {:ok, wrong_reply} = Frame.encode(%Frame{type: :srsp, subsystem: 5, id: 4, payload: <<0>>})
    send(peer, {:inject, wrong_reply})
    assert {:error, %Error{kind: :invalid_frame}} = Task.await(pending)
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.active_endpoints(handle, 1, 100)
  end

  test "stale epochs cannot close, drain or command a live coordinator" do
    {:ok, %Handle{} = handle} = open()
    on_exit(fn -> Zigbee.close(handle) end)
    stale = %Handle{handle | epoch: make_ref()}
    assert {:error, %Error{kind: :stale_handle}} = Zigbee.close(stale)
    assert {:error, %Error{kind: :stale_handle}} = Zigbee.drain_events(stale, 1)
    assert {:error, %Error{kind: :stale_handle}} = Zigbee.active_endpoints(stale, 1, 100)
    assert {:error, %Error{kind: :stale_handle}} = Owner.call(:invalid, :drain, [1])
    assert {:error, %Error{kind: :invalid_config}} = Zigbee.open(:invalid)

    assert Error.message(%Error{kind: :timeout, operation: :command}) ==
             "Zigbee command failed: timeout"
  end

  test "identity and node requests expose NCP admission separately from later peer bytes" do
    {:ok, handle} = open()
    on_exit(fn -> Zigbee.close(handle) end)
    assert_receive {:serial_open, peer, _}
    assert {:ok, %Reply{status: 0, id: 1}} = Zigbee.ieee_address(handle, 0x1234, 100)
    assert_receive {:serial_write, <<0xFE, 4, 0x25, 1, 0x34, 0x12, 0, 0, 6>>}
    assert {:ok, %{events: []}} = Zigbee.drain_events(handle, 10)
    assert {:ok, %Reply{status: 0, id: 2}} = Zigbee.node_descriptor(handle, 0x1234, 100)
    assert_receive {:serial_write, <<0xFE, 4, 0x25, 2, 0x34, 0x12, 0x34, 0x12, 0x23>>}

    identity = <<0, 8, 7, 6, 5, 4, 3, 2, 1, 0x34, 0x12, 0, 0>>
    raw_node = <<2, 0x40, 0x80, 0x1234::little-16, 80, 128::little-16, 0::16, 128::little-16, 0>>
    node = <<0x1234::little-16, 0, 0x1234::little-16, raw_node::binary>>
    send(peer, {:inject, peer_frame(0x45, 0x81, identity) <> peer_frame(0x45, 0x82, node)})
    assert_event_count(handle, 2)

    assert {:ok, %{events: [ieee, descriptor]}} = Zigbee.drain_events(handle, 10)
    assert ieee.kind == :zdo_ieee_address
    assert ieee.zdo.peer_ieee == <<8, 7, 6, 5, 4, 3, 2, 1>>
    assert descriptor.kind == :zdo_node_descriptor
    assert descriptor.zdo.descriptor.logical_type == 2
    assert descriptor.zdo.raw_descriptor == raw_node
  end

  test "ordinary owner calls reject raw administration and malformed profile frames before serial I/O" do
    {:ok, handle} = open()
    on_exit(fn -> Zigbee.close(handle) end)
    assert_receive {:serial_open, _peer, _}
    assert_receive {:serial_write, <<0xFE, 0, 0x21, 2, 0x23>>}

    for frame <- [
          %Frame{type: :sreq, subsystem: 5, id: 0x36, payload: <<0, 0, 0, 254, 1>>},
          %Frame{type: :sreq, subsystem: 1, id: 9, payload: "credential-canary"},
          %Frame{type: :sreq, subsystem: 5, id: 1, payload: <<0x1234::little-16, 1, 0>>},
          %Frame{
            type: :sreq,
            subsystem: 5,
            id: 2,
            payload: <<0x1234::little-16, 0x5678::little-16>>
          }
        ] do
      assert {:error, %Error{kind: :invalid_command} = error} =
               Owner.call(handle, :command, [frame, 100])

      refute inspect(error) =~ "credential-canary"
    end

    refute_receive {:serial_write, _}, 20
    assert {:ok, _} = Zigbee.ieee_address(handle, 1, 100)
  end

  test "a status response with trailing bytes invalidates the uncorrelated owner epoch" do
    {:ok, handle} = open(serial_options: [test_pid: self(), drop_reply: true])
    assert_receive {:serial_open, peer, _}
    command = Task.async(fn -> Zigbee.ieee_address(handle, 0x1234, 100) end)
    assert_receive {:serial_write, <<0xFE, 4, 0x25, 1, _::binary>>}
    send(peer, {:inject, peer_frame(0x65, 1, <<0, 1>>)})
    assert {:error, %Error{kind: :invalid_frame}} = Task.await(command)
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.node_descriptor(handle, 1, 100)
  end

  test "configuration rejects adapter overrides, duplicate keys and malformed versions" do
    assert {:error, %Error{kind: :invalid_config}} = Config.new(:invalid)

    assert {:error, %Error{kind: :invalid_config}} =
             Config.new(serial: TestSerialPeer, serial: TestSerialPeer)

    assert {:error, %Error{kind: :invalid_config}} =
             config(serial_options: [test_pid: self(), baud_rate: 9_600])

    assert {:error, %Error{kind: :invalid_config}} = config(expected_version: :unknown)
    assert {:error, %Error{kind: :invalid_config}} = config(expected_version: {1, 2, 3, 4, 256})

    assert {:error, %Error{kind: :invalid_config}} =
             Zigbee.open(%Config{
               serial: TestSerialPeer,
               device_id: "",
               expected_version: {2, 0, 3, 2, 0}
             })

    assert {:error, %Error{kind: :invalid_command}} =
             Command.data_request(1, 1, 1, 6, 1, <<>>, :not_options)

    assert {:error, %Error{kind: :invalid_command}} =
             Command.data_request(1, 1, 1, 6, 1, <<>>, [{1, 2}])
  end

  test "negotiation admits one waiter and times out without forming a network" do
    {:ok, config} = config(timeout_ms: 100, serial_options: [test_pid: self(), drop_version: true])
    {:ok, owner} = Owner.start(config)
    first = Task.async(fn -> Owner.ready(owner, 100) end)
    assert_receive {:serial_open, _peer, _}
    wait_ready_waiter(owner)
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.handle(owner)
    send(owner, :unrelated_serial_message)
    assert {:error, %Error{kind: :overload}} = Owner.ready(owner, 100)
    assert {:error, %Error{kind: :timeout}} = Task.await(first)
  end

  test "an expired queued call never writes a command after the owner resumes" do
    {:ok, %Handle{} = handle} = open()
    on_exit(fn -> Zigbee.close(handle) end)
    assert_receive {:serial_open, _peer, _}
    :ok = :sys.suspend(handle.owner)
    call = Task.async(fn -> Zigbee.active_endpoints(handle, 0x1234, 20) end)
    wait_queued_call(handle.owner)
    Process.sleep(25)
    :ok = :sys.resume(handle.owner)
    assert {:error, %Error{kind: :timeout}} = Task.await(call)
    refute_receive {:serial_write, <<0xFE, 4, 0x25, 5, _::binary>>}, 20
  end

  test "a valid queued SRSP delivered after the original deadline cannot succeed" do
    {:ok, handle} = open(serial_options: [test_pid: self(), drop_reply: true])
    assert_receive {:serial_open, peer, _}
    call = Task.async(fn -> Zigbee.ieee_address(handle, 0x1234, 50) end)
    assert_receive {:serial_write, <<0xFE, 4, 0x25, 1, _::binary>>}
    :ok = :sys.suspend(handle.owner)
    send(peer, {:inject, peer_frame(0x65, 1, <<0>>)})
    wait_queued_call(handle.owner)
    Process.sleep(55)
    :ok = :sys.resume(handle.owner)
    assert {:error, %Error{kind: :timeout}} = Task.await(call)
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.handle(handle.owner)
  end

  test "caller death while a command is pending fences its uncorrelated owner epoch" do
    {:ok, handle} = open(serial_options: [test_pid: self(), drop_reply: true])
    assert_receive {:serial_open, _, _}
    caller = spawn(fn -> Zigbee.ieee_address(handle, 0x1234, 100) end)
    assert_receive {:serial_write, <<0xFE, 4, 0x25, 1, _::binary>>}
    monitor = Process.monitor(handle.owner)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.handle(handle.owner)
  end

  test "serial callback delay cannot extend the command deadline" do
    {:ok, handle} =
      open(
        serial: Wotex.Zigbee.TestControlledSerial,
        serial_options: [test_pid: self(), write_behavior: {:delay, 30}]
      )

    assert {:error, %Error{kind: :timeout}} = Zigbee.ieee_address(handle, 0x1234, 20)
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.handle(handle.owner)
  end

  test "serial callback failures redact external data and end the command epoch" do
    for behavior <- [:raise, :throw, :exit, :malformed, :error] do
      {:ok, handle} =
        open(
          serial: Wotex.Zigbee.TestControlledSerial,
          serial_options: [test_pid: self(), write_behavior: behavior]
        )

      assert {:error, %Error{kind: :serial} = error} = Zigbee.ieee_address(handle, 0x1234, 100)
      refute inspect(error) =~ "credential-canary"
      assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.handle(handle.owner)
    end
  end

  test "uncatalogued owner operations and malformed envelopes are refused without leaking arguments" do
    {:ok, handle} = open()
    on_exit(fn -> Zigbee.close(handle) end)
    assert_receive {:serial_open, _, _}
    assert_receive {:serial_write, <<0xFE, 0, 0x21, 2, _>>}

    for operation <- [:uncatalogued, "credential-canary"] do
      assert {:error, %Error{kind: :invalid_command} = error} =
               Owner.call(handle, operation, ["credential-canary"])

      refute inspect(error) =~ "credential-canary"
    end

    assert {:error, %Error{kind: :invalid_command} = error} =
             GenServer.call(handle.owner, {:uncatalogued, handle.epoch, ["credential-canary"]})

    refute inspect(error) =~ "credential-canary"

    assert {:error, %Error{kind: :invalid_command}} =
             GenServer.call(handle.owner, {:command, handle.epoch, []})

    assert {:ok, _} = Zigbee.handle(handle.owner)
    refute_receive {:serial_write, _}, 10
  end

  test "receiver admission clamps a forged future deadline to the supplied timeout" do
    {:ok, handle} = open(serial_options: [test_pid: self(), drop_reply: true])
    {:ok, frame} = Command.ieee_address(0x1234)
    deadline = System.monotonic_time(:millisecond) + 60_000

    assert {:error, %Error{kind: :timeout}} =
             GenServer.call(handle.owner, {:command, handle.epoch, [frame, 10, deadline]}, 200)

    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.handle(handle.owner)
  end

  test "a caller that dies while queued cannot dispatch an ordinary command" do
    {:ok, handle} = open()
    on_exit(fn -> Zigbee.close(handle) end)
    assert_receive {:serial_open, _, _}
    assert_receive {:serial_write, <<0xFE, 0, 0x21, 2, _>>}
    :ok = :sys.suspend(handle.owner)
    caller = spawn(fn -> Zigbee.ieee_address(handle, 0x1234, 100) end)
    wait_queued_call(handle.owner)
    monitor = Process.monitor(caller)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}
    :ok = :sys.resume(handle.owner)
    assert {:ok, _} = Zigbee.handle(handle.owner)
    refute_receive {:serial_write, _}, 10
  end

  defp wait_ready_waiter(owner, attempts \\ 50)

  defp wait_ready_waiter(owner, attempts) when attempts > 0 do
    if :sys.get_state(owner).ready_waiter do
      :ok
    else
      Process.sleep(1)
      wait_ready_waiter(owner, attempts - 1)
    end
  end

  defp wait_ready_waiter(_, 0), do: flunk("first readiness waiter was not installed")

  defp wait_queued_call(owner, attempts \\ 50)

  defp wait_queued_call(owner, attempts) when attempts > 0 do
    case Process.info(owner, :message_queue_len) do
      {:message_queue_len, count} when count > 0 ->
        :ok

      _ ->
        Process.sleep(1)
        wait_queued_call(owner, attempts - 1)
    end
  end

  defp wait_queued_call(_, 0), do: flunk("command did not reach the suspended owner")

  defp eventually_handle(owner, attempts \\ 50)

  defp eventually_handle(owner, attempts) when attempts > 0 do
    case Zigbee.handle(owner) do
      {:ok, _} = result ->
        result

      _ ->
        Process.sleep(1)
        eventually_handle(owner, attempts - 1)
    end
  end

  defp eventually_handle(_, 0), do: flunk("supervised coordinator did not negotiate")

  defp config(overrides \\ []) do
    defaults = [
      serial: TestSerialPeer,
      device_id: "simulated-coordinator",
      expected_version: {2, 0, 3, 2, 0},
      serial_options: [test_pid: self()],
      timeout_ms: 100
    ]

    Config.new(Keyword.merge(defaults, overrides))
  end

  defp peer_frame(command, id, payload) do
    bytes = <<byte_size(payload), command, id, payload::binary>>
    checksum = Enum.reduce(:binary.bin_to_list(bytes), 0, &Bitwise.bxor/2)
    <<0xFE, bytes::binary, checksum>>
  end

  defp open(overrides \\ []) do
    {:ok, config} = config(overrides)
    Zigbee.open(config)
  end

  defp assert_event_count(handle, expected, attempts \\ 50)

  defp assert_event_count(handle, expected, attempts) when attempts > 0 do
    %Handle{owner: owner} = handle
    state = :sys.get_state(owner)

    if state.event_count == expected do
      :ok
    else
      Process.sleep(1)
      assert_event_count(handle, expected, attempts - 1)
    end
  end

  defp assert_event_count(_, _, 0), do: flunk("expected indication count was not reached")
end
