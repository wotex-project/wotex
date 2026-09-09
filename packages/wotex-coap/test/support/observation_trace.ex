defmodule Wotex.CoAP.TestObservationTrace do
  @moduledoc false

  import ExUnit.Assertions
  alias Wotex.CoAP
  alias Wotex.CoAP.{Codec, TestDatagram, TestExecution}

  @spec run(map()) :: map()
  def run(input) do
    {:ok, clock} =
      TestExecution.start(%{
        mids: input["allocate_mids"],
        tokens: Enum.map(input["allocate_tokens_hex"], &Base.decode16!(&1, case: :mixed))
      })

    endpoint = input["endpoint"]

    {:ok, session} =
      CoAP.connect(
        host: endpoint["host"],
        port: endpoint["port"],
        timeout: 100,
        execution: {TestExecution, clock},
        datagram: {TestDatagram, %{test: self(), mode: :trace}}
      )

    assert_receive {:adapter, adapter, generation}
    connection_monitor = Process.monitor(session.pid)
    adapter_monitor = Process.monitor(adapter)

    initial = %{
      session: session,
      clock: clock,
      adapter: adapter,
      generation: generation,
      subscribe: nil,
      unsubscribe: nil,
      handle: nil,
      owner: nil,
      outbound: [],
      deliveries: [],
      completion: %{},
      last: nil
    }

    try do
      state =
        Enum.reduce(input["events"], initial, fn event, state ->
          TestExecution.advance(clock, event["at_ms"])
          step(state, event)
        end)

      state = collect(state)
      assert_receive {:DOWN, ^connection_monitor, :process, _, :normal}, 1000
      assert_receive {:DOWN, ^adapter_monitor, :process, _, :normal}, 1000
      environment = TestExecution.snapshot(clock)
      assert environment.mids == [] and environment.tokens == []

      %{
        "outbound_hex" => Enum.reverse(state.outbound),
        "deliveries" => Enum.reverse(state.deliveries),
        "completion" => state.completion,
        "owned_resources" => %{
          "sockets" => if(Process.alive?(adapter), do: 1, else: 0),
          "pending_timers" => map_size(environment.timers),
          "active_subscriptions" => if(Process.alive?(state.owner), do: 1, else: 0)
        }
      }
    after
      CoAP.disconnect(session)
      GenServer.stop(clock)
    end
  end

  defp step(state, %{"event" => "subscribe"} = event) do
    receiver = self()
    session = %{state.session | timeout: event["deadline_ms"]}

    task =
      Task.async(fn ->
        CoAP.subscribe(session, %{path: event["path"], receiver: receiver, renew: event["renew"]})
      end)

    state = sent(%{state | subscribe: task})
    %{state | owner: :sys.get_state(state.session.pid).observation.pid}
  end

  defp step(state, %{"event" => "unsubscribe"} = event) do
    session = %{state.session | timeout: event["deadline_ms"]}
    task = Task.async(fn -> CoAP.unsubscribe(session, state.handle) end)
    sent(%{state | unsubscribe: task})
  end

  defp step(state, %{"event" => "peer_datagram"} = event) do
    bytes = Base.decode16!(event["hex"], case: :mixed)
    {:ok, message} = Codec.decode(bytes)
    send(state.adapter, {:emit, event["host"], event["port"], bytes})
    :ok = GenServer.call(state.adapter, :sync)
    if Process.alive?(state.session.pid), do: :sys.get_state(state.session.pid)
    %{state | last: message}
  end

  defp step(state, %{"event" => "drain"}) do
    state =
      cond do
        state.subscribe ->
          assert {:ok, handle} = Task.await(state.subscribe, 1000)

          %{
            state
            | subscribe: nil,
              handle: handle,
              completion: Map.put(state.completion, "subscribe", "ok")
          }

        state.unsubscribe && Codec.option(state.last, 6) == [] ->
          assert :ok = Task.await(state.unsubscribe, 1000)
          %{state | unsubscribe: nil, completion: Map.put(state.completion, "unsubscribe", "ok")}

        true ->
          state
      end

    if not Map.has_key?(state.completion, "unsubscribe") and Process.alive?(state.owner),
      do: :sys.get_state(state.owner)

    collect(state)
  end

  defp sent(state) do
    adapter = state.adapter
    assert_receive {:sent_datagram, ^adapter, bytes}, 1000
    %{state | outbound: [Base.encode16(bytes, case: :lower) | state.outbound]}
  end

  defp collect(state) do
    adapter = state.adapter
    reference = if state.handle, do: state.handle.reference

    receive do
      {:sent_datagram, ^adapter, bytes} ->
        collect(%{state | outbound: [Base.encode16(bytes, case: :lower) | state.outbound]})

      {:wotex_coap, ^reference, {:ok, message, metadata}} ->
        value = %{
          "payload_hex" => Base.encode16(message.payload, case: :lower),
          "observe" => metadata.observe,
          "code" => metadata.code
        }

        collect(%{state | deliveries: [value | state.deliveries]})

      {:wotex_coap, ^reference, {:error, error}} ->
        flunk("unexpected terminal error: #{inspect(error.code)}")
    after
      0 -> state
    end
  end
end
