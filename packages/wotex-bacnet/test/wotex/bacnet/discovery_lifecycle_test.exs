defmodule Wotex.BACnet.DiscoveryLifecycleTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias BACnet.Protocol.{APDU, ObjectIdentifier}
  alias Wotex.BACnet
  alias Wotex.BACnet.{BACstack, Device, Error, IPv4}
  @moduletag :capture_log
  @port 55_839
  @peer_port 55_838

  setup do
    {:ok, peer} = :gen_udp.open(@peer_port, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, session} = open()

    on_exit(fn ->
      BACnet.disconnect(session)
      :gen_udp.close(peer)
    end)

    %{
      peer: peer,
      session: session,
      owner: session.handle.stack.owner,
      client: session.handle.stack.client
    }
  end

  test "WBA-N04 Who-Is registers first, deduplicates observations and keeps the original route",
       c do
    call = Task.async(fn -> BACnet.who_is(c.session) end)
    assert <<0x10, 8>> = service(c.peer)
    discovery = :sys.get_state(c.owner).discovery
    assert discovery.pid in listeners(c.client)
    send_apdu(c.peer, i_am(10))
    send_apdu(c.peer, i_am(10))
    send_apdu(c.peer, i_am(11))
    assert {:ok, [%Device{instance: 10}, %Device{instance: 11}] = devices} = Task.await(call)
    assert Enum.all?(devices, &(&1.source == {{127, 0, 0, 1}, @peer_port}))
    refute Process.alive?(discovery.pid)
    assert Process.read_timer(discovery.timer) == false
    assert listeners(c.client) == []
    assert :sys.get_state(c.owner).discovery == nil
    assert c.session.handle.stack.destination == {{127, 0, 0, 1}, @peer_port}
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
  end

  test "WBA-N04 range bytes filter both boundaries and ignore malformed reports", c do
    call = Task.async(fn -> BACnet.who_is(c.session, 1, 10) end)
    assert <<0x10, 8, 9, 1, 25, 10>> = service(c.peer)
    send_apdu(c.peer, i_am(0))
    send_apdu(c.peer, i_am(11))
    send_apdu(c.peer, <<0x10, 0>>)
    send_apdu(c.peer, i_am(1))
    send_apdu(c.peer, i_am(10))
    assert {:ok, [%Device{instance: 1}, %Device{instance: 10}]} = Task.await(call)
    assert listeners(c.client) == []
  end

  test "WBA-N04 identical instance from two sources remains two observations", c do
    {:ok, second} = :gen_udp.open(55_840, [:binary, active: false, ip: {127, 0, 0, 1}])
    on_exit(fn -> :gen_udp.close(second) end)
    call = Task.async(fn -> BACnet.who_is(c.session) end)
    service(c.peer)
    send_apdu(second, i_am(10))
    send_apdu(c.peer, i_am(10))

    assert {:ok, [%Device{source: {_, @peer_port}}, %Device{source: {_, 55_840}}]} =
             Task.await(call)
  end

  test "WBA-N04 conflicting observation rejects all results and releases the listener", c do
    call = Task.async(fn -> BACnet.who_is(c.session) end)
    service(c.peer)
    send_apdu(c.peer, i_am(10))
    send_apdu(c.peer, i_am(10, 50))
    assert {:error, %Error{code: :conflicting_discovery_response, effect: :none}} = Task.await(call)
    assert listeners(c.client) == []
  end

  test "WBA-N04 discovery is optional and neither incomplete limits nor forged routes perform I/O",
       c do
    assert {:error, %Error{code: :invalid_discovery_range}} = BACnet.who_is(c.session, 1)
    assert {:error, %Error{code: :invalid_session}} = BACnet.who_is(nil)
    assert {:error, %Error{code: :invalid_discovery_range}} = BACnet.who_is(c.session, 10, 1)
    session = c.session
    missing = put_in(session.handle.stack.discovery, nil)
    assert {:error, %Error{code: :discovery_not_configured}} = BACnet.who_is(missing)
    forged = put_in(session.handle.stack.discovery.destination, {{127, 0, 0, 1}, 55_840})
    assert {:error, %Error{code: :invalid_discovery_options}} = BACnet.who_is(forged)
    assert listeners(c.client) == []
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
  end

  test "WBA-N04 only one discovery is admitted and borrowed raw SDK mode rejects before registration",
       c do
    call = Task.async(fn -> BACnet.who_is(c.session) end)
    service(c.peer)
    assert {:error, %Error{code: :discovery_busy}} = BACnet.who_is(c.session)
    assert {:ok, []} = Task.await(call)

    options = [
      client: BACstack,
      stack_client: c.client,
      discovery: discovery(),
      destination: {{127, 0, 0, 1}, @peer_port},
      timeout: 500
    ]

    {:ok, raw} = BACnet.connect(options)
    assert {:error, %Error{code: :not_supported}} = BACnet.who_is(raw)
    assert :ok = BACnet.disconnect(raw)
    assert Process.alive?(c.client)
    assert listeners(c.client) == []
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
  end

  test "WBA-N04 paused SDK cannot send a stale Who-Is after caller death", c do
    :ok = :sys.suspend(c.client)
    caller = spawn(fn -> BACnet.who_is(c.session) end)
    discovery = await_discovery(c.owner)
    Process.exit(caller, :kill)
    :ok = :sys.resume(c.client)
    assert_stopped(discovery.pid)
    assert listeners(c.client) == []
    assert Process.alive?(c.client)
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 20)
  end

  test "WBA-N04 disconnect releases listener and pending discovery under its shared grace", c do
    call = Task.async(fn -> BACnet.who_is(c.session) end)
    service(c.peer)
    discovery = :sys.get_state(c.owner).discovery
    started = System.monotonic_time(:millisecond)
    assert :ok = BACnet.disconnect(c.session)
    assert System.monotonic_time(:millisecond) - started <= 1100
    assert {:error, %Error{code: :connection_closed}} = Task.await(call)
    refute Process.alive?(discovery.pid)
    refute Process.alive?(c.client)
    assert {:ok, socket} = :gen_udp.open(@port, [:binary])
    :gen_udp.close(socket)
  end

  test "WBA-N04 exceeding the configured limit returns no truncated success", c do
    call = Task.async(fn -> BACnet.who_is(c.session) end)
    service(c.peer)
    for instance <- 1..3, do: send_apdu(c.peer, i_am(instance))
    assert {:error, %Error{code: :discovery_limit}} = Task.await(call)
    assert listeners(c.client) == []
  end

  test "WBA-C03 WBA-N04 interaction deadline cutting the discovery window is not an empty success",
       c do
    call = Task.async(fn -> BACnet.who_is(%{c.session | timeout: 30}) end)
    service(c.peer)
    assert {:error, %Error{code: :deadline_exceeded}} = Task.await(call)
    assert listeners(c.client) == []
    assert Process.alive?(c.client)
  end

  test "WBA-C03 WBA-N04 a suspended collection owner is reaped by its session watchdog", c do
    call = Task.async(fn -> BACnet.who_is(c.session) end)
    service(c.peer)
    discovery = :sys.get_state(c.owner).discovery
    :ok = :sys.suspend(discovery.pid)
    assert {:error, %Error{code: :deadline_exceeded}} = Task.await(call, 2000)
    refute Process.alive?(discovery.pid)
    assert listeners(c.client) == []
    assert Process.alive?(c.client)
  end

  test "WBA-N04 explicit borrowed wrapper discovery and cleanup preserve its socket owner", c do
    {:ok, borrowed} =
      BACnet.connect(
        client: BACstack,
        stack_client: c.client,
        stack_client_kind: :wotex,
        discovery: discovery(),
        destination: {{127, 0, 0, 1}, @peer_port},
        timeout: 500
      )

    call = Task.async(fn -> BACnet.who_is(borrowed) end)
    service(c.peer)
    send_apdu(c.peer, i_am(10))
    assert {:ok, [%Device{instance: 10}]} = Task.await(call)
    assert :ok = BACnet.disconnect(borrowed)
    assert Process.alive?(c.client)
    assert Process.alive?(c.owner)
    assert listeners(c.client) == []
  end

  test "WBA-N04 queued unconfirmed dispatch checks both the absolute deadline and sender liveness",
       c do
    alias Wotex.BACnet.{DiscoveryOptions, StackClient}
    {:ok, apdu} = DiscoveryOptions.request(nil, nil)
    destination = {{127, 0, 0, 1}, @peer_port}
    :ok = :sys.suspend(c.client)
    deadline = System.monotonic_time(:millisecond) + 1000
    worker = spawn(fn -> StackClient.exchange(c.client, destination, apdu, [], deadline) end)
    wait_until(fn -> queued?(c.client, worker) end)
    Process.exit(worker, :kill)
    :ok = :sys.resume(c.client)
    assert listeners(c.client) == []
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)

    assert {:error, %Error{code: :deadline_exceeded}} =
             StackClient.exchange(
               c.client,
               destination,
               apdu,
               [],
               System.monotonic_time(:millisecond) - 1
             )

    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
  end

  test "WBA-N04 final Who-Is emission requires original caller custody even while its wire worker lives",
       c do
    alias Wotex.BACnet.{DiscoveryOptions, StackClient}
    {:ok, apdu} = DiscoveryOptions.request(nil, nil)
    deadline = System.monotonic_time(:millisecond) + 1000

    caller =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    assert :ok = GenServer.call(c.client, {:wotex_client, :register_discovery, deadline})
    :ok = :sys.suspend(c.client)
    listener = self()

    worker =
      Task.async(fn ->
        StackClient.discovery_send(
          c.client,
          {{127, 0, 0, 1}, @peer_port},
          apdu,
          deadline,
          caller,
          listener
        )
      end)

    wait_until(fn -> queued?(c.client, worker.pid) end)
    Process.exit(caller, :kill)
    :ok = :sys.resume(c.client)
    assert {:error, %Error{code: :connection_closed}} = Task.await(worker)
    assert :ok = GenServer.call(c.client, {:wotex_client, :unregister_discovery})
    assert listeners(c.client) == []
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
  end

  test "WBA-N04 adapter callbacks reject expired and forged discovery state without allocating",
       c do
    now = System.monotonic_time(:millisecond)

    for {adapter, handle} <- [{IPv4, c.session.handle}, {BACstack, c.session.handle.stack}] do
      assert {:error, %Error{code: :invalid_request}} = adapter.who_is(nil, nil, nil, 100)
      assert {:error, %Error{code: :invalid_request}} = adapter.who_is(handle, nil, nil, 0)

      assert {:error, %Error{code: :invalid_request}} =
               adapter.who_is_deadline(nil, nil, nil, now, now + 500)

      assert {:error, %Error{code: :deadline_exceeded}} =
               adapter.who_is_deadline(handle, nil, nil, now - 100, now + 400)
    end

    config = c.session.handle.stack
    forged = %{config | generation: make_ref()}
    assert {:error, %Error{code: :connection_closed}} = BACstack.who_is(forged, nil, nil, 500)

    for window <- [nil, %{started: :invalid, deadline: now + 500, low: nil, high: nil}] do
      assert {:error, %Error{code: :invalid_discovery_options}} =
               GenServer.call(c.owner, {:discover, config.generation, window})
    end

    assert listeners(c.client) == []
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
    call = Task.async(fn -> IPv4.who_is(c.session.handle, nil, nil, 500) end)
    assert <<0x10, 8>> = service(c.peer)
    assert {:ok, []} = Task.await(call)
  end

  test "WBA-C03 WBA-N04 explicit disconnect reaps a suspended discovery actor and its socket", c do
    call = Task.async(fn -> BACnet.who_is(c.session) end)
    service(c.peer)
    discovery = :sys.get_state(c.owner).discovery
    :ok = :sys.suspend(discovery.pid)
    started = System.monotonic_time(:millisecond)
    assert :ok = BACnet.disconnect(c.session)
    assert System.monotonic_time(:millisecond) - started <= 1200
    assert {:error, %Error{code: :connection_closed}} = Task.await(call)
    refute Process.alive?(discovery.pid)
    refute Process.alive?(c.client)
    assert {:ok, socket} = :gen_udp.open(@port, [:binary])
    :gen_udp.close(socket)
  end

  test "WBA-N04 discovery shares all 64 admission slots with confirmed reads in both directions",
       c do
    {:ok, borrowed} =
      BACnet.connect(
        client: BACstack,
        stack_client: c.client,
        stack_client_kind: :wotex,
        discovery: %{discovery() | timeout_ms: 500},
        destination: {{127, 0, 0, 1}, @peer_port},
        timeout: 2000
      )

    on_exit(fn -> BACnet.disconnect(borrowed) end)

    calls = for _ <- 1..64, do: Task.async(fn -> BACnet.read_property(borrowed, 1, 0, 85) end)
    invocations = for _ <- calls, do: read_invocation(c.peer)
    assert {:error, %Error{code: :busy}} = BACnet.who_is(borrowed)
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
    complete_reads(c.peer, invocations, calls)

    discovery = Task.async(fn -> BACnet.who_is(borrowed) end)
    assert <<0x10, 8>> = service(c.peer)
    calls = for _ <- 1..63, do: Task.async(fn -> BACnet.read_property(borrowed, 1, 0, 85) end)
    invocations = for _ <- calls, do: read_invocation(c.peer)
    assert {:error, %Error{code: :busy}} = BACnet.read_property(borrowed, 1, 0, 85)
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
    complete_reads(c.peer, invocations, calls)
    assert {:ok, []} = Task.await(discovery)
    assert :sys.get_state(borrowed.handle.owner).pending == %{}
    assert :sys.get_state(borrowed.handle.owner).discovery == nil
    assert listeners(c.client) == []
  end

  defp read_invocation(peer) do
    assert <<flags, _, invoke, 12, _::binary>> = service(peer)
    assert flags in [0, 2]
    invoke
  end

  defp complete_reads(peer, invocations, calls) do
    for invoke <- invocations,
        do: send_apdu(peer, <<0x30, invoke, 12, 0x0C, 1::10, 0::22, 0x19, 85, 0x3E, 0, 0x3F>>)

    for call <- calls,
        do:
          assert(
            {:ok, %Elixir.BACnet.Protocol.ApplicationTags.Encoding{type: :null, value: nil}} =
              Task.await(call)
          )
  end

  defp queued?(client, worker) do
    {:messages, messages} = Process.info(client, :messages)

    Enum.any?(messages, fn
      {:"$gen_call", {^worker, _}, _} -> true
      _ -> false
    end)
  end

  defp wait_until(fun, remaining \\ 100)
  defp wait_until(fun, 0), do: assert(fun.())

  defp wait_until(fun, remaining) do
    unless fun.() do
      Process.sleep(1)
      wait_until(fun, remaining - 1)
    end
  end

  defp open do
    BACnet.connect(
      client: IPv4,
      local_ip: :none,
      local_port: @port,
      destination: {{127, 0, 0, 1}, @peer_port},
      timeout: 500,
      discovery: discovery()
    )
  end

  defp discovery, do: %{destination: {{127, 0, 0, 1}, @peer_port}, timeout_ms: 60, max_devices: 2}
  defp listeners(client), do: :sys.get_state(client).sdk.notification_receiver

  defp service(peer) do
    assert {:ok, {{127, 0, 0, 1}, @port, <<0x81, 10, _::16, 1, control, apdu::binary>>}} =
             :gen_udp.recv(peer, 0, 500)

    assert control in [0, 4]
    apdu
  end

  defp send_apdu(peer, apdu),
    do:
      :gen_udp.send(
        peer,
        {127, 0, 0, 1},
        @port,
        <<0x81, 10, byte_size(apdu) + 6::16, 1, 0, apdu::binary>>
      )

  defp i_am(instance, max_apdu \\ 1476) do
    apdu = %APDU.UnconfirmedServiceRequest{
      service: :i_am,
      parameters: [
        {:object_identifier, %ObjectIdentifier{type: :device, instance: instance}},
        {:unsigned_integer, max_apdu},
        {:enumerated, 3},
        {:unsigned_integer, 260}
      ]
    }

    {:ok, bytes} = APDU.UnconfirmedServiceRequest.encode(apdu)
    IO.iodata_to_binary(bytes)
  end

  defp await_discovery(owner, attempts \\ 100)
  defp await_discovery(_, 0), do: flunk("discovery was never admitted")

  defp await_discovery(owner, attempts) do
    case :sys.get_state(owner).discovery do
      nil ->
        Process.sleep(1)
        await_discovery(owner, attempts - 1)

      discovery ->
        discovery
    end
  end

  defp assert_stopped(pid) do
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1100
  end
end
