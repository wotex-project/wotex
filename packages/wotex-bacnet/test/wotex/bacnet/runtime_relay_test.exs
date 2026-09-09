defmodule Wotex.BACnet.RuntimeRelayTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.{BACstack, COVRequest, Error, RuntimeNative, RuntimeRelay, Session}
  alias Wotex.BACnet.Test.RuntimeClient

  setup do
    {:ok, request} =
      COVRequest.new(
        %{type: :cov_property, device_instance: 123, object_type: 1, instance: 7, property: 85},
        self()
      )

    options = %{
      owner: self(),
      request: request,
      client_options: [client: RuntimeClient, test_owner: self(), destination: :fixture],
      deadline: System.monotonic_time(:millisecond) + 500
    }

    %{options: options}
  end

  test "WBA-I05 injected client reports remain ordered across establishment", c do
    opener = Task.async(fn -> RuntimeRelay.open(c.options) end)
    assert_receive {:native_open, worker, relay, subscription, _}
    {:ok, value} = Encoding.create({:boolean, false})
    metadata = metadata(value)
    send(relay, {:wotex_bacnet, make_ref(), {:ok, :foreign, %{}}})
    send(relay, {:wotex_bacnet, subscription.reference, {:ok, value, metadata}})
    refute_receive {:wotex_transport_frame, _}, 10
    send(worker, {:release, :ok})
    assert {:ok, handle} = Task.await(opener)
    assert_receive {:wotex_transport_frame, {:value, ^value, ^metadata}}
    assert :ok = RuntimeRelay.close(handle)
    assert_receive {:native_cancel, _, ^subscription, timeout}
    assert timeout in 1..500
    assert_receive {:native_disconnect, _}
    refute Process.alive?(worker)
    refute Process.alive?(subscription.pid)
    refute Process.alive?(relay)
  end

  test "WBA-I05 injected-port errors and invalid or dead handles fail establishment", c do
    for result <- [{:error, Error.new(:remote_error)}, {:ok, :forged}, :dead] do
      opener = Task.async(fn -> RuntimeRelay.open(c.options) end)
      assert_receive {:native_open, worker, relay, subscription, _}
      send(worker, {:release, result})
      assert {:error, %Error{}} = Task.await(opener)
      assert_receive {:native_disconnect, _}
      refute Process.alive?(relay)
      refute Process.alive?(worker)
      refute Process.alive?(subscription.pid)
    end
  end

  test "WBA-C03 WBA-I05 injected opening buffer is finite and closes failed native session", c do
    opener = Task.async(fn -> RuntimeRelay.open(c.options) end)
    assert_receive {:native_open, worker, relay, subscription, _}
    for _ <- 1..65, do: send(relay, {:wotex_bacnet, make_ref(), :unrelated})
    assert {:error, %Error{code: :receiver_overflow}} = Task.await(opener)
    assert_receive {:native_disconnect, _}
    refute Process.alive?(worker)
    refute Process.alive?(subscription.pid)
  end

  test "WBA-C03 WBA-I05 opening deadline and caller death interrupt injected blocking I/O", c do
    for cause <- [:deadline, :caller] do
      options = %{c.options | deadline: System.monotonic_time(:millisecond) + 30}
      opener = Task.async(fn -> RuntimeRelay.open(options) end)
      assert_receive {:native_open, worker, relay, subscription, _}

      if cause == :caller do
        Process.unlink(opener.pid)
        Process.exit(opener.pid, :kill)
      else
        assert {:error, %Error{code: :deadline_exceeded}} = Task.await(opener)
      end

      assert_receive {:native_disconnect, _}
      await_dead(relay)
      await_dead(worker)
      await_dead(subscription.pid)
    end
  end

  test "WBA-C03 WBA-I05 failed or blocked connect never leaves a worker", c do
    for mode <- [:failed, :blocked] do
      options = %{
        c.options
        | deadline: System.monotonic_time(:millisecond) + 30,
          client_options: Keyword.put(c.options.client_options, :mode, mode)
      }

      opener = Task.async(fn -> RuntimeRelay.open(options) end)
      assert_receive {:native_connect, worker}
      assert {:error, %Error{code: code}} = Task.await(opener)
      assert code in [:startup_failed, :deadline_exceeded]
      await_dead(worker)
    end
  end

  test "WBA-I05 native malformed report terminates the established relay once", c do
    opener = Task.async(fn -> RuntimeRelay.open(c.options) end)
    assert_receive {:native_open, worker, relay, subscription, _}
    send(worker, {:release, :ok})
    assert {:ok, _} = Task.await(opener)
    send(relay, {:wotex_bacnet, subscription.reference, {:ok, :untyped, %{}}})
    assert_receive {:wotex_transport_frame, {:error, %Error{code: :invalid_runtime_frame}}}
    assert_receive {:wotex_transport_status, :session_lost}
    assert_receive {:native_cancel, _, ^subscription, _}
    assert_receive {:native_disconnect, _}
    await_dead(relay)
    refute_receive {:wotex_transport_status, _}, 10
  end

  test "WBA-I05 first-party handles cannot substitute a foreign session generation", c do
    opener = Task.async(fn -> RuntimeRelay.open(c.options) end)
    assert_receive {:native_open, worker, _, subscription, _}
    generation = make_ref()
    session = %Session{client: BACstack, handle: %{generation: generation}, timeout: 500}
    refute RuntimeNative.valid_subscription?(session, subscription)

    assert RuntimeNative.valid_subscription?(session, %{
             subscription
             | session_generation: generation
           })

    refute RuntimeNative.valid_subscription?(nil, subscription)
    refute RuntimeNative.valid_subscription?(session, :invalid)
    assert :ok = RuntimeNative.close(nil, nil, 0)
    assert :ok = RuntimeNative.abort(nil, nil, 0)
    send(worker, {:release, :ok})
    assert {:ok, handle} = Task.await(opener)
    assert :ok = RuntimeRelay.close(handle)
  end

  test "WBA-C03 native handshake cannot dispatch after its absolute deadline", c do
    token = make_ref()
    options = %{c.options | deadline: System.monotonic_time(:millisecond) - 1}
    {worker, monitor} = RuntimeNative.start(self(), token, options)

    assert_receive {:runtime_subscribed, ^token, ^worker,
                    {:error, %Error{code: :deadline_exceeded}}}

    refute_receive {:native_connect, _}, 10
    send(worker, {:halt, token})
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}

    for action <- [:expire, :late_subscribe] do
      token = make_ref()
      options = %{c.options | deadline: System.monotonic_time(:millisecond) + 25}
      {worker, monitor} = RuntimeNative.start(self(), token, options)
      assert_receive {:runtime_session, ^token, ^worker, _}

      if action == :late_subscribe do
        :erlang.suspend_process(worker)
        send(worker, {:subscribe, token, self()})
        Process.sleep(30)
        :erlang.resume_process(worker)
      end

      assert_receive {:runtime_subscribed, ^token, ^worker,
                      {:error, %Error{code: :deadline_exceeded}}}

      refute_receive {:native_open, _, _, _, _}, 10
      send(worker, {:halt, token})
      assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
    end
  end

  test "WBA-I05 expired establishment starts no native process", c do
    assert {:error, %Error{code: :deadline_exceeded}} =
             RuntimeRelay.open(%{c.options | deadline: System.monotonic_time(:millisecond) - 1})

    refute_receive {:native_connect, _}, 10
  end

  test "WBA-I05 malformed early reports and native owner loss terminate once", c do
    for cause <- [:early_invalid, :child_dead, :worker_dead] do
      opener = Task.async(fn -> RuntimeRelay.open(c.options) end)
      assert_receive {:native_open, worker, relay, subscription, _}

      if cause == :early_invalid,
        do: send(relay, {:wotex_bacnet, subscription.reference, :invalid_envelope})

      send(worker, {:release, :ok})
      assert {:ok, _} = Task.await(opener)

      case cause do
        :child_dead -> send(subscription.pid, :stop)
        :worker_dead -> Process.exit(worker, :kill)
        _ -> :ok
      end

      assert_receive {:wotex_transport_frame, {:error, %Error{}}}
      assert_receive {:wotex_transport_status, :session_lost}
      assert_receive {:native_disconnect, _}
      await_dead(relay)
    end
  end

  test "WBA-I05 injected established owner queue is independently bounded", c do
    owner = spawn(fn -> receive do: (:stop -> :ok) end)
    options = %{c.options | owner: owner}
    opener = Task.async(fn -> RuntimeRelay.open(options) end)
    assert_receive {:native_open, worker, relay, subscription, _}
    send(worker, {:release, :ok})
    assert {:ok, _} = Task.await(opener)
    for _ <- 1..1000, do: send(owner, :queued)
    assert {:message_queue_len, 1000} = Process.info(owner, :message_queue_len)
    {:ok, value} = Encoding.create({:boolean, false})
    send(relay, {:wotex_bacnet, subscription.reference, {:ok, value, metadata(value)}})
    assert_receive {:native_cancel, _, ^subscription, _}
    assert_receive {:native_disconnect, _}
    await_dead(relay)
    assert {:messages, messages} = Process.info(owner, :messages)
    assert {:wotex_transport_frame, {:error, Error.new(:receiver_overflow)}} in messages
    assert {:wotex_transport_status, :session_lost} in messages
    send(owner, :stop)
  end

  defp await_dead(pid) do
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 200
  end

  defp metadata(value) do
    %{
      source: :fixture,
      device_instance: 123,
      process_identifier: 1,
      object_type: 1,
      instance: 7,
      property: 85,
      array_index: nil,
      time_remaining: 2,
      report_values: [%{property: 85, array_index: nil, priority: nil, value: value}]
    }
  end
end
