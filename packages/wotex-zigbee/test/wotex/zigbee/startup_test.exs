defmodule Wotex.Zigbee.StartupTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Wotex.Zigbee
  alias Wotex.Zigbee.{Config, Error, Owner, TestStartupSerial}

  test "open and version-write callback failures return redacted errors and close acquired ports" do
    log =
      capture_log(fn ->
        for stage <- [:open, :write], fault <- [:raise, :throw, :exit, :malformed, :error] do
          assert {:error, %Error{kind: :serial, operation: :open} = error} =
                   Zigbee.open(config([{stage, fault}]))

          refute inspect(error) =~ "credential-canary"
          assert_receive {:serial_callback, :open, owner}

          if stage == :write do
            assert_receive {:serial_open, peer, _}
            assert_receive {:serial_callback, :write, ^owner}
            assert_receive {:serial_callback, :close, ^owner}
            assert_dead(peer)
          else
            refute_receive {:serial_open, _, _}, 1
          end
        end
      end)

    refute log =~ "credential-canary"
  end

  test "serial open consumes the original startup budget and expiry prevents version I/O" do
    config = config(open: :hold, timeout_ms: 30)
    call = Task.async(fn -> Zigbee.open(config) end)
    assert_receive {:serial_callback, :open, owner}
    assert_receive {:serial_open, peer, _}
    Process.sleep(40)
    send(owner, {:release_callback, :open})
    assert {:error, %Error{kind: :timeout}} = Task.await(call)
    assert_receive {:serial_callback, :close, ^owner}
    refute_receive {:serial_callback, :write, _}, 10
    assert_dead(peer)
  end

  test "a version reply queued during a delayed write cannot complete after startup expiry" do
    config = config(write: :hold, timeout_ms: 30)
    call = Task.async(fn -> Zigbee.open(config) end)
    assert_receive {:serial_open, peer, _}
    assert_receive {:serial_callback, :write, owner}
    assert_receive {:serial_write, <<0xFE, 0, 0x21, 2, 0x23>>}
    wait_queued(owner)
    Process.sleep(40)
    send(owner, {:release_callback, :write})
    assert {:error, %Error{kind: :timeout}} = Task.await(call)
    assert_receive {:serial_callback, :close, ^owner}
    assert_dead(peer)
  end

  test "version delivery rechecks the original deadline after mailbox suspension" do
    {:ok, owner} = Owner.start(config(drop_version: true, timeout_ms: 100))
    assert_receive {:serial_open, peer, _}
    assert_receive {:serial_write, _}
    call = Task.async(fn -> Owner.ready(owner, 1_000) end)
    wait_ready(owner)
    :ok = :sys.suspend(owner)
    send(peer, {:inject, version_frame()})
    wait_queued(owner)
    Process.sleep(110)
    :ok = :sys.resume(owner)
    assert {:error, %Error{kind: :timeout}} = Task.await(call)
    assert_dead(owner)
    assert_dead(peer)
  end

  test "ready cannot refresh startup or return a queued handle after its own deadline" do
    {:ok, owner} = Owner.start(config(drop_version: true))
    assert_receive {:serial_open, peer, _}
    assert_receive {:serial_write, _}
    call = Task.async(fn -> Owner.ready(owner, 20) end)
    assert {:error, %Error{kind: :timeout}} = Task.await(call)
    assert_dead(peer)

    {:ok, handle} = Zigbee.open(config())
    on_exit(fn -> Zigbee.close(handle) end)
    :ok = :sys.suspend(handle.owner)
    call = Task.async(fn -> Owner.ready(handle.owner, 20) end)
    wait_queued(handle.owner)
    Process.sleep(30)
    :ok = :sys.resume(handle.owner)
    assert {:error, %Error{kind: :timeout}} = Task.await(call)
    assert {:ok, _} = Zigbee.handle(handle.owner)

    for timeout <- [0, nil, 60_001, "credential-canary"] do
      assert {:error, %Error{kind: :invalid_value}} = Owner.ready(handle.owner, timeout)
    end

    assert {:error, %Error{kind: :invalid_value}} = Owner.ready(nil, 10)
    assert {:error, %Error{kind: :invalid_config}} = Owner.start(nil)
    assert {:error, %Error{kind: :invalid_config}} = Owner.start_link(nil)
  end

  test "one ready waiter owns admission and a timely version reply completes its existing budget" do
    {:ok, owner} = Owner.start(config(drop_version: true))
    assert_receive {:serial_open, peer, _}
    call = Task.async(fn -> Owner.ready(owner, 500) end)
    wait_ready(owner)
    assert {:error, %Error{kind: :overload}} = Owner.ready(owner, 1_000)
    send(peer, {:inject, version_frame()})
    assert {:ok, handle} = Task.await(call)
    assert handle.owner == owner
    assert :ok = Zigbee.close(handle)
    assert_dead(peer)
  end

  test "failed negotiation closes immediately before any ready waiter and never retries close" do
    log =
      capture_log(fn ->
        {:ok, owner} = Owner.start(config(version: {2, 0, 2, 0, 0}, close: :raise))
        assert_receive {:serial_open, peer, _}
        assert_receive {:serial_callback, :close, ^owner}
        assert_dead(peer)
        assert {:error, %Error{kind: :version_mismatch}} = Owner.ready(owner, 500)
        assert_dead(owner)
        refute_receive {:serial_callback, :close, ^owner}, 10
      end)

    refute log =~ "credential-canary"
  end

  test "startup caller death closes a port returned later without a version write" do
    config = config(open: :hold)
    starter = spawn(fn -> Owner.start(config) end)
    assert_receive {:serial_callback, :open, owner}
    assert_receive {:serial_open, peer, _}
    Process.exit(starter, :kill)
    assert_dead(starter)
    send(owner, {:release_callback, :open})
    assert_receive {:serial_callback, :close, ^owner}
    refute_receive {:serial_callback, :write, _}, 10
    assert_dead(owner)
    assert_dead(peer)
  end

  test "original startup and independent ready waiter death close a negotiating owner" do
    test_pid = self()

    starter =
      spawn(fn ->
        {:ok, owner} = Owner.start(config(test_pid: test_pid, drop_version: true))
        send(test_pid, {:started, owner})
        receive do: (:stop -> :ok)
      end)

    assert_receive {:started, owner}
    assert_receive {:serial_open, peer, _}
    Process.exit(starter, :kill)
    assert_dead(owner)
    assert_dead(peer)

    {:ok, owner} = Owner.start(config(drop_version: true))
    assert_receive {:serial_open, peer, _}
    waiter = spawn(fn -> Owner.ready(owner, 1_000) end)
    wait_ready(owner)
    Process.exit(waiter, :kill)
    assert_dead(owner)
    assert_dead(peer)
  end

  test "caller death after version admission but before ready cannot orphan an open owner" do
    opener = start_opener(config(write: :hold))
    assert_receive {:serial_open, peer, _}
    assert_receive {:serial_callback, :write, owner}
    assert :erlang.suspend_process(opener)
    send(owner, {:release_callback, :write})
    wait_mode(owner, :awaiting_handoff)
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.handle(owner)
    Process.exit(opener, :kill)
    assert_dead(opener)
    assert_receive {:serial_callback, :close, ^owner}
    assert_dead(owner)
    assert_dead(peer)
    refute_receive {:serial_callback, :close, ^owner}, 10
  end

  test "the owner links before delivering a negotiated handle to a suspended caller" do
    opener = start_opener(config(drop_version: true))
    assert_receive {:serial_open, peer, _}
    assert_receive {:serial_callback, :write, owner}
    wait_ready(owner)
    assert :erlang.suspend_process(opener)
    send(peer, {:inject, version_frame()})
    wait_mode(owner, :ready)
    assert {:links, links} = Process.info(owner, :links)
    assert opener in links
    refute_receive {:open_result, ^opener, _}, 1
    Process.exit(opener, :kill)
    assert_receive {:serial_callback, :close, ^owner}
    assert_dead(owner)
    assert_dead(peer)
  end

  test "pending handoff refuses another waiter and normal caller exit closes the delivered owner" do
    opener = start_opener(config(write: :hold))
    assert_receive {:serial_open, peer, _}
    assert_receive {:serial_callback, :write, owner}
    assert :erlang.suspend_process(opener)
    send(owner, {:release_callback, :write})
    wait_mode(owner, :awaiting_handoff)
    assert {:error, %Error{kind: :invalid_value}} = Owner.ready(owner, 20)
    assert :erlang.resume_process(opener)
    assert_receive {:open_result, ^opener, {:ok, handle}}
    assert handle.owner == owner
    assert {:links, links} = Process.info(owner, :links)
    assert opener in links
    send(opener, :finish)
    assert_dead(opener)
    assert_receive {:serial_callback, :close, ^owner}
    assert_dead(owner)
    assert_dead(peer)
    refute_receive {:serial_callback, :close, ^owner}, 10
  end

  test "version admission cannot renew the original deadline while handoff is pending" do
    opener = start_opener(config(write: :hold, timeout_ms: 300))
    assert_receive {:serial_open, peer, _}
    assert_receive {:serial_callback, :write, owner}
    assert :erlang.suspend_process(opener)
    send(owner, {:release_callback, :write})
    wait_mode(owner, :awaiting_handoff)
    assert_receive {:serial_callback, :close, ^owner}, 400
    assert_dead(peer)
    assert :erlang.resume_process(opener)
    assert_receive {:open_result, ^opener, {:error, %Error{kind: :timeout}}}
    assert_dead(owner)
    refute_receive {:serial_callback, :close, ^owner}, 10
  end

  test "a handoff queued before the timer still refuses delivery past the startup deadline" do
    opener = start_opener(config(write: :hold, timeout_ms: 150))
    assert_receive {:serial_open, peer, _}
    assert_receive {:serial_callback, :write, owner}
    assert :erlang.suspend_process(opener)
    send(owner, {:release_callback, :write})
    wait_mode(owner, :awaiting_handoff)
    :ok = :sys.suspend(owner)
    assert :erlang.resume_process(opener)
    wait_queued(owner)
    Process.sleep(160)
    :ok = :sys.resume(owner)
    assert_receive {:open_result, ^opener, {:error, %Error{kind: :timeout}}}
    assert_receive {:serial_callback, :close, ^owner}
    assert_dead(owner)
    assert_dead(peer)
    refute_receive {:serial_callback, :close, ^owner}, 10
  end

  test "the separate unlinked startup seam retains its negotiated owner after caller exit" do
    test_pid = self()
    config = config()

    starter =
      spawn(fn ->
        {:ok, owner} = Owner.start(config)
        {:ok, handle} = Owner.ready(owner, 500)
        send(test_pid, {:unlinked_ready, handle})
        receive do: (:finish -> :ok)
      end)

    assert_receive {:unlinked_ready, handle}
    on_exit(fn -> Zigbee.close(handle) end)
    send(starter, :finish)
    assert_dead(starter)
    assert {:ok, ^handle} = Zigbee.handle(handle.owner)
    assert :ok = Zigbee.close(handle)
  end

  test "linked adapter loss fails a pending command with one redacted close attempt" do
    log =
      capture_log(fn ->
        {:ok, handle} = Zigbee.open(config(drop_reply: true))
        assert_receive {:serial_open, peer, _}
        call = Task.async(fn -> Zigbee.active_endpoints(handle, 0x1234, 500) end)
        assert_receive {:serial_write, <<0xFE, 4, 0x25, 5, _::binary>>}
        Process.exit(peer, "credential-canary")
        assert {:error, %Error{kind: :coordinator_lost} = error} = Task.await(call)
        refute inspect(error) =~ "credential-canary"
        assert_receive {:serial_callback, :close, owner}
        assert owner == handle.owner
        assert_dead(owner)
        refute_receive {:serial_callback, :close, ^owner}, 10
      end)

    refute log =~ "credential-canary"
    assert {:error, %Error{kind: :invalid_config}} = Owner.open(nil)
  end

  test "explicit close failures are redacted, attempt close once and end ownership" do
    log =
      capture_log(fn ->
        for fault <- [:raise, :throw, :exit, :malformed, :error] do
          {:ok, handle} = Zigbee.open(config(close: fault))
          assert_receive {:serial_open, peer, _}
          assert {:error, %Error{kind: :serial, operation: :close}} = Zigbee.close(handle)
          assert_receive {:serial_callback, :close, owner}
          assert owner == handle.owner
          refute_receive {:serial_callback, :close, ^owner}, 5
          assert_dead(owner)
          assert_dead(peer)
        end
      end)

    refute log =~ "credential-canary"
  end

  defp config(options) do
    timeout = Keyword.get(options, :timeout_ms, 1_000)
    serial_options = Keyword.delete(options, :timeout_ms)
    serial_options = Keyword.put_new(serial_options, :test_pid, self())

    {:ok, config} =
      Config.new(
        serial: TestStartupSerial,
        device_id: "simulated-coordinator",
        expected_version: {2, 0, 3, 2, 0},
        timeout_ms: timeout,
        serial_options: serial_options
      )

    config
  end

  defp config, do: config([])
  defp version_frame, do: <<0xFE, 5, 0x61, 2, 2, 0, 3, 2, 0, 0x65>>

  defp start_opener(config) do
    test_pid = self()

    opener =
      spawn(fn ->
        result = Zigbee.open(config)
        send(test_pid, {:open_result, self(), result})
        receive do: (:finish -> :ok)
      end)

    on_exit(fn -> Process.exit(opener, :kill) end)
    opener
  end

  defp assert_dead(pid) do
    monitor = Process.monitor(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}
  end

  defp wait_queued(owner, attempts \\ 100)

  defp wait_queued(owner, attempts) when attempts > 0 do
    if elem(Process.info(owner, :message_queue_len), 1) > 0 do
      :ok
    else
      Process.sleep(1)
      wait_queued(owner, attempts - 1)
    end
  end

  defp wait_queued(_, 0), do: flunk("startup response was not queued")

  defp wait_ready(owner, attempts \\ 100)

  defp wait_ready(owner, attempts) when attempts > 0 do
    if :sys.get_state(owner).ready_waiter do
      :ok
    else
      Process.sleep(1)
      wait_ready(owner, attempts - 1)
    end
  end

  defp wait_ready(_, 0), do: flunk("ready waiter was not admitted")

  defp wait_mode(owner, mode, attempts \\ 100)

  defp wait_mode(owner, mode, attempts) when attempts > 0 do
    if :sys.get_state(owner).mode == mode do
      :ok
    else
      Process.sleep(1)
      wait_mode(owner, mode, attempts - 1)
    end
  end

  defp wait_mode(_, _, 0), do: flunk("startup did not reach the expected handoff phase")
end
