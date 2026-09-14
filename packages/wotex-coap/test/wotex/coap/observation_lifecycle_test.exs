defmodule Wotex.CoAP.ObservationLifecycleTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.CoAP
  alias Wotex.CoAP.{Codec, Connection, Error, Message, TestDatagram, TestExecution}

  test "WCO-C03 WCO-V09 cancellation completion cannot succeed at or after its absolute deadline" do
    for completed_at <- [1099, 1100, 1101] do
      state = observing()

      try do
        assert :ok = TestExecution.elapse(state.clock, 1000)
        task = Task.async(fn -> CoAP.unsubscribe(state.session, state.handle) end)
        cancellation = sent(state.adapter)
        assert Codec.option(cancellation, 6) == [<<1>>]
        worker = :sys.get_state(state.owner).task
        worker_monitor = Process.monitor(worker)
        true = :erlang.suspend_process(state.owner)
        assert :ok = TestExecution.elapse(state.clock, 1099)
        emit(state.adapter, %{cancellation | type: :ack, code: 69, options: []})
        assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :normal}, 1000
        assert :sys.get_state(state.session.pid).observation.cancellation_confirmed
        assert TestExecution.snapshot(state.clock).timers == %{}
        assert TestExecution.advance(state.clock, completed_at) == 0
        true = :erlang.resume_process(state.owner)

        if completed_at < 1100,
          do: assert(:ok = Task.await(task)),
          else: assert({:error, %Error{code: :timeout, effect: :none}} = Task.await(task))

        assert_closed(state)
        refute_received {:wotex_coap, _, _}
        refute_received {:sent_datagram, _, _}
      after
        dispose(state)
      end
    end
  end

  test "WCO-C03 WCO-V09 concurrent cancellers retain their individual completion deadlines" do
    state = observing()

    try do
      first = Task.async(fn -> Connection.unobserve(state.session.pid, state.handle, 100) end)
      cancellation = sent(state.adapter)
      assert :ok = TestExecution.elapse(state.clock, 10)
      second = Task.async(fn -> Connection.unobserve(state.session.pid, state.handle, 20) end)
      await_cancellers(state.owner, 2)
      refute_received {:sent_datagram, _, _}
      assert :ok = TestExecution.elapse(state.clock, 50)
      emit(state.adapter, %{cancellation | type: :ack, code: 69, options: [], payload: <<>>})
      assert :ok = Task.await(first)
      assert {:error, %Error{code: :timeout, effect: :none}} = Task.await(second)
      assert_closed(state)
      refute_received {:wotex_coap, _, _}
      refute_received {:sent_datagram, _, _}
    after
      dispose(state)
    end
  end

  test "WCO-S03 WCO-D04 WCO-V08 WCO-V09 sliced refresh and cancellation retain the once-decoded route" do
    state = observing(path: "/a%252Fb//c?x=%252F&x=+&&", max_age: 4_294_967_295)

    try do
      assert Codec.option(state.request, 11) == ["a%2Fb", "", "c"]
      assert Codec.option(state.request, 15) == ["x=%2F", "x=+", "", ""]
      assert Codec.option(state.request, 17) == [<<>>]
      initial = :sys.get_state(state.owner)
      assert initial.expiry == 4_294_967_295_000
      assert TestExecution.snapshot(state.clock).timers[initial.timer].at == 60_000
      assert TestExecution.advance(state.clock, 60_000) == 1
      sliced = :sys.get_state(state.owner)
      assert sliced.expiry == initial.expiry and sliced.timer_ref != initial.timer_ref
      assert TestExecution.snapshot(state.clock).timers[sliced.timer].at == 120_000

      assert TestExecution.advance(state.clock, initial.expiry - 1) == 1
      final_slice = :sys.get_state(state.owner)
      assert final_slice.phase == :active and final_slice.expiry == initial.expiry
      assert TestExecution.snapshot(state.clock).timers[final_slice.timer].at == initial.expiry
      refute_received {:sent_datagram, _, _}
      assert TestExecution.advance(state.clock, initial.expiry) == 1
      renewal = sent(state.adapter)
      assert renewal == %{state.request | message_id: 2}
      deadline_ref = :sys.get_state(state.session.pid).observation.deadline_ref

      emit(state.adapter, %{
        renewal
        | type: :ack,
          code: 69,
          options: [{6, <<10>>}, {14, <<1>>}],
          payload: "renewed"
      })

      reference = state.handle.reference
      assert_receive {:wotex_coap, ^reference, {:ok, %{payload: "renewed"}, %{observe: 10}}}
      current = :sys.get_state(state.owner)
      assert current.expiry == initial.expiry + 1000
      timers = TestExecution.snapshot(state.clock).timers
      send(state.owner, {:expiry, initial.timer_ref})
      send(state.owner, {:expiry, sliced.timer_ref})
      send(state.session.pid, {:observation_deadline, deadline_ref})
      assert synchronized_state(state) == current
      assert TestExecution.snapshot(state.clock).timers == timers
      refute_received {:sent_datagram, _, _}
      refute_received {:wotex_coap, _, _}
      cancel(state)
      assert_closed(state)
    after
      dispose(state)
    end
  end

  test "WCO-S03 WCO-V09 rejected cancellation closes once without claiming confirmation" do
    for {status, expected} <- [
          {132, :remote_response},
          {160, :remote_response},
          {95, :incomplete_response}
        ] do
      state = observing()

      try do
        task = Task.async(fn -> CoAP.unsubscribe(state.session, state.handle) end)
        cancellation = sent(state.adapter)
        assert_route(state, cancellation)
        emit(state.adapter, %{cancellation | type: :ack, code: status, options: []})
        assert {:error, %Error{code: ^expected, effect: :none} = error} = Task.await(task)
        if expected == :remote_response, do: assert(error.details == %{code: status})
        reference = state.handle.reference
        assert_receive {:wotex_coap, ^reference, {:error, %Error{code: ^expected}}}
        assert_closed(state)
        refute_received {:wotex_coap, _, _}
        refute_received {:sent_datagram, _, _}
      after
        dispose(state)
      end
    end
  end

  test "WCO-S02 WCO-S03 WCO-V09 late renewal and continuation responses cannot complete cancellation" do
    for phase <- [:renewing, :assembling] do
      state = observing(max_age: 1)

      try do
        operation =
          if phase == :renewing do
            assert TestExecution.advance(state.clock, 1000) == 1
            sent(state.adapter)
          else
            begin_report(state)
          end

        task = Task.async(fn -> CoAP.unsubscribe(state.session, state.handle) end)
        cancellation = sent(state.adapter)
        assert_route(state, cancellation)
        options = if phase == :renewing, do: [{6, <<11>>}], else: [{4, "stable"}, {23, <<16>>}]
        emit(state.adapter, %{operation | type: :ack, code: 69, options: options, payload: "late"})
        current = synchronized_state(state)
        assert current.phase == :canceling and current.pending == nil
        refute Task.yield(task, 0)
        refute_received {:wotex_coap, _, _}
        refute_received {:sent_datagram, _, _}
        emit(state.adapter, %{cancellation | type: :ack, code: 69, options: [], payload: <<>>})
        assert :ok = Task.await(task)
        assert_closed(state)
        refute_received {:wotex_coap, _, _}
        refute_received {:sent_datagram, _, _}
      after
        dispose(state)
      end
    end
  end

  test "WCO-S03 WCO-V08 failed renewal terminates once without another registration attempt" do
    for {changes, expected} <- [
          {%{code: 132, options: []}, :remote_response},
          {%{options: []}, :invalid_observation_response},
          {%{options: [{6, <<10>>}, {12, <<42>>}]}, :representation_changed},
          {:timeout, :timeout}
        ] do
      state = observing(max_age: 1)

      try do
        assert TestExecution.advance(state.clock, 1000) == 1
        renewal = sent(state.adapter)
        assert renewal == %{state.request | message_id: 2}
        assert :sys.get_state(state.owner).phase == :renewing
        assert :ok = TestExecution.elapse(state.clock, 1050)

        if changes == :timeout do
          assert TestExecution.advance(state.clock, 1100) > 0
        else
          emit(
            state.adapter,
            Map.merge(%{renewal | type: :ack, code: 69, payload: "rejected"}, changes)
          )
        end

        assert_terminal(state, expected)
      after
        dispose(state)
      end
    end
  end

  test "WCO-S02 WCO-S03 WCO-V10 incomplete reports fail without promoting a pending Property" do
    for {changes, expected} <- [
          {%{options: [{4, "changed"}, {23, <<16>>}]}, :representation_changed},
          {%{code: 132}, :remote_response},
          {%{options: []}, :missing_block},
          {:timeout, :timeout}
        ] do
      state = observing()

      try do
        continuation = begin_report(state)
        assert :ok = TestExecution.elapse(state.clock, 50)

        pending = %{
          state.request
          | type: :con,
            code: 69,
            message_id: 101,
            options: [{4, "newer"}, {6, <<12>>}],
            payload: "pending"
        }

        emit(state.adapter, pending)
        assert sent(state.adapter) == %Message{type: :ack, code: 0, message_id: 101}
        current = synchronized_state(state)
        assert current.report.metadata.etag == "stable" and current.pending.first == pending
        assert current.phase_deadline == 100
        refute_received {:wotex_coap, _, _}

        if changes == :timeout do
          assert TestExecution.advance(state.clock, 100) > 0
        else
          final = %{
            continuation
            | type: :ack,
              code: 69,
              options: [{4, "stable"}, {23, <<16>>}],
              payload: "end"
          }

          emit(state.adapter, Map.merge(final, changes))
        end

        assert_terminal(state, expected)
      after
        dispose(state)
      end
    end
  end

  test "WCO-C03 WCO-C05 WCO-V09 WCO-V15 receiver death interrupts renewal and report assembly" do
    for phase <- [:renewing, :assembling] do
      receiver = spawn(fn -> receive do: (:stop -> :ok) end)
      state = observing(receiver: receiver, max_age: 1)

      try do
        if phase == :renewing do
          assert TestExecution.advance(state.clock, 1000) == 1
          assert Codec.option(sent(state.adapter), 6) == [<<>>]
        else
          begin_report(state)
        end

        current = :sys.get_state(state.owner)
        assert current.phase == phase
        worker_monitor = Process.monitor(current.task)
        send(receiver, :stop)
        assert_receive {:DOWN, ^worker_monitor, :process, _, _}, 1000
        cancellation = sent(state.adapter)
        assert_route(state, cancellation)
        assert_closed(state)
        refute Process.alive?(receiver)
        refute_received {:wotex_coap, _, _}
        refute_received {:sent_datagram, _, _}
      after
        send(receiver, :stop)
        dispose(state)
      end
    end
  end

  defp observing(options \\ []) do
    {:ok, clock} =
      TestExecution.start(%{mids: Enum.to_list(1..20), tokens: ["observed", "cont-1", "cont-2"]})

    {:ok, session} =
      CoAP.connect(
        host: "127.0.0.1",
        timeout: 100,
        execution: {TestExecution, clock},
        datagram: {TestDatagram, %{test: self(), mode: :trace}},
        observation_options: [accept: 0]
      )

    assert_receive {:adapter, adapter, _}
    receiver = Keyword.get(options, :receiver, self())
    path = Keyword.get(options, :path, "/x")
    task = Task.async(fn -> CoAP.subscribe(session, %{path: path, receiver: receiver}) end)
    request = sent(adapter)
    max_age = Keyword.get(options, :max_age, 60)

    emit(adapter, %{
      request
      | type: :ack,
        code: 69,
        options: [{6, <<10>>}, {14, Codec.uint(max_age)}],
        payload: "initial"
    })

    assert {:ok, handle} = Task.await(task)
    reference = handle.reference

    if receiver == self(),
      do: assert_receive({:wotex_coap, ^reference, {:ok, _, %{observe: 10}}}),
      else:
        assert(
          {:messages, [{:wotex_coap, ^reference, {:ok, _, %{observe: 10}}}]} =
            Process.info(receiver, :messages)
        )

    owner = :sys.get_state(session.pid).observation.pid
    assert :sys.get_state(owner).phase == :active

    %{
      clock: clock,
      session: session,
      adapter: adapter,
      handle: handle,
      owner: owner,
      request: request,
      monitors: Enum.map([session.pid, owner, adapter], &Process.monitor/1)
    }
  end

  defp begin_report(state) do
    emit(state.adapter, %{
      state.request
      | type: :con,
        code: 69,
        message_id: 100,
        options: [{4, "stable"}, {6, <<11>>}, {23, <<8>>}],
        payload: :binary.copy("x", 16)
    })

    assert sent(state.adapter) == %Message{type: :ack, code: 0, message_id: 100}
    continuation = sent(state.adapter)
    assert continuation.token != state.request.token
    assert Codec.option(continuation, 6) == [] and Codec.option(continuation, 23) == [<<16>>]
    continuation
  end

  defp synchronized_state(state) do
    assert :ok = GenServer.call(state.adapter, :sync)
    :sys.get_state(state.session.pid)
    :sys.get_state(state.owner)
  end

  defp await_cancellers(owner, count, attempts \\ 100) do
    if length(:sys.get_state(owner).cancel_from) == count do
      :ok
    else
      assert attempts > 0
      Process.sleep(1)
      await_cancellers(owner, count, attempts - 1)
    end
  end

  defp assert_terminal(state, expected) do
    reference = state.handle.reference
    assert_receive {:wotex_coap, ^reference, {:error, %Error{code: ^expected, effect: :none}}}
    assert_route(state, sent(state.adapter))
    assert_closed(state)
    refute_received {:wotex_coap, ^reference, _}
    refute_received {:sent_datagram, _, _}
  end

  defp cancel(state) do
    task = Task.async(fn -> CoAP.unsubscribe(state.session, state.handle) end)
    cancellation = sent(state.adapter)
    assert_route(state, cancellation)
    emit(state.adapter, %{cancellation | type: :ack, code: 69, options: [], payload: <<>>})
    assert :ok = Task.await(task)
  end

  defp assert_route(state, cancellation) do
    assert cancellation.token == state.request.token
    assert cancellation.message_id != state.request.message_id
    assert cancellation.code == 1

    assert cancellation.options ==
             [{6, <<1>>} | Enum.reject(state.request.options, &(elem(&1, 0) == 6))]
  end

  defp assert_closed(state) do
    for monitor <- state.monitors, do: assert_receive({:DOWN, ^monitor, :process, _, _}, 1000)
    assert TestExecution.snapshot(state.clock).timers == %{}
    assert TestExecution.snapshot(state.clock).owners == %{}
    assert :ok = CoAP.unsubscribe(state.session, state.handle)
    assert :ok = CoAP.disconnect(state.session)
  end

  defp dispose(state) do
    CoAP.disconnect(state.session)
    GenServer.stop(state.clock)
  end

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
