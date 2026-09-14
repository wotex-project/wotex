defmodule Wotex.CoAP.ExchangeDeadlineTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.CoAP
  alias Wotex.CoAP.{Codec, Connection, Error, Message, TestDatagram, TestExecution}

  for kind <- [:request, :transfer], method <- [:get, :put], arrival <- [100, 101] do
    @kind kind
    @method method
    @arrival arrival
    test "WCO-C03 WCO-V02 #{@kind} #{@method} refuses a response at #{@arrival} before its timer arrives" do
      context = connection()
      {:ok, request} = CoAP.message(%{method: @method, path: "/value", payload: "input"})
      task = Task.async(fn -> invoke(@kind, context.session.pid, request) end)
      wire = sent(context.adapter)
      :ok = TestExecution.elapse(context.clock, @arrival)
      emit(context, %{wire | type: :ack, code: 69, options: [], payload: "late"})
      effect = if @method == :put, do: :unknown, else: :none
      assert {:error, %Error{code: :timeout, effect: ^effect, retryable: false}} = Task.await(task)
      closed(context)
      refute_received {:sent_datagram, _, _}
    end
  end

  test "WCO-C03 WCO-V02 whole-body completion cannot outlive its deadline or dispatch queued writes" do
    context = connection()
    task = Task.async(fn -> CoAP.put(context.session, "/value", "input") end)
    wire = sent(context.adapter)
    state = :sys.get_state(context.session.pid)
    worker = state.calls[state.active].worker
    true = :erlang.suspend_process(worker)
    queued = Task.async(fn -> CoAP.put(%{context.session | timeout: 200}, "/queued", "later") end)
    await_calls(context.session.pid, 2)
    :ok = TestExecution.elapse(context.clock, 99)
    emit(context, %{wire | type: :ack, code: 69, options: [], payload: "complete"})
    state = :sys.get_state(context.session.pid)
    assert state.calls[state.active].exchange == nil
    :ok = TestExecution.elapse(context.clock, 100)
    true = :erlang.resume_process(worker)
    assert {:error, %Error{code: :timeout, effect: :unknown}} = Task.await(task)
    assert {:error, %Error{code: :connection_closed, effect: :none}} = Task.await(queued)
    closed(context)
    refute_received {:sent_datagram, _, _}
  end

  for mode <- [:non, :acknowledged] do
    @mode mode
    test "WCO-S01 WCO-V01 WCO-V02 #{@mode} stale traffic cannot move timers or produce another result" do
      context = connection()

      task =
        Task.async(fn ->
          CoAP.put(context.session, "/value", "input", confirmable: @mode != :non)
        end)

      wire = sent(context.adapter)

      if @mode == :acknowledged,
        do: emit(context, %Message{type: :ack, code: 0, message_id: wire.message_id})

      original = TestExecution.snapshot(context.clock).timers
      assert map_size(original) == 2
      assert Enum.all?(original, fn {_, timer} -> timer.at == 100 end)

      for time <- 1..99 do
        assert TestExecution.advance(context.clock, time) == 0
        stale_traffic(context, wire)
        assert TestExecution.snapshot(context.clock).timers == original
        state = :sys.get_state(context.session.pid)
        assert map_size(state.calls) == 1
        assert map_size(state.responses) == 0
        assert map_size(state.history) == 1
        refute_received {:sent_datagram, _, _}
      end

      assert TestExecution.advance(context.clock, 100) == 2
      assert {:error, %Error{code: :timeout, effect: :unknown}} = Task.await(task)
      closed(context)
      refute_received {:sent_datagram, _, _}
    end
  end

  test "WCO-C03 WCO-V01 a response immediately before the deadline still succeeds" do
    context = connection()
    task = Task.async(fn -> CoAP.get(context.session, "/value") end)
    wire = sent(context.adapter)
    :ok = TestExecution.elapse(context.clock, 99)
    emit(context, %{wire | type: :ack, code: 69, options: [], payload: "on time"})
    assert {:ok, %Message{payload: "on time"}} = Task.await(task)
    assert :ok = CoAP.disconnect(context.session)
    closed(context)
  end

  defp connection do
    {:ok, clock} = TestExecution.start(%{mids: [1, 2], tokens: ["first", "second"]})
    Process.unlink(clock)

    {:ok, session} =
      CoAP.connect(
        host: "127.0.0.1",
        timeout: 100,
        ack_timeout: 10,
        execution: {TestExecution, clock},
        datagram: {TestDatagram, %{test: self(), mode: :trace}}
      )

    assert_receive {:adapter, adapter, _}
    monitors = for pid <- [session.pid, adapter], do: {pid, Process.monitor(pid)}

    on_exit(fn ->
      CoAP.disconnect(session)
      if Process.alive?(clock), do: GenServer.stop(clock)
    end)

    %{clock: clock, session: session, adapter: adapter, monitors: monitors}
  end

  defp invoke(:request, pid, request), do: Connection.request(pid, request, 100)
  defp invoke(:transfer, pid, request), do: Connection.transfer(pid, request, 100)

  defp sent(adapter) do
    assert_receive {:sent_datagram, ^adapter, bytes}, 1000
    assert {:ok, message} = Codec.decode(bytes)
    message
  end

  defp emit(context, message) do
    {:ok, bytes} = Codec.encode(message)
    send(context.adapter, {:emit, bytes})
    assert :ok = GenServer.call(context.adapter, :sync)
    :sys.get_state(context.session.pid)
    :ok
  catch
    :exit, {reason, _} when reason in [:normal, :noproc] -> :ok
  end

  defp stale_traffic(context, wire) do
    wrong_mid = rem(wire.message_id + 1, 65_536)

    for message <- [
          %{wire | type: :non, code: 69, token: "stale", payload: "old"},
          %{wire | type: :ack, code: 69, message_id: wrong_mid},
          %Message{type: :rst, code: 0, message_id: wrong_mid}
        ],
        do: emit(context, message)
  end

  defp closed(context) do
    for {pid, monitor} <- context.monitors,
        do: assert_receive({:DOWN, ^monitor, :process, ^pid, :normal}, 1000)

    assert TestExecution.snapshot(context.clock).timers == %{}
    assert TestExecution.snapshot(context.clock).owners == %{}
    assert :ok = CoAP.disconnect(context.session)
  end

  defp await_calls(pid, count, attempts \\ 1000) do
    if map_size(:sys.get_state(pid).calls) == count do
      :ok
    else
      assert attempts > 0
      await_calls(pid, count, attempts - 1)
    end
  end
end
