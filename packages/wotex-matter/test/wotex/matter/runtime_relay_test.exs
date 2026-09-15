defmodule Wotex.Matter.RuntimeRelayTest do
  @moduledoc false

  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias Wotex.Matter.{Address, Error, RuntimeClient, RuntimeRelay}
  alias Wotex.Matter.RuntimeRelay.Frame

  @path %{fabric_id: 1, node_id: 1234, endpoint: 1, cluster: 6, member: 0}
  @event_path %{fabric_id: 1, node_id: 1234, endpoint: 2, cluster: 0x0039, member: 3}
  @value %{tag: :anonymous, type: :boolean, value: false}

  test "malformed stream options fail before acquiring a client" do
    for options <- [
          [:malformed],
          [min_interval_s: 0] ++ [:malformed],
          [{"min_interval_s", 0}],
          [{:min_interval_s, 0} | :malformed],
          [min_interval_s: 0, min_interval_s: 0],
          [unknown: true],
          [min_interval_s: 2, max_interval_s: 1],
          [owner_queue_limit: 0],
          [max_queue_length: 10_001]
        ] do
      result = start(options)
      if match?({:ok, _}, result), do: RuntimeRelay.close(elem(result, 1))
      assert {:error, %Error{code: :invalid_subscription}} = result
      refute_receive {:matter_connect, _}, 0
    end

    for options <- [[:malformed], [{"client", RuntimeClient}]] do
      assert {:error, %Error{code: :invalid_subscription}} = start([], 1_000, options)
      refute_receive {:matter_connect, _}, 0
    end
  end

  test "non-positive and out-of-range startup budgets fail before client acquisition" do
    for timeout <- [-1, 0, 60_001, :infinity, 1.0] do
      result = start([], timeout)
      if match?({:ok, _}, result), do: RuntimeRelay.close(elem(result, 1))
      assert {:error, %Error{code: :invalid_subscription}} = result
      refute_receive {:matter_connect, _}, 0
    end
  end

  test "finite option boundaries preserve the requested native subscription" do
    {:ok, handle} =
      start(
        [
          min_interval_s: 0,
          max_interval_s: 65_535,
          max_queue_length: 10_000,
          owner_queue_limit: 10_000
        ],
        60_000
      )

    pid = handle.pid
    on_exit(fn -> RuntimeRelay.close(handle) end)
    assert_receive {:matter_connect, ^pid}
    assert_receive {:matter_subscribe, ^pid, ^pid, request, _, _}
    assert request.min_interval_s == 0
    assert request.max_interval_s == 65_535
    assert request.queue_limit == 10_000
    assert request.paths == [@path]
    assert request.resubscribe == false
    assert :ok = RuntimeRelay.close(handle)
    assert_receive {:matter_unsubscribe, ^pid, _, _}
    assert_receive :disconnected
  end

  test "a frame can be consumed once only by its original owner and request" do
    {handle, reference} = bound()
    pid = handle.pid
    send(pid, {:wotex_matter, reference, {:ok, @value, metadata()}})
    assert_receive {:wotex_transport_frame, %Frame{} = frame}
    address = address()

    assert :ignore = Task.async(fn -> decode(frame, address) end) |> Task.await()
    assert :ignore = decode(%{frame | generation: "forged"}, address)
    assert :ignore = decode(%{frame | token: make_ref()}, address)
    assert :ignore = decode(%{frame | value: :forged}, address)
    assert :ignore = decode(frame, %{address | node_id: 4321})
    assert :ignore = RuntimeRelay.decode(frame, "different", :observeproperty, :attribute, address)
    assert :ignore = RuntimeRelay.decode(frame, "request", :subscribeevent, :event, address)

    assert {:error, %Error{code: :invalid_handle}} =
             RuntimeRelay.close(%{handle | generation: "forged"})

    assert {:ok, @value, %{data_version: 1, status: 0}} = decode(frame, address)
    assert :ignore = decode(frame, address)
    assert :ignore = decode(:invalid, address)
    assert :ok = RuntimeRelay.close(handle)
    assert_receive {:matter_unsubscribe, ^pid, _, _}
    assert_receive :disconnected
    assert :ignore = decode(frame, address)
    assert :ok = RuntimeRelay.close(handle)
  end

  test "64 opening reports remain bounded when another delivery arrives before consumption" do
    delivery = {:ok, @value, metadata()}
    {handle, reference} = bound([], opening_deliveries: List.duplicate(delivery, 64))
    pid = handle.pid
    monitor = Process.monitor(pid)

    frames =
      for _ <- 1..64 do
        assert_receive {:wotex_transport_frame, %Frame{} = frame}
        frame
      end

    send(pid, {:wotex_matter, reference, delivery})
    assert_receive {:wotex_transport, {:error, %Error{code: :receiver_overflow}}}
    assert_receive {:wotex_transport_status, :transport_down}
    assert_receive {:matter_unsubscribe, ^pid, _, _}
    assert_receive :disconnected
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
    assert Enum.all?(frames, &(decode(&1, address()) == :ignore))
    refute_receive {:wotex_transport_frame, _}, 0
  end

  test "invalid report metadata closes the bound route without exposing a frame" do
    for metadata <- [
          %{metadata() | path: %{@path | node_id: 4321}},
          %{metadata() | data_version: -1},
          %{metadata() | data_version: 0x100000000},
          Map.put(metadata(), :status, 1),
          Map.put(metadata(), :kind, :event),
          %{}
        ] do
      {handle, reference} = bound()
      pid = handle.pid
      monitor = Process.monitor(pid)
      send(pid, {:wotex_matter, reference, {:ok, @value, metadata}})
      assert_receive {:wotex_transport, {:error, %Error{code: :invalid_transport_return}}}
      assert_receive {:wotex_transport_status, :transport_down}
      assert_receive {:matter_unsubscribe, ^pid, _, _}
      assert_receive :disconnected
      assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
      refute_receive {:wotex_transport_frame, _}, 0
    end
  end

  test "dead owners and failed connections do not establish a subscription" do
    {owner, monitor} = spawn_monitor(fn -> :ok end)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
    assert {:error, %Error{code: :receiver_closed}} = start([], 1_000, [], owner)
    refute_receive {:matter_connect, _}, 0
    error = Error.new(:storage_open_failed)
    assert {:error, ^error} = start([], 1_000, connect_error: error)
    assert_receive {:matter_connect, _}
    refute_receive {:matter_subscribe, _, _, _, _, _}, 0
  end

  test "subscription and cleanup failures remain exact structured errors" do
    subscribe_error = Error.new(:subscription_failed)

    assert {:error, ^subscribe_error} =
             start([], 1_000, subscribe_error: subscribe_error)

    assert_receive {:matter_connect, _}
    assert_receive {:matter_subscribe, _, _, _, _, _}
    assert_receive :disconnected

    for {option, expected} <- [
          {:unsubscribe_error, Error.new(:subscription_cancel_failed)},
          {:disconnect_error, Error.new(:transport_closed)}
        ] do
      assert {:ok, handle} = start([], 1_000, [{option, expected}])
      pid = handle.pid
      assert_receive {:matter_connect, ^pid}
      assert_receive {:matter_subscribe, ^pid, ^pid, _, _, _}
      assert {:error, ^expected} = RuntimeRelay.close(handle)
      assert_receive {:matter_unsubscribe, ^pid, _, _}
      assert_receive :disconnected
    end
  end

  test "opening and terminal stream failures close resources without publishing a frame" do
    assert {:error, %Error{code: :subscription_failed}} =
             start([], 1_000, opening_deliveries: [{:status, :resubscribed, %{}}])

    assert_receive {:matter_connect, opening}
    assert_receive {:matter_subscribe, ^opening, ^opening, _, _, _}
    assert_receive {:matter_unsubscribe, ^opening, _, _}
    assert_receive :disconnected
    refute_receive {:wotex_transport_frame, _}, 0

    for {terminal, status} <- [
          {{:error, Error.new(:receiver_overflow)}, :transport_down},
          {{:error, Error.new(:session_lost)}, :session_lost},
          {{:status, :resubscribed, %{}}, :transport_down}
        ] do
      {handle, reference} = bound()
      pid = handle.pid
      monitor = Process.monitor(pid)
      send(pid, {:wotex_matter, reference, terminal})
      assert_receive {:wotex_transport, {:error, %Error{}}}
      assert_receive {:wotex_transport_status, ^status}
      assert_receive {:matter_unsubscribe, ^pid, _, _}
      assert_receive :disconnected
      assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
      refute_receive {:wotex_transport_frame, _}, 0
    end
  end

  test "a full final-owner mailbox terminates the route before frame admission" do
    parent = self()

    owner =
      spawn(fn ->
        send(parent, {:owner_ready, self()})

        receive do
          :release -> send(parent, {:owner_messages, Process.info(self(), :messages)})
        end
      end)

    assert_receive {:owner_ready, ^owner}
    send(owner, :occupied)
    assert {:ok, handle} = start([owner_queue_limit: 1], 1_000, [], owner)
    pid = handle.pid
    monitor = Process.monitor(pid)
    assert_receive {:matter_connect, ^pid}
    assert_receive {:matter_subscribe, ^pid, ^pid, _, _, reference}
    send(pid, {:wotex_matter, reference, {:ok, @value, metadata()}})
    assert_receive {:matter_unsubscribe, ^pid, _, _}
    assert_receive :disconnected
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}

    assert {:messages, messages} = Process.info(owner, :messages)
    assert :occupied in messages
    assert {:wotex_transport_status, :transport_down} in messages
    refute Enum.any?(messages, &match?({:wotex_transport_frame, _}, &1))
    send(owner, :release)
    assert_receive {:owner_messages, _}
  end

  test "event routes reject schema and timestamp ambiguity with bounded public failures" do
    address = event_address()

    event_value = %{
      tag: :anonymous,
      type: :structure,
      value: [%{tag: {:context, 0}, type: :boolean, value: false}]
    }

    valid_metadata = %{
      kind: :event,
      path: @event_path,
      event_number: 1,
      priority: 1,
      timestamp: %{kind: :epoch, value: 1}
    }

    for {value, metadata, code} <- [
          {@value, valid_metadata, :invalid_value},
          {event_value, %{valid_metadata | timestamp: %{kind: :unknown, value: 1}},
           :invalid_transport_return}
        ] do
      assert {:ok, handle} = start_event(address)
      pid = handle.pid
      monitor = Process.monitor(pid)
      assert_receive {:matter_connect, ^pid}
      assert_receive {:matter_subscribe, ^pid, ^pid, _, _, reference}
      send(pid, {:wotex_matter, reference, {:ok, value, metadata}})
      assert_receive {:wotex_transport, {:error, %Error{code: ^code}}}
      assert_receive {:wotex_transport_status, :transport_down}
      assert_receive {:matter_unsubscribe, ^pid, _, _}
      assert_receive :disconnected
      assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
      refute_receive {:wotex_transport_frame, _}, 0
    end
  end

  test "unknown calls return structured errors without leaking route diagnostics" do
    canary = "relay-private-canary"
    {:ok, handle} = start([], 1_000, [], self(), canary)
    pid = handle.pid
    assert_receive {:matter_connect, ^pid}
    assert_receive {:matter_subscribe, ^pid, ^pid, _, _, _}
    monitor = Process.monitor(pid)
    refute inspect(:sys.get_status(pid)) =~ canary

    status =
      RuntimeRelay.format_status(%{
        state: %{state: :bound, operation: :observeproperty, private: canary},
        message: canary,
        reason: canary,
        log: [canary],
        other: :kept
      })

    assert status.message == :redacted
    assert status.reason == :redacted
    assert status.log == []
    assert status.other == :kept
    refute inspect(status) =~ canary

    log =
      capture_log(fn ->
        assert {:error, %Error{code: :invalid_handle}} =
                 GenServer.call(pid, {:unknown_call, canary})

        assert Process.alive?(pid)
        assert :ok = RuntimeRelay.close(handle)
        assert_receive {:matter_unsubscribe, ^pid, _, _}
        assert_receive :disconnected
        assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
      end)

    assert log == ""
    refute log =~ canary
    assert :ok = RuntimeRelay.close(handle)
  end

  defp bound(stream_options \\ [], client_options \\ []) do
    assert {:ok, handle} = start(stream_options, 1_000, client_options)
    pid = handle.pid
    on_exit(fn -> RuntimeRelay.close(handle) end)
    assert_receive {:matter_connect, ^pid}
    assert_receive {:matter_subscribe, ^pid, ^pid, _, _, reference}
    {handle, reference}
  end

  defp start(
         stream_options,
         timeout \\ 1_000,
         extra \\ [],
         owner \\ self(),
         request_id \\ "request"
       ) do
    RuntimeRelay.start(
      owner,
      request_id,
      :observeproperty,
      :attribute,
      address(),
      [client: RuntimeClient, test_pid: self()] ++ extra,
      stream_options,
      timeout
    )
  end

  defp address do
    {:ok, address} = Address.new(@path)
    address
  end

  defp event_address do
    {:ok, address} = Address.new(@event_path)
    address
  end

  defp start_event(address) do
    RuntimeRelay.start(
      self(),
      "event-request",
      :subscribeevent,
      :event,
      address,
      [client: RuntimeClient, test_pid: self()],
      [],
      1_000
    )
  end

  defp metadata, do: %{kind: :attribute, path: @path, data_version: 1}

  defp decode(frame, address),
    do: RuntimeRelay.decode(frame, "request", :observeproperty, :attribute, address)
end
