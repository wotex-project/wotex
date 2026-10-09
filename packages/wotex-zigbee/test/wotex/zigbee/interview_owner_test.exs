defmodule Wotex.Zigbee.InterviewOwnerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee
  alias Wotex.Zigbee.{Config, Error, Interview, TestSerialPeer}
  alias Wotex.Zigbee.Interview.Result

  @route 0x1234
  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>

  test "complete interview preserves duplicates, unknown descriptors and distinct observations" do
    {handle, peer} = open()
    call = interview(handle)
    identity(peer, early: true)
    respond_node(peer)
    active(peer, [1, 1, 2])
    simple(peer, 1, [0, 0, 0xFFFF])
    simple(peer, 2, [0], profile: 0xFFFF)
    basic(peer, 1, 0, basic_records(), early: true, security: false)

    assert {:ok, %Result{outcome: :complete, identity_matches: true} = result} = Task.await(call)
    assert result.owner_epoch == handle.epoch
    assert result.peer_ieee == @ieee
    assert result.route_address == @route

    assert Enum.map(result.steps, & &1.stage) == [
             :identity,
             :node,
             :active,
             {:simple, 1},
             {:simple, 2},
             {:basic, 1}
           ]

    assert Enum.at(result.steps, 2).response.zdo.endpoints == [1, 1, 2]
    assert Enum.at(result.steps, 3).response.zdo.descriptor.input_clusters == [0, 0, 0xFFFF]
    assert Enum.at(result.steps, 4).response.zdo.descriptor.profile == 0xFFFF
    step = List.last(result.steps)
    assert step.admission.status == 0
    assert step.confirmation.kind == :aps_confirm
    assert step.response.security_used == false
    assert Enum.map(step.attributes.attributes, & &1.value) == [8, "consumer", "sensor", 3]

    assert {:error, %Error{kind: :correlation_exhausted}} =
             Zigbee.interview(handle, request(), 1_000)

    refute_receive {:serial_write, _}, 10
  end

  test "unrelated, replayed, wrong-source and wrong-sequence indications stay in the ordinary queue" do
    {handle, peer} = open()
    call = interview(handle)
    identity(peer)
    respond_node(peer)
    active(peer, [1])
    simple(peer, 1, [0])
    expect_basic(1, 0)

    unrelated = [
      wire(0x45, 0x81, ieee_payload()),
      incoming(1, <<8, 1, 1, basic_records()::binary>>),
      incoming(1, <<8, 0, 10, 4::little-16, 0x42, 1, ?x>>),
      incoming(1, <<8, 0, 1, basic_records()::binary>>, route: 0x5678),
      incoming(2, <<8, 0, 1, basic_records()::binary>>),
      incoming(1, <<0, 0, 1, basic_records()::binary>>),
      incoming(1, <<12, 1::little-16, 0, 1, basic_records()::binary>>),
      incoming(1, <<8, 0, 1, basic_records()::binary>>, local: 3),
      incoming(1, <<8, 0, 1, 0>>),
      wire(0x44, 0x80, <<0, 2, 1>>)
    ]

    inject(peer, IO.iodata_to_binary(unrelated))

    inject(
      peer,
      wire(0x64, 1, <<0>>) <>
        wire(0x44, 0x80, <<0, 2, 0>>) <>
        incoming(1, <<8, 0, 1, basic_records()::binary>>)
    )

    assert {:ok, %Result{outcome: :complete}} = Task.await(call)
    assert {:ok, %{events: events, dropped: 0}} = Zigbee.drain_events(handle, 32)
    assert length(events) == length(unrelated)
    assert hd(events).kind == :zdo_ieee_address
    assert Enum.any?(events, &(&1.kind == :af_incoming and &1.source_address == 0x5678))
  end

  test "mismatched identity stops inspection and preserves the conflicting raw claim" do
    {handle, peer} = open()
    call = interview(handle)
    identity(peer, ieee: <<1, 2, 3, 4, 5, 6, 7, 8>>)

    assert {:ok, %Result{outcome: :partial, identity_matches: false, steps: [step]}} =
             Task.await(call)

    assert step.issues == [:identity_mismatch]
    assert step.response.zdo.peer_ieee == <<1, 2, 3, 4, 5, 6, 7, 8>>
    refute_receive {:serial_write, _}, 10
    assert {:ok, _} = Zigbee.handle(handle.owner)
  end

  test "nonzero NCP admission never promotes an early response into a successful interview" do
    {handle, peer} = open()
    call = interview(handle)
    expect(0x25, 1, <<@route::little-16, 0, 0>>)
    inject(peer, wire(0x45, 0x81, ieee_payload()) <> wire(0x65, 1, <<0x10>>))

    assert {:ok, %Result{outcome: :partial, identity_matches: false, steps: [step]}} =
             Task.await(call)

    assert step.admission.status == 0x10
    assert step.response.status == 0
    assert step.issues == [:ncp_rejected]
    refute_receive {:serial_write, _}, 10
  end

  test "failed IEEE and active responses remain partial and perform no retries" do
    for stage <- [:identity, :active] do
      {handle, peer} = open()
      call = interview(handle)

      if stage == :identity do
        identity(peer, status: 0x81)
      else
        identity(peer)
        respond_node(peer)
        active(peer, [], status: 0x81)
      end

      assert {:ok, %Result{outcome: :partial} = result} = Task.await(call)
      assert List.last(result.steps).issues == [:status_failure]
      refute_receive {:serial_write, _}, 10
    end
  end

  test "node and individual descriptor failures preserve partial outcomes while other endpoints finish" do
    {handle, peer} = open()
    call = interview(handle)
    identity(peer)
    respond_node(peer, status: 0x89)
    active(peer, [0, 1, 2, 241])
    simple(peer, 1, [], status: 0x81)
    simple(peer, 2, [6])
    assert {:ok, %Result{outcome: :partial} = result} = Task.await(call)
    assert Enum.at(result.steps, 1).response.zdo.descriptor == nil
    assert Enum.at(result.steps, 1).issues == [:status_failure]
    assert Enum.at(result.steps, 2).response.zdo.endpoints == [0, 1, 2, 241]
    assert Enum.at(result.steps, 2).issues == [:invalid_endpoint]
    assert Enum.at(result.steps, 3).issues == [:status_failure]
    assert List.last(result.steps).stage == {:simple, 2}
  end

  test "advertised endpoint bounds include duplicates and empty lists finish without invented descriptors" do
    for endpoints <- [[1, 1], []] do
      {handle, peer} = open()
      call = interview(handle, max_endpoints: 1)
      identity(peer)
      respond_node(peer)
      active(peer, endpoints)
      assert {:ok, %Result{} = result} = Task.await(call)
      assert List.last(result.steps).response.zdo.endpoints == endpoints
      assert result.outcome == if(endpoints == [], do: :complete, else: :partial)
      assert List.last(result.steps).issues == if(endpoints == [], do: [], else: [:overload])
      refute_receive {:serial_write, _}, 10
    end
  end

  test "Basic records retain failure, duplicates, unexpected and missing IDs without false success" do
    {handle, peer} = open()
    call = interview(handle)
    descriptors(peer)

    records =
      <<0::little-16, 0, 0x20, 8, 0::little-16, 0, 0x20, 7, 4::little-16, 0x86, 7::little-16, 0,
        0x20, 3>>

    basic(peer, 1, 0, records)
    assert {:ok, %Result{outcome: :partial} = result} = Task.await(call)
    step = List.last(result.steps)
    assert Enum.map(step.attributes.attributes, & &1.id) == [0, 0, 4, 7]

    assert step.issues == [
             :duplicate_attribute,
             :unexpected_attribute,
             :missing_attribute,
             :attribute_failure,
             :invalid_value
           ]

    assert Enum.at(step.attributes.attributes, 2).status == {:error, 0x86}
  end

  test "Basic null, excessive string, invalid UTF-8 and wrong types remain raw partial evidence" do
    for record <- [
          <<4::little-16, 0, 0x42, 0xFF>>,
          <<4::little-16, 0, 0x42, 33, :binary.copy("x", 33)::binary>>,
          <<4::little-16, 0, 0x42, 1, 0xFF>>,
          <<4::little-16, 0, 0x20, 1>>,
          <<4::little-16, 0, 0x99, 1, 2>>
        ] do
      {handle, peer} = open()
      call = interview(handle, basic_attributes: [4])
      descriptors(peer)
      basic(peer, 1, 0, record, attributes: [4])
      assert {:ok, %Result{outcome: :partial} = result} = Task.await(call)
      assert List.last(result.steps).issues == [:invalid_value]
      assert List.last(result.steps).response.payload == <<8, 0, 1, record::binary>>
    end
  end

  test "Basic numeric non-values remain null evidence and cannot complete the interview" do
    for {id, type, raw} <- [{0, 0x20, <<0xFF>>}, {0xFFFD, 0x21, <<0xFF, 0xFF>>}] do
      {handle, peer} = open()
      call = interview(handle, basic_attributes: [id])
      descriptors(peer)
      record = <<id::little-16, 0, type, raw::binary>>
      basic(peer, 1, 0, record, attributes: [id])
      assert {:ok, %Result{outcome: :partial} = result} = Task.await(call)
      step = List.last(result.steps)
      assert step.issues == [:invalid_value]
      assert [%{value: :null, raw: ^raw}] = step.attributes.attributes
      assert step.response.payload == <<8, 0, 1, record::binary>>
    end
  end

  test "APS failure and a second Basic endpoint retain distinct per-endpoint results" do
    {handle, peer} = open()
    call = interview(handle)
    identity(peer)
    respond_node(peer)
    active(peer, [1, 2])
    simple(peer, 1, [0])
    simple(peer, 2, [0])
    expect_basic(1, 0)
    inject(peer, wire(0x64, 1, <<0>>) <> wire(0x44, 0x80, <<0xCD, 2, 0>>))
    basic(peer, 2, 1, basic_records())
    assert {:ok, %Result{outcome: :partial} = result} = Task.await(call)
    first = Enum.at(result.steps, -2)
    assert first.issues == [:aps_failure]
    assert first.response == nil
    assert first.confirmation.status == 0xCD
    assert List.last(result.steps).issues == []
  end

  test "a previously queried route is retired for interviews and raw frames cannot bypass request admission" do
    {handle, peer} = open()
    query = Task.async(fn -> Zigbee.node_descriptor(handle, @route, 1_000) end)
    respond_node(peer)
    assert {:ok, _} = Task.await(query)

    assert {:error, %Error{kind: :correlation_exhausted}} =
             Zigbee.interview(handle, request(), 1_000)

    for value <- [
          nil,
          Map.put(request(), :key, "credential-canary"),
          %{request() | max_endpoints: 78}
        ] do
      assert {:error, %Error{kind: :invalid_value} = error} = Zigbee.interview(handle, value, 1_000)
      refute inspect(error) =~ "credential-canary"
    end

    assert {:error, %Error{kind: :stale_handle}} =
             Zigbee.interview(%{handle | epoch: make_ref()}, request(), 1_000)

    assert {:error, %Error{kind: :invalid_value}} = Zigbee.interview(handle, request(), 0)
    refute_receive {:serial_write, _}, 10
  end

  test "the original deadline expires while a valid response is queued and ends the epoch" do
    {handle, peer} = open()
    call = interview(handle, [], 100)
    identity(peer)
    expect(0x25, 2, <<@route::little-16, @route::little-16>>)
    :ok = :sys.suspend(handle.owner)
    inject(peer, wire(0x65, 2, <<0>>) <> wire(0x45, 0x82, node_payload()))
    wait_messages(handle.owner)
    Process.sleep(110)
    :ok = :sys.resume(handle.owner)
    assert {:ok, %Result{outcome: :partial} = result} = Task.await(call)
    assert List.last(result.steps).issues == [:timeout]
    assert Enum.map(result.steps, & &1.stage) == [:identity, :node]
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.handle(handle.owner)
    refute_receive {:serial_write, _}, 10
  end

  test "an admitted interview shares one deadline across steps instead of restarting it" do
    {handle, peer} = open()
    call = interview(handle, [], 100)
    identity(peer)
    respond_node(peer)
    active(peer, [1])
    simple(peer, 1, [0])
    expect_basic(1, 0)
    inject(peer, wire(0x64, 1, <<0>>))
    assert {:ok, %Result{outcome: :partial} = result} = Task.await(call)
    assert result.identity_matches
    step = List.last(result.steps)
    assert step.stage == {:basic, 1}
    assert step.admission.status == 0
    assert step.issues == [:timeout]
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.handle(handle.owner)
  end

  test "serial loss, malformed SRSP and explicit close return retained partial observations" do
    for failure <- [:serial_loss, :malformed, :close] do
      {handle, peer} = open()
      call = interview(handle)
      identity(peer)
      expect(0x25, 2, <<@route::little-16, @route::little-16>>)

      case failure do
        :serial_loss -> send(peer, {:disconnect, :credential_canary})
        :malformed -> inject(peer, wire(0x65, 2, <<0, 1>>))
        :close -> assert :ok = Zigbee.close(handle)
      end

      assert {:ok, %Result{outcome: :partial} = result} = Task.await(call)
      assert length(result.steps) == 2

      assert List.last(result.steps).issues == [
               if(failure == :malformed, do: :invalid_frame, else: :coordinator_lost)
             ]

      refute inspect(result) =~ "credential_canary"
    end
  end

  test "caller death closes the serial owner without starting the next interview stage" do
    {handle, _} = open()
    caller = spawn(fn -> Zigbee.interview(handle, request(), 1_000) end)
    expect(0x25, 1, <<@route::little-16, 0, 0>>)
    monitor = Process.monitor(handle.owner)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    refute_receive {:serial_write, _}, 10
    assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.interview(handle, request(), 1_000)
  end

  test "a queued reply cannot advance or finish an interview after its caller dies" do
    for stage <- [:identity, :active] do
      {handle, peer} = open()
      owner_monitor = Process.monitor(handle.owner)
      peer_monitor = Process.monitor(peer)
      caller = spawn(fn -> Zigbee.interview(handle, request(), 1_000) end)

      if stage == :active do
        identity(peer)
        respond_node(peer)
        expect(0x25, 5, <<@route::little-16, @route::little-16>>)
      else
        expect(0x25, 1, <<@route::little-16, 0, 0>>)
      end

      :ok = :sys.suspend(handle.owner)

      response =
        if stage == :active do
          wire(0x65, 5, <<0>>) <>
            wire(0x45, 0x85, <<@route::little-16, 0, @route::little-16, 0>>)
        else
          wire(0x65, 1, <<0>>) <> wire(0x45, 0x81, ieee_payload())
        end

      inject(peer, response)
      wait_messages(handle.owner)
      caller_monitor = Process.monitor(caller)
      Process.exit(caller, :kill)
      assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :killed}
      :ok = :sys.resume(handle.owner)
      assert_receive {:DOWN, ^owner_monitor, :process, _, :normal}
      assert_receive {:DOWN, ^peer_monitor, :process, _, :normal}
      refute_receive {:serial_write, _}, 10
    end
  end

  test "expired queued interviews perform no serial I/O and preserve a usable owner" do
    {handle, _} = open()
    :ok = :sys.suspend(handle.owner)
    call = interview(handle, [], 20)
    wait_messages(handle.owner)
    Process.sleep(25)
    :ok = :sys.resume(handle.owner)
    assert {:error, %Error{kind: :timeout}} = Task.await(call)
    assert {:ok, _} = Zigbee.handle(handle.owner)
    refute_receive {:serial_write, _}, 10
  end

  test "manual AF transactions and ZCL sequences are skipped by interview token allocation" do
    {handle, peer} = open()

    manual =
      Task.async(fn ->
        Zigbee.send_data(handle, 0x5678, 1, 2, 6, 0, <<4, 1::little-16, 1, 0, 0::little-16>>, 1_000)
      end)

    expect(
      0x24,
      1,
      <<0x5678::little-16, 1, 2, 6::little-16, 0, 0x50, 5, 7, 4, 1::little-16, 1, 0, 0::little-16>>
    )

    inject(peer, wire(0x64, 1, <<0>>))
    assert {:ok, _} = Task.await(manual)
    call = interview(handle)
    descriptors(peer)
    basic(peer, 1, 2, basic_records())
    assert {:ok, %Result{outcome: :complete}} = Task.await(call)
  end

  test "route capacity and token exhaustion are finite observable refusals" do
    {handle, peer} = open()

    for route <- 0..127 do
      query = Task.async(fn -> Zigbee.node_descriptor(handle, route, 1_000) end)
      expect(0x25, 2, <<route::little-16, route::little-16>>)
      inject(peer, wire(0x65, 2, <<0>>))
      assert {:ok, _} = Task.await(query)
    end

    assert {:error, %Error{kind: :overload}} = Zigbee.interview(handle, request(), 1_000)
    assert {:error, %Error{kind: :overload}} = Zigbee.node_descriptor(handle, @route, 1_000)
    assert :ok = Zigbee.close(handle)
    {handle, peer} = open()

    for token <- 0..255 do
      query = Task.async(fn -> Zigbee.send_data(handle, 1, 1, 2, 6, token, <<>>, 1_000) end)
      expect(0x24, 1, <<1::little-16, 1, 2, 6::little-16, token, 0x50, 5, 0>>)
      inject(peer, wire(0x64, 1, <<0>>))
      assert {:ok, _} = Task.await(query)
    end

    call = interview(handle)
    descriptors(peer)
    assert {:ok, %Result{outcome: :partial} = result} = Task.await(call)
    assert List.last(result.steps).stage == {:basic, 1}
    assert List.last(result.steps).issues == [:correlation_exhausted]
    assert {:ok, _} = Zigbee.handle(handle.owner)
    refute_receive {:serial_write, _}, 10
  end

  test "serial write delay and callback failures return partial observations without external text" do
    for behavior <- [:raise, :throw, :exit, :malformed, :error, {:delay, 30}] do
      {:ok, config} =
        Config.new(
          serial: Wotex.Zigbee.TestControlledSerial,
          device_id: "simulated-coordinator",
          expected_version: {2, 0, 3, 2, 0},
          timeout_ms: 100,
          serial_options: [test_pid: self(), write_behavior: behavior]
        )

      {:ok, handle} = Zigbee.open(config)

      assert {:ok, %Result{outcome: :partial, steps: [step]} = result} =
               Zigbee.interview(handle, request(), 20)

      assert step.stage == :identity
      assert step.issues == [if(is_tuple(behavior), do: :timeout, else: :serial)]
      refute inspect(result) =~ "credential-canary"
      assert {:error, %Error{kind: :coordinator_lost}} = Zigbee.handle(handle.owner)
      assert_receive {:serial_write, <<0xFE, 0, 0x21, 2, _>>}
      assert_receive {:serial_open, _, _}
      if is_tuple(behavior), do: expect(0x25, 1, <<@route::little-16, 0, 0>>)
    end
  end

  test "another interview and ordinary commands are overloaded while an interview owns admission" do
    {handle, peer} = open()
    call = interview(handle)
    expect(0x25, 1, <<@route::little-16, 0, 0>>)
    assert {:error, %Error{kind: :overload}} = Zigbee.interview(handle, request(), 1_000)
    assert {:error, %Error{kind: :overload}} = Zigbee.node_descriptor(handle, 1, 1_000)
    inject(peer, wire(0x65, 1, <<1>>))
    assert {:ok, %Result{outcome: :partial}} = Task.await(call)
  end

  test "the same raw identity can be inspected at a new route without adopting a device label" do
    {handle, peer} = open()

    results =
      for route <- [@route, 0x5678] do
        call = interview(handle, route_address: route)
        identity(peer, route: route)
        respond_node(peer, route: route)
        active(peer, [], route: route)
        assert {:ok, %Result{outcome: :complete} = result} = Task.await(call)
        result
      end

    assert Enum.map(results, & &1.peer_ieee) == [@ieee, @ieee]
    assert Enum.map(results, & &1.route_address) == [@route, 0x5678]
    assert Enum.all?(results, &(&1.owner_epoch == handle.epoch))
  end

  test "wrong ZDO source and endpoint claims do not advance the pending interview" do
    {handle, peer} = open()
    call = interview(handle)
    identity(peer)
    expect(0x25, 2, <<@route::little-16, @route::little-16>>)

    wrong_node =
      <<0x5678::little-16, 0, @route::little-16, binary_part(node_payload(), 5, 13)::binary>>

    inject(
      peer,
      wire(0x45, 0x82, wrong_node) <> wire(0x65, 2, <<0>>) <> wire(0x45, 0x82, node_payload())
    )

    active(peer, [1])
    expect(0x25, 4, <<@route::little-16, @route::little-16, 1>>)

    wrong_simple =
      <<@route::little-16, 0, @route::little-16, 8, 2, 0x0104::little-16, 0x0100::little-16, 0, 0,
        0>>

    correct_simple =
      <<@route::little-16, 0, @route::little-16, 8, 1, 0x0104::little-16, 0x0100::little-16, 0, 0,
        0>>

    inject(
      peer,
      wire(0x45, 0x84, wrong_simple) <>
        wire(0x45, 0x84, correct_simple) <>
        wire(0x45, 0x84, correct_simple) <> wire(0x65, 4, <<0>>)
    )

    assert {:ok, %Result{outcome: :complete}} = Task.await(call)
    assert {:ok, %{events: events}} = Zigbee.drain_events(handle, 32)

    assert Enum.map(events, & &1.kind) == [
             :zdo_node_descriptor,
             :zdo_simple_descriptor,
             :zdo_simple_descriptor
           ]

    assert Enum.at(events, 1).zdo.descriptor.endpoint == 2
  end

  test "queue overflow counts unrelated indications while matched interview responses remain bounded" do
    {handle, peer} = open()
    call = interview(handle)
    expect(0x25, 1, <<@route::little-16, 0, 0>>)
    unrelated = for value <- 1..50, into: <<>>, do: wire(0x45, 0x90, <<value>>)
    inject(peer, unrelated <> wire(0x45, 0x81, ieee_payload()) <> wire(0x65, 1, <<0>>))
    respond_node(peer)
    active(peer, [])
    assert {:ok, %Result{outcome: :complete}} = Task.await(call)
    assert {:ok, %{events: events, dropped: 18}} = Zigbee.drain_events(handle, 32)
    assert length(events) == 32
    assert Enum.map(events, & &1.payload) == Enum.map(1..32, &<<&1>>)
  end

  test "an abandoned queued interview consumes no route slot and performs no serial I/O" do
    {handle, _} = open()
    :ok = :sys.suspend(handle.owner)
    caller = spawn(fn -> Zigbee.interview(handle, request(), 1_000) end)
    wait_messages(handle.owner)
    monitor = Process.monitor(caller)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}
    :ok = :sys.resume(handle.owner)
    assert {:ok, _} = Zigbee.handle(handle.owner)
    assert :sys.get_state(handle.owner).query_routes == MapSet.new()
    refute_receive {:serial_write, _}, 10
  end

  defp request(options \\ []) do
    {:ok, request} =
      Interview.new(
        Keyword.merge(
          [peer_ieee: @ieee, route_address: @route, source_endpoint: 2],
          options
        )
      )

    request
  end

  defp interview(handle, options \\ [], timeout \\ 1_000),
    do: Task.async(fn -> Zigbee.interview(handle, request(options), timeout) end)

  defp open do
    {:ok, config} =
      Config.new(
        serial: TestSerialPeer,
        device_id: "simulated-coordinator",
        expected_version: {2, 0, 3, 2, 0},
        timeout_ms: 1_000,
        serial_options: [test_pid: self(), drop_reply: true],
        max_events: 32
      )

    {:ok, handle} = Zigbee.open(config)
    on_exit(fn -> Zigbee.close(handle) end)
    assert_receive {:serial_open, peer, _}
    expect(0x21, 2, <<>>)
    {handle, peer}
  end

  defp descriptors(peer) do
    identity(peer)
    respond_node(peer)
    active(peer, [1])
    simple(peer, 1, [0])
  end

  defp identity(peer, options \\ []) do
    expect(0x25, 1, <<Keyword.get(options, :route, @route)::little-16, 0, 0>>)
    respond(peer, 1, 0x81, ieee_payload(options), options)
  end

  defp ieee_payload(options \\ []),
    do:
      <<Keyword.get(options, :status, 0), Keyword.get(options, :ieee, @ieee)::binary,
        Keyword.get(options, :route, @route)::little-16, 0, 0>>

  defp respond_node(peer, options \\ []) do
    route = Keyword.get(options, :route, @route)
    expect(0x25, 2, <<route::little-16, route::little-16>>)
    respond(peer, 2, 0x82, node_payload(options), options)
  end

  defp node_payload(options \\ []),
    do:
      <<Keyword.get(options, :route, @route)::little-16, Keyword.get(options, :status, 0),
        Keyword.get(options, :route, @route)::little-16, 2, 0x40, 0x80, 0x1234::little-16, 80,
        128::little-16, 0::16, 128::little-16, 0>>

  defp active(peer, endpoints, options \\ []) do
    route = Keyword.get(options, :route, @route)
    expect(0x25, 5, <<route::little-16, route::little-16>>)

    payload =
      <<route::little-16, Keyword.get(options, :status, 0), route::little-16, length(endpoints),
        :erlang.list_to_binary(endpoints)::binary>>

    respond(peer, 5, 0x85, payload, options)
  end

  defp simple(peer, endpoint, clusters, options \\ []) do
    expect(0x25, 4, <<@route::little-16, @route::little-16, endpoint>>)
    status = Keyword.get(options, :status, 0)

    descriptor =
      if status == 0 do
        cluster_bytes = for cluster <- clusters, into: <<>>, do: <<cluster::little-16>>

        <<endpoint, Keyword.get(options, :profile, 0x0104)::little-16, 0x0100::little-16, 0,
          length(clusters), cluster_bytes::binary, 0>>
      else
        <<>>
      end

    payload =
      <<@route::little-16, status, @route::little-16, byte_size(descriptor), descriptor::binary>>

    respond(peer, 4, 0x84, payload, options)
  end

  defp basic(peer, endpoint, token, records, options \\ []) do
    expect_basic(endpoint, token, Keyword.get(options, :attributes, [0, 4, 5, 0xFFFD]))
    srsp = wire(0x64, 1, <<0>>)

    observations =
      wire(0x44, 0x80, <<0, 2, token>>) <>
        incoming(endpoint, <<8, token, 1, records::binary>>, options)

    inject(
      peer,
      if(Keyword.get(options, :early, false), do: observations <> srsp, else: srsp <> observations)
    )
  end

  defp expect_basic(endpoint, token, ids \\ [0, 4, 5, 0xFFFD]) do
    attributes = for id <- ids, into: <<>>, do: <<id::little-16>>
    data = <<0, token, 0, attributes::binary>>

    expect(
      0x24,
      1,
      <<@route::little-16, endpoint, 2, 0::little-16, token, 0x50, 5, byte_size(data),
        data::binary>>
    )
  end

  defp basic_records,
    do:
      <<0::little-16, 0, 0x20, 8, 4::little-16, 0, 0x42, 8, "consumer", 5::little-16, 0, 0x42, 6,
        "sensor", 0xFFFD::little-16, 0, 0x21, 3::little-16>>

  defp incoming(endpoint, bytes, options \\ []) do
    wire(
      0x44,
      0x81,
      <<0::16, 0::16, Keyword.get(options, :route, @route)::little-16, endpoint,
        Keyword.get(options, :local, 2), 0, 200,
        if(Keyword.get(options, :security, true), do: 1, else: 0), 0::32, 0, byte_size(bytes),
        bytes::binary>>
    )
  end

  defp respond(peer, id, response_id, payload, options) do
    srsp = wire(0x65, id, <<0>>)
    areq = wire(0x45, response_id, payload)
    inject(peer, if(Keyword.get(options, :early, false), do: areq <> srsp, else: srsp <> areq))
  end

  defp expect(command, id, payload) do
    expected = wire(command, id, payload)
    assert_receive {:serial_write, ^expected}, 500
  end

  defp inject(peer, bytes), do: send(peer, {:inject, bytes})

  defp wire(command, id, payload) do
    body = <<byte_size(payload), command, id, payload::binary>>
    checksum = Enum.reduce(:binary.bin_to_list(body), 0, &Bitwise.bxor/2)
    <<0xFE, body::binary, checksum>>
  end

  defp wait_messages(owner, attempts \\ 100)

  defp wait_messages(owner, attempts) when attempts > 0 do
    if elem(Process.info(owner, :message_queue_len), 1) > 0 do
      :ok
    else
      Process.sleep(1)
      wait_messages(owner, attempts - 1)
    end
  end

  defp wait_messages(_, 0), do: flunk("request did not reach the suspended owner")
end
