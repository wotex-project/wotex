defmodule Wotex.BACnet.COVLifecycleTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet
  alias Wotex.BACnet.{BACstack, Error, IPv4, Subscription, Tags}
  @moduletag :capture_log
  @destination {{127, 0, 0, 1}, 55_828}
  @fixture Jason.decode!(File.read!(Path.expand("../../fixtures/cov_lifecycle_v1.json", __DIR__)))

  setup context do
    # The admission case holds all 64 requests before responding. Reserve enough
    # peer receive capacity for that burst, including the kernel's UDP accounting.
    {:ok, peer} =
      :gen_udp.open(55_828, [:binary, active: false, ip: {127, 0, 0, 1}, recbuf: 262_144])

    {:ok, session} =
      BACnet.connect(
        client: IPv4,
        local_ip: :none,
        local_port: 55_829,
        destination: @destination,
        timeout: Map.get(context, :session_timeout, 500)
      )

    on_exit(fn ->
      BACnet.disconnect(session)
      :gen_udp.close(peer)
    end)

    request = %{
      type: :cov,
      object_type: 1,
      instance: 0,
      device_instance: 123,
      lifetime: 2,
      renew: false,
      receiver: self()
    }

    %{peer: peer, session: session, request: request}
  end

  test "WBA-S04 WBA-V06 WBA-V10 early report waits for registration ACK and cancel retains identity",
       c do
    subscribing = Task.async(fn -> BACnet.subscribe(c.session, c.request) end)
    {invoke, 5, parameters} = service(c.peer)

    [
      {:tagged, {0, bytes, _}},
      {:tagged, {1, object, 4}},
      {:tagged, {2, <<1>>, 1}},
      {:tagged, {3, <<2>>, 1}}
    ] = parameters

    identifier = :binary.decode_unsigned(bytes)
    report(c.peer, identifier, 44, 1.5)
    assert {:ok, {_, _, <<0x81, 0x0A, _::16, 1, 0, 0x20, 44, 1>>}} = :gen_udp.recv(c.peer, 0, 1000)
    assert Task.yield(subscribing, 10) == nil
    refute_receive {:wotex_bacnet, _, _}, 10
    send_apdu(c.peer, <<0x20, invoke, 5>>)
    assert {:ok, %Subscription{} = subscription} = Task.await(subscribing)
    ref = subscription.reference

    assert_receive {:wotex_bacnet, ^ref,
                    {:ok, [%{property: 85, value: %Encoding{type: :real, value: 1.5}}], metadata}},
                   1000

    assert metadata.device_instance == 123 and metadata.source == @destination

    assert metadata.report_values == [
             %{property: 85, array_index: nil, priority: nil, value: Encoding.create!({:real, 1.5})}
           ]

    cancelling = Task.async(fn -> BACnet.unsubscribe(c.session, subscription) end)
    {cancel_invoke, 5, cancel_parameters} = service(c.peer)
    assert cancel_parameters == [{:tagged, {0, bytes, byte_size(bytes)}}, {:tagged, {1, object, 4}}]
    send_apdu(c.peer, <<0x20, cancel_invoke, 5>>)
    assert :ok = Task.await(cancelling)
    assert :ok = BACnet.unsubscribe(c.session, subscription)
    assert :sys.get_state(c.session.handle.stack.client).cov.filters == %{}
    assert :sys.get_state(c.session.handle.stack.client).sdk.apdu_timers == %{}
    assert :sys.get_state(c.session.handle.stack.owner).subscriptions == %{}
  end

  test "WBA-CL01 WBA-S04 WBA-V07 WBA-V08 confirmed receipt ACKs retain fresh content", c do
    row = fixture("WBA-CL01")
    {subscription, identifier, _} = subscribe(c)
    ref = subscription.reference

    acknowledgments =
      for value <- row["input"]["values"] do
        report(c.peer, identifier, row["input"]["invoke_id"], value)
        acknowledgment(c.peer, row["input"]["invoke_id"])
      end

    assert length(acknowledgments) == row["expected"]["ack_count"]

    for value <- row["expected"]["delivered_values"] do
      assert_receive {:wotex_bacnet, ^ref, {:ok, [%{value: %Encoding{value: ^value}}], _}}
    end

    refute_receive {:wotex_bacnet, ^ref, _}, 20
    cancel(c, subscription)

    assert map_size(:sys.get_state(c.session.handle.stack.owner).subscriptions) ==
             row["expected"]["live_subscriptions_after_cancel"]
  end

  test "WBA-S04 WBA-V08 equal unconfirmed Property values remain distinct and retain companions",
       c do
    request =
      Map.merge(c.request, %{type: :cov_property, property: 85, array_index: 0, confirmed: false})

    {subscription, identifier, _} = subscribe(%{c | request: request})
    ref = subscription.reference
    values = <<9, 85, 0x19, 0, 0x2E, 0x44, 1.5::float-32, 0x2F, 9, 111, 0x2E, 0x82, 4, 0, 0x2F>>

    for _ <- 1..2, do: report_values(c.peer, identifier, nil, values)

    for _ <- 1..2 do
      assert_receive {:wotex_bacnet, ^ref, {:ok, %Encoding{value: 1.5}, metadata}}, 1000
      assert metadata.property == 85 and metadata.array_index == 0

      assert [
               %{property: 85},
               %{
                 property: 111,
                 value: %Encoding{type: :bitstring, value: {false, false, false, false}}
               }
             ] = metadata.report_values
    end

    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 20)
    cancel(c, subscription)
  end

  test "WBA-S04 WBA-V07 missing or foreign selectors acquire no acknowledgment context", c do
    request = Map.merge(c.request, %{type: :cov_property, property: 85, array_index: 0})
    {subscription, identifier, _} = subscribe(%{c | request: request})
    values = <<9, 85, 0x19, 0, 0x2E, 0x44, 1.5::float-32, 0x2F>>
    report_values(c.peer, identifier + 1, 41, values)
    report_values(c.peer, identifier, 42, values, device: 124)
    report_values(c.peer, identifier, 43, values, object: 2)
    report_values(c.peer, identifier, 44, values, instance: 1)
    report(c.peer, identifier, 45, 1.5)
    report_values(c.peer, identifier, 46, <<9, 111, 0x2E, 0x10, 0x2F>>)
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 30)
    refute_receive {:wotex_bacnet, _, _}, 10
    assert :sys.get_state(c.session.handle.stack.client).cov.replies == %{}
    report_values(c.peer, identifier, 47, values)
    acknowledgment(c.peer, 47)
    assert_receive {:wotex_bacnet, _, {:ok, %Encoding{value: 1.5}, _}}
    cancel(c, subscription)
  end

  test "WBA-S04 WBA-V07 conflicting selected values terminate before success ACK", c do
    request = Map.merge(c.request, %{type: :cov_property, property: 85})
    {subscription, identifier, _} = subscribe(%{c | request: request})
    ref = subscription.reference
    values = <<9, 85, 0x2E, 0x44, 1.5::float-32, 0x2F, 9, 85, 0x2E, 0x44, 2.5::float-32, 0x2F>>
    report_values(c.peer, identifier, 44, values)
    assert_receive {:wotex_bacnet, ^ref, {:error, %Error{code: :conflicting_cov_values}}}, 1000
    finish_automatic_cancel(c, subscription)
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 20)
  end

  test "WBA-S04 WBA-V06 negative opening ACK fails without publishing a handle", c do
    task = Task.async(fn -> BACnet.subscribe(c.session, c.request) end)
    {invoke, 5, _} = service(c.peer)
    send_apdu(c.peer, <<0x50, invoke, 5, 0x91, 5, 0x91, 9>>)

    assert {:error, %Error{code: :remote_error, effect: :none, details: %{class: 5, code: 9}}} =
             Task.await(task)

    {cancel_id, 5, tags} = service(c.peer)
    assert length(tags) == 2
    send_apdu(c.peer, <<0x20, cancel_id, 5>>)
    refute_receive {:wotex_bacnet, _, _}, 20
  end

  test "WBA-S04 WBA-V11 lost registration ACK attempts original-route cancellation", c do
    task = Task.async(fn -> BACnet.subscribe(c.session, c.request) end)
    {invoke, 5, [identity, object | _]} = service(c.peer)
    assert {:error, %Error{effect: :none}} = Task.await(task)
    {cancel_id, 5, tags} = service(c.peer)
    assert tags == [identity, object]
    assert cancel_id != invoke
    send_apdu(c.peer, <<0x20, cancel_id, 5>>)
    refute_receive {:wotex_bacnet, _, _}, 20
  end

  test "WBA-S04 WBA-V09 renewal uses half lifetime, fresh invoke ID, and stable identity", c do
    {subscription, _, initial_id} = subscribe(%{c | request: %{c.request | renew: true}})
    state = :sys.get_state(subscription.pid)
    started = state.expiry - c.request.lifetime * 1000
    {renew_id, 5, tags} = service(c.peer)
    assert (System.monotonic_time(:millisecond) - started) in 900..1500
    assert renew_id != initial_id

    assert [
             {:tagged, {0, _, _}},
             {:tagged, {1, _, _}},
             {:tagged, {2, <<1>>, 1}},
             {:tagged, {3, <<2>>, 1}}
           ] = tags

    send_apdu(c.peer, <<0x20, renew_id, 5>>)
    send(subscription.pid, {:renew, make_ref()})
    # The wire ACK is processed asynchronously; the stale token test uses the next committed lease.
    renewed = await_renewal(subscription.pid, state.expiry)
    send(subscription.pid, {:expire, state.lifetime_token})
    assert :sys.get_state(subscription.pid).lifetime_token == renewed.lifetime_token
    cancel(c, subscription)
  end

  test "WBA-S04 WBA-V09 lost renewal ACK emits one terminal error and releases the lease", c do
    {subscription, _, _} = subscribe(%{c | request: %{c.request | renew: true}})
    ref = subscription.reference
    {_invoke, 5, _tags} = service(c.peer)
    assert_receive {:wotex_bacnet, ^ref, {:error, %Error{effect: :none}}}, 1000
    finish_automatic_cancel(c, subscription)
    refute_receive {:wotex_bacnet, ^ref, _}, 20
    assert :sys.get_state(c.session.handle.stack.owner).controls == %{}
  end

  test "WBA-S04 WBA-V11 forged, foreign, and dead subscription handles are finite", c do
    {subscription, _, _} = subscribe(c)

    for forged <- [
          %{subscription | pid: self()},
          %{subscription | reference: make_ref()},
          %{subscription | generation: make_ref()},
          %{subscription | session_generation: make_ref()},
          %{subscription | pid: nil}
        ] do
      assert {:error, %Error{code: :invalid_subscription}} = BACnet.unsubscribe(c.session, forged)
    end

    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 20)
    cancel(c, subscription)
    refute Process.alive?(subscription.pid)
    assert :ok = BACnet.unsubscribe(c.session, subscription)
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 20)
  end

  test "WBA-S04 WBA-V11 receiver death terminates only its subscription", c do
    receiver =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {subscription, _, _} = subscribe(%{c | request: %{c.request | receiver: receiver}})
    Process.exit(receiver, :kill)
    finish_automatic_cancel(c, subscription)
    assert Process.alive?(c.session.handle.stack.owner)
    assert Process.alive?(c.session.handle.stack.client)
  end

  test "WBA-S04 WBA-V11 full receiver mailbox causes finite terminal cleanup", c do
    receiver =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> Process.exit(receiver, :kill) end)
    request = Map.merge(c.request, %{receiver: receiver, max_queue_length: 1})
    {subscription, identifier, _} = subscribe(%{c | request: request})
    send(receiver, :occupied)
    report(c.peer, identifier, 44, 1.5)
    acknowledgment(c.peer, 44)
    finish_automatic_cancel(c, subscription)

    assert {:messages, [queued, terminal]} = Process.info(receiver, :messages)
    assert queued == :occupied
    assert {:wotex_bacnet, _, {:error, %Error{code: :receiver_overflow}}} = terminal
  end

  @tag session_timeout: 5000
  test "WBA-CL02 WBA-S03 WBA-S04 WBA-V14 opening controls share read admission", c do
    row = fixture("WBA-CL02")

    tasks =
      for _ <- 1..row["input"]["opening_controls"],
          do: Task.async(fn -> BACnet.subscribe(c.session, c.request) end)

    initial = for _ <- tasks, do: service(c.peer)
    before = :sys.get_state(c.session.handle.stack.owner)
    assert map_size(before.controls) == row["input"]["opening_controls"]
    assert map_size(before.subscriptions) == row["expected"]["admitted_subscriptions"]
    assert {:error, %Error{code: overflow, effect: :none}} = BACnet.subscribe(c.session, c.request)
    assert Atom.to_string(overflow) == row["expected"]["overflow_code"]

    assert {:error, %Error{code: read_overflow, effect: :none}} =
             BACnet.send(c.session, %{
               type: :read_property,
               object_type: 1,
               instance: 0,
               property: 85
             })

    assert Atom.to_string(read_overflow) == row["expected"]["read_overflow_code"]
    assert :sys.get_state(c.session.handle.stack.owner).controls == before.controls
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
    for {invoke, service, _} <- initial, do: send_apdu(c.peer, <<0x20, invoke, service>>)

    subscriptions =
      for task <- tasks do
        assert {:ok, subscription} = Task.await(task)
        subscription
      end

    assert :sys.get_state(c.session.handle.stack.owner).controls == %{}
    assert {:error, %Error{code: :busy}} = BACnet.subscribe(c.session, c.request)

    cancellations =
      for subscription <- subscriptions,
          do: Task.async(fn -> BACnet.unsubscribe(c.session, subscription) end)

    for _ <- cancellations do
      {invoke, service, _} = service(c.peer)
      send_apdu(c.peer, <<0x20, invoke, service>>)
    end

    for task <- cancellations, do: assert(:ok = Task.await(task))

    assert map_size(:sys.get_state(c.session.handle.stack.owner).subscriptions) ==
             row["expected"]["live_subscriptions_after_cancel"]

    assert map_size(:sys.get_state(c.session.handle.stack.client).cov.filters) ==
             row["expected"]["local_listeners_after_cancel"]

    assert map_size(:sys.get_state(c.session.handle.stack.client).sdk.apdu_timers) ==
             row["expected"]["sdk_requests_after_cancel"]
  end

  test "WBA-S04 WBA-V11 abrupt subscription-owner death kills linked children and informs receiver",
       c do
    {subscription, _, _} = subscribe(c)
    ref = subscription.reference
    state = :sys.get_state(subscription.pid)
    listener = Process.monitor(state.listener)
    Process.exit(subscription.pid, :kill)
    assert_receive {:DOWN, ^listener, :process, _, :killed}, 100
    assert_receive {:wotex_bacnet, ^ref, {:error, %Error{code: :connection_closed}}}, 100
    assert :sys.get_state(c.session.handle.stack.client).cov.filters == %{}
    assert :ok = BACnet.unsubscribe(c.session, subscription)
  end

  test "WBA-S04 WBA-V11 listener death cancels active remote state", c do
    {subscription, _, _} = subscribe(c)
    ref = subscription.reference
    Process.exit(:sys.get_state(subscription.pid).listener, :kill)
    assert_receive {:wotex_bacnet, ^ref, {:error, %Error{code: :connection_closed}}}, 100
    finish_automatic_cancel(c, subscription)
  end

  test "WBA-S04 WBA-V11 a blocked listener ACK cannot delay borrowed cleanup for SDK call timeout",
       c do
    {:ok, borrowed} =
      BACnet.connect(
        client: BACstack,
        stack_client: c.session.handle.stack.client,
        stack_client_kind: :wotex,
        destination: @destination,
        timeout: 100
      )

    on_exit(fn -> BACnet.disconnect(borrowed) end)
    {subscription, identifier, _} = subscribe(%{c | session: borrowed})
    state = :sys.get_state(subscription.pid)
    client = c.session.handle.stack.client
    :ok = :sys.suspend(state.listener)
    report(c.peer, identifier, 44, 1.5)
    await_reply_context(client)
    :ok = :sys.suspend(client)
    :ok = :sys.resume(state.listener)
    await_call(client, :reply)
    listener_monitor = Process.monitor(state.listener)
    started = System.monotonic_time(:millisecond)
    assert {:error, %Error{code: :deadline_exceeded}} = BACnet.unsubscribe(borrowed, subscription)
    assert System.monotonic_time(:millisecond) - started < 1100
    assert_receive {:DOWN, ^listener_monitor, :process, _, :killed}, 100
    refute Process.alive?(subscription.pid)
    assert Process.alive?(client)
    :ok = :sys.resume(client)
    assert :sys.get_state(client).cov.filters == %{}
    assert :sys.get_state(client).cov.replies == %{}
    assert :sys.get_state(client).sdk.apdu_timers == %{}
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 20)
  end

  test "WBA-S04 WBA-V11 two distinct early reports close without exposing a subscription", c do
    task = Task.async(fn -> BACnet.subscribe(c.session, c.request) end)
    {_invoke, 5, [{:tagged, {0, bytes, _}} | _]} = service(c.peer)
    identifier = :binary.decode_unsigned(bytes)

    for {invoke, value} <- [{44, 1.5}, {45, 2.5}] do
      report(c.peer, identifier, invoke, value)
      acknowledgment(c.peer, invoke)
    end

    assert {:error, %Error{code: :receiver_overflow}} = Task.await(task)
    {cancel_id, 5, tags} = service(c.peer)
    assert length(tags) == 2
    send_apdu(c.peer, <<0x20, cancel_id, 5>>)
    refute_receive {:wotex_bacnet, _, _}, 20
  end

  test "WBA-S04 WBA-V11 a killed opening caller closes listener and cancels original identity", c do
    caller = spawn(fn -> BACnet.subscribe(c.session, c.request) end)
    {_invoke, 5, [identity, object | _]} = service(c.peer)
    [{pid, _}] = Map.to_list(:sys.get_state(c.session.handle.stack.owner).subscriptions)
    monitor = Process.monitor(pid)
    Process.exit(caller, :kill)
    {cancel_id, 5, tags} = service(c.peer)
    assert tags == [identity, object]
    send_apdu(c.peer, <<0x20, cancel_id, 5>>)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1000
    assert :sys.get_state(c.session.handle.stack.client).cov.filters == %{}
  end

  test "WBA-CL03 WBA-S04 WBA-V09 server lifetime metadata cannot extend the local lease", c do
    row = fixture("WBA-CL03")
    assert c.request.lifetime == row["input"]["requested_lifetime_seconds"]
    {subscription, identifier, _} = subscribe(c)
    ref = subscription.reference
    expiry = :sys.get_state(subscription.pid).expiry

    for remaining <- row["input"]["server_time_remaining"] do
      values = <<9, 85, 0x2E, 0x44, 1.5::float-32, 0x2F>>
      report_values(c.peer, identifier, 44, values, remaining: remaining)
      acknowledgment(c.peer, 44)
      assert_receive {:wotex_bacnet, ^ref, {:ok, _, %{time_remaining: ^remaining}}}, 1000

      assert :sys.get_state(subscription.pid).expiry - expiry ==
               row["expected"]["local_expiry_changes"]
    end

    assert_receive {:wotex_bacnet, ^ref, {:error, %Error{code: code}}}, 2100
    assert Atom.to_string(code) == row["expected"]["terminal_error"]
    finish_automatic_cancel(c, subscription)
    refute_receive {:wotex_bacnet, ^ref, {:error, _}}, 10
    assert row["expected"]["terminal_count"] == 1
  end

  test "WBA-S03 WBA-S04 WBA-V11 session disconnect waits for subscription cancellation and closes owned sockets",
       c do
    {subscription, _, _} = subscribe(c)
    group = :sys.get_state(c.session.handle.owner)
    task = Task.async(fn -> BACnet.disconnect(c.session) end)
    {invoke, 5, tags} = service(c.peer)
    assert length(tags) == 2
    send_apdu(c.peer, <<0x20, invoke, 5>>)
    assert :ok = Task.await(task)
    refute Process.alive?(subscription.pid)

    for key <- [:transport, :client, :segmentator, :segments_store],
        do: refute(Process.alive?(group[key]))

    {:ok, socket} = :gen_udp.open(55_829, [:binary])
    :gen_udp.close(socket)
  end

  test "WBA-S03 WBA-S04 WBA-V11 one shared cleanup grace kills a paused SDK and listener", c do
    {subscription, _, _} = subscribe(c)
    group = :sys.get_state(c.session.handle.owner)
    :ok = :sys.suspend(group.client)
    started = System.monotonic_time(:millisecond)
    assert :ok = BACnet.disconnect(c.session)
    assert System.monotonic_time(:millisecond) - started < 1100
    refute Process.alive?(subscription.pid)

    for key <- [:transport, :client, :segmentator, :segments_store],
        do: refute(Process.alive?(group[key]))

    {:ok, socket} = :gen_udp.open(55_829, [:binary])
    :gen_udp.close(socket)
  end

  test "WBA-S04 WBA-V11 negative cancellation ACK preserves error and still releases all local state",
       c do
    {subscription, _, _} = subscribe(c)
    task = Task.async(fn -> BACnet.unsubscribe(c.session, subscription) end)
    {invoke, 5, _} = service(c.peer)
    assert {:error, %Error{code: :busy}} = BACnet.unsubscribe(c.session, subscription)
    send_apdu(c.peer, <<0x50, invoke, 5, 0x91, 5, 0x91, 9>>)
    assert {:error, %Error{code: :remote_error, effect: :none}} = Task.await(task)
    refute Process.alive?(subscription.pid)
    assert :sys.get_state(c.session.handle.stack.client).cov.filters == %{}
    assert :ok = BACnet.unsubscribe(c.session, subscription)
  end

  test "WBA-S04 WBA-V11 dead receiver and expired queue entries emit no registration", c do
    receiver = spawn(fn -> :ok end)
    monitor = Process.monitor(receiver)
    assert_receive {:DOWN, ^monitor, :process, _, _}

    assert {:error, %Error{code: :receiver_closed}} =
             BACnet.subscribe(c.session, %{c.request | receiver: receiver})

    {:ok, request} = Wotex.BACnet.COVRequest.new(c.request, self())
    owner = c.session.handle.stack.owner
    generation = c.session.handle.stack.generation

    assert {:error, %Error{code: :deadline_exceeded}} =
             Wotex.BACnet.OperationOwner.subscribe(
               owner,
               generation,
               request,
               System.monotonic_time(:millisecond),
               100
             )

    assert {:error, %Error{code: :connection_closed}} =
             Wotex.BACnet.OperationOwner.subscribe(
               owner,
               make_ref(),
               request,
               System.monotonic_time(:millisecond) + 100,
               100
             )

    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 20)
  end

  test "WBA-S04 WBA-V11 paused SDK registration expires without later emission", c do
    client = c.session.handle.stack.client
    :ok = :sys.suspend(client)

    assert {:error, %Error{code: :deadline_exceeded}} =
             BACnet.subscribe(%{c.session | timeout: 10}, c.request)

    :ok = :sys.resume(client)
    assert :sys.get_state(client).cov.filters == %{}
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 30)
  end

  test "WBA-S04 WBA-V11 killed registration worker returns a finite error and cancels", c do
    task = Task.async(fn -> BACnet.subscribe(c.session, c.request) end)
    {_invoke, 5, _} = service(c.peer)
    [{pid, _}] = Map.to_list(:sys.get_state(c.session.handle.stack.owner).subscriptions)
    Process.exit(:sys.get_state(pid).control.worker, :kill)
    assert {:error, %Error{code: :connection_closed}} = Task.await(task)
    {invoke, 5, _} = service(c.peer)
    send_apdu(c.peer, <<0x20, invoke, 5>>)
    refute_receive {:wotex_bacnet, _, _}, 20
  end

  @tag session_timeout: 5000
  test "WBA-S03 WBA-S04 WBA-V09 renewal honors shared capacity and never retries", c do
    {subscription, _, _} = subscribe(%{c | request: %{c.request | renew: true}})
    ref = subscription.reference

    reads =
      for _ <- 1..64,
          do:
            Task.async(fn ->
              BACnet.send(c.session, %{
                type: :read_property,
                object_type: 1,
                instance: 0,
                property: 85
              })
            end)

    for _ <- reads, do: assert({_, 12, _} = service(c.peer))
    monitor = Process.monitor(subscription.pid)
    assert_receive {:wotex_bacnet, ^ref, {:error, %Error{code: :busy}}}, 1200
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1000
    assert :sys.get_state(c.session.handle.stack.owner).controls == %{}
    assert :sys.get_state(c.session.handle.stack.client).cov.filters == %{}
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
    BACnet.disconnect(c.session)
    for task <- reads, do: assert({:error, %Error{code: :connection_closed}} = Task.await(task))
  end

  test "WBA-C08 WBA-S04 subscription telemetry exposes counts and finite outcomes only", c do
    receiver = self()
    handler = make_ref()

    :ok =
      :telemetry.attach_many(
        handler,
        for(event <- [:open, :deliver, :close], do: [:wotex, :bacnet, :subscription, event]),
        fn event, measurements, metadata, receiver ->
          send(receiver, {:metric, event, measurements, metadata})
        end,
        receiver
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    {subscription, identifier, _} = subscribe(c)
    secret = "payload-canary-credential"
    value = <<9, 85, 0x2E, 0x65, byte_size(secret), secret::binary, 0x2F>>
    report_values(c.peer, identifier, 44, value)
    acknowledgment(c.peer, 44)
    assert_receive {:wotex_bacnet, _, {:ok, [%{value: %Encoding{value: ^secret}}], _}}
    cancel(c, subscription)

    for event <- [:open, :deliver, :close] do
      assert_receive {:metric, [:wotex, :bacnet, :subscription, ^event], %{count: 1}, metadata}
      assert metadata == %{result: :ok}
      refute inspect(metadata) =~ secret
    end

    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
  end

  test "WBA-C05 WBA-S04 session generation and live membership are checked by the original owner",
       c do
    {subscription, _, _} = subscribe(c)
    generation = make_ref()
    forged_stack = %{c.session.handle.stack | generation: generation}
    forged_session = %{c.session | handle: %{c.session.handle | stack: forged_stack}}

    assert {:error, %Error{code: :invalid_subscription}} =
             BACnet.unsubscribe(forged_session, %{subscription | session_generation: generation})

    owner = c.session.handle.stack.owner

    assert {:error, %Error{code: :connection_closed}} =
             GenServer.call(owner, {:cov_lease, self(), generation})

    send(owner, {:cov_established, self(), subscription})
    send(owner, {:cov_cancelled, self(), :ok})
    send(owner, {:cov_control_release, subscription.pid, make_ref()})
    assert :sys.get_state(owner).controls == %{}
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
    cancel(c, subscription)
  end

  test "WBA-S04 WBA-V11 session shutdown with an opening caller releases its waiter", c do
    task = Task.async(fn -> BACnet.subscribe(c.session, c.request) end)
    {_invoke, 5, _} = service(c.peer)
    closing = Task.async(fn -> BACnet.disconnect(c.session) end)
    {invoke, 5, _} = service(c.peer)
    send_apdu(c.peer, <<0x20, invoke, 5>>)
    assert {:error, %Error{code: :connection_closed}} = Task.await(task)
    assert :ok = Task.await(closing)
  end

  defp await_reply_context(client, attempts \\ 100)
  defp await_reply_context(_, 0), do: flunk("missing SDK reply context")

  defp await_reply_context(client, attempts) do
    if map_size(:sys.get_state(client).cov.replies) == 0 do
      Process.sleep(1)
      await_reply_context(client, attempts - 1)
    end
  end

  defp await_call(client, command, attempts \\ 100)
  defp await_call(_, _, 0), do: flunk("missing SDK call")

  defp await_call(client, command, attempts) do
    {:messages, messages} = Process.info(client, :messages)

    if Enum.any?(messages, fn
         {:"$gen_call", _, {^command, _, _, _}} -> true
         _ -> false
       end) do
      :ok
    else
      Process.sleep(1)
      await_call(client, command, attempts - 1)
    end
  end

  defp subscribe(c) do
    task = Task.async(fn -> BACnet.subscribe(c.session, c.request) end)
    {invoke, service, [{:tagged, {0, identifier, _}} | _]} = service(c.peer)
    assert service in [5, 28]
    send_apdu(c.peer, <<0x20, invoke, service>>)
    assert {:ok, %Subscription{} = subscription} = Task.await(task)
    {subscription, :binary.decode_unsigned(identifier), invoke}
  end

  defp cancel(c, subscription) do
    task = Task.async(fn -> BACnet.unsubscribe(c.session, subscription) end)
    {invoke, service, tags} = service(c.peer)
    assert length(tags) in [2, 3]
    send_apdu(c.peer, <<0x20, invoke, service>>)
    assert :ok = Task.await(task)
    refute Process.alive?(subscription.pid)
    assert :sys.get_state(c.session.handle.stack.client).cov.filters == %{}
  end

  defp finish_automatic_cancel(c, subscription) do
    monitor = Process.monitor(subscription.pid)
    {invoke, service, tags} = service(c.peer)
    assert length(tags) in [2, 3]
    send_apdu(c.peer, <<0x20, invoke, service>>)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1100
    assert :sys.get_state(c.session.handle.stack.client).cov.filters == %{}
    assert :sys.get_state(c.session.handle.stack.client).sdk.apdu_timers == %{}
  end

  defp await_renewal(pid, old_expiry, attempts \\ 100)
  defp await_renewal(_, _, 0), do: flunk("renewal did not commit")

  defp await_renewal(pid, old_expiry, attempts) do
    state = :sys.get_state(pid)

    if state.expiry > old_expiry do
      state
    else
      receive do
      after
        5 -> await_renewal(pid, old_expiry, attempts - 1)
      end
    end
  end

  defp acknowledgment(peer, invoke) do
    assert {:ok, {_, _, <<0x81, 0x0A, _::16, 1, 0, 0x20, ^invoke, 1>>}} =
             :gen_udp.recv(peer, 0, 1000)
  end

  defp report_values(peer, identifier, invoke, values, opts \\ []) do
    device = Keyword.get(opts, :device, 123)
    object = Keyword.get(opts, :object, 1)
    instance = Keyword.get(opts, :instance, 0)
    remaining = Keyword.get(opts, :remaining, 2)
    header = if invoke, do: <<2, 0x65, invoke, 1>>, else: <<16, 2>>

    send_apdu(
      peer,
      <<header::binary, 9, identifier, 0x1C, 8::10, device::22, 0x2C, object::10, instance::22,
        0x3C, remaining::32, 0x4E, values::binary, 0x4F>>
    )
  end

  defp fixture(id), do: Enum.find(@fixture["cases"], &(&1["id"] == id))

  defp service(peer) do
    assert {:ok, {_, _, <<0x81, 0x0A, _::16, 1, 4, _, _, invoke, service, bytes::binary>>}} =
             :gen_udp.recv(peer, 0, 1500)

    assert {:ok, parameters} = Tags.decode(bytes)
    {invoke, service, parameters}
  end

  defp report(peer, identifier, invoke, value) do
    send_apdu(
      peer,
      <<2, 0x65, invoke, 1, 0x09, identifier, 0x1C, 8::10, 123::22, 0x2C, 1::10, 0::22, 0x39, 2,
        0x4E, 0x09, 85, 0x2E, 0x44, value::float-32, 0x2F, 0x4F>>
    )
  end

  defp send_apdu(peer, apdu),
    do:
      :gen_udp.send(
        peer,
        {127, 0, 0, 1},
        55_829,
        <<0x81, 0x0A, byte_size(apdu) + 6::16, 1, 4, apdu::binary>>
      )
end
