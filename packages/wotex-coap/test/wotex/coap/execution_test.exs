defmodule Wotex.CoAP.ExecutionTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.CoAP
  alias Wotex.CoAP.{Codec, Connection, Error, Execution, Message, TestDatagram, TestExecution}

  test "WCO-S03 WCO-V05 live reports keep stale metadata inert at the exact freshness boundary" do
    for {previous, candidate} <- [{10, 10}, {10, 9}, {0, 0x800000}, {0x800000, 0}] do
      {clock, session, adapter, handle, request} =
        observing(:property, observe: previous, max_age: 300)

      owner = :sys.get_state(session.pid).observation.pid
      before = :sys.get_state(owner)
      timers = TestExecution.snapshot(clock).timers
      reference = handle.reference

      try do
        assert before.report.received_at == 0 and before.expiry == 300_000
        assert :ok = TestExecution.elapse(clock, 128_000)

        stale = %{
          request
          | type: :con,
            code: 69,
            message_id: 20,
            options: [{4, "stale"}, {6, Codec.uint(candidate)}, {12, <<42>>}, {14, <<255>>}],
            payload: "stale"
        }

        emit(adapter, stale)
        assert sent(adapter) == %Message{type: :ack, code: 0, message_id: 20}
        assert synchronized_state(adapter, session, owner) == before
        assert TestExecution.snapshot(clock).timers == timers
        refute_received {:wotex_coap, ^reference, _}
        refute_received {:sent_datagram, ^adapter, _}

        assert :ok = TestExecution.elapse(clock, 128_001)

        fresh = %{
          stale
          | message_id: 21,
            options: [{4, "fresh"}, {6, Codec.uint(candidate)}, {14, Codec.uint(600)}],
            payload: "fresh"
        }

        emit(adapter, fresh)
        assert sent(adapter) == %Message{type: :ack, code: 0, message_id: 21}

        assert_receive {:wotex_coap, ^reference,
                        {:ok, ^fresh, %{observe: ^candidate, etag: "fresh", max_age: 600}}}

        current = synchronized_state(adapter, session, owner)
        assert current.report.received_at == 128_001 and current.expiry == 728_001
        assert current.refresh_at == current.expiry and current.timer_ref != before.timer_ref
        refute_received {:wotex_coap, ^reference, _}
      after
        stop_observing(clock, session, adapter, handle)
      end
    end
  end

  test "WCO-S03 WCO-V07 unrelated report tokens and endpoints cannot change active observation state" do
    {clock, session, adapter, handle, request} = observing(:property)
    owner = :sys.get_state(session.pid).observation.pid
    before = :sys.get_state(owner)
    reference = handle.reference

    report = %{
      request
      | type: :con,
        code: 69,
        message_id: 20,
        options: [{6, <<11>>}],
        payload: "fresh"
    }

    try do
      for type <- [:con, :non] do
        emit(adapter, %{report | type: type, token: "foreign"})

        if type == :con,
          do: assert(sent(adapter) == %Message{type: :rst, code: 0, message_id: 20})

        assert synchronized_state(adapter, session, owner) == before
        refute_received {:sent_datagram, ^adapter, _}
        refute_received {:wotex_coap, ^reference, _}
      end

      {:ok, bytes} = Codec.encode(report)

      for {host, port} <- [{"127.0.0.2", 5683}, {"127.0.0.1", 5684}] do
        send(adapter, {:emit, host, port, bytes})
        assert synchronized_state(adapter, session, owner) == before
        refute_received {:sent_datagram, ^adapter, _}
        refute_received {:wotex_coap, ^reference, _}
      end

      emit(adapter, report)
      assert sent(adapter) == %Message{type: :ack, code: 0, message_id: 20}
      assert_receive {:wotex_coap, ^reference, {:ok, ^report, %{observe: 11}}}
      refute_received {:wotex_coap, ^reference, _}
    after
      stop_observing(clock, session, adapter, handle)
    end
  end

  test "WCO-S03 WCO-V06 negative and malformed registration responses never expose a handle" do
    for input <- [:negative_status, :truncated_observe, :overlong_observe] do
      {:ok, clock} = TestExecution.start(%{mids: [1, 2], tokens: ["observe"]})
      {:ok, session} = connect(clock)
      assert_receive {:adapter, adapter, _}
      receiver = self()
      task = Task.async(fn -> CoAP.subscribe(session, %{path: "/x", receiver: receiver}) end)
      request = sent(adapter)
      monitor = Process.monitor(session.pid)
      adapter_monitor = Process.monitor(adapter)

      response = %{request | type: :ack, code: 69, options: []}
      assert :ok = TestExecution.elapse(clock, 50)

      case input do
        :negative_status ->
          emit(adapter, %{response | code: 132})

        :truncated_observe ->
          {:ok, bytes} = Codec.encode(response)
          send(adapter, {:emit, bytes <> <<0x62, 1>>})

        :overlong_observe ->
          emit(adapter, %{response | options: [{6, <<1, 2, 3, 4>>}]})
      end

      if input != :negative_status do
        assert :ok = GenServer.call(adapter, :sync)
        :sys.get_state(session.pid)
        refute Task.yield(task, 0)
        refute_received {:wotex_coap, _, _}
        refute_received {:sent_datagram, ^adapter, _}
        assert TestExecution.advance(clock, 100) > 0
      end

      expected = if input == :negative_status, do: :remote_response, else: :timeout
      assert {:error, %Error{code: ^expected, effect: :none}} = Task.await(task)
      assert_receive {:wotex_coap, reference, {:error, %Error{code: ^expected}}}
      cancellation = sent(adapter)
      assert cancellation.token == request.token and Codec.option(cancellation, 6) == [<<1>>]
      assert cancellation.message_id != request.message_id
      assert Codec.option(cancellation, 11) == Codec.option(request, 11)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1000
      assert_receive {:DOWN, ^adapter_monitor, :process, _, :normal}, 1000
      assert :ok = CoAP.disconnect(session)
      assert TestExecution.snapshot(clock).timers == %{}
      assert TestExecution.snapshot(clock).owners == %{}
      GenServer.stop(clock)
      refute_received {:wotex_coap, ^reference, _}
      refute_received {:sent_datagram, ^adapter, _}
    end
  end

  test "WCO-S03 WCO-V08 zero Max-Age remains stale and renews at most once per virtual second" do
    {:ok, clock} = TestExecution.start(%{mids: [1, 2, 3], tokens: ["token"]})
    {:ok, session} = connect(clock)
    assert_receive {:adapter, adapter, _}
    receiver = self()
    task = Task.async(fn -> CoAP.subscribe(session, %{path: "/x", receiver: receiver}) end)
    request = sent(adapter)

    emit(adapter, %{
      request
      | type: :ack,
        code: 69,
        options: [{6, <<10>>}, {14, <<>>}],
        payload: "value"
    })

    assert {:ok, handle} = Task.await(task)
    assert_receive {:wotex_coap, _, {:ok, _, %{max_age: 0}}}
    owner = :sys.get_state(session.pid).observation.pid
    assert :sys.get_state(owner).expiry == 0
    assert :sys.get_state(owner).refresh_at == 1000
    assert TestExecution.advance(clock, 999) == 0
    refute_received {:sent_datagram, ^adapter, _}
    assert TestExecution.advance(clock, 1000) == 1
    renewal = sent(adapter)
    assert renewal.message_id == 2 and renewal.token == request.token

    emit(adapter, %{
      renewal
      | type: :ack,
        code: 69,
        options: [{6, <<10>>}, {14, <<>>}],
        payload: "again"
    })

    assert_receive {:wotex_coap, _, {:ok, %{payload: "again"}, %{max_age: 0, observe: 10}}}
    assert :sys.get_state(owner).expiry == 1000
    assert :sys.get_state(owner).refresh_at == 2000
    assert TestExecution.advance(clock, 1999) == 0
    refute_received {:sent_datagram, ^adapter, _}
    task = Task.async(fn -> CoAP.unsubscribe(session, handle) end)
    cancellation = sent(adapter)
    assert cancellation.message_id == 3
    emit(adapter, %{cancellation | type: :ack, code: 69, options: [], payload: <<>>})
    assert :ok = Task.await(task)
    assert :ok = CoAP.disconnect(session)
    assert TestExecution.snapshot(clock).timers == %{}
    assert TestExecution.snapshot(clock).owners == %{}
    GenServer.stop(clock)
  end

  test "WCO-S03 WCO-V08 zero Max-Age without renewal becomes terminal at the actual expiry" do
    {:ok, clock} = TestExecution.start(%{mids: [1, 2], tokens: ["token"]})
    {:ok, session} = connect(clock)
    assert_receive {:adapter, adapter, _}
    receiver = self()

    task =
      Task.async(fn -> CoAP.subscribe(session, %{path: "/x", receiver: receiver, renew: false}) end)

    request = sent(adapter)
    emit(adapter, %{request | type: :ack, code: 69, options: [{6, <<10>>}, {14, <<>>}]})
    assert {:ok, handle} = Task.await(task)
    assert_receive {:wotex_coap, _, {:ok, _, %{max_age: 0}}}
    owner = :sys.get_state(session.pid).observation.pid
    assert :sys.get_state(owner).refresh_at == 0
    assert TestExecution.advance(clock, 0) == 1
    reference = handle.reference
    assert_receive {:wotex_coap, ^reference, {:error, %Error{code: :observation_stale}}}
    assert Codec.option(sent(adapter), 6) == [<<1>>]
    assert :ok = CoAP.disconnect(session)
    assert TestExecution.snapshot(clock).timers == %{}
    GenServer.stop(clock)
    refute_received {:wotex_coap, ^reference, _}
  end

  test "WCO-S02 WCO-V10 Events cannot coalesce while renewal waits for a response" do
    {clock, session, adapter, handle, request} = observing(:event)
    assert TestExecution.advance(clock, 1000) == 1
    renewal = sent(adapter)
    assert Codec.option(renewal, 6) == [<<>>]
    owner = :sys.get_state(session.pid).observation.pid
    true = :erlang.suspend_process(:sys.get_state(owner).task)
    emit(adapter, %{request | type: :con, code: 69, message_id: 20, options: [{6, <<11>>}]})
    assert sent(adapter).type == :ack
    emit(adapter, %{request | type: :con, code: 69, message_id: 21, options: [{6, <<12>>}]})
    assert sent(adapter).type == :ack
    reference = handle.reference
    assert_receive {:wotex_coap, ^reference, {:error, %Error{code: :overlapping_event_report}}}
    assert Codec.option(sent(adapter), 6) == [<<1>>]
    assert :ok = CoAP.disconnect(session)
    assert TestExecution.snapshot(clock).timers == %{}
    GenServer.stop(clock)
    refute_received {:wotex_coap, ^reference, _}
  end

  test "WCO-C03 WCO-V08 WCO-V10 suspended renewal and report delivery retain a hard deadline" do
    for phase <- [:renewal, :blockwise] do
      {clock, session, adapter, handle, request} = observing(:property)
      owner = :sys.get_state(session.pid).observation.pid

      if phase == :renewal do
        assert TestExecution.advance(clock, 1000) == 1
      else
        emit(adapter, %{
          request
          | type: :con,
            code: 69,
            message_id: 20,
            options: [{6, <<11>>}, {23, <<8>>}],
            payload: :binary.copy("x", 16)
        })

        assert sent(adapter).type == :ack
      end

      operation = sent(adapter)
      task = :sys.get_state(owner).task
      true = :erlang.suspend_process(task)
      true = :erlang.suspend_process(owner)
      options = if phase == :renewal, do: [{6, <<10>>}], else: [{23, <<16>>}]
      emit(adapter, %{operation | type: :ack, code: 69, options: options, payload: "complete"})
      assert :ok = GenServer.call(adapter, :sync)
      :sys.get_state(session.pid)
      monitor = Process.monitor(session.pid)
      TestExecution.advance(clock, if(phase == :renewal, do: 1100, else: 100))
      reference = handle.reference
      assert_receive {:wotex_coap, ^reference, {:error, %Error{code: :timeout}}}
      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1000
      assert Codec.option(sent(adapter), 6) == [<<1>>]
      refute Process.alive?(owner)
      refute Process.alive?(task)
      assert :ok = CoAP.disconnect(session)
      assert TestExecution.snapshot(clock).timers == %{}
      GenServer.stop(clock)
      refute_received {:wotex_coap, ^reference, _}
    end
  end

  @tag capture_log: true
  test "WCO-C02 WCO-D05 fixture execution rejects invalid startup before opening the adapter" do
    for input <- [
          %{now: nil, mids: [1], tokens: ["token"]},
          %{mids: [65_536], tokens: ["token"]},
          %{mids: [], tokens: []}
        ] do
      {:ok, clock} = TestExecution.start(input)
      assert {:error, %Error{code: :invalid_execution}} = connect(clock)
      refute_received {:opening, _, _, _}
      refute_received {:adapter, _, _}
      GenServer.stop(clock)
    end

    assert {:error, %Error{code: :invalid_execution}} =
             CoAP.connect(
               host: "127.0.0.1",
               execution: {MissingExecution, []},
               datagram: {TestDatagram, %{test: self(), mode: :trace}}
             )

    for opts <- [
          [execution: nil],
          [execution: {nil, []}],
          [observation_kind: :other],
          [execution: {TestExecution, self()}]
        ] do
      assert {:error, %Error{code: :invalid_execution}} =
               Connection.config([host: "127.0.0.1"] ++ opts)
    end

    assert Execution.context(self()) == :system
    assert Execution.context(nil) == :system
  end

  test "WCO-C02 WCO-D05 exhausted token or MID scripts never switch to random wire identifiers" do
    for {tokens, mids} <- [{[], [1]}, {[<<>>], [1]}, {["token", "second"], [1, :invalid]}] do
      {:ok, clock} = TestExecution.start(%{mids: mids, tokens: tokens})
      {:ok, session} = connect(clock)
      assert_receive {:adapter, adapter, _}

      if length(tokens) == 2 do
        task = Task.async(fn -> CoAP.get(session, "/x") end)
        request = sent(adapter)
        emit(adapter, %{request | type: :ack, code: 69, options: [], payload: "value"})
        assert {:ok, _} = Task.await(task)
      end

      assert {:error, %Error{code: :invalid_execution, effect: :none}} = CoAP.get(session, "/x")
      refute_received {:sent_datagram, ^adapter, _}
      assert :ok = CoAP.disconnect(session)
      GenServer.stop(clock)
    end
  end

  test "WCO-C02 WCO-S02 WCO-V10 continuation refuses its first token and bounds collision allocation" do
    first = %Message{
      type: :con,
      code: 69,
      message_id: 50,
      token: "observed",
      options: [{6, <<10>>}, {23, <<8>>}],
      payload: :binary.copy("x", 16)
    }

    for tokens <- [["observed", "observed", "next"], List.duplicate("observed", 8)] do
      {:ok, clock} = TestExecution.start(%{mids: [1], tokens: tokens})
      {:ok, session} = connect(clock)
      assert_receive {:adapter, adapter, _}
      {:ok, request} = CoAP.message(%{method: :get, path: "/x"})

      try do
        assert {:error, %Error{code: :invalid_block_payload, effect: :none}} =
                 Connection.continue(session.pid, request, %{first | payload: "short"}, 100)

        assert TestExecution.snapshot(clock).tokens == tokens
        assert :sys.get_state(session.pid).calls == %{}
        refute_received {:sent_datagram, ^adapter, _}
        task = Task.async(fn -> Connection.continue(session.pid, request, first, 100) end)

        if List.last(tokens) == "next" do
          wire = sent(adapter)
          assert wire.token == "next" and wire.message_id == 1
          assert Codec.option(wire, 6) == [] and Codec.option(wire, 23) == [<<16>>]
          emit(adapter, %{wire | type: :ack, code: 69, options: [{23, <<16>>}], payload: "!"})
          assert {:ok, complete} = Task.await(task)
          assert complete.token == first.token and complete.payload == first.payload <> "!"
          assert Codec.option(complete, 6) == [<<10>>]
        else
          assert {:error, %Error{code: :exchange_unavailable, effect: :none}} = Task.await(task)
          assert TestExecution.snapshot(clock).mids == [1]
        end

        assert TestExecution.snapshot(clock).tokens == []
        refute_received {:sent_datagram, ^adapter, _}
      after
        assert :ok = CoAP.disconnect(session)
        assert TestExecution.snapshot(clock).timers == %{}
        assert TestExecution.snapshot(clock).owners == %{}
        GenServer.stop(clock)
      end
    end
  end

  defp observing(kind, options \\ []) do
    {:ok, clock} = TestExecution.start(%{mids: [1, 2, 3], tokens: ["observe", "continue"]})
    {:ok, session} = connect(clock, kind)
    assert_receive {:adapter, adapter, _}
    receiver = self()
    task = Task.async(fn -> CoAP.subscribe(session, %{path: "/x", receiver: receiver}) end)
    request = sent(adapter)
    observe = Keyword.get(options, :observe, 10)
    max_age = Keyword.get(options, :max_age, 1)

    emit(adapter, %{
      request
      | type: :ack,
        code: 69,
        options: [{6, Codec.uint(observe)}, {14, Codec.uint(max_age)}]
    })

    assert {:ok, handle} = Task.await(task)
    assert_receive {:wotex_coap, _, {:ok, _, %{observe: ^observe}}}
    owner = :sys.get_state(session.pid).observation.pid
    assert :sys.get_state(owner).phase == :active
    {clock, session, adapter, handle, request}
  end

  defp synchronized_state(adapter, session, owner) do
    assert :ok = GenServer.call(adapter, :sync)
    :sys.get_state(session.pid)
    :sys.get_state(owner)
  end

  defp stop_observing(clock, session, adapter, handle) do
    task = Task.async(fn -> CoAP.unsubscribe(session, handle) end)
    cancellation = sent(adapter)
    assert Codec.option(cancellation, 6) == [<<1>>]
    emit(adapter, %{cancellation | type: :ack, code: 69, options: [], payload: <<>>})
    assert :ok = Task.await(task)
    assert :ok = CoAP.disconnect(session)
    assert TestExecution.snapshot(clock).timers == %{}
    assert TestExecution.snapshot(clock).owners == %{}
    GenServer.stop(clock)
  end

  defp connect(clock, kind \\ :property),
    do:
      CoAP.connect(
        host: "127.0.0.1",
        timeout: 100,
        observation_kind: kind,
        execution: {TestExecution, clock},
        datagram: {TestDatagram, %{test: self(), mode: :trace}}
      )

  defp sent(adapter) do
    assert_receive {:sent_datagram, ^adapter, bytes}, 1000
    assert {:ok, message} = Codec.decode(bytes)
    message
  end

  defp emit(adapter, message) do
    {:ok, bytes} = Codec.encode(message)
    send(adapter, {:emit, bytes})
  end
end
