defmodule Wotex.BACnet.RuntimeStreamTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.BACnet.{Error, IPv4, RuntimeHandle, RuntimeRelay, Tags, Transport}
  alias Wotex.BACnet.Test.RuntimeCredentials
  alias Wotex.Runtime.{ConsumedThing, Context, Subscription}
  @moduletag :capture_log

  setup do
    {:ok, peer} = :gen_udp.open(55_834, [:binary, active: false, ip: {127, 0, 0, 1}])
    on_exit(fn -> :gen_udp.close(peer) end)

    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "COV test",
        "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
        "security" => ["none"],
        "properties" => %{
          "reading" => %{
            "type" => "number",
            "observable" => true,
            "forms" => [
              %{"href" => "bacnet://123/1,7/85", "op" => ["observeproperty"]},
              %{"href" => "bacnet://999/2,8/77", "op" => ["unobserveproperty"]}
            ]
          }
        }
      })

    {:ok, profile} = Wotex.BACnet.profile(:ip_cov)

    config = [
      client: IPv4,
      local_ip: :none,
      local_port: 55_835,
      destination: {{127, 0, 0, 1}, 55_834},
      target: "123",
      timeout: 500,
      cov: %{lifetime: 2, renew: false}
    ]

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{bacnet_cov: {Transport, config}},
        credentials: {RuntimeCredentials, []}
      )

    {:ok, context} = Context.new(request_id: "observation-1")

    {:ok, spec} =
      ConsumedThing.observation_child_spec(consumed, "reading", context,
        id: :reading,
        receiver: self(),
        restart: :temporary,
        max_queue_length: 1000,
        overflow: :stop
      )

    %{peer: peer, spec: spec, config: config}
  end

  test "WBA-S05 WBA-I05 WBA-V12 real Runtime observation owns native Property COV", c do
    peer = c.peer
    owner = start_supervised!(c.spec)
    {invoke, [{:tagged, {0, bytes, _}} | tags]} = service(peer)
    identifier = :binary.decode_unsigned(bytes)

    assert [
             {:tagged, {1, <<1::10, 7::22>>, 4}},
             {:tagged, {2, <<1>>, 1}},
             {:tagged, {3, <<2>>, 1}},
             {:constructed, {4, {:tagged, {0, <<85>>, 1}}, 0}}
           ] = tags

    send_apdu(peer, <<0x20, invoke, 28>>)

    send_apdu(
      peer,
      <<2, 0x65, 44, 1, 9, identifier, 0x1C, 8::10, 123::22, 0x2C, 1::10, 7::22, 0x39, 2, 0x4E, 9,
        85, 0x2E, 0x44, 1.5::float-32, 0x2F, 0x4F>>
    )

    assert {:ok, {_, _, <<0x81, 0x0A, _::16, 1, 0, 0x20, 44, 1>>}} = :gen_udp.recv(peer, 0, 1000)
    assert_receive {:wotex_runtime, :reading, {:ok, 1.5, metadata}}, 1000
    assert metadata.device_instance == 123 and metadata.property == 85
    assert metadata.object_type == 1 and metadata.instance == 7
    stop = Task.async(fn -> Subscription.stop(owner) end)
    {cancel_id, cancel_tags} = service(peer)

    assert [
             {:tagged, {0, ^bytes, _}},
             {:tagged, {1, <<1::10, 7::22>>, 4}},
             {:constructed, {4, {:tagged, {0, <<85>>, 1}}, 0}}
           ] = cancel_tags

    send_apdu(peer, <<0x20, cancel_id, 28>>)
    assert :ok = Task.await(stop)
    {:ok, socket} = :gen_udp.open(55_835, [:binary])
    :gen_udp.close(socket)
  end

  test "WBA-S05 WBA-I05 receiver death closes the original native association", c do
    receiver =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    spec = %{c.spec | start: replace_receiver(c.spec.start, receiver)}
    owner = start_supervised!(spec)
    {invoke, _} = service(c.peer)
    send_apdu(c.peer, <<0x20, invoke, 28>>)
    relay = await_handle(owner, 100).pid
    native = :sys.get_state(relay).session.handle.stack.client
    monitor = Process.monitor(owner)
    Process.exit(receiver, :kill)
    acknowledge_cancel(c.peer)
    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, :receiver_down}}, 1100
    refute Process.alive?(relay)
    refute Process.alive?(native)
    assert_socket_free()
  end

  test "WBA-S05 WBA-I05 Runtime owner death interrupts opening and cancels server state", c do
    owner = start_supervised!(c.spec)
    {_, [identity, object | _]} = service(c.peer)
    Process.exit(owner, :kill)
    {invoke, tags} = service(c.peer)
    assert [^identity, ^object, _] = tags
    send_apdu(c.peer, <<0x20, invoke, 28>>)
    await_socket_free(1000)
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
  end

  test "WBA-S05 WBA-I05 malformed native generation and unrelated envelopes cannot reopen a stream",
       c do
    owner = start_supervised!(c.spec)
    {invoke, _} = service(c.peer)
    send_apdu(c.peer, <<0x20, invoke, 28>>)
    handle = await_handle(owner, 100)
    state = :sys.get_state(handle.pid)

    assert {:error, %Error{code: :invalid_subscription}} =
             RuntimeRelay.close(%{handle | generation: make_ref()})

    assert {:error, %Error{code: :invalid_subscription}} =
             RuntimeRelay.close(%RuntimeHandle{pid: nil, generation: make_ref()})

    send(handle.pid, {:wotex_bacnet, make_ref(), {:ok, :foreign, %{}}})
    send(handle.pid, {:runtime_subscribed, make_ref(), state.worker, {:ok, state.subscription}})
    send(handle.pid, {:opening_deadline, make_ref()})
    send(owner, {:wotex_transport_frame, :keepalive})
    refute_receive {:wotex_runtime, :reading, _}, 20
    assert Process.alive?(handle.pid)
    stop = Task.async(fn -> Subscription.stop(owner) end)
    acknowledge_cancel(c.peer)
    assert :ok = Task.await(stop)
    assert :ok = RuntimeRelay.close(handle)
  end

  test "WBA-S05 WBA-I05 killed native worker reports terminal loss through Runtime", c do
    owner = start_supervised!(c.spec)
    {invoke, _} = service(c.peer)
    send_apdu(c.peer, <<0x20, invoke, 28>>)
    relay = await_handle(owner, 100).pid
    state = :sys.get_state(relay)
    worker = state.worker
    client = state.session.handle.stack.client
    monitor = Process.monitor(owner)
    Process.exit(worker, :kill)
    assert_receive {:wotex_runtime, :reading, {:error, %Wotex.Runtime.Error{}}}, 1000
    assert_receive {:wotex_runtime, :reading, {:status, :session_lost}}, 1000
    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, :session_lost}}, 1100
    refute Process.alive?(client)
    refute_receive {:wotex_runtime, :reading, {:error, _}}, 10
    assert_socket_free()
  end

  test "WBA-S05 WBA-I05 wrong target and malformed COV configuration acquire no protocol resources",
       c do
    for change <- [[target: "124"], [cov: %{receiver: self()}], [cov: %{lifetime: 0}]] do
      spec = configure(c.spec, Keyword.merge(c.config, change))
      owner = start_supervised!(spec)
      monitor = Process.monitor(owner)
      assert_receive {:wotex_runtime, :reading, {:error, %Wotex.Runtime.Error{}}}, 1000
      assert_receive {:DOWN, ^monitor, :process, ^owner, reason}, 1000
      assert reason == :noproc or match?({:shutdown, _}, reason)
      assert_socket_free()
      assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
    end
  end

  test "WBA-C03 WBA-I05 paused SDK cleanup has one shared grace", c do
    owner = start_supervised!(c.spec)
    {invoke, _} = service(c.peer)
    send_apdu(c.peer, <<0x20, invoke, 28>>)
    relay = await_handle(owner, 100).pid
    state = :sys.get_state(relay)
    client = state.session.handle.stack.client
    :ok = :sys.suspend(client)
    started = System.monotonic_time(:millisecond)
    stop = Task.async(fn -> Subscription.stop(owner) end)
    await_closing(relay, 100)
    handle = %RuntimeHandle{pid: relay, generation: state.generation}
    assert {:error, %Error{code: :busy}} = RuntimeRelay.close(handle)

    assert {:error, %Wotex.Runtime.Error{code: :transport_unsubscribe_failed}} =
             Task.await(stop, 1300)

    await_socket_free(20)
    assert System.monotonic_time(:millisecond) - started <= 1150
    refute Process.alive?(client)
    refute Process.alive?(relay)
  end

  test "WBA-C03 WBA-I05 paused native session owner cannot restart a cleanup grace", c do
    owner = start_supervised!(c.spec)
    {invoke, _} = service(c.peer)
    send_apdu(c.peer, <<0x20, invoke, 28>>)
    relay = await_handle(owner, 100).pid
    state = :sys.get_state(relay)
    client = state.session.handle.stack.client
    native_owner = state.session.handle.stack.owner
    :ok = :sys.suspend(native_owner)
    :ok = :sys.suspend(client)
    started = System.monotonic_time(:millisecond)
    stop = Task.async(fn -> Subscription.stop(owner) end)

    assert {:error, %Wotex.Runtime.Error{code: :transport_unsubscribe_failed}} =
             Task.await(stop, 1300)

    await_socket_free(20)
    assert System.monotonic_time(:millisecond) - started <= 1150
    refute Process.alive?(client)
    refute Process.alive?(native_owner)
    refute Process.alive?(relay)
  end

  test "WBA-S05 WBA-I05 negative native establishment cannot publish an observation", c do
    owner = start_supervised!(c.spec)
    {invoke, _} = service(c.peer)
    send_apdu(c.peer, <<0x50, invoke, 28, 0x91, 5, 0x91, 9>>)
    acknowledge_cancel(c.peer)
    assert_receive {:wotex_runtime, :reading, {:error, %Wotex.Runtime.Error{}}}, 1100
    refute_receive {:wotex_runtime, :reading, {:ok, _, _}}, 10
    await_socket_free(50)
    refute Process.alive?(owner)
  end

  test "WBA-S05 WBA-I05 Runtime observation keeps a borrowed wrapper alive", c do
    {:ok, session} = Wotex.BACnet.connect(Keyword.drop(c.config, [:target, :cov]))
    client = session.handle.stack.client

    config = [
      client: Wotex.BACnet.BACstack,
      stack_client: client,
      stack_client_kind: :wotex,
      receive_policy: :wotex_bounded,
      destination: c.config[:destination],
      timeout: 500,
      target: "123",
      cov: %{lifetime: 2, renew: false}
    ]

    owner = start_supervised!(configure(c.spec, config))
    {invoke, _} = service(c.peer)
    send_apdu(c.peer, <<0x20, invoke, 28>>)
    relay = await_handle(owner, 100).pid
    stop = Task.async(fn -> Subscription.stop(owner) end)
    acknowledge_cancel(c.peer)
    assert :ok = Task.await(stop)
    refute Process.alive?(relay)
    assert Process.alive?(client)
    assert map_size(:sys.get_state(client).cov.filters) == 0
    assert :ok = Wotex.BACnet.disconnect(session)
    assert_socket_free()
  end

  test "WBA-C03 WBA-I05 forced Runtime cleanup preserves a paused borrowed client", c do
    {:ok, session} = Wotex.BACnet.connect(Keyword.drop(c.config, [:target, :cov]))
    client = session.handle.stack.client

    config = [
      client: Wotex.BACnet.BACstack,
      stack_client: client,
      stack_client_kind: :wotex,
      receive_policy: :wotex_bounded,
      destination: c.config[:destination],
      timeout: 500,
      target: "123",
      cov: %{lifetime: 2, renew: false}
    ]

    owner = start_supervised!(configure(c.spec, config))
    {invoke, _} = service(c.peer)
    send_apdu(c.peer, <<0x20, invoke, 28>>)
    relay = await_handle(owner, 100).pid
    native_owner = :sys.get_state(relay).session.handle.owner
    :ok = :sys.suspend(client)
    :ok = :sys.suspend(native_owner)
    monitor = Process.monitor(native_owner)
    stop = Task.async(fn -> Subscription.stop(owner) end)

    assert {:error, %Wotex.Runtime.Error{code: :transport_unsubscribe_failed}} =
             Task.await(stop, 1300)

    assert_receive {:DOWN, ^monitor, :process, ^native_owner, _}, 100
    refute Process.alive?(relay)
    assert Process.alive?(client)
    :ok = :sys.resume(client)
    assert map_size(:sys.get_state(client).cov.filters) == 0
    assert :ok = Wotex.BACnet.disconnect(session)
    assert_socket_free()
  end

  test "WBA-C03 WBA-I05 final receiver death interrupts pending Runtime establishment", c do
    receiver = spawn(fn -> receive do: (:stop -> :ok) end)
    spec = %{c.spec | start: replace_receiver(c.spec.start, receiver)}
    owner = start_supervised!(spec)
    {_, [identity, object | _]} = service(c.peer)
    monitor = Process.monitor(owner)
    started = System.monotonic_time(:millisecond)
    Process.exit(receiver, :kill)
    {invoke, tags} = service(c.peer)
    assert [^identity, ^object, _] = tags
    send_apdu(c.peer, <<0x20, invoke, 28>>)
    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, :receiver_down}}, 1100
    await_socket_free(50)
    assert System.monotonic_time(:millisecond) - started <= 1100
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
  end

  test "WBA-S05 WBA-V12 unsupported Event and credentials acquire no native resources", c do
    {_, _, [options]} = c.spec.start
    request = options.start_request
    {:ok, context} = Context.new(request_id: "invalid-security")
    execution = Wotex.Runtime.ExecutionContext.new(context, "credential-canary")

    assert {:error, %Error{code: :not_supported}} =
             Transport.subscribe(request, self(), execution, c.config)

    nosec = Wotex.Runtime.ExecutionContext.new(context, nil)
    event = %{request | operation: :subscribeevent, affordance_type: :event}

    assert {:error, %Error{code: :not_supported}} =
             Transport.subscribe(event, self(), nosec, c.config)

    assert {:error, %Error{code: :invalid_transport_context}} =
             Transport.request(request, nosec, c.config)

    assert_socket_free()
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
  end

  defp await_handle(_, 0), do: flunk("Runtime did not acquire its native handle")

  defp await_handle(owner, attempts) do
    case :sys.get_state(owner).handle do
      nil ->
        Process.sleep(1)
        await_handle(owner, attempts - 1)

      handle ->
        handle
    end
  end

  defp await_closing(_, 0), do: flunk("relay did not enter closing")

  defp await_closing(relay, attempts) do
    if :sys.get_state(relay).phase != :closing do
      Process.sleep(1)
      await_closing(relay, attempts - 1)
    end
  end

  defp replace_receiver({module, function, [options]}, receiver),
    do: {module, function, [%{options | receiver: receiver}]}

  defp configure(spec, config) do
    {module, function, [options]} = spec.start
    %{spec | start: {module, function, [%{options | transport: {Transport, config}}]}}
  end

  defp acknowledge_cancel(peer) do
    {invoke, tags} = service(peer)
    assert length(tags) == 3
    send_apdu(peer, <<0x20, invoke, 28>>)
  end

  defp assert_socket_free do
    {:ok, socket} = :gen_udp.open(55_835, [:binary])
    :gen_udp.close(socket)
  end

  defp await_socket_free(attempts) when attempts > 0 do
    case :gen_udp.open(55_835, [:binary]) do
      {:ok, socket} ->
        :gen_udp.close(socket)

      {:error, :eaddrinuse} ->
        Process.sleep(1)
        await_socket_free(attempts - 1)
    end
  end

  defp await_socket_free(_), do: flunk("owned socket not released")

  defp service(peer) do
    assert {:ok, {_, _, <<0x81, 0x0A, _::16, 1, 4, _, _, invoke, 28, bytes::binary>>}} =
             :gen_udp.recv(peer, 0, 1000)

    assert {:ok, tags} = Tags.decode(bytes)
    {invoke, tags}
  end

  defp send_apdu(peer, apdu),
    do:
      :gen_udp.send(
        peer,
        {127, 0, 0, 1},
        55_835,
        <<0x81, 0x0A, byte_size(apdu) + 6::16, 1, 4, apdu::binary>>
      )
end
