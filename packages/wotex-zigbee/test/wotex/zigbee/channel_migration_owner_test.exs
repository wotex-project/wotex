defmodule Wotex.Zigbee.ChannelMigrationOwnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee

  alias Wotex.Zigbee.{
    ChannelMigration,
    Config,
    Credentials,
    Error,
    Interview,
    Owner,
    Routes,
    TestCredentials,
    TestMigrationSerial
  }

  alias Wotex.Zigbee.ChannelMigration.Result

  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>
  @extended <<0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8>>
  @device <<0, @ieee::binary, 0::little-16, 7, 9, 0>>
  @peers [
    %{peer_ieee: <<9::64>>, route_address: 0x1234, source_endpoint: 2, destination_endpoint: 1},
    %{peer_ieee: <<10::64>>, route_address: 0x2345, source_endpoint: 2, destination_endpoint: 1}
  ]

  test "fresh custody, local channel and every peer observation share one finite lifetime" do
    {handle, peer, credentials, routes} = open()
    monitor = Process.monitor(handle.owner)
    request = request()
    call = Task.async(fn -> Zigbee.migrate_channel(handle, credentials, routes, request, 1_000) end)
    assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}
    assert {:error, %Error{kind: :overload}} = Zigbee.inspect_network(handle, 1_000)
    metadata(peer, 15, true)
    assert_receive {:credential_request, _, context, budget}
    assert context.operation == :channel_migration
    assert context.request == request and context.owner_epoch == handle.epoch
    assert context.network.owner_epoch == handle.epoch
    assert budget > 0 and budget == context.deadline_ms - context.now_ms
    admin(peer)
    metadata(peer, 20)

    for {expected, index} <- Enum.with_index(@peers) do
      token = probe(expected.route_address)
      assert token == index + 2
      response = incoming(expected.route_address, token, <<0, 0, 0, 0x20, 8>>, index)
      confirmation = wire(0x44, 0x80, <<0, 2, token>>)
      admission = wire(0x64, 1, <<0>>)

      bytes =
        if index == 0,
          do: response <> confirmation <> admission,
          else: admission <> confirmation <> response

      send(peer, {:inject, bytes})
    end

    assert {:ok, %Result{outcome: :observed_cohort, issue: nil} = result} = Task.await(call)
    assert result.before.readings |> Enum.map(& &1.payload) == [@device, network(15)]
    assert result.after.readings |> Enum.map(& &1.payload) == [@device, network(20)]
    assert result.admission.id == 0x37 and result.admission.status == 0
    assert Enum.map(result.peers, & &1.outcome) == [:responsive, :responsive]
    assert Enum.map(result.peers, & &1.response.security_used) == [false, true]
    assert Enum.map(result.peers, & &1.peer) == @peers
    assert Enum.all?(result.peers, &(&1.response.owner_epoch == handle.epoch))
    refute inspect(result) =~ "credential-canary"
    closed(monitor, peer)
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.inspect_network(handle, 1_000)
  end

  test "one missing application response remains partial while a later peer is observed" do
    {handle, peer, credentials, routes} = open()

    call =
      Task.async(fn ->
        Zigbee.migrate_channel(handle, credentials, routes, request(peer_timeout_ms: 40), 1_000)
      end)

    migrate(peer)
    first = probe(0x1234)
    send(peer, {:inject, wire(0x64, 1, <<0>>) <> wire(0x44, 0x80, <<0, 2, first>>)})
    second = probe(0x2345)
    send(peer, {:inject, incoming(0x1234, first) <> wire(0x45, 0xCB, <<0>>)})
    wait_state(handle.owner, &(&1.event_count == 2))
    assert {:ok, %{events: events, dropped: 0}} = Zigbee.drain_events(handle, 128)
    assert Enum.map(events, & &1.kind) == [:af_incoming, :permit_join_indication]
    success(peer, 0x2345, second)
    assert {:ok, %Result{outcome: :partial, issue: nil, peers: [first, second]}} = Task.await(call)
    assert first.outcome == :unconfirmed and first.issue == :timeout
    assert first.admission.status == 0 and first.confirmation.status == 0 and first.response == nil
    assert second.outcome == :responsive
    refute_receive {:serial_write, _}, 10
  end

  test "NCP and APS failures retain different per-peer outcomes without global success" do
    {handle, peer, credentials, routes} = open()

    call =
      Task.async(fn -> Zigbee.migrate_channel(handle, credentials, routes, request(), 1_000) end)

    migrate(peer)
    first = probe(0x1234)
    send(peer, {:inject, wire(0x64, 1, <<0xA7>>)})
    second = probe(0x2345)
    send(peer, {:inject, wire(0x44, 0x80, <<0xCD, 2, second>>) <> wire(0x64, 1, <<0>>)})
    assert {:ok, %Result{outcome: :partial, peers: [a, b]}} = Task.await(call)
    assert a.outcome == :ncp_rejected and a.admission.status == 0xA7 and a.response == nil
    assert b.outcome == :aps_failed and b.confirmation.status == 0xCD
    assert first != second
  end

  test "wrong sources, endpoints, tokens and ZCL headers remain queued until a matched probe" do
    {handle, peer, credentials, routes} = open()

    call =
      Task.async(fn ->
        Zigbee.migrate_channel(handle, credentials, routes, request(peer_timeout_ms: 500), 1_000)
      end)

    migrate(peer)
    token = probe(0x1234)

    wrong = [
      incoming(0x2345, token),
      incoming(0x1234, token + 1),
      incoming(0x1234, token, <<0, 0, 0, 0x20, 8>>, 1, 2, 2),
      incoming(0x1234, token, <<0, 0, 0, 0x20, 8>>, 1, 1, 3),
      raw_incoming(0x1234, <<0x10, token, 1, 0, 0, 0, 0x20, 8>>),
      raw_incoming(0x1234, <<0x1C, 0x34, 0x12, token, 1, 0, 0, 0, 0x20, 8>>),
      raw_incoming(0x1234, <<0x18, token, 1, 0, 0, 0, 0x20>>),
      wire(0x44, 0x80, <<0, 3, token>>)
    ]

    send(peer, {:inject, IO.iodata_to_binary(wrong)})
    wait_state(handle.owner, &(&1.event_count == length(wrong)))
    assert {:ok, %{events: events}} = Zigbee.drain_events(handle, 128)
    assert length(events) == length(wrong)
    refute_receive {:serial_write, _}, 10
    success(peer, 0x1234, token)
    second = probe(0x2345)
    success(peer, 0x2345, second)
    assert {:ok, %Result{outcome: :observed_cohort}} = Task.await(call)
  end

  test "null, duplicate, failed or unexpected Basic records preserve raw partial evidence" do
    for records <- [
          <<0, 0, 0, 0x20, 255>>,
          <<0, 0, 0x86>>,
          <<1, 0, 0, 0x20, 8>>,
          <<0, 0, 0, 0x20, 8, 0, 0, 0, 0x20, 8>>,
          <<0, 0, 0, 0x21, 8, 0>>,
          <<0, 0, 0, 0xF0, 0xAA, 0, 0, 0, 0x20, 8>>
        ] do
      {handle, peer, credentials, routes} = open()

      call =
        Task.async(fn -> Zigbee.migrate_channel(handle, credentials, routes, request(), 1_000) end)

      migrate(peer)
      token = probe(0x1234)
      success(peer, 0x1234, token, records)
      second = probe(0x2345)
      success(peer, 0x2345, second)
      assert {:ok, %Result{outcome: :partial, peers: [first, _]}} = Task.await(call)
      assert first.outcome == :responsive and first.issue == :invalid_value
      assert first.response.payload == <<0x18, token, 1, records::binary>>
    end
  end

  test "malformed values, raw administration and absent/stale/expired custody refuse before I/O" do
    {handle, _, credentials, routes} = open()
    {:ok, empty} = Routes.new(handle.epoch)
    {:ok, stale} = Routes.rebind(routes, make_ref())

    for {port, table, request} <- [
          {nil, routes, request()},
          {credentials, routes, nil},
          {Map.put(credentials, :key, "credential-canary"), routes, request()},
          {credentials, routes, Map.put(request(), :key, "credential-canary")},
          {credentials, routes, %{request() | peers: [hd(@peers) | :bad]}}
        ] do
      assert {:error, %Error{kind: :invalid_value} = error} =
               Zigbee.migrate_channel(handle, port, table, request, 1_000)

      refute inspect(error) =~ "credential-canary"
    end

    for {table, kind} <- [{nil, :invalid_value}, {empty, :unknown_route}, {stale, :stale_epoch}] do
      assert {:error, %Error{kind: ^kind}} =
               Zigbee.migrate_channel(handle, credentials, table, request(), 1_000)
    end

    for timeout <- [nil, 0, 1_001] do
      assert {:error, %Error{kind: :invalid_value}} =
               Zigbee.migrate_channel(handle, credentials, routes, request(), timeout)
    end

    assert {:error, %Error{kind: :stale_handle}} =
             Zigbee.migrate_channel(nil, credentials, routes, request(), 1_000)

    {:ok, frame} = ChannelMigration.frame(request())
    assert {:error, %Error{kind: :invalid_command}} = Owner.call(handle, :command, [frame, 1_000])
    refute_receive {:serial_write, _}, 10
    refute_receive {:credential_request, _, _, _}, 10
  end

  test "unknown original network refuses before authorization and leaves the owner usable" do
    {handle, peer, credentials, routes} = open()

    call =
      Task.async(fn -> Zigbee.migrate_channel(handle, credentials, routes, request(), 1_000) end)

    metadata(peer, 26)

    assert {:ok, result} = Task.await(call)
    assert %Result{outcome: :unconfirmed, issue: :network_mismatch, admission: nil} = result

    assert result.before.outcome == :observed and result.after == nil
    refute_receive {:credential_request, _, _, _}, 10
    refute_receive {:serial_write, _}, 10
    assert Process.alive?(handle.owner)
  end

  test "the old local channel never establishes peer migration after NCP admission" do
    {handle, peer, credentials, routes} = open()
    monitor = Process.monitor(handle.owner)

    call =
      Task.async(fn -> Zigbee.migrate_channel(handle, credentials, routes, request(), 1_000) end)

    metadata(peer, 15)
    assert_receive {:credential_request, _, _, _}
    admin(peer)
    metadata(peer, 15)

    assert {:ok, %Result{outcome: :unconfirmed, issue: :network_mismatch} = result} =
             Task.await(call)

    assert result.admission.status == 0 and result.after.outcome == :observed
    assert Enum.all?(result.peers, &(&1.response == nil and &1.admission == nil))
    refute_receive {:serial_write, _}, 10
    closed(monitor, peer)
  end

  test "a rejected local-copy send retains the unknown broadcast outcome and closes" do
    {handle, peer, credentials, routes} = open()
    monitor = Process.monitor(handle.owner)

    call =
      Task.async(fn -> Zigbee.migrate_channel(handle, credentials, routes, request(), 1_000) end)

    metadata(peer, 15)
    assert_receive {:credential_request, _, _, _}
    admin(peer, 0xA7)
    assert {:ok, %Result{outcome: :unconfirmed, issue: :status_failure} = result} = Task.await(call)
    assert result.admission.status == 0xA7 and result.after == nil
    refute_receive {:serial_write, _}, 10
    closed(monitor, peer)
  end

  test "denial, custody faults and expired authorization expose no private text or administration" do
    for {behavior, kind} <- [
          {:deny, :credential_denied},
          {:raise, :credentials},
          {:throw, :credentials},
          {:exit, :credentials},
          {:malformed, :credentials},
          {:bad_horizon, :credentials},
          {:huge_horizon, :credentials},
          {{:horizon, 0}, :timeout}
        ] do
      {handle, peer, credentials, routes} = open(credentials: behavior)

      call =
        Task.async(fn -> Zigbee.migrate_channel(handle, credentials, routes, request(), 1_000) end)

      metadata(peer, 15)
      assert_receive {:credential_request, _, _, _}

      assert {:ok, %Result{outcome: :unconfirmed, issue: ^kind, admission: nil} = result} =
               Task.await(call)

      assert result.before.outcome == :observed and result.after == nil
      refute inspect(result) =~ "credential-canary"
      assert Process.alive?(handle.owner)
      refute_receive {:serial_write, _}, 10
    end
  end

  test "authorization must cover the qualified settling delay before administrative dispatch" do
    {handle, peer, credentials, routes} = open(credentials: {:horizon, 40})

    call =
      Task.async(fn ->
        Zigbee.migrate_channel(handle, credentials, routes, request(settle_ms: 500), 1_000)
      end)

    metadata(peer, 15)
    assert_receive {:credential_request, _, _, _}
    assert {:ok, %Result{outcome: :unconfirmed, issue: :timeout, after: nil}} = Task.await(call)
    refute_receive {:serial_write, _}, 10
    assert Process.alive?(handle.owner)
  end

  test "an admitted horizon expires during observation without extending the original budget" do
    {handle, peer, credentials, routes} = open(credentials: {:horizon, 80})
    monitor = Process.monitor(handle.owner)

    call =
      Task.async(fn -> Zigbee.migrate_channel(handle, credentials, routes, request(), 1_000) end)

    metadata(peer, 15)
    assert_receive {:credential_request, _, _, _}
    admin(peer)
    assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}

    assert {:ok,
            %Result{
              outcome: :unconfirmed,
              issue: :timeout,
              after: %{outcome: :partial, readings: []}
            }} = Task.await(call)

    refute_receive {:serial_write, _}, 10
    closed(monitor, peer)
  end

  test "a delayed serial write cannot consume the reserved settling interval" do
    {handle, peer, credentials, routes} =
      open(credentials: {:horizon, 100}, migration_write: {:delay, 70})

    monitor = Process.monitor(handle.owner)

    call =
      Task.async(fn ->
        Zigbee.migrate_channel(handle, credentials, routes, request(settle_ms: 60), 1_000)
      end)

    metadata(peer, 15)
    assert_receive {:credential_request, _, _, _}
    assert_receive {:serial_write, <<0xFE, 11, 0x25, 0x37, _::binary>>}
    assert {:ok, %Result{issue: :timeout, admission: nil, after: nil}} = Task.await(call)
    closed(monitor, peer)
    refute_receive {:serial_write, _}, 10
  end

  test "an unanswered AF SREQ cannot be skipped even when another peer remains" do
    {handle, peer, credentials, routes} = open()
    monitor = Process.monitor(handle.owner)

    call =
      Task.async(fn ->
        Zigbee.migrate_channel(handle, credentials, routes, request(peer_timeout_ms: 40), 1_000)
      end)

    migrate(peer)
    first = probe(0x1234)
    send(peer, {:inject, incoming(0x1234, first) <> wire(0x44, 0x80, <<0, 2, first>>)})
    assert {:ok, %Result{outcome: :partial, issue: :timeout, peers: [a, b]}} = Task.await(call)
    assert a.response != nil and a.admission == nil and a.outcome == :unconfirmed
    assert b.response == nil and b.admission == nil and b.outcome == :unconfirmed
    refute_receive {:serial_write, _}, 10
    closed(monitor, peer)
  end

  test "wrong or malformed synchronous replies end the epoch with available readings" do
    for response <- [wire(0x65, 0x36, <<0>>), wire(0x65, 0x37, <<0, 0>>)] do
      {handle, peer, credentials, routes} = open()
      monitor = Process.monitor(handle.owner)

      call =
        Task.async(fn -> Zigbee.migrate_channel(handle, credentials, routes, request(), 1_000) end)

      metadata(peer, 15)
      assert_receive {:credential_request, _, _, _}
      assert_receive {:serial_write, <<0xFE, 11, 0x25, 0x37, _::binary>>}
      send(peer, {:inject, response})
      assert {:ok, %Result{issue: :invalid_frame, admission: nil} = result} = Task.await(call)
      assert result.before.outcome == :observed
      closed(monitor, peer)
    end
  end

  test "administrative serial callback faults or late completion attempt cleanup once" do
    for behavior <- [:raise, :throw, :exit, :malformed, :error, {:delay, 130}] do
      {handle, peer, credentials, routes} = open(migration_write: behavior)
      monitor = Process.monitor(handle.owner)
      timeout = if is_tuple(behavior), do: 100, else: 1_000

      call =
        Task.async(fn ->
          Zigbee.migrate_channel(handle, credentials, routes, request(), timeout)
        end)

      metadata(peer, 15)
      assert_receive {:credential_request, _, _, _}
      assert {:ok, %Result{outcome: :unconfirmed, admission: nil} = result} = Task.await(call)
      assert result.issue == if(is_tuple(behavior), do: :timeout, else: :serial)
      assert result.before.outcome == :observed
      refute inspect(result) =~ "credential-canary"
      closed(monitor, peer)
    end
  end

  test "late custody authorization cannot dispatch and a known refusal preserves the owner" do
    {handle, peer, credentials, routes} = open(credentials: {:delay, 130})
    call = Task.async(fn -> Zigbee.migrate_channel(handle, credentials, routes, request(), 100) end)
    metadata(peer, 15)
    assert_receive {:credential_request, _, _, _}

    assert {:ok, %Result{issue: :timeout, admission: nil, before: %{outcome: :observed}}} =
             Task.await(call)

    refute_receive {:serial_write, _}, 10
    assert Process.alive?(handle.owner)
  end

  test "caller loss during credential custody cannot dispatch or keep an epoch alive" do
    {handle, peer, credentials, routes} = open(credentials: {:delay, 70})
    monitor = Process.monitor(handle.owner)
    caller = spawn(fn -> Zigbee.migrate_channel(handle, credentials, routes, request(), 1_000) end)
    metadata(peer, 15)
    assert_receive {:credential_request, _, _, _}
    Process.exit(caller, :kill)
    refute_receive {:serial_write, _}, 100
    closed(monitor, peer)
  end

  test "queued final observations cannot finish a dead caller's workflow before its DOWN message" do
    for last_leg <- [:before, :move, :peer] do
      {handle, peer, credentials, routes} = open()
      monitor = Process.monitor(handle.owner)

      caller =
        spawn(fn -> Zigbee.migrate_channel(handle, credentials, routes, request(), 1_000) end)

      bytes =
        case last_leg do
          :before ->
            assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}
            send(peer, {:inject, wire(0x67, 0, @device)})
            assert_receive {:serial_write, <<0xFE, 0, 0x25, 0x50, _>>}
            wire(0x65, 0x50, network(15))

          :move ->
            metadata(peer, 15)
            assert_receive {:credential_request, _, _, _}
            assert_receive {:serial_write, <<0xFE, 11, 0x25, 0x37, _::binary>>}
            wire(0x65, 0x37, <<0>>)

          :peer ->
            migrate(peer)
            token = probe(0x1234)
            success(peer, 0x1234, token)
            token = probe(0x2345)
            send(peer, {:inject, wire(0x64, 1, <<0>>) <> wire(0x44, 0x80, <<0, 2, token>>)})
            wait_state(handle.owner, &(&1.pending == nil))
            incoming(0x2345, token)
        end

      :ok = :sys.suspend(handle.owner)
      send(peer, {:inject, bytes})
      wait_message(handle.owner, &match?({:zigbee_serial, ^peer, _}, &1))
      Process.exit(caller, :kill)
      wait_message(handle.owner, &match?({:DOWN, _, :process, ^caller, _}, &1))
      :ok = :sys.resume(handle.owner)
      closed(monitor, peer)
      refute_receive {:serial_write, _}, 10
      if last_leg == :before, do: refute_receive({:credential_request, _, _, _}, 10)
    end
  end

  test "queued expiry before initial dispatch does no I/O and leaves admission usable" do
    {handle, _, credentials, routes} = open()
    :ok = :sys.suspend(handle.owner)
    call = Task.async(fn -> Zigbee.migrate_channel(handle, credentials, routes, request(), 20) end)
    wait_message(handle.owner, &match?({:"$gen_call", _, {:channel_migration, _, _}}, &1))
    Process.sleep(30)
    :ok = :sys.resume(handle.owner)
    assert {:error, %Error{kind: :timeout}} = Task.await(call)
    refute_receive {:serial_write, _}, 10
    refute_receive {:credential_request, _, _, _}, 10
    assert Process.alive?(handle.owner)
  end

  test "an already queued AF admission beyond its peer deadline cannot advance to another peer" do
    {handle, peer, credentials, routes} = open()
    monitor = Process.monitor(handle.owner)

    call =
      Task.async(fn ->
        Zigbee.migrate_channel(handle, credentials, routes, request(peer_timeout_ms: 50), 1_000)
      end)

    migrate(peer)
    token = probe(0x1234)
    :ok = :sys.suspend(handle.owner)

    send(
      peer,
      {:inject,
       wire(0x64, 1, <<0>>) <> wire(0x44, 0x80, <<0, 2, token>>) <> incoming(0x1234, token)}
    )

    wait_message(handle.owner, &match?({:zigbee_serial, ^peer, _}, &1))
    Process.sleep(60)
    :ok = :sys.resume(handle.owner)

    assert {:ok, %Result{outcome: :partial, issue: :timeout, peers: [first, second]}} =
             Task.await(call)

    assert first.admission == nil and first.outcome == :unconfirmed
    assert second.admission == nil and second.response == nil
    closed(monitor, peer)
    refute_receive {:serial_write, _}, 10
  end

  test "serial loss and explicit close preserve completed peers and never launch the next one" do
    for failure <- [:disconnect, :close] do
      {handle, peer, credentials, routes} = open()
      monitor = Process.monitor(handle.owner)

      call =
        Task.async(fn -> Zigbee.migrate_channel(handle, credentials, routes, request(), 1_000) end)

      migrate(peer)
      token = probe(0x1234)
      success(peer, 0x1234, token)
      probe(0x2345)

      case failure do
        :disconnect -> send(peer, {:disconnect, "credential-canary"})
        :close -> assert Zigbee.close(handle) == :ok
      end

      assert {:ok, result} = Task.await(call)
      assert %Result{outcome: :partial, issue: :coordinator_lost, peers: [first, second]} = result

      assert first.outcome == :responsive and first.issue == nil
      assert second.outcome == :unconfirmed and second.admission == nil
      assert result.before.outcome == :observed and result.after.outcome == :observed
      refute inspect(result) =~ "credential-canary"
      closed(monitor, peer)
      refute_receive {:serial_write, _}, 10
    end
  end

  test "metadata truncation before and after dispatch retains only available raw readings" do
    for phase <- [:before, :after] do
      {handle, peer, credentials, routes} = open()
      monitor = Process.monitor(handle.owner)

      call =
        Task.async(fn -> Zigbee.migrate_channel(handle, credentials, routes, request(), 1_000) end)

      if phase == :after do
        metadata(peer, 15)
        assert_receive {:credential_request, _, _, _}
        admin(peer)
      end

      assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}
      send(peer, {:inject, wire(0x67, 0, @device)})
      assert_receive {:serial_write, <<0xFE, 0, 0x25, 0x50, _>>}
      send(peer, {:inject, wire(0x65, 0x50, <<0>>)})

      assert {:ok, %Result{outcome: :unconfirmed, issue: :invalid_frame} = result} =
               Task.await(call)

      assert Map.fetch!(result, phase).outcome == :partial
      assert Enum.map(Map.fetch!(result, phase).readings, & &1.payload) == [@device]
      assert Enum.all?(result.peers, &(&1.admission == nil))
      closed(monitor, peer)
    end
  end

  test "custody expiry is rechecked after a blocking authorization callback" do
    {handle, peer, credentials, routes} = open(credentials: {:delay, 250}, lifetime: 200)

    call =
      Task.async(fn -> Zigbee.migrate_channel(handle, credentials, routes, request(), 1_000) end)

    metadata(peer, 15)
    assert_receive {:credential_request, _, _, _}
    assert {:ok, %Result{issue: :timeout, admission: nil}} = Task.await(call)
    refute_receive {:serial_write, _}, 10
    assert Process.alive?(handle.owner)

    assert {:error, %Error{kind: :route_expired}} =
             Zigbee.migrate_channel(handle, credentials, routes, request(), 1_000)
  end

  test "finite token exhaustion is refused before metadata or administrative dispatch" do
    {handle, peer, credentials, routes} = open()

    for token <- 2..254 do
      {:ok, frame} =
        Wotex.Zigbee.Command.data_request(0x1234, 1, 2, 0, token, <<0, token, 0, 0, 0>>)

      call = Task.async(fn -> Owner.call(handle, :command, [frame, 1_000]) end)
      probe(0x1234)
      send(peer, {:inject, wire(0x64, 1, <<0>>)})
      assert {:ok, _} = Task.await(call)
    end

    assert {:error, %Error{kind: :correlation_exhausted}} =
             Zigbee.migrate_channel(handle, credentials, routes, request(), 1_000)

    refute_receive {:credential_request, _, _, _}, 10
    refute_receive {:serial_write, _}, 10
    assert Process.alive?(handle.owner)
  end

  defp open(options \\ []) do
    credential_owner = TestCredentials.start(self(), Keyword.get(options, :credentials, :allow))
    on_exit(fn -> send(credential_owner, :stop) end)
    {:ok, credentials} = Credentials.new(TestCredentials, credential_owner)

    {:ok, config} =
      Config.new(
        serial: TestMigrationSerial,
        device_id: "simulated-coordinator",
        expected_version: {2, 0, 3, 2, 0},
        timeout_ms: 1_000,
        serial_options: [
          test_pid: self(),
          drop_reply: true,
          migration_write: Keyword.get(options, :migration_write, :ok)
        ]
      )

    {:ok, handle} = Zigbee.open(config)
    on_exit(fn -> Zigbee.close(handle) end)
    assert_receive {:serial_open, peer, _}
    assert_receive {:serial_write, <<0xFE, 0, 0x21, 2, _>>}
    {:ok, routes} = Routes.new(handle.epoch)

    routes =
      Enum.reduce(@peers, routes, fn expected, routes ->
        {:ok, interview} =
          Interview.new(
            peer_ieee: expected.peer_ieee,
            route_address: expected.route_address,
            source_endpoint: 2,
            basic_attributes: [0]
          )

        call = Task.async(fn -> Zigbee.interview(handle, interview, 1_000) end)
        route = expected.route_address
        assert_receive {:serial_write, <<0xFE, 4, 0x25, 1, _::binary>>}

        send(
          peer,
          {:inject,
           wire(0x65, 1, <<0>>) <>
             wire(0x45, 0x81, <<0, expected.peer_ieee::binary, route::little-16, 0, 0>>)}
        )

        assert_receive {:serial_write, <<0xFE, 4, 0x25, 2, _::binary>>}

        send(
          peer,
          {:inject,
           wire(0x65, 2, <<0>>) <>
             wire(0x45, 0x82, <<route::little-16, 0, route::little-16, 0::104>>)}
        )

        assert_receive {:serial_write, <<0xFE, 4, 0x25, 5, _::binary>>}

        endpoints = <<route::little-16, 0, route::little-16, 1, 1>>
        send(peer, {:inject, wire(0x65, 5, <<0>>) <> wire(0x45, 0x85, endpoints)})

        assert_receive {:serial_write, <<0xFE, 5, 0x25, 4, _::binary>>}
        descriptor = <<1, 0x0104::little-16, 1::little-16, 0, 1, 0::little-16, 0>>

        send(
          peer,
          {:inject,
           wire(0x65, 4, <<0>>) <>
             wire(
               0x45,
               0x84,
               <<route::little-16, 0, route::little-16, byte_size(descriptor), descriptor::binary>>
             )}
        )

        token = probe(route)
        success(peer, route, token)
        assert {:ok, %{outcome: :complete} = result} = Task.await(call)
        {:ok, routes} = Routes.adopt(routes, result, now(), Keyword.get(options, :lifetime, 20_000))
        routes
      end)

    {handle, peer, credentials, routes}
  end

  defp request(overrides \\ []) do
    {:ok, request} =
      ChannelMigration.new(
        Keyword.merge(
          [
            coordinator_ieee: @ieee,
            extended_pan_id: @extended,
            pan_id: 0x1234,
            channel: 15,
            target_channel: 20,
            settle_ms: 5,
            peer_timeout_ms: 100,
            peers: @peers,
            correlation_id: "migration"
          ],
          overrides
        )
      )

    request
  end

  defp migrate(peer) do
    metadata(peer, 15)
    assert_receive {:credential_request, _, _, _}
    admin(peer)
    metadata(peer, 20)
  end

  defp admin(peer, status \\ 0) do
    assert_receive {:serial_write,
                    <<0xFE, 11, 0x25, 0x37, 0xFD, 0xFF, 0x0F, 0, 0, 0x10, 0, 0xFE, 0, 0, 0, 0xFA>>}

    send(peer, {:inject, wire(0x65, 0x37, <<status>>)})
  end

  defp metadata(peer, channel, started \\ false) do
    unless started, do: assert_receive({:serial_write, <<0xFE, 0, 0x27, 0, _>>})
    send(peer, {:inject, wire(0x67, 0, @device)})
    assert_receive {:serial_write, <<0xFE, 0, 0x25, 0x50, _>>}
    send(peer, {:inject, wire(0x65, 0x50, network(channel))})
  end

  defp network(channel),
    do:
      <<0::little-16, 9, 0x1234::little-16, 0::little-16, @extended::binary, @ieee::binary,
        channel>>

  defp probe(route) do
    assert_receive {:serial_write,
                    <<0xFE, 15, 0x24, 1, ^route::little-16, 1, 2, 0::little-16, token, 0x50, 5, 5,
                      0, token, 0, 0, 0, _>>}

    token
  end

  defp success(peer, route, token, records \\ <<0, 0, 0, 0x20, 8>>) do
    send(
      peer,
      {:inject,
       incoming(route, token, records) <> wire(0x44, 0x80, <<0, 2, token>>) <> wire(0x64, 1, <<0>>)}
    )
  end

  defp incoming(
         route,
         token,
         records \\ <<0, 0, 0, 0x20, 8>>,
         security \\ 1,
         remote \\ 1,
         local \\ 2
       ),
       do: raw_incoming(route, <<0x18, token, 1, records::binary>>, security, remote, local)

  defp raw_incoming(route, payload, security \\ 1, remote \\ 1, local \\ 2),
    do:
      wire(
        0x44,
        0x81,
        <<0::little-16, 0::little-16, route::little-16, remote, local, 0, 120, security,
          0::little-32, 0, byte_size(payload), payload::binary>>
      )

  defp wire(command, id, payload) do
    body = <<byte_size(payload), command, id, payload::binary>>
    checksum = Enum.reduce(:binary.bin_to_list(body), 0, &Bitwise.bxor/2)
    <<0xFE, body::binary, checksum>>
  end

  defp closed(monitor, peer) do
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    assert_receive {:migration_serial_close, ^peer}
    refute_receive {:migration_serial_close, ^peer}, 10
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp wait_state(owner, predicate, attempts \\ 200)

  defp wait_state(owner, predicate, attempts) when attempts > 0 do
    if predicate.(:sys.get_state(owner)) do
      :ok
    else
      Process.sleep(1)
      wait_state(owner, predicate, attempts - 1)
    end
  end

  defp wait_state(_, _, 0), do: flunk("migration state did not arrive")

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

  defp wait_message(_, _, 0), do: flunk("migration message was not queued")
end
