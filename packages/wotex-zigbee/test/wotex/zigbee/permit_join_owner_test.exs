defmodule Wotex.Zigbee.PermitJoinOwnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee

  alias Wotex.Zigbee.{
    Config,
    Credentials,
    Error,
    Owner,
    PermitJoin,
    Routes,
    TestCredentials,
    TestPermitSerial
  }

  alias Wotex.Zigbee.PermitJoin.Result

  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>
  @extended <<0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8>>
  @device <<0, @ieee::binary, 0::little-16, 7, 9, 0>>
  @network <<0::little-16, 9, 0x1234::little-16, 0::little-16, @extended::binary, @ieee::binary,
             15>>

  test "fresh network custody authorizes one local request while indications stay independent" do
    {handle, peer, credentials} = open()
    request = request()
    call = Task.async(fn -> Zigbee.permit_join(handle, credentials, request, 1_000) end)
    assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, 0x27>>}
    assert {:error, %Error{kind: :overload}} = Zigbee.inspect_network(handle, 1_000)

    assert {:error, %Error{kind: :overload}} =
             Zigbee.permit_join(handle, credentials, request, 1_000)

    refute_receive {:credential_request, _, _, _}, 10
    send(peer, {:inject, wire(0x45, 0xB6, <<0, 0, 0>>) <> wire(0x67, 0, @device)})
    assert_receive {:serial_write, <<0xFE, 0, 0x25, 0x50, 0x75>>}
    send(peer, {:inject, wire(0x65, 0x50, @network)})
    assert_receive {:credential_request, _, context, budget}
    assert context.operation == :permit_join
    assert context.owner_epoch == handle.epoch
    assert context.request == request
    assert context.network.owner_epoch == handle.epoch
    assert Enum.map(context.network.readings, & &1.payload) == [@device, @network]
    assert budget > 0 and budget <= 1_000
    assert context.deadline_ms - context.now_ms == budget
    refute inspect(context) =~ "credential-canary"
    assert_receive {:serial_write, <<0xFE, 5, 0x25, 0x36, 2, 0, 0, 60, 1, 0x29>>}
    {:ok, routes} = Routes.new(handle.epoch)
    assert {:error, %Error{kind: :overload}} = Zigbee.change_binding(handle, routes, nil, 1_000)
    assert {:error, %Error{kind: :overload}} = Zigbee.active_endpoints(handle, 1, 1_000)
    send(peer, {:inject, wire(0x45, 0xCB, <<0>>) <> wire(0x45, 0xB6, <<0, 0, 0>>)})
    assert Task.yield(call, 10) == nil
    send(peer, {:inject, wire(0x65, 0x36, <<0>>)})
    assert {:ok, %Result{outcome: :ncp_admitted, issue: nil} = result} = Task.await(call)
    assert result.request == request
    assert result.admission.status == 0
    assert result.network.outcome == :observed
    refute Map.has_key?(result, :response)
    refute Map.has_key?(result, :credentials)
    refute Map.has_key?(result, :joining_open)
    assert {:ok, %{events: events, dropped: 0}} = Zigbee.drain_events(handle, 128)

    assert Enum.map(events, & &1.kind) == [
             :zdo_permit_join,
             :permit_join_indication,
             :zdo_permit_join
           ]

    assert Enum.at(events, 1).zdo == %{duration_s: 0}
    assert Enum.all?(events, &(&1.owner_epoch == handle.epoch))
    assert Enum.all?(events, &(&1.transaction == nil and &1.security_used == nil))
    refute inspect(result) =~ "credential-canary"
  end

  test "opening and explicit closure each inspect and authorize without borrowing old responses" do
    {handle, peer, credentials} = open()

    for duration <- [60, 0] do
      request = request(duration_s: duration, correlation_id: "joining-#{duration}")
      call = Task.async(fn -> Zigbee.permit_join(handle, credentials, request, 1_000) end)
      metadata(peer)
      assert_receive {:credential_request, _, %{request: ^request}, _}
      assert_receive {:serial_write, <<0xFE, 5, 0x25, 0x36, 2, 0, 0, ^duration, 1, _>>}
      send(peer, {:inject, wire(0x45, 0xB6, <<0, 0, 0>>)})
      assert Task.yield(call, 10) == nil
      send(peer, {:inject, wire(0x65, 0x36, <<0>>)})
      assert {:ok, %Result{outcome: :ncp_admitted, request: ^request}} = Task.await(call)
    end

    assert {:ok, %{events: [_, _]}} = Zigbee.drain_events(handle, 128)
    refute_receive {:serial_write, _}, 10
  end

  test "malformed requests, custody ports, handles and raw commands fail before inspection" do
    {handle, _, credentials} = open()

    for {port, request} <- [
          {nil, request()},
          {Map.put(credentials, :key, "credential-canary"), request()},
          {credentials, nil},
          {credentials, Map.put(request(), :key, "credential-canary")},
          {credentials, %{request() | duration_s: 255}}
        ] do
      assert {:error, %Error{kind: :invalid_value} = error} =
               Zigbee.permit_join(handle, port, request, 1_000)

      refute inspect(error) =~ "credential-canary"
    end

    for timeout <- [nil, 0, 1_001] do
      assert {:error, %Error{kind: :invalid_value}} =
               Zigbee.permit_join(handle, credentials, request(), timeout)
    end

    assert {:error, %Error{kind: :stale_handle}} =
             Zigbee.permit_join(nil, credentials, request(), 1_000)

    assert {:error, %Error{kind: :stale_handle}} =
             Zigbee.permit_join(%{handle | epoch: make_ref()}, credentials, request(), 1_000)

    {:ok, frame} = PermitJoin.frame(request())
    assert {:error, %Error{kind: :invalid_command}} = Owner.call(handle, :command, [frame, 1_000])
    refute_receive {:credential_request, _, _, _}, 10
    refute_receive {:serial_write, _}, 10
  end

  test "changed or wrong network metadata refuses custody and joining while retaining readings" do
    for overrides <- [
          [coordinator_ieee: <<1::64>>],
          [extended_pan_id: <<1::64>>],
          [pan_id: 1],
          [channel: 26]
        ] do
      {handle, peer, credentials} = open()

      call =
        Task.async(fn -> Zigbee.permit_join(handle, credentials, request(overrides), 1_000) end)

      metadata(peer)

      assert {:ok,
              %Result{outcome: :unconfirmed, issue: :network_mismatch, admission: nil} = result} =
               Task.await(call)

      assert result.network.outcome == :observed
      refute_receive {:credential_request, _, _, _}, 10
      refute_receive {:serial_write, _}, 10
      assert {:ok, _} = Zigbee.handle(handle.owner)
    end

    {handle, peer, credentials} = open()
    call = Task.async(fn -> Zigbee.permit_join(handle, credentials, request(), 1_000) end)
    metadata(peer, network: :binary.copy(<<255>>, 24))

    assert {:ok, %Result{issue: :network_mismatch, network: %{consistency: :changed}}} =
             Task.await(call)

    refute_receive {:credential_request, _, _, _}, 10
    refute_receive {:serial_write, _}, 10
  end

  test "failed device status stops the workflow with partial readings before authorization" do
    {handle, peer, credentials} = open()
    call = Task.async(fn -> Zigbee.permit_join(handle, credentials, request(), 1_000) end)
    assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}
    <<_, tail::binary>> = @device
    send(peer, {:inject, wire(0x67, 0, <<2, tail::binary>>)})

    assert {:ok, %Result{issue: :status_failure, admission: nil, network: network}} =
             Task.await(call)

    assert network.outcome == :partial
    assert length(network.readings) == 1
    assert {:ok, _} = Zigbee.handle(handle.owner)
    refute_receive {:credential_request, _, _, _}, 10
    refute_receive {:serial_write, _}, 10
  end

  test "credential denial, faults and malformed horizons stay redacted and cannot dispatch" do
    for behavior <- [:deny, :raise, :throw, :exit, :malformed, :bad_horizon, :huge_horizon] do
      {handle, peer, credentials} = open(credentials: behavior)
      call = Task.async(fn -> Zigbee.permit_join(handle, credentials, request(), 1_000) end)
      metadata(peer)
      assert_receive {:credential_request, _, _, _}
      assert {:ok, %Result{outcome: :unconfirmed, admission: nil} = result} = Task.await(call)
      assert result.issue == if(behavior == :deny, do: :credential_denied, else: :credentials)
      assert result.network.outcome == :observed
      refute inspect(result) =~ "credential-canary"
      refute inspect(:sys.get_state(handle.owner)) =~ "credential-canary"
      assert {:ok, _} = Zigbee.handle(handle.owner)
      refute_receive {:serial_write, _}, 10
    end

    {handle, peer, _} = open()
    {:ok, missing} = Credentials.new(__MODULE__, make_ref())
    call = Task.async(fn -> Zigbee.permit_join(handle, missing, request(), 1_000) end)
    metadata(peer)
    assert {:ok, %Result{issue: :credentials, admission: nil}} = Task.await(call)
    refute_receive {:serial_write, _}, 10
  end

  test "authorization covers the whole requested window and shortens the original dispatch deadline" do
    {handle, peer, credentials} = open(credentials: {:horizon, 0})
    call = Task.async(fn -> Zigbee.permit_join(handle, credentials, request(), 1_000) end)
    metadata(peer)
    assert_receive {:credential_request, _, _, _}
    assert {:ok, %Result{issue: :timeout, admission: nil}} = Task.await(call)
    assert {:ok, _} = Zigbee.handle(handle.owner)
    refute_receive {:serial_write, _}, 10

    {handle, peer, credentials} = open(credentials: {:horizon, 50})
    monitor = Process.monitor(handle.owner)
    call = Task.async(fn -> Zigbee.permit_join(handle, credentials, request(), 1_000) end)
    metadata(peer)
    assert_receive {:credential_request, _, context, _}
    assert_receive {:serial_write, <<0xFE, 5, 0x25, 0x36, _::binary>>}
    deadline = :sys.get_state(handle.owner).network.deadline
    assert deadline == context.now_ms + 50
    assert deadline < context.deadline_ms

    assert {:ok, %Result{issue: :timeout, admission: nil, network: %{outcome: :observed}}} =
             Task.await(call)

    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    assert_receive {:permit_serial_close, ^peer}
  end

  test "late credential callbacks cannot write joining commands or extend the workflow" do
    {handle, peer, credentials} = open(credentials: {:delay, 150})
    call = Task.async(fn -> Zigbee.permit_join(handle, credentials, request(), 100) end)
    metadata(peer)
    assert_receive {:credential_request, _, _, _}
    assert {:ok, %Result{issue: :timeout, admission: nil}} = Task.await(call)
    assert {:ok, _} = Zigbee.handle(handle.owner)
    refute_receive {:serial_write, _}, 10
  end

  test "caller loss during custody closes once without dispatch after the callback returns" do
    {handle, peer, credentials} = open(credentials: {:delay, 80})
    monitor = Process.monitor(handle.owner)
    caller = spawn(fn -> Zigbee.permit_join(handle, credentials, request(), 1_000) end)
    metadata(peer)
    assert_receive {:credential_request, _, _, _}
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 500
    assert_receive {:permit_serial_close, ^peer}
    refute_receive {:permit_serial_close, ^peer}, 10
    refute_receive {:serial_write, _}, 10
  end

  test "timeouts and serial loss retain partial inspection or unconfirmed command admission" do
    for phase <- [:device, :permit], ending <- [:timeout, :disconnect, :close] do
      {handle, peer, credentials} = open()
      monitor = Process.monitor(handle.owner)
      call = Task.async(fn -> Zigbee.permit_join(handle, credentials, request(), 100) end)

      if phase == :permit do
        metadata(peer)
        assert_receive {:credential_request, _, _, _}
        assert_receive {:serial_write, <<0xFE, 5, 0x25, 0x36, _::binary>>}
      else
        assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}
      end

      case ending do
        :timeout -> :ok
        :disconnect -> send(peer, {:disconnect, "credential-canary"})
        :close -> assert :ok = Zigbee.close(handle)
      end

      assert {:ok, %Result{outcome: :unconfirmed, admission: nil} = result} = Task.await(call)
      assert result.issue == if(ending == :timeout, do: :timeout, else: :coordinator_lost)
      assert result.network.outcome == if(phase == :device, do: :partial, else: :observed)
      refute inspect(result) =~ "credential-canary"
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
      assert_receive {:permit_serial_close, ^peer}
      refute_receive {:permit_serial_close, ^peer}, 10
    end
  end

  test "wrong, malformed or late permit SRSP ends the epoch without promoting queued indications" do
    for reply <- [wire(0x65, 0x37, <<0>>), wire(0x65, 0x36, <<>>), wire(0x65, 0x36, <<0, 0>>)] do
      {handle, peer, credentials} = open()
      monitor = Process.monitor(handle.owner)
      call = Task.async(fn -> Zigbee.permit_join(handle, credentials, request(), 1_000) end)
      metadata(peer)
      assert_receive {:credential_request, _, _, _}
      assert_receive {:serial_write, <<0xFE, 5, 0x25, 0x36, _::binary>>}
      send(peer, {:inject, wire(0x45, 0xCB, <<60>>) <> reply})
      assert {:ok, %Result{issue: :invalid_frame, admission: nil}} = Task.await(call)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
    end

    {handle, peer, credentials} = open()
    monitor = Process.monitor(handle.owner)
    call = Task.async(fn -> Zigbee.permit_join(handle, credentials, request(), 100) end)
    metadata(peer)
    assert_receive {:credential_request, _, _, _}
    assert_receive {:serial_write, <<0xFE, 5, 0x25, 0x36, _::binary>>}
    deadline = :sys.get_state(handle.owner).network.deadline
    :ok = :sys.suspend(handle.owner)
    send(peer, {:inject, wire(0x65, 0x36, <<0>>)})
    wait_message(handle.owner, &match?({:zigbee_serial, _, _}, &1))
    Process.sleep(max(0, deadline - now() + 5))
    :ok = :sys.resume(handle.owner)
    assert {:ok, %Result{issue: :timeout, admission: nil}} = Task.await(call)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
  end

  test "NCP rejection is distinct from management success and leaves the owner usable" do
    {handle, peer, credentials} = open()

    call =
      Task.async(fn -> Zigbee.permit_join(handle, credentials, request(duration_s: 0), 1_000) end)

    metadata(peer)
    assert_receive {:credential_request, _, _, _}
    assert_receive {:serial_write, <<0xFE, 5, 0x25, 0x36, _::binary>>}
    send(peer, {:inject, wire(0x45, 0xB6, <<0, 0, 0>>) <> wire(0x65, 0x36, <<0x10>>)})

    assert {:ok, %Result{outcome: :ncp_rejected, issue: :status_failure, admission: admission}} =
             Task.await(call)

    assert admission.status == 0x10

    assert {:ok, %{events: [%{kind: :zdo_permit_join, status: 0}]}} =
             Zigbee.drain_events(handle, 128)

    assert {:ok, _} = Zigbee.handle(handle.owner)
  end

  test "queued expiry before inspection keeps the owner usable and performs no custody call" do
    {handle, _, credentials} = open()
    :ok = :sys.suspend(handle.owner)
    call = Task.async(fn -> Zigbee.permit_join(handle, credentials, request(), 20) end)
    wait_message(handle.owner, &match?({:"$gen_call", _, {:permit_join, _, _}}, &1))
    Process.sleep(25)
    :ok = :sys.resume(handle.owner)
    assert {:error, %Error{kind: :timeout}} = Task.await(call)
    assert {:ok, _} = Zigbee.handle(handle.owner)
    refute_receive {:credential_request, _, _, _}, 10
    refute_receive {:serial_write, _}, 10
  end

  test "a permit reply queued before caller death cannot release the lifetime monitor" do
    {handle, peer, credentials} = open()
    monitor = Process.monitor(handle.owner)
    caller = spawn(fn -> Zigbee.permit_join(handle, credentials, request(), 1_000) end)
    metadata(peer)
    assert_receive {:credential_request, _, _, _}
    assert_receive {:serial_write, <<0xFE, 5, 0x25, 0x36, _::binary>>}
    :ok = :sys.suspend(handle.owner)
    send(peer, {:inject, wire(0x65, 0x36, <<0>>)})
    wait_message(handle.owner, &match?({:zigbee_serial, _, _}, &1))
    caller_monitor = Process.monitor(caller)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :killed}
    :ok = :sys.resume(handle.owner)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    assert_receive {:permit_serial_close, ^peer}
    refute_receive {:permit_serial_close, ^peer}, 10
  end

  test "permit write faults and blocking callbacks retain observed metadata with redacted cleanup" do
    for behavior <- [:raise, :throw, :exit, :malformed, :error, {:delay, 150}] do
      {handle, peer, credentials} = open(permit_write: behavior)
      monitor = Process.monitor(handle.owner)
      timeout = if is_tuple(behavior), do: 100, else: 1_000
      call = Task.async(fn -> Zigbee.permit_join(handle, credentials, request(), timeout) end)
      metadata(peer)
      assert_receive {:credential_request, _, _, _}
      assert {:ok, %Result{outcome: :unconfirmed, admission: nil} = result} = Task.await(call)
      assert result.issue == if(is_tuple(behavior), do: :timeout, else: :serial)
      assert result.network.outcome == :observed
      refute inspect(result) =~ "credential-canary"
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
      assert_receive {:permit_serial_close, ^peer}
      refute_receive {:permit_serial_close, ^peer}, 10

      if is_tuple(behavior),
        do: assert_receive({:serial_write, <<0xFE, 5, 0x25, 0x36, _::binary>>}),
        else: refute_receive({:serial_write, _}, 10)
    end
  end

  defp open(options \\ []) do
    credential_owner = TestCredentials.start(self(), Keyword.get(options, :credentials, :allow))
    on_exit(fn -> send(credential_owner, :stop) end)
    {:ok, credentials} = Credentials.new(TestCredentials, credential_owner)

    {:ok, config} =
      Config.new(
        serial: TestPermitSerial,
        device_id: "simulated-coordinator",
        expected_version: {2, 0, 3, 2, 0},
        timeout_ms: 1_000,
        serial_options: [
          test_pid: self(),
          drop_reply: true,
          permit_write: Keyword.get(options, :permit_write, :ok)
        ]
      )

    {:ok, handle} = Zigbee.open(config)
    on_exit(fn -> Zigbee.close(handle) end)
    assert_receive {:serial_open, peer, _}
    assert_receive {:serial_write, <<0xFE, 0, 0x21, 2, _>>}
    {handle, peer, credentials}
  end

  defp request(overrides \\ []) do
    {:ok, request} =
      PermitJoin.new(
        Keyword.merge(
          [
            coordinator_ieee: @ieee,
            extended_pan_id: @extended,
            pan_id: 0x1234,
            channel: 15,
            duration_s: 60,
            tc_significance: 1,
            correlation_id: "joining"
          ],
          overrides
        )
      )

    request
  end

  defp metadata(peer, overrides \\ []) do
    assert_receive {:serial_write, <<0xFE, 0, 0x27, 0, _>>}
    send(peer, {:inject, wire(0x67, 0, @device)})
    assert_receive {:serial_write, <<0xFE, 0, 0x25, 0x50, _>>}
    send(peer, {:inject, wire(0x65, 0x50, Keyword.get(overrides, :network, @network))})
  end

  defp wire(command, id, payload) do
    body = <<byte_size(payload), command, id, payload::binary>>
    checksum = Enum.reduce(:binary.bin_to_list(body), 0, &Bitwise.bxor/2)
    <<0xFE, body::binary, checksum>>
  end

  defp now, do: System.monotonic_time(:millisecond)

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

  defp wait_message(_, _, 0), do: flunk("permit-join message was not queued")
end
