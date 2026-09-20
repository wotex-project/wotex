defmodule Wotex.CoAP.TelemetryTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.CoAP
  alias Wotex.CoAP.{Codec, Error, Message, Telemetry}

  @request_event [:wotex, :coap, :request, :stop]
  @subscription_events [
    [:wotex, :coap, :subscription, :open],
    [:wotex, :coap, :subscription, :deliver],
    [:wotex, :coap, :subscription, :close]
  ]

  test "WCO-C08 request telemetry is finite and omits route and payload data" do
    attach([@request_event])
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 1_000)
    payload = "private-request-payload"
    path = "/private/request/path"

    request = Task.async(fn -> CoAP.post(session, path, payload) end)
    first = wire()
    send(peer.pid, {:reply, %{first.message | type: :ack, code: 68, payload: "accepted"}})
    assert {:ok, %Message{code: 68}} = Task.await(request)

    assert_receive {:telemetry, @request_event, %{duration: duration}, metadata}
    assert is_integer(duration) and duration >= 0
    assert metadata == %{operation: :post, result: :ok, status: 68}

    request = Task.async(fn -> CoAP.get(session, path) end)
    second = wire()
    send(peer.pid, {:reply, %{second.message | type: :ack, code: 132, payload: payload}})
    assert {:error, %Error{code: :remote_response}} = Task.await(request)

    assert_receive {:telemetry, @request_event, %{duration: duration}, metadata}
    assert is_integer(duration) and duration >= 0
    assert metadata == %{operation: :get, result: :protocol, status: 132}

    emitted = inspect(metadata)
    refute emitted =~ payload
    refute emitted =~ path
    refute emitted =~ "127.0.0.1"

    assert :ok = CoAP.disconnect(session)
    close(peer)
  end

  test "WCO-C08 subscription telemetry records lifecycle counts without observed data" do
    attach(@subscription_events)
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 1_000)
    path = "/private/observed/path"
    payload = "private-observed-payload"
    receiver = self()

    subscription =
      Task.async(fn ->
        CoAP.subscribe(session, %{path: path, receiver: receiver, renew: false})
      end)

    opening = wire()
    send(peer.pid, {:reply, report(opening.message, 10, payload)})
    assert {:ok, handle} = Task.await(subscription)
    reference = handle.reference
    assert_receive {:wotex_coap, ^reference, {:ok, %Message{payload: ^payload}, _}}

    assert_receive {:telemetry, [:wotex, :coap, :subscription, :open], %{count: 1}, open}
    assert open == %{kind: :property, result: :ok}

    assert_receive {:telemetry, [:wotex, :coap, :subscription, :deliver], %{count: 1}, delivery}
    assert delivery == %{kind: :property, result: :ok}

    cancel = Task.async(fn -> CoAP.unsubscribe(session, handle) end)
    cancellation = wire().message
    send(peer.pid, {:reply, %{cancellation | type: :ack, code: 69, options: []}})
    assert :ok = Task.await(cancel)

    assert_receive {:telemetry, [:wotex, :coap, :subscription, :close], %{count: 1}, close_event}
    assert close_event == %{kind: :property, result: :ok}

    emitted = inspect([open, delivery, close_event])
    refute emitted =~ path
    refute emitted =~ payload
    refute emitted =~ "127.0.0.1"

    assert :ok = CoAP.disconnect(session)
    close(peer)
  end

  test "WCO-C08 failed subscription establishment emits one bounded open result" do
    attach(@subscription_events)
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 1_000)
    receiver = self()

    subscription =
      Task.async(fn ->
        CoAP.subscribe(session, %{path: "/private/failure", receiver: receiver})
      end)

    opening = wire()
    send(peer.pid, {:reply, %{opening.message | type: :ack, code: 69, options: []}})
    assert {:error, %Error{code: :invalid_observation_response}} = Task.await(subscription)

    assert_receive {:telemetry, [:wotex, :coap, :subscription, :open], %{count: 1}, metadata}
    assert metadata == %{kind: :property, result: :protocol}
    refute_receive {:telemetry, [:wotex, :coap, :subscription, :close], _, _}

    wire()
    assert :ok = CoAP.disconnect(session)
    close(peer)
  end

  test "WCO-C08 exception and startup failure diagnostics remain bounded" do
    attach([@request_event])
    canary = "private-exception-and-startup-detail"
    started = System.monotonic_time()

    assert :ok =
             Telemetry.request_stop(started, :unknown, {:error, RuntimeError.exception(canary)})

    assert_receive {:telemetry, @request_event, %{duration: duration}, exception}
    assert is_integer(duration) and duration >= 0
    assert exception == %{operation: :unknown, result: :error, status: nil}

    failure = Error.new(:native_unavailable, nil, %{reason: canary})
    assert :ok = Telemetry.request_stop(started, :get, {:error, failure})

    assert_receive {:telemetry, @request_event, %{duration: duration}, startup}
    assert is_integer(duration) and duration >= 0
    assert startup == %{operation: :get, result: :unavailable, status: nil}
    refute inspect([exception, startup]) =~ canary
  end

  defp attach(events) do
    id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach_many(
        id,
        events,
        fn event, measurements, metadata, owner ->
          send(owner, {:telemetry, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  defp report(request, sequence, payload) do
    %{request | type: :ack, code: 69, options: [{6, Codec.uint(sequence)}], payload: payload}
  end

  defp peer do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: true, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    owner = self()

    task =
      Task.async(fn ->
        receive do
          :ready -> loop(socket, owner, nil)
        end
      end)

    :ok = :gen_udp.controlling_process(socket, task.pid)
    send(task.pid, :ready)
    {task, port}
  end

  defp loop(socket, owner, endpoint) do
    receive do
      {:udp, ^socket, host, port, bytes} ->
        {:ok, message} = Codec.decode(bytes)
        send(owner, {:wire, host, port, message})
        loop(socket, owner, {host, port})

      {:reply, message} ->
        {:ok, bytes} = Codec.encode(message)
        {host, port} = endpoint
        :ok = :gen_udp.send(socket, host, port, bytes)
        loop(socket, owner, endpoint)

      :close ->
        :gen_udp.close(socket)
    after
      5_000 -> flunk("telemetry peer was not closed")
    end
  end

  defp wire do
    assert_receive {:wire, host, port, message}, 1_500
    %{host: host, port: port, message: message}
  end

  defp close(peer) do
    send(peer.pid, :close)
    assert :ok = Task.await(peer)
  end
end
