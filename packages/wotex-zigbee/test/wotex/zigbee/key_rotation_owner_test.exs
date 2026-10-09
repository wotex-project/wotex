defmodule Wotex.Zigbee.KeyRotationOwnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee

  alias Wotex.Zigbee.{
    Config,
    Credentials,
    Error,
    Interview,
    KeyRotation,
    Owner,
    Routes,
    TestKeyCredentials,
    TestKeySerial
  }

  alias Wotex.Zigbee.KeyRotation.Result

  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>
  @extended <<0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8>>
  @device <<0, @ieee::binary, 0::little-16, 7, 9, 0>>
  @peers [
    %{peer_ieee: <<9::64>>, route_address: 0x1234, source_endpoint: 2, destination_endpoint: 1},
    %{peer_ieee: <<10::64>>, route_address: 0x2345, source_endpoint: 2, destination_endpoint: 1}
  ]

  test "one-use custody, two grants and three readings retain distinct peer evidence" do
    {handle, peer, credentials, routes, key} = open()
    monitor = Process.monitor(handle.owner)
    request = request()
    call = Task.async(fn -> Zigbee.rotate_key(handle, credentials, routes, request, 1_000) end)
    assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}
    assert {:error, %Error{kind: :overload}} = Zigbee.inspect_network(handle, 1_000)
    metadata(peer, 15, true)
    update(peer, key)
    wait_state(handle.owner, & &1.migration.dispatched)
    secret_free(:sys.get_state(handle.owner), key)
    secret_free(Process.info(handle.owner, :dictionary), key)
    metadata(peer, 15)
    switch(peer)
    metadata(peer, 15)

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

    assert {:ok,
            %Result{outcome: :observed_cohort_after_switch, activation: :unconfirmed, issue: nil} =
              result} = Task.await(call)

    for snapshot <- [result.before, result.before_switch, result.after] do
      assert Enum.map(snapshot.readings, & &1.payload) == [@device, network(15)]
    end

    assert result.update.id == 0x4E and result.switch.id == 0x4F
    assert Enum.map(result.peers, & &1.outcome) == [:responsive, :responsive]
    assert Enum.map(result.peers, & &1.response.security_used) == [false, true]
    assert Enum.map(result.peers, & &1.peer) == @peers
    secret_free(result, key)
    refute_receive {:key_custody, :key, _, _}, 10
    closed(monitor, peer)
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.inspect_network(handle, 1_000)
  end

  test "missing application evidence retains every peer and continues once" do
    {handle, peer, credentials, routes, key} = open()

    call =
      Task.async(fn ->
        Zigbee.rotate_key(handle, credentials, routes, request(peer_timeout_ms: 40), 1_000)
      end)

    rotate(peer, key)
    token = probe(0x1234)
    send(peer, {:inject, wire(0x64, 1, <<0>>) <> wire(0x44, 0x80, <<0, 2, token>>)})
    token = probe(0x2345)
    success(peer, 0x2345, token)

    assert {:ok, %Result{outcome: :partial, activation: :unconfirmed, peers: [first, second]}} =
             Task.await(call)

    assert first.outcome == :unconfirmed and first.issue == :timeout
    assert second.outcome == :responsive
  end

  for {phase, id} <- [update: 0x4E, switch: 0x4F] do
    test "#{phase} rejection preserves send status and closes without retry" do
      {handle, peer, credentials, routes, key} = open()
      monitor = Process.monitor(handle.owner)
      call = Task.async(fn -> Zigbee.rotate_key(handle, credentials, routes, request(), 1_000) end)
      metadata(peer, 15)

      if unquote(phase) == :switch do
        update(peer, key)
        metadata(peer, 15)
        switch(peer, 1)
      else
        update(peer, key, 1)
      end

      assert {:ok,
              %Result{outcome: :unconfirmed, activation: :unconfirmed, issue: :status_failure} =
                result} = Task.await(call)

      assert Map.fetch!(result, unquote(phase)).id == unquote(id)
      assert Map.fetch!(result, unquote(phase)).status == 1
      assert Enum.all?(result.peers, &(&1.outcome == :unconfirmed))
      secret_free(result, key)
      refute_receive {:serial_write, _}, 10
      closed(monitor, peer)
    end
  end

  for {behavior, issue} <- [
        deny: :credential_denied,
        raise: :credentials,
        throw: :credentials,
        exit: :credentials,
        no_call: :credentials,
        bad_return: :credentials,
        bad_key: :credentials,
        zero_key: :credentials,
        ff_key: :credentials,
        foreign: :credentials,
        save: :credentials
      ] do
    test "private callback #{behavior} refuses before key dispatch and keeps owner usable" do
      {handle, peer, credentials, routes, key} = open(key: unquote(behavior))
      call = Task.async(fn -> Zigbee.rotate_key(handle, credentials, routes, request(), 1_000) end)
      metadata(peer, 15)

      assert {:ok, %Result{update: nil, switch: nil, issue: unquote(issue)} = result} =
               Task.await(call)

      secret_free(result, key)
      secret_free(:sys.get_state(handle.owner), key)
      secret_free(Process.info(handle.owner, :dictionary), key)

      if unquote(behavior) == :save do
        assert_receive {:saved_consumer_write, consume, ^key}
        assert consume.(key) == {:error, :credentials}
      end

      refute_receive {:serial_write, _}, 10
      assert Process.alive?(handle.owner)
    end
  end

  for behavior <- [:multiple, :raise_after] do
    test "private callback #{behavior} cannot dispatch twice and closes after its write" do
      {handle, peer, credentials, routes, key} = open(key: unquote(behavior))
      monitor = Process.monitor(handle.owner)
      call = Task.async(fn -> Zigbee.rotate_key(handle, credentials, routes, request(), 1_000) end)
      metadata(peer, 15)
      assert_receive {:serial_write, bytes}
      assert bytes == wire(0x25, 0x4E, <<0xFFFD::little-16, 1, key::binary>>)
      assert {:ok, %Result{issue: :credentials, update: nil} = result} = Task.await(call)
      secret_free(result, key)
      refute_receive {:serial_write, _}, 10
      closed(monitor, peer)
    end
  end

  for {phase, behavior, issue} <- [
        {:update, :deny, :credential_denied},
        {:update, :raise, :credentials},
        {:switch, :deny, :credential_denied},
        {:switch, :raise, :credentials}
      ] do
    test "#{phase} authorization #{behavior} has no implicit administrative fallback" do
      {handle, peer, credentials, routes, key} = open([{unquote(phase), unquote(behavior)}])
      monitor = Process.monitor(handle.owner)
      call = Task.async(fn -> Zigbee.rotate_key(handle, credentials, routes, request(), 1_000) end)
      metadata(peer, 15)

      if unquote(phase) == :switch do
        update(peer, key)
        metadata(peer, 15)
      end

      assert {:ok, %Result{switch: nil, issue: unquote(issue)} = result} = Task.await(call)
      secret_free(result, key)
      refute_receive {:serial_write, _}, 10

      if unquote(phase) == :switch,
        do: closed(monitor, peer),
        else: assert(Process.alive?(handle.owner))
    end
  end

  test "fresh before-switch mismatch retains the update but cannot switch" do
    {handle, peer, credentials, routes, key} = open()
    monitor = Process.monitor(handle.owner)
    call = Task.async(fn -> Zigbee.rotate_key(handle, credentials, routes, request(), 1_000) end)
    metadata(peer, 15)
    update(peer, key)
    metadata(peer, 20)

    assert {:ok,
            %Result{
              update: %{status: 0},
              switch: nil,
              issue: :network_mismatch,
              before_switch: %{readings: [_, %{value: %{channel: 20}}]}
            }} = Task.await(call)

    refute_receive {:key_custody, :authorize, %{phase: :switch}, _}, 10
    refute_receive {:serial_write, _}, 10
    closed(monitor, peer)
  end

  for phase <- [:update, :switch] do
    test "#{phase} authorization reserves the qualified delays" do
      {handle, peer, credentials, routes, key} = open([{unquote(phase), {:horizon, 20}}])
      monitor = Process.monitor(handle.owner)

      call =
        Task.async(fn ->
          Zigbee.rotate_key(
            handle,
            credentials,
            routes,
            request(distribution_ms: 30, settle_ms: 30),
            1_000
          )
        end)

      metadata(peer, 15)

      if unquote(phase) == :switch do
        update(peer, key)
        metadata(peer, 15)
      end

      assert {:ok, %Result{issue: :timeout, switch: nil}} = Task.await(call)
      refute_receive {:serial_write, _}, 10

      if unquote(phase) == :switch,
        do: closed(monitor, peer),
        else: assert(Process.alive?(handle.owner))
    end
  end

  test "late private callback cannot start a key write" do
    {handle, peer, credentials, routes, _} = open(key: {:delay, 100})
    call = Task.async(fn -> Zigbee.rotate_key(handle, credentials, routes, request(), 60) end)
    metadata(peer, 15)
    assert {:ok, %Result{issue: :timeout, update: nil}} = Task.await(call)
    refute_receive {:serial_write, _}, 10
    assert Process.alive?(handle.owner)
  end

  test "late return after key dispatch preserves uncertainty and closes" do
    {handle, peer, credentials, routes, key} = open(key: {:delay_after, 100})
    monitor = Process.monitor(handle.owner)
    call = Task.async(fn -> Zigbee.rotate_key(handle, credentials, routes, request(), 60) end)
    metadata(peer, 15)
    assert_receive {:serial_write, bytes}
    assert bytes == wire(0x25, 0x4E, <<0xFFFD::little-16, 1, key::binary>>)
    assert {:ok, %Result{issue: :timeout, update: nil}} = Task.await(call)
    closed(monitor, peer)
  end

  for phase <- [:update, :switch], behavior <- [:raise, :error, :malformed] do
    test "#{phase} write #{behavior} is redacted and closes once" do
      option = if unquote(phase) == :update, do: :update_write, else: :switch_write
      {handle, peer, credentials, routes, key} = open([{option, unquote(behavior)}])
      monitor = Process.monitor(handle.owner)
      call = Task.async(fn -> Zigbee.rotate_key(handle, credentials, routes, request(), 1_000) end)
      metadata(peer, 15)

      if unquote(phase) == :switch do
        update(peer, key)
        metadata(peer, 15)
      end

      assert {:ok, %Result{issue: :serial} = result} = Task.await(call)
      secret_free(result, key)
      closed(monitor, peer)
    end
  end

  test "switch serial write is bounded before the reserved settling interval" do
    {handle, peer, credentials, routes, key} =
      open(
        switch: {:horizon, 100},
        switch_write: {:delay, 70}
      )

    monitor = Process.monitor(handle.owner)

    call =
      Task.async(fn ->
        Zigbee.rotate_key(handle, credentials, routes, request(settle_ms: 50), 1_000)
      end)

    metadata(peer, 15)
    update(peer, key)
    metadata(peer, 15)
    assert_receive {:serial_write, <<0xFE, 3, 0x25, 0x4F, _::binary>>}
    assert {:ok, %Result{update: %{status: 0}, switch: nil, issue: :timeout}} = Task.await(call)
    closed(monitor, peer)
  end

  test "caller loss inside private custody refuses I/O and closes once" do
    {handle, peer, credentials, routes, _} = open(key: {:delay, 60})
    monitor = Process.monitor(handle.owner)
    call = spawn(fn -> Zigbee.rotate_key(handle, credentials, routes, request(), 1_000) end)
    metadata(peer, 15)
    assert_receive {:key_custody, :key, _, _}
    Process.exit(call, :kill)
    closed(monitor, peer)
    refute_receive {:serial_write, _}, 10
  end

  for phase <- [:update, :switch, :peer] do
    test "queued #{phase} reply before caller death cannot advance" do
      {handle, peer, credentials, routes, key} = open()
      monitor = Process.monitor(handle.owner)
      call = spawn(fn -> Zigbee.rotate_key(handle, credentials, routes, request(), 1_000) end)
      metadata(peer, 15)

      if unquote(phase) != :update do
        update(peer, key)
        metadata(peer, 15)

        if unquote(phase) == :peer do
          switch(peer)
          metadata(peer, 15)
          probe(0x1234)
        else
          assert_receive {:serial_write, <<0xFE, 3, 0x25, 0x4F, _::binary>>}
        end
      else
        assert_receive {:serial_write, <<0xFE, 19, 0x25, 0x4E, _::binary>>}
      end

      :ok = :sys.suspend(handle.owner)

      id =
        case unquote(phase) do
          :update -> 0x4E
          :switch -> 0x4F
          :peer -> 1
        end

      command = if unquote(phase) == :peer, do: 0x64, else: 0x65
      send(peer, {:inject, wire(command, id, <<0>>)})
      wait_message(handle.owner, &match?({:zigbee_serial, ^peer, _}, &1))
      Process.exit(call, :kill)
      wait_message(handle.owner, &match?({:DOWN, _, :process, _, _}, &1))
      :ok = :sys.resume(handle.owner)
      closed(monitor, peer)
      refute_receive {:serial_write, _}, 10
    end
  end

  test "an unanswered SREQ ends the epoch without probing the next peer" do
    {handle, peer, credentials, routes, key} = open()
    monitor = Process.monitor(handle.owner)

    call =
      Task.async(fn ->
        Zigbee.rotate_key(handle, credentials, routes, request(peer_timeout_ms: 30), 1_000)
      end)

    rotate(peer, key)
    probe(0x1234)
    assert {:ok, %Result{issue: :timeout, peers: [first, second]}} = Task.await(call)
    assert first.admission == nil and second.admission == nil
    refute_receive {:serial_write, _}, 10
    closed(monitor, peer)
  end

  test "serial loss after an observed peer retains available evidence" do
    {handle, peer, credentials, routes, key} = open()
    monitor = Process.monitor(handle.owner)
    call = Task.async(fn -> Zigbee.rotate_key(handle, credentials, routes, request(), 1_000) end)
    rotate(peer, key)
    token = probe(0x1234)
    success(peer, 0x1234, token)
    probe(0x2345)
    send(peer, {:disconnect, "credential-canary"})

    assert {:ok, %Result{issue: :coordinator_lost, peers: [first, second]} = result} =
             Task.await(call)

    assert first.outcome == :responsive and second.outcome == :unconfirmed
    secret_free(result, key)
    closed(monitor, peer)
  end

  test "invalid requests, stale routes and raw key commands fail before I/O" do
    {handle, _, credentials, routes, key} = open()

    assert {:error, %Error{kind: :invalid_value}} =
             Zigbee.rotate_key(
               handle,
               credentials,
               routes,
               %{request() | next_sequence: 1.0},
               1_000
             )

    assert {:error, %Error{kind: :invalid_value}} =
             Zigbee.rotate_key(handle, credentials, routes, request(), 0)

    {:ok, empty} = Routes.new(handle.epoch)

    assert {:error, %Error{kind: :unknown_route}} =
             Zigbee.rotate_key(handle, credentials, empty, request(), 1_000)

    for frame <- [
          %Wotex.Zigbee.Frame{
            type: :sreq,
            subsystem: 5,
            id: 0x4E,
            payload: <<0xFFFD::little-16, 1, key::binary>>
          },
          %Wotex.Zigbee.Frame{
            type: :sreq,
            subsystem: 5,
            id: 0x4F,
            payload: <<0xFFFD::little-16, 1>>
          }
        ] do
      assert {:error, %Error{kind: :invalid_command}} = Owner.call(handle, :command, [frame, 1_000])
    end

    refute_receive {:serial_write, _}, 10
  end

  for phase <- [:before, :before_switch, :after] do
    test "#{phase} metadata truncation preserves only available readings" do
      {handle, peer, credentials, routes, key} = open()
      monitor = Process.monitor(handle.owner)
      call = Task.async(fn -> Zigbee.rotate_key(handle, credentials, routes, request(), 1_000) end)

      if unquote(phase) != :before do
        metadata(peer, 15)
        update(peer, key)

        if unquote(phase) == :after do
          metadata(peer, 15)
          switch(peer)
        end
      end

      assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}
      send(peer, {:inject, wire(0x67, 0, @device)})
      assert_receive {:serial_write, <<0xFE, 0, 0x25, 0x50, _>>}
      send(peer, {:inject, wire(0x65, 0x50, <<0>>)})
      assert {:ok, %Result{issue: :invalid_frame} = result} = Task.await(call)
      partial = Map.fetch!(result, unquote(phase))
      assert partial.outcome == :partial
      assert Enum.map(partial.readings, & &1.payload) == [@device]
      assert Enum.all?(result.peers, &(&1.admission == nil))
      secret_free(result, key)
      closed(monitor, peer)
    end
  end

  test "wrong source, endpoint, token and manufacturer responses remain unrelated" do
    {handle, peer, credentials, routes, key} = open()
    call = Task.async(fn -> Zigbee.rotate_key(handle, credentials, routes, request(), 1_000) end)
    rotate(peer, key)
    token = probe(0x1234)
    correct = <<0x18, token, 1, 0, 0, 0, 0x20, 8>>

    unrelated = [
      raw_incoming(0x2345, correct, 1, 1, 2),
      raw_incoming(0x1234, correct, 1, 3, 2),
      raw_incoming(0x1234, correct, 1, 1, 3),
      incoming(0x1234, token + 1),
      raw_incoming(0x1234, <<0x1C, 0x34, 0x12, token, 1, 0, 0, 0, 0x20, 8>>, 1, 1, 2)
    ]

    send(peer, {:inject, IO.iodata_to_binary(unrelated)})
    wait_state(handle.owner, &(:queue.len(&1.events) == 5))
    success(peer, 0x1234, token)
    token = probe(0x2345)
    success(peer, 0x2345, token)
    assert {:ok, %Result{outcome: :observed_cohort_after_switch}} = Task.await(call)
  end

  for {records, expected} <- [
        {<<0, 0, 0, 0x20, 0xFF>>, :invalid_value},
        {<<0, 0, 0x86>>, :invalid_value},
        {<<0, 0, 0, 0x20, 8, 0, 0, 0, 0x20, 8>>, :invalid_value}
      ] do
    test "malformed or unavailable Basic records #{inspect(records)} retain partial observations" do
      {handle, peer, credentials, routes, key} = open()
      call = Task.async(fn -> Zigbee.rotate_key(handle, credentials, routes, request(), 1_000) end)
      rotate(peer, key)
      token = probe(0x1234)
      success(peer, 0x1234, token, unquote(records))
      token = probe(0x2345)
      success(peer, 0x2345, token)
      assert {:ok, %Result{outcome: :partial, peers: [first, second]}} = Task.await(call)
      assert first.issue == unquote(expected) and first.response != nil
      assert second.outcome == :responsive
    end
  end

  test "authorization cannot extend the caller budget to fit its delays" do
    {handle, peer, credentials, routes, _} = open(update: {:horizon, 1_000})

    call =
      Task.async(fn ->
        Zigbee.rotate_key(
          handle,
          credentials,
          routes,
          request(distribution_ms: 30, settle_ms: 30),
          50
        )
      end)

    metadata(peer, 15)
    assert {:ok, %Result{issue: :timeout, update: nil}} = Task.await(call)
    refute_receive {:key_custody, :key, _, _}, 10
    refute_receive {:serial_write, _}, 10
    assert Process.alive?(handle.owner)
  end

  test "an authorization-only port has no implicit key retrieval path" do
    {handle, peer, _, routes, _} = open()
    custodian = Wotex.Zigbee.TestCredentials.start(self(), :allow)
    on_exit(fn -> send(custodian, :stop) end)
    {:ok, credentials} = Credentials.new(Wotex.Zigbee.TestCredentials, custodian)
    call = Task.async(fn -> Zigbee.rotate_key(handle, credentials, routes, request(), 1_000) end)
    metadata(peer, 15)
    assert {:ok, %Result{issue: :credentials, update: nil}} = Task.await(call)
    refute_receive {:serial_write, _}, 10
    assert Process.alive?(handle.owner)
  end

  test "late private return cannot consume reserved delays even before the overall horizon" do
    {handle, peer, credentials, routes, key} =
      open(
        update: {:horizon, 500},
        key: {:delay_after, 150}
      )

    monitor = Process.monitor(handle.owner)

    call =
      Task.async(fn ->
        Zigbee.rotate_key(
          handle,
          credentials,
          routes,
          request(distribution_ms: 200, settle_ms: 200),
          1_000
        )
      end)

    metadata(peer, 15)
    update(peer, key)
    assert {:ok, %Result{issue: :timeout, update: nil, before_switch: nil}} = Task.await(call)
    refute_receive {:serial_write, _}, 10
    closed(monitor, peer)
  end

  defp open(options \\ []) do
    {credential_owner, key} = TestKeyCredentials.start(self(), options)
    on_exit(fn -> send(credential_owner, :stop) end)
    {:ok, credentials} = Credentials.new(TestKeyCredentials, credential_owner)

    {:ok, config} =
      Config.new(
        serial: TestKeySerial,
        device_id: "simulated-coordinator",
        expected_version: {2, 0, 3, 2, 0},
        timeout_ms: 1_000,
        serial_options: [
          test_pid: self(),
          drop_reply: true,
          update_write: Keyword.get(options, :update_write, :ok),
          switch_write: Keyword.get(options, :switch_write, :ok)
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

    {handle, peer, credentials, routes, key}
  end

  defp request(overrides \\ []) do
    {:ok, request} =
      KeyRotation.new(
        Keyword.merge(
          [
            coordinator_ieee: @ieee,
            extended_pan_id: @extended,
            pan_id: 0x1234,
            channel: 15,
            current_sequence: 0,
            next_sequence: 1,
            distribution_ms: 5,
            settle_ms: 5,
            peer_timeout_ms: 100,
            peers: @peers,
            correlation_id: "rotation"
          ],
          overrides
        )
      )

    request
  end

  defp update(peer, key, status \\ 0) do
    assert_receive {:key_custody, :authorize, %{phase: :update, update: nil}, _}
    assert_receive {:key_custody, :key, %{phase: :update} = context, budget}
    assert budget > 0
    secret_free(context, key)
    assert_receive {:serial_write, bytes}
    assert bytes == wire(0x25, 0x4E, <<0xFFFD::little-16, 1, key::binary>>)
    send(peer, {:inject, wire(0x65, 0x4E, <<status>>)})
  end

  defp switch(peer, status \\ 0) do
    assert_receive {:key_custody, :authorize, %{phase: :switch, update: %{status: 0}}, _}
    assert_receive {:serial_write, <<0xFE, 3, 0x25, 0x4F, 0xFD, 0xFF, 1, 0x6A>>}
    send(peer, {:inject, wire(0x65, 0x4F, <<status>>)})
  end

  defp rotate(peer, key) do
    metadata(peer, 15)
    update(peer, key)
    metadata(peer, 15)
    switch(peer)
    metadata(peer, 15)
  end

  defp secret_free(value, key) do
    bytes = :erlang.term_to_binary(value)
    assert :binary.match(bytes, key) == :nomatch
    refute inspect(value) =~ "credential-canary"
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
         security \\ 1
       ),
       do: raw_incoming(route, <<0x18, token, 1, records::binary>>, security, 1, 2)

  defp raw_incoming(route, payload, security, remote, local),
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
    assert_receive {:key_serial_close, ^peer}
    refute_receive {:key_serial_close, ^peer}, 10
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

  defp wait_state(_, _, 0), do: flunk("rotation state did not arrive")

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

  defp wait_message(_, _, 0), do: flunk("rotation message was not queued")
end
