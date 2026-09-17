defmodule Wotex.CoAP.RuntimeStreamTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.CoAP.{Codec, Error, Message, RuntimeHandle, RuntimeRelay, Transport}
  alias Wotex.CoAP.Test.RuntimeCredentials
  alias Wotex.Runtime.{ConsumedThing, Context, ExecutionContext, Subscription}
  @moduletag :capture_log

  setup do
    {:ok, peer} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(peer)
    on_exit(fn -> :gen_udp.close(peer) end)
    %{peer: peer, port: port}
  end

  test "WCO-S04 WCO-I05 WCO-V11 real Runtime Property and Event streams preserve fresh equal values",
       c do
    for kind <- [:property, :event] do
      {spec, _, _} = specification(c, kind)
      owner = start_supervised!(spec)
      initial = wire(c.peer)
      assert initial.message.code == 1 and initial.message.type == :con
      assert Codec.option(initial.message, 6) == [<<>>]
      assert Codec.option(initial.message, 17) == [<<50>>]
      assert Codec.option(initial.message, 11) == ["x/y"]
      assert Codec.option(initial.message, 15) == ["a=x&y"]
      reply(c.peer, initial, report(initial.message, 10, "false"))
      assert_receive {:wotex_runtime, ^kind, {:ok, false, metadata}}, 1000
      assert metadata == %{code: 69, observe: 10, etag: "e", content_format: 50, max_age: 60}
      handle = await_handle(owner)
      resources = resources(handle.pid)

      notification = %{report(initial.message, 11, "false") | type: :con, message_id: 900}
      reply(c.peer, initial, notification)
      assert wire(c.peer).message == %Message{type: :ack, code: 0, message_id: 900}
      assert_receive {:wotex_runtime, ^kind, {:ok, false, %{observe: 11}}}, 1000
      reply(c.peer, initial, notification)
      assert wire(c.peer).message.type == :ack
      refute_receive {:wotex_runtime, ^kind, _}, 10
      stop(c.peer, owner, initial)
      released(resources)
      assert :ok = RuntimeRelay.close(handle)
    end
  end

  test "WCO-S02 WCO-S04 both Runtime streams decode only the complete initial report metadata", c do
    for kind <- [:property, :event] do
      {spec, _, _} = specification(c, kind)
      owner = start_supervised!(spec)
      initial = wire(c.peer)
      body = "\"" <> String.duplicate("a", 20) <> "\""
      <<first::binary-size(16), rest::binary>> = body
      message = report(initial.message, 10, first)

      reply(c.peer, initial, %{
        message
        | options: [{14, <<30>>}, {23, <<8>>}, {100, "first"} | message.options]
      })

      continuation = wire(c.peer)
      assert Codec.option(continuation.message, 6) == []
      assert Codec.option(continuation.message, 23) == [<<16>>]
      assert continuation.message.token != initial.message.token
      refute_received {:wotex_runtime, ^kind, _}

      reply(c.peer, continuation, %{
        continuation.message
        | type: :ack,
          code: 69,
          options: [{4, "e"}, {12, <<0, 50>>}, {14, <<1>>}, {23, <<16>>}, {100, "last"}],
          payload: rest
      })

      assert_receive {:wotex_runtime, ^kind, {:ok, value, metadata}}, 1000
      assert value == String.duplicate("a", 20)
      assert metadata == %{code: 69, observe: 10, etag: "e", content_format: 50, max_age: 30}
      owned = resources(await_handle(owner).pid)
      refute_receive {:wotex_runtime, ^kind, _}, 10
      stop(c.peer, owner, initial)
      released(owned)
    end
  end

  test "WCO-S04 WCO-I03 both Runtime stream contexts preserve every supported representation", c do
    for kind <- [:property, :event],
        {media, format, values} <- [
          {"application/json", 50,
           [{"null", nil}, {"false", false}, {"0", 0}, {"[]", []}, {"{}", %{}}, {"\"\"", ""}]},
          {"text/plain;charset=utf-8", 0, [{"", ""}, {"smörgås", "smörgås"}]},
          {"application/octet-stream", 42, [{"", ""}, {<<0, 255, 128>>, <<0, 255, 128>>}]}
        ] do
      {spec, _, _} = specification(c, kind, media: media, format: format)
      owner = start_supervised!(spec)
      initial = wire(c.peer)
      assert Codec.option(initial.message, 17) == [Codec.uint(format)]

      for {{payload, expected}, sequence} <- Enum.with_index(values, 10) do
        message = %{
          initial.message
          | type: if(sequence == 10, do: :ack, else: :con),
            code: 69,
            message_id: if(sequence == 10, do: initial.message.message_id, else: 900 + sequence),
            options: [{4, "e"}, {6, Codec.uint(sequence)}, {12, Codec.uint(format)}],
            payload: payload
        }

        reply(c.peer, initial, message)

        if sequence > 10,
          do:
            assert(
              wire(c.peer).message == %Message{
                type: :ack,
                code: 0,
                message_id: message.message_id
              }
            )

        assert_receive {:wotex_runtime, ^kind, {:ok, ^expected, metadata}}, 1000

        assert metadata == %{
                 code: 69,
                 observe: sequence,
                 etag: "e",
                 content_format: format,
                 max_age: 60
               }
      end

      owned = resources(await_handle(owner).pid)
      stop(c.peer, owner, initial)
      released(owned)
      refute_received {:wotex_runtime, ^kind, _}
    end
  end

  test "WCO-S04 WCO-I05 terminal native failure reports one supported Runtime status", c do
    {owner, initial, handle} = established(c)
    owned = resources(handle.pid)
    owner_monitor = Process.monitor(owner)

    reply(c.peer, initial, %{
      initial.message
      | type: :con,
        code: 132,
        message_id: 901,
        options: [],
        payload: <<>>
    })

    assert_receive {:wotex_runtime, :property, {:error, %Wotex.Runtime.Error{}}}, 1000
    assert_receive {:wotex_runtime, :property, {:status, :transport_down}}, 1000
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, {:shutdown, :transport_down}}, 1000
    released(owned)
    refute_receive {:wotex_runtime, :property, _}, 10
  end

  test "WCO-S04 WCO-I03 malformed stream payloads remain decoding errors in both contexts", c do
    for kind <- [:property, :event],
        {media, format, payload} <- [
          {"application/json", 50, "{\"duplicate\":1,\"duplicate\":2}"},
          {"application/json", 50, "["},
          {"text/plain;charset=utf-8", 0, <<255>>}
        ] do
      {spec, _, _} = specification(c, kind, media: media, format: format)
      owner = start_supervised!(spec)
      initial = wire(c.peer)

      reply(c.peer, initial, %{
        report(initial.message, 10, payload)
        | options: [{6, <<10>>}, {12, Codec.uint(format)}]
      })

      assert_receive {:wotex_runtime, ^kind,
                      {:error, %Wotex.Runtime.Error{details: %{cause: %{code: :invalid_payload}}}}},
                     1000

      owned = resources(await_handle(owner).pid)
      refute_receive {:wotex_runtime, ^kind, _}, 10
      stop(c.peer, owner, initial)
      released(owned)
    end
  end

  test "WCO-C03 WCO-I05 Runtime owner death interrupts an unanswered native registration", c do
    {spec, _, _} = specification(c, :property)
    owner = start_supervised!(spec)
    initial = wire(c.peer)
    relay = find_relay(owner)
    owned = resources(relay)
    Process.exit(owner, :kill)
    cancellation = wire(c.peer)
    assert cancellation.message.token == initial.message.token
    assert Codec.option(cancellation.message, 6) == [<<1>>]
    released(owned)
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
  end

  test "WCO-C03 WCO-I05 receiver death closes the established original route", c do
    receiver = spawn(fn -> receive do: (:done -> :ok) end)
    {spec, _, _} = specification(c, :property, receiver: receiver)
    owner = start_supervised!(spec)
    initial = wire(c.peer)
    reply(c.peer, initial, report(initial.message, 10, "false"))
    handle = await_handle(owner)
    owned = resources(handle.pid)
    Process.exit(receiver, :kill)
    cancellation = wire(c.peer)
    assert Codec.option(cancellation.message, 6) == [<<1>>]
    reply(c.peer, cancellation, %{cancellation.message | type: :ack, code: 69, options: []})
    released(owned)
  end

  test "WCO-C02 WCO-I05 malformed Runtime input and forged close handles acquire no socket", c do
    {spec, context, config} = specification(c, :property)
    {_, _, [options]} = spec.start
    request = options.start_request
    execution = ExecutionContext.new(context, nil)
    assert {:error, _} = Transport.request(request, execution, config)

    for bad <- [
          nil,
          %{request | input: false},
          %{request | operation: :readproperty},
          %{request | affordance_type: :event},
          %{request | request_id: "different"},
          %{request | form: %Wotex.Form{value: nil}},
          %{request | profile: nil},
          %{request | profile: %{request.profile | operations: nil}},
          %{request | profile: %{request.profile | schemes: MapSet.new(["https"])}},
          Map.put(request, :extra, true)
        ] do
      assert {:error, _} = Transport.subscribe(bad, self(), execution, config)
    end

    for bad <- [
          nil,
          ExecutionContext.new(context, "secret"),
          %{execution | context: nil},
          Map.put(execution, :extra, true)
        ] do
      assert {:error, _} = Transport.subscribe(request, self(), bad, config)
    end

    for bad <- [
          nil,
          [timeout: 0],
          [renew: nil],
          [max_queue_length: 0],
          [max_queue_length: 10_001],
          [renew: true, renew: false],
          [block_size: 16],
          [{:timeout, 100} | nil]
        ] do
      assert {:error, _} = Transport.subscribe(request, self(), execution, bad)
    end

    assert {:error, _} = Transport.subscribe(request, nil, execution, config)
    {:ok, agent} = Agent.start_link(fn -> :untouched end)

    for pid <- [self(), agent, nil] do
      assert {:error, %Error{code: :invalid_subscription}} =
               RuntimeRelay.close(%RuntimeHandle{pid: pid, generation: make_ref()})
    end

    assert Agent.get(agent, & &1) == :untouched
    Agent.stop(agent)
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
    refute_received {:"$gen_call", _, _}
  end

  test "WCO-C05 WCO-I05 opening buffers exactly 64 native envelopes before binding", c do
    for count <- [63, 64] do
      {spec, _, _} = specification(c, :property)
      owner = start_supervised!(%{spec | id: {:buffer, count}})
      initial = wire(c.peer)
      relay = find_relay(owner)
      state = :sys.get_state(relay)
      owned = resources(relay)
      true = :erlang.suspend_process(state.worker)
      for _ <- 1..count, do: send(relay, {:wotex_coap, make_ref(), :unrelated})
      assert length(:sys.get_state(relay).buffered) == count
      reply(c.peer, initial, report(initial.message, 10, "false"))

      if count == 63 do
        await(fn -> length(:sys.get_state(relay).buffered) == 64 end)
        true = :erlang.resume_process(state.worker)
        assert_receive {:wotex_runtime, :property, {:ok, false, _}}, 1000
        refute_receive {:wotex_runtime, :property, _}, 10
        stop(c.peer, owner, initial)
      else
        assert_receive {:wotex_runtime, :property,
                        {:error,
                         %Wotex.Runtime.Error{
                           details: %{cause: %{code: :receiver_overflow}}
                         }}},
                       1000

        cancellation = wire(c.peer)
        assert Codec.option(cancellation.message, 6) == [<<1>>]
      end

      released(owned)
    end
  end

  test "WCO-C02 WCO-I05 unrelated generations are ignored and malformed associated reports terminate",
       c do
    {owner, initial, handle} = established(c)
    state = :sys.get_state(handle.pid)
    owned = resources(handle.pid)

    assert {:error, %Error{code: :invalid_subscription}} =
             RuntimeRelay.close(%{handle | generation: make_ref()})

    send(handle.pid, {:wotex_coap, make_ref(), {:ok, nil, %{}}})
    send(handle.pid, {:runtime_subscribed, make_ref(), state.worker, {:ok, state.subscription}})
    send(handle.pid, {:opening_deadline, make_ref()})
    send(handle.pid, :unrelated)
    send(owner, {:wotex_transport_frame, :keepalive})
    assert :sys.get_state(handle.pid).phase == :bound
    refute_receive {:wotex_runtime, :property, _}, 10

    send(
      handle.pid,
      {:wotex_coap, state.subscription.reference, {:ok, report(initial.message, 11, "true"), %{}}}
    )

    assert_receive {:wotex_runtime, :property, {:error, %Wotex.Runtime.Error{}}}, 1000
    assert_receive {:wotex_runtime, :property, {:status, :transport_down}}, 1000
    cancellation = wire(c.peer)
    reply(c.peer, cancellation, %{cancellation.message | type: :ack, code: 69, options: []})
    released(owned)
  end

  test "WCO-C03 WCO-I05 paused relay or native owners cannot restart the cleanup grace", c do
    for paused <- [:relay, :native, :adapter] do
      {owner, initial, handle} = established(c)
      state = :sys.get_state(handle.pid)
      native = state.session.pid
      adapter = :sys.get_state(native).handle.pid
      owned = resources(handle.pid)

      target =
        case paused do
          :relay -> handle.pid
          :native -> native
          :adapter -> adapter
        end

      true = :erlang.suspend_process(target)
      started = System.monotonic_time(:millisecond)
      task = Task.async(fn -> Subscription.stop(owner) end)
      assert {:error, %Wotex.Runtime.Error{}} = Task.await(task, 1200)
      released(owned)
      assert System.monotonic_time(:millisecond) - started < 1100
      assert :ok = RuntimeRelay.close(handle)
      assert initial.port > 0
    end
  end

  test "WCO-S04 WCO-I05 setup deadline and invalid first reports close provisional sessions", c do
    for response <- [:absent, :malformed] do
      {spec, _, _} = specification(c, :property, config: [timeout: 100])
      owner = start_supervised!(%{spec | id: response})
      initial = wire(c.peer)
      relay = find_relay(owner)
      owned = resources(relay)

      if response == :malformed do
        reply(c.peer, initial, %{
          initial.message
          | type: :ack,
            code: 69,
            options: [],
            payload: "false"
        })
      end

      assert_receive {:wotex_runtime, :property, {:error, %Wotex.Runtime.Error{}}}, 1000
      cancellation = wire(c.peer)
      assert Codec.option(cancellation.message, 6) == [<<1>>]
      released(owned)
    end
  end

  test "WCO-C05 WCO-I05 owner queue overflow becomes terminal loss without forwarding another value",
       c do
    # One slot of headroom lets the initial report pass while the owner may still
    # hold its subscribe reply; two queued messages then fill the bound.
    {owner, initial, handle} = established(c, config: [timeout: 1000, max_queue_length: 2])
    owned = resources(handle.pid)
    true = :erlang.suspend_process(owner)
    send(owner, :queued)
    send(owner, :queued)
    reply(c.peer, initial, %{report(initial.message, 11, "true") | type: :non, message_id: 902})
    cancellation = wire(c.peer)
    assert Codec.option(cancellation.message, 6) == [<<1>>]
    reply(c.peer, cancellation, %{cancellation.message | type: :ack, code: 69, options: []})
    true = :erlang.resume_process(owner)
    assert_receive {:wotex_runtime, :property, {:error, %Wotex.Runtime.Error{}}}, 1000
    assert_receive {:wotex_runtime, :property, {:status, :transport_down}}, 1000
    refute_receive {:wotex_runtime, :property, {:ok, true, _}}, 10
    released(owned)
  end

  test "WCO-C03 WCO-I05 an opening caller can die without leaving the Runtime owner's session behind",
       c do
    {spec, context, config} = specification(c, :property)
    {_, _, [options]} = spec.start
    owner = self()

    task =
      Task.async(fn ->
        Transport.subscribe(
          options.start_request,
          owner,
          ExecutionContext.new(context, nil),
          config
        )
      end)

    initial = wire(c.peer)
    relay = find_relay(owner)
    owned = resources(relay)
    Task.shutdown(task, :brutal_kill)
    cancellation = wire(c.peer)
    assert cancellation.message.token == initial.message.token
    released(owned)
    assert Process.alive?(owner)
  end

  test "WCO-C03 WCO-I05 concurrent close and native worker loss remain bounded and terminal", c do
    {owner, initial, handle} = established(c)

    assert {:error, %Error{code: :invalid_subscription}} =
             GenServer.call(handle.pid, {:close, make_ref(), 0})

    owned = resources(handle.pid)
    task = Task.async(fn -> Subscription.stop(owner) end)
    cancellation = wire(c.peer)
    assert cancellation.message.token == initial.message.token
    assert {:error, %Error{code: :busy}} = RuntimeRelay.close(handle)
    reply(c.peer, cancellation, %{cancellation.message | type: :ack, code: 69, options: []})
    assert :ok = Task.await(task)
    released(owned)

    {owner, _, handle} = established(c)
    state = :sys.get_state(handle.pid)
    owned = resources(handle.pid)
    owner_monitor = Process.monitor(owner)
    Process.exit(state.worker, :kill)
    assert_receive {:wotex_runtime, :property, {:error, %Wotex.Runtime.Error{}}}, 1000
    assert_receive {:wotex_runtime, :property, {:status, :transport_down}}, 1000
    released(owned)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, _}, 1000
  end

  test "WCO-C04 WCO-I05 relay diagnostics omit retained report bodies", c do
    {owner, initial, handle} = established(c)
    assert is_tuple(:sys.get_status(handle.pid))

    status =
      RuntimeRelay.format_status(%{
        state: %{payload: "PRIVATE"},
        message: "PRIVATE",
        reason: "PRIVATE",
        log: ["PRIVATE"]
      })

    refute inspect(status) =~ "PRIVATE"
    stop(c.peer, owner, initial)
  end

  test "WCO-C03 WCO-I04 expired cancellation uses cleanup without claiming peer confirmation", c do
    {owner, initial, handle} = established(c)
    owned = resources(handle.pid)
    request = :sys.get_state(owner).stop_request

    for invalid <- [nil, -1, 1001],
        do: assert({:error, %Error{code: :invalid_options}} = RuntimeRelay.close(handle, invalid))

    deadline = System.monotonic_time(:millisecond) - 1

    assert {:error, %Error{code: :deadline_exceeded}} =
             Transport.unsubscribe(handle, %{request | deadline: deadline}, nil, nil)

    cancellation = wire(c.peer)
    assert cancellation.message.token == initial.message.token
    assert Codec.option(cancellation.message, 6) == [<<1>>]
    released(owned)
    assert :ok = Subscription.stop(owner)
  end

  test "WCO-I04 Runtime wall-clock deadlines and malformed clocks fail before acquisition", c do
    {spec, context, config} = specification(c, :property)
    {_, _, [options]} = spec.start

    for value <- [DateTime.add(DateTime.utc_now(), -1), %{DateTime.utc_now() | year: :invalid}] do
      request = %{options.start_request | deadline: value}
      execution = ExecutionContext.new(%{context | deadline: value}, nil)
      assert {:error, _} = Transport.subscribe(request, self(), execution, config)
    end

    deadline = DateTime.add(DateTime.utc_now(), 10)
    owner = self()
    request = %{options.start_request | deadline: deadline}
    execution = ExecutionContext.new(%{context | deadline: deadline}, nil)
    task = Task.async(fn -> Transport.subscribe(request, owner, execution, config) end)
    initial = wire(c.peer)
    reply(c.peer, initial, report(initial.message, 10, "false"))
    assert {:ok, handle} = Task.await(task)
    assert_receive {:wotex_transport_frame, {:value, message, metadata}}

    assert {:ok, false, ^metadata} =
             Transport.decode_frame({:value, message, metadata}, request, config)

    cancel = Task.async(fn -> Transport.unsubscribe(handle, nil, nil, []) end)
    cancellation = wire(c.peer)
    reply(c.peer, cancellation, %{cancellation.message | type: :ack, code: 69, options: []})
    assert :ok = Task.await(cancel)
    assert {:error, :timeout} = :gen_udp.recv(c.peer, 0, 10)
  end

  defp specification(c, kind, options \\ []) do
    {open, close} =
      if kind == :property,
        do: {"observeproperty", "unobserveproperty"},
        else: {"subscribeevent", "unsubscribeevent"}

    forms = [
      %{
        "href" => "coap://127.0.0.1:#{c.port}/x%2Fy?a=x%26y",
        "op" => open,
        "contentType" => Keyword.get(options, :media, "application/json"),
        "cov:accept" => Keyword.get(options, :format, 50)
      },
      %{"href" => "coap://127.0.0.1:1/different", "op" => close}
    ]

    affordance =
      if kind == :property, do: %{"observable" => true, "forms" => forms}, else: %{"forms" => forms}

    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => "https://www.w3.org/2022/wot/td/v1.1",
        "title" => "Observe test",
        "securityDefinitions" => %{"none" => %{"scheme" => "nosec"}},
        "security" => ["none"],
        if(kind == :property, do: "properties", else: "events") => %{"reading" => affordance}
      })

    {:ok, profile} = Wotex.CoAP.profile(:udp_observe)

    config = Keyword.get(options, :config, timeout: 1000)

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{coap_observe: {Transport, config}},
        credentials: {RuntimeCredentials, []}
      )

    {:ok, context} = Context.new(request_id: "observation")

    callback =
      if kind == :property, do: :observation_child_spec, else: :event_subscription_child_spec

    {:ok, spec} =
      apply(ConsumedThing, callback, [
        consumed,
        "reading",
        context,
        [
          id: kind,
          receiver: Keyword.get(options, :receiver, self()),
          restart: :temporary,
          max_queue_length: 1000,
          overflow: :stop
        ]
      ])

    {spec, context, config}
  end

  defp established(c, options \\ []) do
    {spec, _, _} = specification(c, :property, options)
    owner = start_supervised!(spec)
    initial = wire(c.peer)
    reply(c.peer, initial, report(initial.message, 10, "false"))
    assert_receive {:wotex_runtime, :property, {:ok, false, _}}, 1000
    {owner, initial, await_handle(owner)}
  end

  defp report(request, sequence, payload),
    do: %{
      request
      | type: :ack,
        code: 69,
        options: [{4, "e"}, {6, Codec.uint(sequence)}, {12, <<50>>}],
        payload: payload
    }

  defp wire(peer) do
    assert {:ok, {ip, port, bytes}} = :gen_udp.recv(peer, 0, 1500)
    assert {:ok, message} = Codec.decode(bytes)
    %{ip: ip, port: port, message: message}
  end

  defp reply(peer, route, message) do
    assert {:ok, bytes} = Codec.encode(message)
    assert :ok = :gen_udp.send(peer, route.ip, route.port, bytes)
  end

  defp stop(peer, owner, initial) do
    task = Task.async(fn -> Subscription.stop(owner) end)
    cancellation = wire(peer)
    assert cancellation.port == initial.port
    assert cancellation.message.token == initial.message.token
    assert Codec.option(cancellation.message, 6) == [<<1>>]
    assert Codec.option(cancellation.message, 11) == ["x/y"]
    reply(peer, cancellation, %{cancellation.message | type: :ack, code: 69, options: []})
    assert :ok = Task.await(task, 1500)
  end

  defp await_handle(owner), do: await(fn -> :sys.get_state(owner).handle end)

  defp find_relay(owner) do
    await(fn ->
      Enum.find(Process.list(), fn pid ->
        match?(
          {{:dictionary, :wotex_coap_runtime_relay}, {RuntimeRelay, _}},
          :erlang.process_info(pid, {:dictionary, :wotex_coap_runtime_relay})
        ) and :sys.get_state(pid).owner == owner
      end)
    end)
  end

  defp resources(relay) do
    state = :sys.get_state(relay)
    connection = :sys.get_state(state.session.pid)
    adapter = :sys.get_state(connection.handle.pid)

    pids = [
      relay,
      state.lifetime,
      state.worker,
      state.session.pid,
      connection.lifetime,
      connection.handle.pid,
      adapter.lifetime,
      connection.observation.pid
    ]

    %{socket: adapter.socket, monitors: Enum.map(pids, &Process.monitor/1)}
  end

  defp released(owned) do
    for reference <- owned.monitors, do: assert_receive({:DOWN, ^reference, :process, _, _}, 1100)
    assert :erlang.port_info(owned.socket) == :undefined
  end

  defp await(fun), do: await(fun, System.monotonic_time(:millisecond) + 1000)

  defp await(fun, deadline) do
    case fun.() do
      value when value not in [nil, false] ->
        value

      _ ->
        assert System.monotonic_time(:millisecond) < deadline

        receive do
        after
          1 -> await(fun, deadline)
        end
    end
  end
end
