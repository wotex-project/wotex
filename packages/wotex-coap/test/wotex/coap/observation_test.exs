defmodule Wotex.CoAP.ObservationTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.CoAP
  alias Wotex.CoAP.{Codec, Connection, Error, Message, Observation, Subscription}

  test "WCO-S03 WCO-V06 WCO-V07 register, fresh reports and cancel use one dedicated UDP session" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 1000)
    receiver = self()

    subscribe =
      Task.async(fn -> CoAP.subscribe(session, %{path: "/x", receiver: receiver, renew: false}) end)

    initial = wire()
    assert initial.message.code == 1
    assert Codec.option(initial.message, 6) == [<<>>]
    refute Task.yield(subscribe, 0)
    send(peer.pid, {:reply, report(initial.message, :ack, 10, "20")})
    assert {:ok, %Subscription{} = handle} = Task.await(subscribe)
    reference = handle.reference
    assert_receive {:wotex_coap, ^reference, {:ok, %{payload: "20"}, %{observe: 10, max_age: 60}}}
    assert {:error, %Error{code: :observation_active}} = CoAP.get(session, "/other")
    assert {:error, %Error{code: :observation_active}} = CoAP.subscribe(session, "/other")

    for {mid, sequence, payload} <- [{200, 11, "21"}, {201, 12, "21"}] do
      message = %{report(initial.message, :con, sequence, payload) | message_id: mid}
      send(peer.pid, {:reply, message})
      assert wire().message == %Message{type: :ack, code: 0, message_id: mid}
      assert_receive {:wotex_coap, ^reference, {:ok, %{payload: ^payload}, %{observe: ^sequence}}}
      send(peer.pid, {:reply, message})
      assert wire().message == %Message{type: :ack, code: 0, message_id: mid}
      refute_received {:wotex_coap, ^reference, _}
    end

    cancel = Task.async(fn -> CoAP.unsubscribe(session, handle) end)
    request = wire().message
    assert request.token == initial.message.token
    assert request.message_id != initial.message.message_id
    assert Codec.option(request, 6) == [<<1>>]
    assert Codec.option(request, 11) == ["x"]
    notification = %{report(initial.message, :con, 13, "22") | message_id: 202}
    send(peer.pid, {:reply, notification})
    assert wire().message == %Message{type: :ack, code: 0, message_id: 202}
    refute Task.yield(cancel, 0)
    refute_received {:wotex_coap, ^reference, _}
    send(peer.pid, {:reply, report(request, :ack, 14, "not cancellation")})
    observer = :sys.get_state(session.pid).observation.pid
    assert :sys.get_state(observer).phase == :canceling
    refute Task.yield(cancel, 0)
    send(peer.pid, {:reply, %{request | type: :ack, code: 69, options: []}})
    assert :ok = Task.await(cancel)
    assert :ok = CoAP.unsubscribe(session, handle)
    assert :ok = CoAP.disconnect(session)
    close(peer)
    refute_received {:wire, _, _, _, _}
  end

  test "WCO-C02 WCO-V06 WCO-V09 invalid options and foreign handles fail before I/O" do
    for {path, receiver, opts} <- [
          {nil, self(), []},
          {"/x", nil, []},
          {"/x", self(), nil},
          {"/x", self(), [renew: nil]},
          {"/x", self(), [max_queue_length: 0]},
          {"/x", self(), [max_queue_length: 10_001]},
          {"/x", self(), [renew: true, renew: false]},
          {"/x", self(), [{:renew, true} | nil]}
        ] do
      assert {:error, %Error{code: :invalid_observation_options}} =
               Observation.options(path, receiver, opts)
    end

    assert {:error, _} = CoAP.subscribe(nil, nil)
    assert {:error, _} = CoAP.subscribe(nil, %{path: "/x", extra: true})
    assert {:error, _} = Connection.observe(nil, "/x", self(), [], 0)
    assert {:error, _} = Connection.unobserve(nil, nil, 0)
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port)
    {:ok, foreign} = Subscription.new(session.pid, make_ref(), make_ref())
    assert {:error, %Error{code: :invalid_subscription}} = CoAP.unsubscribe(session, foreign)
    assert :ok = CoAP.disconnect(session)
    close(peer)
    refute_received {:wire, _, _, _, _}
  end

  test "WCO-S03 WCO-V06 missing Observe rejects establishment and sends best-effort cancellation" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 1000)
    receiver = self()
    task = Task.async(fn -> CoAP.subscribe(session, %{path: "/x", receiver: receiver}) end)
    request = wire().message

    send(
      peer.pid,
      {:reply, %{request | type: :ack, code: 69, options: [], payload: "not observed"}}
    )

    assert {:error, %Error{code: :invalid_observation_response}} = Task.await(task)
    cancellation = wire().message
    assert cancellation.token == request.token
    assert Codec.option(cancellation, 6) == [<<1>>]
    assert :ok = CoAP.disconnect(session)
    close(peer)
  end

  test "WCO-S03 WCO-V05 stale reports do not move arrival or expiry and wraparound stays fresh" do
    {peer, session, handle, request} = established(16_777_215, "initial")
    owner = :sys.get_state(session.pid).observation.pid
    before = :sys.get_state(owner)

    for {mid, sequence} <- [{300, 16_777_215}, {301, 16_777_214}, {302, 0x7FFFFF}] do
      send(peer.pid, {:reply, %{report(request, :con, sequence, "stale") | message_id: mid}})
      assert wire().message == %Message{type: :ack, code: 0, message_id: mid}
    end

    current = :sys.get_state(owner)
    assert current.report.received_at == before.report.received_at
    assert current.expiry == before.expiry
    refute_received {:wotex_coap, _, _}
    send(owner, {:expiry, make_ref()})
    send(owner, {:result, make_ref(), {:error, Error.new(:timeout)}})
    send(owner, {:report, make_ref(), report(request, :con, 0, "forged")})
    send(owner, {:DOWN, make_ref(), :process, self(), :normal})
    send(peer.pid, {:reply, %{report(request, :con, 0, "wrapped") | message_id: 303}})
    assert wire().message.type == :ack
    assert_receive {:wotex_coap, _, {:ok, %{payload: "wrapped"}, %{observe: 0}}}
    cancel(peer, session, handle)
  end

  test "WCO-S03 WCO-V08 renewal keeps token and admits unchanged serial without moving stale clocks" do
    {peer, session, handle, request} = established(10, "initial", max_age: 1)
    renewal = wire().message
    assert renewal.token == request.token
    assert renewal.message_id != request.message_id
    assert Codec.option(renewal, 6) == [<<>>]
    send(peer.pid, {:reply, report(renewal, :ack, 10, "renewed")})
    assert_receive {:wotex_coap, _, {:ok, %{payload: "renewed"}, %{observe: 10}}}
    cancel(peer, session, handle)
  end

  test "WCO-S03 WCO-V08 disabled renewal terminates stale state and preserves bounded large timers" do
    {peer, session, handle, _} = established(10, "initial", max_age: 1, renew: false)
    reference = handle.reference
    assert_receive {:wotex_coap, ^reference, {:error, %Error{code: :observation_stale}}}, 1500
    cancellation = wire().message
    assert Codec.option(cancellation, 6) == [<<1>>]
    assert :ok = CoAP.disconnect(session)
    close(peer)
    refute_received {:wotex_coap, ^reference, _}

    {peer, session, handle, _} = established(10, "initial", max_age: 4_294_967_295)
    owner = :sys.get_state(session.pid).observation.pid
    state = :sys.get_state(owner)
    assert Process.read_timer(state.timer) in 1..60_000
    send(owner, {:expiry, state.timer_ref})
    next = :sys.get_state(owner)
    assert next.expiry == state.expiry
    assert next.timer_ref != state.timer_ref
    cancel(peer, session, handle)
  end

  test "WCO-C03 WCO-C05 WCO-V15 owner or receiver death releases observation and actual socket" do
    for reason <- [:owner, :receiver] do
      other = spawn(fn -> receive do: (:done -> :ok) end)
      options = if reason == :owner, do: [owner: other], else: []
      receiver = if reason == :receiver, do: other, else: self()
      {peer, session, handle, _} = established(10, "initial", connect: options, receiver: receiver)
      state = :sys.get_state(session.pid)
      socket = :sys.get_state(state.handle.pid).socket
      monitor = Process.monitor(session.pid)
      observation_monitor = Process.monitor(state.observation.pid)
      adapter_monitor = Process.monitor(state.handle.pid)
      send(other, :done)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1000
      assert_receive {:DOWN, ^observation_monitor, :process, _, _}, 1000
      assert_receive {:DOWN, ^adapter_monitor, :process, _, :normal}, 1000
      assert :erlang.port_info(socket) == :undefined
      assert Codec.option(wire().message, 6) == [<<1>>]
      assert :ok = CoAP.unsubscribe(session, handle)
      assert :ok = CoAP.disconnect(session)
      close(peer)

      if reason == :owner do
        reference = handle.reference
        assert_receive {:wotex_coap, ^reference, {:error, %Error{code: :connection_closed}}}
        refute_received {:wotex_coap, ^reference, _}
      end
    end
  end

  test "WCO-C05 WCO-V15 a full receiver queue terminates without silently dropping a fresh report" do
    receiver = spawn(fn -> receive do: (:done -> :ok) end)

    {peer, session, handle, request} =
      established(10, "initial", receiver: receiver, max_queue_length: 1)

    monitor = Process.monitor(session.pid)
    send(peer.pid, {:reply, %{report(request, :con, 11, "next") | message_id: 555}})
    assert wire().message.type == :ack
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1000
    reference = handle.reference

    assert {:messages,
            [
              {:wotex_coap, ^reference, {:ok, %{payload: "initial"}, _}},
              {:wotex_coap, ^reference, {:error, %Error{code: :receiver_overflow}}}
            ]} =
             Process.info(receiver, :messages)

    assert Codec.option(wire().message, 6) == [<<1>>]
    assert :ok = CoAP.disconnect(session)
    send(receiver, :done)
    close(peer)
  end

  test "WCO-S03 WCO-V06 initial Block2 body must finish before a handle or report is returned" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 1000)
    receiver = self()
    task = Task.async(fn -> CoAP.subscribe(session, %{path: "/x", receiver: receiver}) end)
    request = wire().message

    initial = %{
      report(request, :ack, 10, :binary.copy("a", 16))
      | options: [{6, <<10>>}, {23, <<8>>}]
    }

    send(peer.pid, {:reply, initial})
    continuation = wire().message
    assert continuation.token != request.token
    assert Codec.option(continuation, 6) == []
    assert Codec.option(continuation, 23) == [<<16>>]
    refute Task.yield(task, 0)
    refute_received {:wotex_coap, _, {:ok, _, _}}

    send(
      peer.pid,
      {:reply, %{continuation | type: :ack, code: 69, options: [{23, <<16>>}], payload: "last"}}
    )

    assert {:ok, handle} = Task.await(task)
    assert_receive {:wotex_coap, _, {:ok, complete, %{observe: 10}}}
    assert complete.payload == :binary.copy("a", 16) <> "last"
    assert complete.token == request.token
    cancel(peer, session, handle)
  end

  test "WCO-S03 WCO-V07 server termination and format changes each produce exactly one terminal error" do
    for {changes, code} <- [
          {%{code: 132, options: []}, :remote_response},
          {%{options: [{6, <<11>>}, {12, <<42>>}]}, :representation_changed}
        ] do
      {peer, session, handle, request} = established(10, "initial")
      message = Map.merge(%{report(request, :con, 11, "next") | message_id: 888}, changes)
      send(peer.pid, {:reply, message})
      assert wire().message.type == :ack
      reference = handle.reference
      assert_receive {:wotex_coap, ^reference, {:error, %Error{code: ^code}}}
      assert Codec.option(wire().message, 6) == [<<1>>]
      assert :ok = CoAP.disconnect(session)
      close(peer)
      refute_received {:wotex_coap, ^reference, _}
    end
  end

  test "WCO-S03 WCO-V06 registration and initial-body deadlines produce errors and cleanup" do
    for stage <- [:initial, :body] do
      {peer, port} = peer()
      {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 40)
      receiver = self()
      task = Task.async(fn -> CoAP.subscribe(session, %{path: "/x", receiver: receiver}) end)
      request = wire().message

      if stage == :body do
        initial = %{
          report(request, :ack, 10, :binary.copy("x", 16))
          | options: [{6, <<10>>}, {23, <<8>>}]
        }

        send(peer.pid, {:reply, initial})
        assert Codec.option(wire().message, 23) == [<<16>>]
      end

      assert {:error, %Error{code: :timeout}} = Task.await(task)
      assert_receive {:wotex_coap, reference, {:error, %Error{code: :timeout}}}
      assert Codec.option(wire().message, 6) == [<<1>>]
      assert :ok = CoAP.disconnect(session)
      close(peer)
      refute_received {:wotex_coap, ^reference, _}
    end
  end

  test "WCO-S03 WCO-V09 concurrent cancellation shares one exchange while canceled assembly is released" do
    {peer, session, handle, request} = established(10, "initial")

    next = %{
      report(request, :con, 11, :binary.copy("x", 16))
      | message_id: 999,
        options: [{6, <<11>>}, {23, <<8>>}]
    }

    send(peer.pid, {:reply, next})
    assert wire().message.type == :ack
    assert Codec.option(wire().message, 23) == [<<16>>]
    cancel_one = Task.async(fn -> CoAP.unsubscribe(session, handle) end)
    cancel_request = wire().message
    assert Codec.option(cancel_request, 6) == [<<1>>]
    cancel_two = Task.async(fn -> CoAP.unsubscribe(session, handle) end)
    owner = :sys.get_state(session.pid).observation.pid
    await(owner, &(is_list(&1.cancel_from) and length(&1.cancel_from) == 2))
    send(peer.pid, {:reply, %{cancel_request | type: :ack, code: 69, options: []}})
    assert :ok = Task.await(cancel_one)
    assert :ok = Task.await(cancel_two)
    assert :ok = CoAP.disconnect(session)
    close(peer)
    refute_received {:wotex_coap, _, _}
    refute_received {:wire, _, _, _, _}
  end

  test "WCO-S03 WCO-V10 one latest Property report survives overlapping Block2 assembly" do
    {peer, session, handle, request} = established(10, "initial")
    owner = :sys.get_state(session.pid).observation.pid

    block = %{
      report(request, :con, 11, :binary.copy("x", 16))
      | message_id: 800,
        options: [{6, <<11>>}, {23, <<8>>}]
    }

    send(peer.pid, {:reply, block})
    assert wire().message.type == :ack
    continuation = wire().message

    for {sequence, mid} <- [{12, 801}, {13, 802}, {12, 803}] do
      send(peer.pid, {:reply, %{report(request, :con, sequence, "latest") | message_id: mid}})
      assert wire().message.type == :ack
    end

    state = await(owner, &(&1.pending && &1.pending.metadata.observe == 13))
    assert state.report.metadata.observe == 11

    send(
      peer.pid,
      {:reply, %{continuation | type: :ack, code: 69, options: [{23, <<16>>}], payload: "end"}}
    )

    assert_receive {:wotex_coap, _, {:ok, %{payload: body}, %{observe: 11}}}
    assert body == :binary.copy("x", 16) <> "end"
    assert_receive {:wotex_coap, _, {:ok, %{payload: "latest"}, %{observe: 13}}}
    refute_received {:wotex_coap, _, _}
    cancel(peer, session, handle)
  end

  test "WCO-C03 WCO-V15 setup caller death and failed report worker stop all owned resources" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 60_000)
    receiver = self()
    task = Task.async(fn -> CoAP.subscribe(session, %{path: "/x", receiver: receiver}) end)
    wire()
    monitor = Process.monitor(session.pid)
    Task.shutdown(task, :brutal_kill)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1000
    assert Codec.option(wire().message, 6) == [<<1>>]
    assert :ok = CoAP.disconnect(session)
    close(peer)
    assert_receive {:wotex_coap, _, {:error, %Error{code: :connection_closed}}}

    {peer, session, _, request} = established(10, "initial")
    owner = :sys.get_state(session.pid).observation.pid

    block = %{
      report(request, :con, 11, :binary.copy("x", 16))
      | message_id: 900,
        options: [{6, <<11>>}, {23, <<8>>}]
    }

    send(peer.pid, {:reply, block})
    assert wire().message.type == :ack
    wire()
    state = :sys.get_state(owner)
    Process.exit(state.task, :kill)
    assert_receive {:wotex_coap, _, {:error, %Error{}}}
    assert Codec.option(wire().message, 6) == [<<1>>]
    assert :ok = CoAP.disconnect(session)
    close(peer)
    refute_received {:wotex_coap, _, _}
  end

  test "WCO-C02 WCO-V09 internal observer authority cannot be forged on a live owner" do
    {peer, session, handle, request} = established(10, "initial")
    owner = :sys.get_state(session.pid).observation.pid
    {:ok, foreign} = Subscription.new(session.pid, make_ref(), handle.generation)

    assert {:error, %Error{code: :invalid_subscription}} =
             GenServer.call(owner, {:cancel, foreign, 1})

    assert {:error, %Error{code: :invalid_subscription}} =
             Connection.observation_abort(session.pid, make_ref())

    assert {:error, %Error{code: :invalid_subscription}} =
             Connection.observation_terminal(session.pid, make_ref(), Error.new(:timeout))

    assert {:error, %Error{code: :observation_active}} =
             Connection.observation_exchange(session.pid, make_ref(), request, :register, 100)

    capability = :sys.get_state(session.pid).observation.capability

    assert {:error, %Error{code: :invalid_subscription}} =
             Connection.observation_exchange(
               session.pid,
               capability,
               %{request | token: "foreign"},
               :register,
               100
             )

    assert {:error, _} = Connection.observation_abort(self(), make_ref())
    assert {:error, _} = Connection.observation_terminal(self(), make_ref(), Error.new(:timeout))
    assert {:error, _} = Connection.observe(self(), "/x", self(), [], 100)
    assert {:error, _} = Connection.unobserve(self(), %{handle | pid: self()}, 100)
    cancel(peer, session, handle)
  end

  test "WCO-S03 WCO-V07 reports received before registration result delivery stay bounded" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 1000)
    receiver = self()
    task = Task.async(fn -> CoAP.subscribe(session, %{path: "/x", receiver: receiver}) end)
    request = wire().message
    owner = :sys.get_state(session.pid).observation.pid
    worker = :sys.get_state(owner).task
    true = :erlang.suspend_process(worker)
    send(peer.pid, {:reply, report(request, :ack, 10, "initial")})

    for {sequence, mid} <- [{11, 500}, {12, 501}, {11, 502}] do
      send(peer.pid, {:reply, %{report(request, :con, sequence, "latest") | message_id: mid}})
      assert wire().message.type == :ack
    end

    state = await(owner, &(&1.pending && &1.pending.metadata.observe == 12))
    assert state.report == nil
    refute Task.yield(task, 0)
    received_before_resume = System.monotonic_time(:millisecond)
    true = :erlang.resume_process(worker)
    assert {:ok, handle} = Task.await(task)
    assert_receive {:wotex_coap, _, {:ok, %{payload: "initial"}, %{observe: 10}}}
    assert_receive {:wotex_coap, _, {:ok, %{payload: "latest"}, %{observe: 12}}}
    assert :sys.get_state(owner).report.received_at <= received_before_resume
    cancel(peer, session, handle)
  end

  test "WCO-S03 WCO-V09 cancellation deadline closes locally without claiming remote confirmation" do
    {peer, session, handle, _} = established(10, "initial")
    cancel = Task.async(fn -> Connection.unobserve(session.pid, handle, 40) end)
    assert Codec.option(wire().message, 6) == [<<1>>]
    assert {:error, %Error{code: :timeout}} = Task.await(cancel)
    reference = handle.reference
    assert_receive {:wotex_coap, ^reference, {:error, %Error{code: :timeout}}}
    assert :ok = CoAP.disconnect(session)
    close(peer)
    refute_received {:wotex_coap, ^reference, _}
    refute_received {:wire, _, _, _, _}
  end

  test "WCO-C03 WCO-V06 a completed body delivered after its assembly deadline is rejected" do
    {peer, session, handle, request} = established(10, "initial")
    owner = :sys.get_state(session.pid).observation.pid

    first = %{
      report(request, :con, 11, :binary.copy("x", 16))
      | message_id: 950,
        options: [{6, <<11>>}, {23, <<8>>}]
    }

    send(peer.pid, {:reply, first})
    assert wire().message.type == :ack
    continuation = wire().message
    :sys.replace_state(owner, &%{&1 | phase_deadline: System.monotonic_time(:millisecond) - 1})

    send(
      peer.pid,
      {:reply, %{continuation | type: :ack, code: 69, options: [{23, <<16>>}], payload: "end"}}
    )

    reference = handle.reference
    assert_receive {:wotex_coap, ^reference, {:error, %Error{code: :timeout}}}
    assert Codec.option(wire().message, 6) == [<<1>>]
    assert :ok = CoAP.disconnect(session)
    close(peer)
    refute_received {:wotex_coap, ^reference, _}
  end

  test "WCO-S02 WCO-S03 WCO-V10 Event overlap terminates instead of coalescing ordered reports" do
    {peer, session, handle, request} =
      established(10, "initial", connect: [observation_kind: :event])

    first = %{
      report(request, :con, 11, :binary.copy("x", 16))
      | message_id: 970,
        options: [{6, <<11>>}, {23, <<8>>}]
    }

    send(peer.pid, {:reply, first})
    assert wire().message.type == :ack
    assert Codec.option(wire().message, 23) == [<<16>>]
    send(peer.pid, {:reply, %{report(request, :con, 12, "next") | message_id: 971}})
    assert wire().message.type == :ack
    reference = handle.reference
    assert_receive {:wotex_coap, ^reference, {:error, %Error{code: :overlapping_event_report}}}
    assert Codec.option(wire().message, 6) == [<<1>>]
    assert :ok = CoAP.disconnect(session)
    close(peer)
    refute_received {:wotex_coap, ^reference, _}
  end

  test "WCO-C03 WCO-V06 suspended establishment cannot outlive its connection deadline" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 200)
    receiver = self()
    task = Task.async(fn -> CoAP.subscribe(session, %{path: "/x", receiver: receiver}) end)
    request = wire().message
    state = :sys.get_state(session.pid)
    socket = :sys.get_state(state.handle.pid).socket
    monitors = Enum.map([session.pid, state.observation.pid, state.handle.pid], &Process.monitor/1)
    true = :erlang.suspend_process(state.observation.pid)
    send(peer.pid, {:reply, report(request, :ack, 10, "too late")})
    assert {:error, %Error{code: :timeout}} = Task.await(task)
    assert_receive {:wotex_coap, _, {:error, %Error{code: :timeout}}}
    for monitor <- monitors, do: assert_receive({:DOWN, ^monitor, :process, _, _}, 1000)
    assert :erlang.port_info(socket) == :undefined
    cancellation = wire().message
    assert cancellation.token == request.token
    assert Codec.option(cancellation, 6) == [<<1>>]
    assert :ok = CoAP.disconnect(session)
    close(peer)
    refute_received {:wotex_coap, _, _}
  end

  test "WCO-C03 WCO-V09 suspended cancellation releases the socket without inventing confirmation" do
    {peer, session, handle, request} = established(10, "initial")
    state = :sys.get_state(session.pid)
    socket = :sys.get_state(state.handle.pid).socket
    monitors = Enum.map([session.pid, state.observation.pid, state.handle.pid], &Process.monitor/1)
    true = :erlang.suspend_process(state.observation.pid)
    task = Task.async(fn -> Connection.unobserve(session.pid, handle, 40) end)
    assert {:error, %Error{code: :timeout}} = Task.await(task)
    reference = handle.reference
    assert_receive {:wotex_coap, ^reference, {:error, %Error{code: :timeout}}}
    for monitor <- monitors, do: assert_receive({:DOWN, ^monitor, :process, _, _}, 1000)
    assert :erlang.port_info(socket) == :undefined
    cancellation = wire().message
    assert cancellation.token == request.token
    assert Codec.option(cancellation, 6) == [<<1>>]
    assert :ok = CoAP.disconnect(session)
    close(peer)
    refute_received {:wotex_coap, ^reference, _}
    refute_received {:wire, _, _, _, _}
  end

  test "WCO-S02 WCO-V10 Event overlap before the initial result cannot lose a report" do
    {peer, port} = peer()

    {:ok, session} =
      CoAP.connect(host: "127.0.0.1", port: port, timeout: 1000, observation_kind: :event)

    receiver = self()
    task = Task.async(fn -> CoAP.subscribe(session, %{path: "/x", receiver: receiver}) end)
    request = wire().message
    owner = :sys.get_state(session.pid).observation.pid
    true = :erlang.suspend_process(:sys.get_state(owner).task)
    send(peer.pid, {:reply, report(request, :ack, 10, "initial")})
    send(peer.pid, {:reply, %{report(request, :con, 11, "next") | message_id: 972}})
    assert wire().message.type == :ack
    assert {:error, %Error{code: :overlapping_event_report}} = Task.await(task)
    assert_receive {:wotex_coap, _, {:error, %Error{code: :overlapping_event_report}}}
    assert Codec.option(wire().message, 6) == [<<1>>]
    assert :ok = CoAP.disconnect(session)
    close(peer)
    refute_received {:wotex_coap, _, _}
  end

  test "WCO-C07 WCO-V15 owner diagnostics redact report values and terminating messages" do
    for role <- [:connection, :observation, :datagram] do
      secret = "private-observed-value-" <> Atom.to_string(role)
      {peer, session, _, _} = established(10, secret)
      state = :sys.get_state(session.pid)

      pid =
        case role do
          :connection -> session.pid
          :observation -> state.observation.pid
          :datagram -> state.handle.pid
        end

      Process.unlink(session.pid)
      monitor = Process.monitor(session.pid)
      status = inspect(:sys.get_status(pid), limit: :infinity)
      refute String.contains?(status, secret)
      assert String.contains?(status, "redacted")

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          GenServer.cast(pid, {:unsupported, secret})
          assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
        end)

      refute String.contains?(log, secret)
      if role != :observation, do: assert(String.contains?(log, "redacted"), inspect(role))
      assert_receive {:wotex_coap, _, {:error, %Error{code: :connection_closed}}}
      if role != :datagram, do: assert(Codec.option(wire().message, 6) == [<<1>>])
      assert :ok = CoAP.disconnect(session)
      close(peer)
    end
  end

  test "WCO-S02 WCO-V10 native initial and subsequent notifications accept 1024-byte Block2" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 1000)
    receiver = self()
    task = Task.async(fn -> CoAP.subscribe(session, %{path: "/x", receiver: receiver}) end)
    request = wire().message

    for sequence <- [10, 11] do
      type = if sequence == 10, do: :ack, else: :con
      mid = if sequence == 10, do: request.message_id, else: 799

      first = %{
        report(request, type, sequence, :binary.copy("x", 1024))
        | message_id: mid,
          options: [{6, Codec.uint(sequence)}, {23, <<14>>}]
      }

      send(peer.pid, {:reply, first})
      if sequence == 11, do: assert(wire().message.type == :ack)
      continuation = wire().message
      assert Codec.option(continuation, 23) == [<<22>>]
      assert continuation.token != request.token
      assert Codec.option(continuation, 6) == []

      send(
        peer.pid,
        {:reply, %{continuation | type: :ack, code: 69, options: [{23, <<22>>}], payload: "!"}}
      )

      assert_receive {:wotex_coap, _, {:ok, %{payload: body}, %{observe: ^sequence}}}
      assert body == :binary.copy("x", 1024) <> "!"
    end

    send(
      peer.pid,
      {:reply,
       %{report(request, :con, 12, "small") | message_id: 798, options: [{6, <<12>>}, {23, <<6>>}]}}
    )

    assert wire().message.type == :ack
    assert_receive {:wotex_coap, _, {:ok, %{payload: "small"}, %{observe: 12}}}
    assert {:ok, handle} = Task.await(task)
    cancel(peer, session, handle)
  end

  test "WCO-S04 WCO-I05 explicit wire defaults survive registration, renewal and cancellation" do
    for accept <- [0, 50, 65_535] do
      {peer, port} = peer()

      {:ok, session} =
        CoAP.connect(
          host: "127.0.0.1",
          port: port,
          timeout: 1000,
          observation_options: [accept: accept, confirmable: false]
        )

      receiver = self()
      task = Task.async(fn -> CoAP.subscribe(session, %{path: "/x?a=b", receiver: receiver}) end)
      initial = wire().message
      assert initial.type == :non and Codec.option(initial, 17) == [Codec.uint(accept)]

      send(
        peer.pid,
        {:reply,
         %{
           report(initial, :non, 10, "value")
           | message_id: 700,
             options: [{6, <<10>>}, {14, <<1>>}]
         }}
      )

      assert {:ok, handle} = Task.await(task)
      assert_receive {:wotex_coap, _, {:ok, _, %{observe: 10}}}
      renewal = wire().message
      assert renewal.type == :non and renewal.token == initial.token
      assert Codec.option(renewal, 17) == [Codec.uint(accept)]
      assert Codec.option(renewal, 15) == ["a=b"]
      send(peer.pid, {:reply, %{report(renewal, :non, 11, "next") | message_id: 701}})
      assert_receive {:wotex_coap, _, {:ok, _, %{observe: 11}}}
      cancel = Task.async(fn -> CoAP.unsubscribe(session, handle) end)
      request = wire().message
      assert request.type == :non and request.token == initial.token
      assert Codec.option(request, 17) == [Codec.uint(accept)]
      assert Codec.option(request, 6) == [<<1>>]
      send(peer.pid, {:reply, %{request | type: :non, code: 69, message_id: 702, options: []}})
      assert :ok = Task.await(cancel)
      assert :ok = CoAP.disconnect(session)
      close(peer)
    end
  end

  test "WCO-C02 WCO-S04 malformed explicit wire defaults fail before socket acquisition" do
    for options <- [
          nil,
          %{},
          [accept: nil],
          [accept: -1],
          [accept: 65_536],
          [accept: 50.0],
          [confirmable: nil],
          [accept: 50, accept: 50],
          [path: "/x"],
          [{:accept, 50} | nil]
        ] do
      assert {:error, %Error{code: :invalid_observation_options}} =
               CoAP.connect(host: "127.0.0.1", observation_options: options)
    end

    assert {:ok, %{accept: nil, confirmable: true}} = Observation.wire_options([])
  end

  defp await(owner, predicate),
    do: await(owner, predicate, System.monotonic_time(:millisecond) + 1000)

  defp await(owner, predicate, deadline) do
    state = :sys.get_state(owner)

    if predicate.(state),
      do: state,
      else:
        (
          assert System.monotonic_time(:millisecond) < deadline

          receive do
          after
            1 -> await(owner, predicate, deadline)
          end
        )
  end

  defp established(sequence, payload, options \\ []) do
    {peer, port} = peer()

    {:ok, session} =
      CoAP.connect(
        [host: "127.0.0.1", port: port, timeout: 1000] ++ Keyword.get(options, :connect, [])
      )

    receiver = Keyword.get(options, :receiver, self())

    task =
      Task.async(fn ->
        CoAP.subscribe(session, %{
          path: "/x",
          receiver: receiver,
          renew: Keyword.get(options, :renew, true),
          max_queue_length: Keyword.get(options, :max_queue_length, 1000)
        })
      end)

    request = wire().message
    initial = report(request, :ack, sequence, payload)

    initial =
      if Keyword.has_key?(options, :max_age),
        do: %{initial | options: [{14, Codec.uint(options[:max_age])} | initial.options]},
        else: initial

    send(peer.pid, {:reply, initial})
    assert {:ok, handle} = Task.await(task)
    if receiver == self(), do: assert_receive({:wotex_coap, _, {:ok, %{payload: ^payload}, _}})
    {peer, session, handle, request}
  end

  defp cancel(peer, session, handle) do
    task = Task.async(fn -> CoAP.unsubscribe(session, handle) end)
    request = wire().message
    assert Codec.option(request, 6) == [<<1>>]
    send(peer.pid, {:reply, %{request | type: :ack, code: 69, options: []}})
    assert :ok = Task.await(task)
    assert :ok = CoAP.disconnect(session)
    close(peer)
  end

  defp report(request, type, sequence, payload),
    do: %{request | type: type, code: 69, options: [{6, Codec.uint(sequence)}], payload: payload}

  defp peer do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: true, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    test = self()
    peer = Task.async(fn -> receive do: (:go -> loop(socket, test, nil)) end)
    :ok = :gen_udp.controlling_process(socket, peer.pid)
    send(peer.pid, :go)
    {peer, port}
  end

  defp loop(socket, test, endpoint) do
    receive do
      {:udp, ^socket, host, port, bytes} ->
        {:ok, message} = Codec.decode(bytes)
        send(test, {:wire, host, port, bytes, message})
        loop(socket, test, {host, port})

      {:reply, message} ->
        {:ok, bytes} = Codec.encode(message)
        {host, port} = endpoint
        :ok = :gen_udp.send(socket, host, port, bytes)
        loop(socket, test, endpoint)

      :close ->
        :gen_udp.close(socket)
    after
      5000 -> flunk("peer was not closed")
    end
  end

  defp wire do
    assert_receive {:wire, host, port, bytes, message}, 1500
    %{host: host, port: port, bytes: bytes, message: message}
  end

  defp close(peer) do
    send(peer.pid, :close)
    Task.await(peer)
  end
end
