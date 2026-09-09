defmodule Wotex.CoAP.ExchangeLifecycleTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.CoAP
  alias Wotex.CoAP.{Codec, Connection, Error, Exchange, Message, TestDatagram}
  alias Wotex.CoAP.Datagram.UDP

  test "WCO-S01 WCO-V02 pure retry schedule sends four identical retransmissions then stops" do
    message = %Message{type: :con, code: 3, message_id: 42, token: <<1>>, payload: "mutation"}
    assert {:ok, initial} = Exchange.new(message, 0, 1000, 10)
    assert Exchange.wake(initial) == 10
    assert {:wait, ^initial} = Exchange.tick(initial, 9)

    last =
      Enum.reduce([10, 30, 70, 150], initial, fn time, exchange ->
        assert {:send, bytes, next} = Exchange.tick(exchange, time)
        assert bytes == initial.bytes
        assert next.retries == exchange.retries + 1
        next
      end)

    assert last.retries == 4
    assert Exchange.wake(last) == 310
    assert :timeout = Exchange.tick(last, 310)
    assert :timeout = Exchange.tick(initial, 1000)
    assert {:ok, non} = Exchange.new(%{message | type: :non}, 0, 100, 10)
    assert Exchange.wake(non) == 100
    assert {:wait, ^non} = Exchange.tick(non, 99)
    assert :timeout = Exchange.tick(non, 100)
    acknowledged = %{initial | acknowledged: true}
    assert Exchange.wake(acknowledged) == 1000
    assert {:wait, ^acknowledged} = Exchange.tick(acknowledged, 999)

    for {message, now, deadline, interval} <- [
          {nil, 0, 1, 10},
          {message, 0, 0, 10},
          {message, 0, 60_001, 10},
          {message, 0, 50, 0},
          {%{message | token: nil}, 0, 50, 10}
        ] do
      assert {:error, %Error{}} = Exchange.new(message, now, deadline, interval)
    end

    assert :ignore = Exchange.incoming(initial, nil)
    assert :ignore = Exchange.incoming(initial, %{message | type: :ack, options: [{99, <<>>}]})

    assert {:error, %Error{code: :invalid_response}} =
             Exchange.incoming(initial, %{message | type: :ack, code: 96})
  end

  test "WCO-D01 capability claims admit only established implementation cells" do
    assert CoAP.capabilities().max_payload_size == 1152
    assert CoAP.capabilities().supports_streaming
    assert CoAP.capabilities().discovery_capable
  end

  test "WCO-C02 WCO-S01 forged exchange values are rejected by every transition boundary" do
    message = %Message{type: :con, code: 1, message_id: 42, token: <<1>>}
    {:ok, valid} = Exchange.new(message, 0, 1000, 10)

    for forged <- [
          nil,
          %{},
          %{valid | request: nil},
          %{valid | bytes: "forged"},
          %{valid | deadline: nil},
          %{valid | retry_at: nil},
          %{valid | interval: 0},
          %{valid | retries: 5},
          %{valid | acknowledged: nil},
          Map.put(valid, :extra, true)
        ] do
      assert {:error, %Error{code: :invalid_exchange}} = Exchange.wake(forged)
      assert {:error, %Error{code: :invalid_exchange}} = Exchange.tick(forged, 10)
      assert {:error, %Error{code: :invalid_exchange}} = Exchange.incoming(forged, message)
    end

    assert {:error, %Error{code: :invalid_exchange}} = Exchange.tick(valid, nil)
  end

  test "WCO-C03 WCO-S01 WCO-V02 capacity includes one active transfer and canceled queues consume no MID" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 3000)
    first = Task.async(fn -> CoAP.get(session, "/first") end)
    wire = wire()
    queued = for n <- 1..63, do: Task.async(fn -> CoAP.put(session, "/queued", <<n>>) end)
    state = await_calls(session.pid, 64)
    assert :queue.len(state.queue) == 63
    assert {:error, %Error{code: :busy, effect: :none}} = CoAP.put(session, "/excess", "x")
    Enum.each(queued, &Task.shutdown(&1, :brutal_kill))
    assert map_size(await_calls(session.pid, 1).calls) == 1
    assert :sys.get_state(session.pid).mid == state.mid
    send(peer.pid, {:reply, ack(wire.message, "first")})
    assert {:ok, %{payload: "first"}} = Task.await(first)
    second = Task.async(fn -> CoAP.get(session, "/second") end)
    next = wire()
    assert next.message.message_id == rem(wire.message.message_id + 1, 65_536)
    refute next.message.token == wire.message.token
    send(peer.pid, {:reply, ack(next.message, "second")})
    assert {:ok, %{payload: "second"}} = Task.await(second)
    assert :ok = CoAP.disconnect(session)
    close_peer(peer)
    refute_received {:wire, _, _, _, _}
  end

  test "WCO-C03 WCO-V02 a queued expired mutation has no wire effect and stale timers do nothing" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port)
    first = Task.async(fn -> CoAP.get(session, "/first") end)
    wire = wire()
    {:ok, message} = CoAP.message(%{method: :put, path: "/expired", payload: "x"})
    second = Task.async(fn -> Connection.transfer(session.pid, message, 30) end)
    state = await_calls(session.pid, 2)
    [ref] = :queue.to_list(state.queue)
    assert {:error, %Error{code: :timeout, effect: :none}} = Task.await(second)
    send(session.pid, {:deadline, ref})
    send(session.pid, {:retry, ref, make_ref()})
    send(session.pid, {:completed, ref, {:ok, message}})
    send(session.pid, {:wotex_datagram, make_ref(), :closed})
    send(session.pid, {:DOWN, make_ref(), :process, self(), :normal})
    send(peer.pid, {:reply, ack(wire.message, "first")})
    assert {:ok, %{payload: "first"}} = Task.await(first)
    assert :sys.get_state(session.pid).mid == state.mid
    assert :ok = CoAP.disconnect(session)
    close_peer(peer)
    refute_received {:wire, _, _, _, _}
  end

  test "WCO-C03 WCO-V15 owner death interrupts a 60-second mutation and closes all owned resources" do
    {peer, port} = peer()

    owner =
      spawn(fn ->
        receive do
          :finish -> :ok
        end
      end)

    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, owner: owner, timeout: 60_000)
    call = Task.async(fn -> CoAP.put(session, "/x", "mutation") end)
    wire()
    resources = resources(session)
    start = System.monotonic_time(:millisecond)
    send(owner, :finish)
    monitor = resources.monitor
    pid = session.pid
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 100
    assert System.monotonic_time(:millisecond) - start < 1000
    assert {:error, %Error{code: :connection_closed, effect: :unknown}} = Task.await(call)
    assert_clean(resources)
    assert :ok = CoAP.disconnect(session)
    close_peer(peer)
  end

  test "WCO-C03 WCO-V15 active caller death closes its generation and refuses queued writes" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 60_000)
    active = Task.async(fn -> CoAP.put(session, "/x", "one") end)
    wire()
    queued = Task.async(fn -> CoAP.put(session, "/x", "two") end)
    await_calls(session.pid, 2)
    resources = resources(session)
    Task.shutdown(active, :brutal_kill)
    assert {:error, %Error{code: :connection_closed, effect: :none}} = Task.await(queued)
    assert_clean(resources)
    close_peer(peer)
    refute_received {:wire, _, _, _, _}
  end

  test "WCO-S01 WCO-V01 accepted CON duplicates are ACKed while idle and during a different exchange" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port)
    first = Task.async(fn -> CoAP.get(session, "/first") end)
    first_wire = wire()

    response = %Message{
      type: :con,
      code: 69,
      message_id: 500,
      token: first_wire.message.token,
      payload: "one"
    }

    send(
      peer.pid,
      {:reply, %Message{type: :ack, code: 0, message_id: first_wire.message.message_id}}
    )

    send(peer.pid, {:reply, response})
    assert wire().message == %Message{type: :ack, code: 0, message_id: 500}
    assert {:ok, %{payload: "one"}} = Task.await(first)
    send(peer.pid, {:reply, response})
    assert wire().message == %Message{type: :ack, code: 0, message_id: 500}
    next = Task.async(fn -> CoAP.put(session, "/next", "two") end)
    next_wire = wire()
    send(peer.pid, {:reply, response})
    assert wire().message == %Message{type: :ack, code: 0, message_id: 500}
    send(peer.pid, {:reply, %{response | message_id: 501, token: "unknown"}})
    assert wire().message == %Message{type: :rst, code: 0, message_id: 501}
    send(peer.pid, {:reply, ack(next_wire.message, "two")})
    assert {:ok, %{payload: "two"}} = Task.await(next)
    send(peer.pid, {:reply, %{response | message_id: 502, token: "unknown"}})
    assert wire().message == %Message{type: :rst, code: 0, message_id: 502}
    assert :ok = CoAP.disconnect(session)
    close_peer(peer)
  end

  test "WCO-S01 WCO-V01 malformed datagrams and wrong endpoint packets cannot extend the deadline" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 50, ack_timeout: 10)
    call = Task.async(fn -> CoAP.get(session, "/x", confirmable: false) end)
    request = wire()
    {:ok, foreign} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, bytes} = Codec.encode(ack(request.message, "wrong-peer"))
    :ok = :gen_udp.send(foreign, request.host, request.port, bytes)

    for bytes <- [<<>>, <<0x40>>, :binary.copy(<<0>>, 1153)],
        do: send(peer.pid, {:reply_bytes, bytes})

    assert {:error, %Error{code: :timeout, effect: :none}} = Task.await(call)
    assert :ok = CoAP.disconnect(session)
    :ok = :gen_udp.close(foreign)
    close_peer(peer)
    refute_received {:wire, _, _, _, _}
  end

  test "WCO-C02 WCO-C03 a forged live PID cannot receive protocol calls or stop another process" do
    {:ok, agent} = Agent.start_link(fn -> :untouched end)
    {:ok, message} = CoAP.message(%{method: :get, path: "/"})

    for pid <- [self(), agent, nil, :invalid] do
      assert {:error, %Error{code: :invalid_session}} = Connection.request(pid, message, 100)
      assert {:error, %Error{code: :invalid_session}} = Connection.close(pid)
    end

    assert Agent.get(agent, & &1) == :untouched
    :ok = Agent.stop(agent)

    assert {:error, %Error{code: :connection_closed, effect: :none}} =
             Connection.request(agent, message, 100)

    assert :ok = Connection.close(agent)
    refute_received {:"$gen_call", _, _}
  end

  test "WCO-C03 WCO-V15 suspended real owners are force-closed and never report successful cleanup" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port)
    resources = resources(session)
    true = :erlang.suspend_process(session.pid)
    assert {:error, %Error{code: :cleanup_timeout}} = CoAP.disconnect(session)
    assert_clean(resources)
    assert :ok = CoAP.disconnect(session)
    close_peer(peer)
  end

  test "WCO-C02 WCO-V15 explicit adapter setup faults and bounded configuration are caller-safe" do
    for options <- [
          [host: "127.0.0.1", host: "127.0.0.1"],
          [{:host, "127.0.0.1"} | nil],
          [host: <<255>>],
          [host: String.duplicate("1", 65)],
          [host: "127.0.0.1", owner: :invalid],
          [host: "127.0.0.1", datagram: nil],
          [host: "127.0.0.1", datagram: {UDP, [:unknown]}]
        ],
        do: assert({:error, %Error{}} = Connection.config(options))

    modes = [:open_error, :open_raise, :open_malformed, :arm_error, :arm_raise, :arm_malformed]

    for mode <- modes do
      before = Process.info(self(), :links)

      assert {:error, %Error{}} =
               CoAP.connect(
                 host: "127.0.0.1",
                 datagram: {TestDatagram, %{test: self(), mode: mode}}
               )

      assert before == Process.info(self(), :links)
    end
  end

  test "WCO-C03 WCO-V15 startup timeout kills a blocked adapter opening worker" do
    test = self()

    call =
      Task.async(fn ->
        CoAP.connect(
          host: "127.0.0.1",
          timeout: 30,
          datagram: {TestDatagram, %{test: test, mode: :open_block}}
        )
      end)

    assert_receive {:opening, worker, connection, _}
    monitor = Process.monitor(worker)
    assert {:error, %Error{code: :timeout}} = Task.await(call)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
    refute Process.alive?(connection)
  end

  test "WCO-C04 WCO-V15 transport and ACK send errors cannot produce native success" do
    for mode <- [:send_error, :ack_error, :send_raise, :send_malformed] do
      {:ok, session} =
        CoAP.connect(host: "127.0.0.1", datagram: {TestDatagram, %{test: self(), mode: mode}})

      assert_receive {:adapter, adapter, _}
      call = Task.async(fn -> CoAP.put(session, "/x", "value") end)
      assert_receive {:sent_datagram, ^adapter, bytes}
      {:ok, request} = Codec.decode(bytes)

      if mode == :ack_error do
        {:ok, bytes} =
          Codec.encode(%Message{
            type: :con,
            code: 69,
            message_id: 77,
            token: request.token,
            payload: "value"
          })

        send(adapter, {:emit, bytes})
      end

      expected =
        if mode in [:send_raise, :send_malformed], do: :datagram_failed, else: :transport_error

      assert {:error, %Error{code: ^expected, effect: :unknown}} = Task.await(call)
      assert :ok = CoAP.disconnect(session)
    end
  end

  test "WCO-C03 WCO-C04 adapter cleanup failure is retained by explicit disconnect" do
    {:ok, session} =
      CoAP.connect(host: "127.0.0.1", datagram: {TestDatagram, %{test: self(), mode: :close_error}})

    assert {:error, %Error{code: :cleanup_timeout}} = CoAP.disconnect(session)
    refute Process.alive?(session.pid)
    assert :ok = CoAP.disconnect(session)
  end

  test "WCO-S01 WCO-V02 real CON retries preserve bytes and exhausted attempts end once" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port, timeout: 1000, ack_timeout: 5)
    call = Task.async(fn -> CoAP.put(session, "/x", "same mutation") end)
    first = wire()
    for _ <- 1..4, do: assert(wire().bytes == first.bytes)
    assert {:error, %Error{code: :timeout, effect: :unknown}} = Task.await(call)
    assert :ok = CoAP.disconnect(session)
    close_peer(peer)
    refute_received {:wire, _, _, _, _}
  end

  test "WCO-S01 WCO-V01 raw exchanges reject terminal Continue, Reset and remote failures" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port)
    message = %Message{type: :con, code: 3, message_id: 0, payload: "write"}

    for {code, expected} <- [
          {95, :incomplete_response},
          {128, :remote_response},
          {160, :remote_response},
          {192, :invalid_response}
        ] do
      call = Task.async(fn -> Connection.request(session.pid, message, 1000) end)
      request = wire().message
      send(peer.pid, {:reply, %{request | type: :ack, code: code, payload: <<>>}})
      assert {:error, %Error{code: ^expected, effect: :unknown} = error} = Task.await(call)
      if expected == :remote_response, do: assert(error.details == %{code: code})
    end

    call = Task.async(fn -> Connection.request(session.pid, message, 1000) end)
    request = wire().message
    send(peer.pid, {:reply, %Message{type: :rst, code: 0, message_id: request.message_id}})
    assert {:error, %Error{code: :reset, effect: :unknown}} = Task.await(call)
    assert {:error, %Error{}} = Connection.request(session.pid, nil, 1000)
    assert {:error, %Error{}} = Connection.request(session.pid, %{message | type: :ack}, 1000)
    assert :ok = CoAP.disconnect(session)
    close_peer(peer)
  end

  test "WCO-S01 WCO-V02 retained MID exhaustion rejects before send and expires after its lifetime" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port)
    now = System.monotonic_time(:millisecond)
    full = Map.new(0..65_535, &{&1, now})
    :sys.replace_state(session.pid, &%{&1 | mid: 65_535, history: full})

    assert {:error, %Error{code: :exchange_unavailable, effect: :none}} =
             CoAP.put(session, "/x", "x")

    refute_received {:wire, _, _, _, _}
    expired = Map.new(0..65_535, &{&1, now - 247_000})
    :sys.replace_state(session.pid, &%{&1 | history: expired})

    for mid <- [65_535, 0] do
      call = Task.async(fn -> CoAP.get(session, "/x") end)
      request = wire().message
      assert request.message_id == mid
      send(peer.pid, {:reply, ack(request, "value")})
      assert {:ok, %{payload: "value"}} = Task.await(call)
    end

    assert map_size(:sys.get_state(session.pid).history) == 2
    assert :ok = CoAP.disconnect(session)
    close_peer(peer)
  end

  test "WCO-S01 WCO-V01 the accepted CON cache evicts oldest entries and expires by lifetime" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port)
    now = System.monotonic_time(:millisecond)
    entries = Map.new(0..1023, &{{&1, <<&1::16>>}, {now, &1}})
    :sys.replace_state(session.pid, &%{&1 | responses: entries, response_order: 1024})
    call = Task.async(fn -> CoAP.get(session, "/x") end)
    request = wire().message
    response = %{ack(request, "value") | type: :con, message_id: 2000}
    send(peer.pid, {:reply, response})
    assert wire().message == %Message{type: :ack, code: 0, message_id: 2000}
    assert {:ok, %{payload: "value"}} = Task.await(call)
    state = :sys.get_state(session.pid)
    assert map_size(state.responses) == 1024
    refute Map.has_key?(state.responses, {0, <<0::16>>})
    assert Map.has_key?(state.responses, {2000, request.token})

    :sys.replace_state(session.pid, fn state ->
      %{
        state
        | responses:
            Map.new(state.responses, fn {key, {_, order}} ->
              {key, {now - 247_000, order}}
            end)
      }
    end)

    send(peer.pid, {:reply, response})
    assert wire().message == %Message{type: :rst, code: 0, message_id: 2000}
    assert :sys.get_state(session.pid).responses == %{}
    assert :ok = CoAP.disconnect(session)
    close_peer(peer)
  end

  test "WCO-C03 WCO-V15 transfer worker failure closes the active generation and pending callers" do
    {peer, port} = peer()
    {:ok, session} = CoAP.connect(host: "127.0.0.1", port: port)
    call = Task.async(fn -> CoAP.put(session, "/x", "value") end)
    wire()
    state = :sys.get_state(session.pid)
    resources = resources(session)
    Process.exit(state.calls[state.active].worker, :kill)
    assert {:error, %Error{code: :connection_closed, effect: :unknown}} = Task.await(call)
    assert_clean(resources)
    assert :ok = CoAP.disconnect(session)
    close_peer(peer)
  end

  test "WCO-C03 WCO-V15 adapter rearm failure cannot leave an ACKed exchange waiting" do
    {:ok, session} =
      CoAP.connect(
        host: "127.0.0.1",
        datagram: {TestDatagram, %{test: self(), mode: :rearm_error}}
      )

    assert_receive {:adapter, adapter, _}
    monitor = Process.monitor(adapter)
    call = Task.async(fn -> CoAP.put(session, "/x", "value") end)
    assert_receive {:sent_datagram, ^adapter, bytes}
    {:ok, request} = Codec.decode(bytes)
    {:ok, bytes} = Codec.encode(%Message{type: :ack, code: 0, message_id: request.message_id})
    send(adapter, {:emit, bytes})
    assert {:error, %Error{code: :connection_closed, effect: :unknown}} = Task.await(call)
    assert_receive {:DOWN, ^monitor, :process, ^adapter, :normal}
    assert :ok = CoAP.disconnect(session)
  end

  test "WCO-C03 WCO-V15 setup worker or setup caller death releases the opening generation" do
    test = self()

    for cause <- [:worker, :caller] do
      call =
        Task.async(fn ->
          CoAP.connect(
            host: "127.0.0.1",
            timeout: 60_000,
            datagram: {TestDatagram, %{test: test, mode: :open_block}}
          )
        end)

      assert_receive {:opening, worker, connection, _}
      monitor = Process.monitor(connection)
      worker_monitor = Process.monitor(worker)
      message = %Message{type: :con, code: 1, message_id: 0}

      assert {:error, %Error{code: :connection_closed, effect: :none}} =
               Connection.request(connection, message, 100)

      if cause == :worker do
        Process.exit(worker, :kill)
        assert {:error, %Error{code: :datagram_failed}} = Task.await(call)
      else
        Task.shutdown(call, :brutal_kill)
      end

      assert_receive {:DOWN, ^monitor, :process, ^connection, :normal}
      assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :killed}
    end
  end

  defp peer do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: true, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    test = self()

    task =
      Task.async(fn ->
        receive do
          :go -> peer_loop(socket, test, nil)
        end
      end)

    :ok = :gen_udp.controlling_process(socket, task.pid)
    send(task.pid, :go)
    {task, port}
  end

  defp peer_loop(socket, test, endpoint) do
    receive do
      {:udp, ^socket, host, port, bytes} ->
        {:ok, message} = Codec.decode(bytes)
        send(test, {:wire, host, port, bytes, message})
        peer_loop(socket, test, {host, port})

      {:reply, message} ->
        {:ok, bytes} = Codec.encode(message)
        {host, port} = endpoint
        :ok = :gen_udp.send(socket, host, port, bytes)
        peer_loop(socket, test, endpoint)

      {:reply_bytes, bytes} ->
        {host, port} = endpoint
        :ok = :gen_udp.send(socket, host, port, bytes)
        peer_loop(socket, test, endpoint)

      :close ->
        :gen_udp.close(socket)
    after
      5000 -> flunk("owned peer was not closed")
    end
  end

  defp close_peer(peer) do
    send(peer.pid, :close)
    assert :ok = Task.await(peer)
  end

  defp wire do
    assert_receive {:wire, host, port, bytes, message}, 1000
    %{host: host, port: port, bytes: bytes, message: message}
  end

  defp ack(message, payload), do: %{message | type: :ack, code: 69, options: [], payload: payload}

  defp await_calls(pid, count),
    do: await_calls(pid, count, System.monotonic_time(:millisecond) + 1000)

  defp await_calls(pid, count, deadline) do
    state = :sys.get_state(pid)

    if map_size(state.calls) == count do
      state
    else
      assert System.monotonic_time(:millisecond) < deadline

      receive do
      after
        1 -> await_calls(pid, count, deadline)
      end
    end
  end

  defp resources(session) do
    state = :sys.get_state(session.pid)
    adapter = :sys.get_state(state.handle.pid)

    %{
      pid: session.pid,
      monitor: Process.monitor(session.pid),
      adapter: state.handle.pid,
      adapter_monitor: Process.monitor(state.handle.pid),
      socket: adapter.socket,
      timers: [
        state.startup_timer
        | Enum.flat_map(state.calls, fn {_, call} ->
            [call.timer] ++ if(call.exchange, do: [call.exchange.timer], else: [])
          end)
      ]
    }
  end

  defp assert_clean(resources) do
    adapter_monitor = resources.adapter_monitor
    adapter = resources.adapter
    assert_receive {:DOWN, ^adapter_monitor, :process, ^adapter, :normal}, 1000
    refute Process.alive?(resources.pid)
    assert :erlang.port_info(resources.socket) == :undefined
    assert Enum.all?(resources.timers, &(Process.read_timer(&1) == false))
  end
end
