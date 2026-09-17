defmodule Wotex.OPCUA.RuntimeStreamTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.OPCUA.{
    Error,
    Mapping,
    RuntimeHandle,
    RuntimeRelay,
    TestClient,
    TestNosecCredentials,
    TestStreamClient,
    Transport
  }

  alias Wotex.Runtime.{
    BindingProfile,
    ConsumedThing,
    Context,
    ExecutionContext,
    Request,
    Subscription
  }

  @target "opc.tcp://localhost:4840/"
  @href "opc.tcp://localhost:4840/?id=ns%3D2%3Bs%3Dreading"
  @double %{
    "has_value" => true,
    "status" => 0,
    "value" => %{"type" => "Double", "array" => false, "value" => 1.5}
  }
  @metadata %{
    "sequence" => 1,
    "publish_time" => 1001,
    "client_handle" => 1,
    "overflow" => false,
    "datetime_resolution_ns" => 100,
    "raw_datetime_ticks_available" => true
  }

  @corpus "docs/specs/fixtures/native-contract-v1.json"
  @corpus_sha256 :crypto.hash(:sha256, File.read!(@corpus)) |> Base.encode16(case: :lower)
  @handoff @corpus
           |> File.read!()
           |> Jason.decode!()
           |> Map.fetch!("cases")
           |> Enum.find(&(&1["id"] == "WOP-X-F23"))

  setup do
    {:ok, form} =
      Wotex.Form.new(%{
        "href" => @href,
        "op" => ["readproperty", "observeproperty", "unobserveproperty"]
      })

    {:ok, context} = Context.new(request_id: "observe-1")

    request = %Request{
      operation: :observeproperty,
      affordance_type: :property,
      affordance_name: "reading",
      form: form,
      resolved_href: @href,
      profile: nil,
      request_id: "observe-1",
      deadline: nil,
      input: nil
    }

    config = [client: TestStreamClient, target: @target, test: self(), timeout: 1000]

    %{
      request: request,
      execution: ExecutionContext.new(context, nil),
      config: config,
      context: context
    }
  end

  test "WOP-S05 a Runtime observation child delivers projected values and releases its Session",
       context do
    consumed = consumed(context.config)

    assert {:ok, spec} =
             ConsumedThing.observation_child_spec(consumed, "reading", context.context,
               id: :reading,
               receiver: self(),
               max_queue_length: 1000,
               overflow: :stop,
               restart: :temporary
             )

    owner = start_supervised!(spec)
    assert_receive {:stream_connected, relay, _}
    assert_receive {:stream_subscribed, ^relay, subscription, request}

    assert %{node_id: "ns=2;s=reading", max_queue_length: 64, queue_size: 100} = request
    refute Map.has_key?(request, :receiver)
    reference = subscription.reference
    send(relay, {:wotex_opcua, reference, {:ok, @double, @metadata}})

    assert_receive {:wotex_runtime, :reading,
                    {:ok, 1.5,
                     %{
                       opcua_type: "Double",
                       status: 0,
                       sequence: 1,
                       overflow: false,
                       client_handle: 1
                     }}}

    send(relay, {:wotex_opcua, make_ref(), {:ok, @double, @metadata}})
    assert :ok = Subscription.stop(owner)
    assert_receive {:stream_unsubscribed, ^reference}
    assert_receive {:stream_disconnected, ^relay}
    refute Process.alive?(relay)
    refute_receive {:wotex_runtime, :reading, {:ok, _, _}}, 50
  end

  @tag case: "WOP-X-F23", corpus_sha256: @corpus_sha256
  test "WOP-X-F23 Runtime handoff survives callback worker exit and ends with the final owner",
       context do
    expected = @handoff["expectation"]["value"]
    parent = self()

    owner =
      spawn(fn ->
        receive do
          {:wotex_transport_frame, frame} -> send(parent, {:owner_frame, frame})
        end

        Process.sleep(:infinity)
      end)

    {worker, worker_monitor} =
      spawn_monitor(fn ->
        send(
          parent,
          {:handoff, Transport.subscribe(context.request, owner, context.execution, context.config)}
        )
      end)

    assert_receive {:stream_subscribed, relay, %{reference: reference}, _}
    assert %{owner: ^owner, caller: ^worker} = :sys.get_state(relay)
    assert_receive {:handoff, {:ok, handle}}
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :normal}
    send(relay, {:wotex_opcua, reference, {:ok, @double, @metadata}})
    assert_receive {:owner_frame, {:value, @double, @metadata}}
    {:messages, pending} = Process.info(owner, :messages)
    deliveries = 1 + Enum.count(pending, &match?({:wotex_transport_frame, _}, &1))
    closed_by_worker_exit = not Process.alive?(relay)
    relay_monitor = Process.monitor(relay)
    Process.exit(owner, :kill)
    assert_receive {:stream_unsubscribed, ^reference}
    assert_receive {:stream_disconnected, ^relay}
    assert_receive {:DOWN, ^relay_monitor, :process, ^relay, :normal}, 1000
    refute_received {:owner_frame, _}
    active = Enum.count([relay], &Process.alive?/1)

    assert %{
             "deliveries" => deliveries,
             "closed_by_worker_exit" => closed_by_worker_exit,
             "active_local_resources" => active
           } == expected

    assert :ok = Transport.unsubscribe(handle, context.request, context.execution, context.config)
  end

  test "WOP-S05 terminal native loss reports a Runtime status and closes without unsubscribe",
       context do
    for {code, status} <- [subscription_lost: :session_lost, connection_failed: :transport_down] do
      consumed = consumed(context.config)
      id = {:loss, code}

      assert {:ok, spec} =
               ConsumedThing.observation_child_spec(consumed, "reading", context.context,
                 id: id,
                 receiver: self(),
                 restart: :temporary
               )

      owner = start_supervised!(spec)
      monitor = Process.monitor(owner)
      assert_receive {:stream_subscribed, relay, %{reference: reference}, _}
      send(relay, {:wotex_opcua, reference, {:ok, @double, @metadata}})
      assert_receive {:wotex_runtime, ^id, {:ok, 1.5, _}}
      send(relay, {:wotex_opcua, reference, {:error, Error.new(code)}})
      assert_receive {:wotex_runtime, ^id, {:error, _}}
      assert_receive {:wotex_runtime, ^id, {:status, ^status}}
      assert_receive {:stream_disconnected, ^relay}
      refute_received {:stream_unsubscribed, ^reference}
      assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, ^status}}
    end
  end

  test "WOP-C05 a full Runtime owner queue ends delivery with receiver_overflow", context do
    owner = spawn(fn -> Process.sleep(:infinity) end)
    config = Keyword.put(context.config, :max_queue_length, 2)
    assert {:ok, handle} = Transport.subscribe(context.request, owner, context.execution, config)
    assert_receive {:stream_subscribed, relay, %{reference: reference}, _}
    relay_monitor = Process.monitor(relay)

    for _ <- 1..3, do: send(relay, {:wotex_opcua, reference, {:ok, @double, @metadata}})

    assert_receive {:stream_unsubscribed, ^reference}
    assert_receive {:stream_disconnected, ^relay}
    assert_receive {:DOWN, ^relay_monitor, :process, ^relay, :normal}
    {:messages, messages} = Process.info(owner, :messages)

    assert [
             {:wotex_transport_frame, {:value, @double, @metadata}},
             {:wotex_transport_frame, {:value, @double, @metadata}},
             {:wotex_transport_frame, {:error, %Error{code: :receiver_overflow}}},
             {:wotex_transport_status, :transport_down}
           ] = messages

    assert :ok = Transport.unsubscribe(handle, context.request, context.execution, config)
    Process.exit(owner, :kill)
  end

  test "WOP-C03 owner death after binding releases the subscription and Session", context do
    owner = spawn(fn -> Process.sleep(:infinity) end)

    assert {:ok, %RuntimeHandle{} = handle} =
             Transport.subscribe(context.request, owner, context.execution, context.config)

    assert inspect(handle) =~ "RuntimeHandle"
    refute inspect(handle) =~ inspect(handle.pid)
    assert_receive {:stream_subscribed, relay, %{reference: reference}, _}
    Process.exit(owner, :kill)
    assert_receive {:stream_unsubscribed, ^reference}
    assert_receive {:stream_disconnected, ^relay}
    assert :ok = Transport.unsubscribe(handle, context.request, context.execution, context.config)
  end

  test "WOP-C03 owner or caller death during establishment interrupts the relay", context do
    config = Keyword.put(context.config, :mode, :block)

    owner = spawn(fn -> Process.sleep(:infinity) end)
    parent = self()

    spawn(fn ->
      send(
        parent,
        {:opened, Transport.subscribe(context.request, owner, context.execution, config)}
      )
    end)

    assert_receive {:stream_blocked, relay}
    monitor = Process.monitor(relay)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^relay, :killed}, 1000
    assert_receive {:opened, {:error, %Error{code: :connection_failed}}}, 1000

    caller =
      spawn(fn ->
        Transport.subscribe(context.request, self(), context.execution, config)
      end)

    assert_receive {:stream_blocked, relay}
    monitor = Process.monitor(relay)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^relay, :killed}, 1000
  end

  test "WOP-S05 establishment failures close what was opened", context do
    request = context.request
    execution = context.execution

    for {mode, code, disconnected} <- [
          {:connect_error, :connection_failed, false},
          {:subscribe_error, :remote_error, true}
        ] do
      config = Keyword.put(context.config, :mode, mode)

      assert {:error, %Error{code: ^code}} =
               Transport.subscribe(request, self(), execution, config)

      assert_receive {:stream_connected, _, _}

      if disconnected,
        do: assert_receive({:stream_disconnected, _}),
        else: refute_received({:stream_disconnected, _})
    end

    config = [client: TestClient, target: @target]

    assert {:error, %Error{code: :not_supported}} =
             Transport.subscribe(request, self(), execution, config)

    slow = %{request | deadline: System.monotonic_time(:millisecond) + 30}
    config = Keyword.put(context.config, :mode, :slow_connect)

    assert {:error, %Error{code: :deadline_exceeded}} =
             Transport.subscribe(slow, self(), execution, config)

    assert_receive {:stream_connected, relay, timeout} when timeout <= 30
    assert_receive {:stream_disconnected, ^relay}

    assert {:error, %Error{code: :deadline_exceeded}} =
             RuntimeRelay.open(%{
               owner: self(),
               deadline: System.monotonic_time(:millisecond) - 1,
               connection: context.config
             })

    expired = %{request | deadline: System.monotonic_time(:millisecond) - 1}

    assert {:error, %Error{code: :deadline_exceeded}} =
             Transport.subscribe(expired, self(), execution, context.config)

    refute_received {:stream_connected, _, _}
  end

  test "WOP-S05 invalid observation requests start no relay", context do
    %{request: request, execution: execution, config: config} = context
    {:ok, runtime_context} = Context.new(request_id: "observe-2")
    dead = spawn(fn -> :ok end)
    ref = Process.monitor(dead)
    assert_receive {:DOWN, ^ref, :process, ^dead, _}

    for {arguments, code} <- [
          {[%{request | operation: :subscribeevent}, self(), execution, config],
           :unsupported_operation},
          {[request, self(), ExecutionContext.new(runtime_context, "secret"), config],
           :invalid_transport_context},
          {[%{request | input: 1}, self(), execution, config], :invalid_transport_context},
          {[request, dead, execution, config], :invalid_transport_context},
          {[request, self(), execution, [:bad]], :invalid_transport_context},
          {[request, self(), execution, Keyword.put(config, :target, "opc.tcp://other:4840/")],
           :target_mismatch},
          {[request, self(), execution, Keyword.put(config, :subscription, %{receiver: self()})],
           :invalid_value},
          {[request, self(), execution, Keyword.put(config, :subscription, :fast)], :invalid_value},
          {[request, self(), execution, Keyword.put(config, :max_queue_length, 0)], :invalid_value},
          {[request, self(), execution, Keyword.put(config, :timeout, 0)], :invalid_timeout},
          {[nil, self(), execution, config], :invalid_transport_context}
        ] do
      assert {:error, %Error{code: ^code}} = apply(Transport, :subscribe, arguments)
    end

    {:ok, read_only} = Wotex.Form.new(%{"href" => @href})

    assert {:error, %Error{code: :unsupported_operation}} =
             Transport.subscribe(%{request | form: read_only}, self(), execution, config)

    assert {:error, %Error{code: :unsupported_operation}} =
             Transport.request(request, execution, config)

    assert {:ok, %{message: %{type: :observe}}} =
             Mapping.command(request.form, :unobserveproperty, nil)

    refute_received {:stream_connected, _, _}
  end

  test "WOP-S05 decode_frame projects validated values and rejects malformed frames", context do
    request = context.request
    bytes = %{"type" => "bytes", "base64" => Base.encode64(<<0, 255>>)}

    timed =
      Map.merge(@double, %{
        "source_timestamp" => 1,
        "server_timestamp" => 2,
        "source_picoseconds" => 30,
        "server_picoseconds" => 40
      })

    assert {:ok, 1.5,
            %{
              source_timestamp: 1,
              server_timestamp: 2,
              source_picoseconds: 30,
              server_picoseconds: 40,
              raw_datetime_ticks_available: true,
              datetime_resolution_ns: 100,
              publish_time: 1001
            }} =
             Transport.decode_frame({:value, timed, @metadata}, request, [])

    array = %{
      @double
      | "value" => %{"type" => "ByteString", "array" => true, "value" => [bytes, nil]}
    }

    assert {:ok, [<<0, 255>>, nil], %{opcua_type: "ByteString"}} =
             Transport.decode_frame({:value, array, @metadata}, request, [])

    scalar = %{@double | "value" => %{"type" => "ByteString", "array" => false, "value" => bytes}}
    assert {:ok, <<0, 255>>, _} = Transport.decode_frame({:value, scalar, @metadata}, request, [])

    for {value, metadata, code} <- [
          {@double, Map.delete(@metadata, "sequence"), :invalid_native_frame},
          {@double, Map.put(Map.delete(@metadata, "sequence"), "other", 1), :invalid_native_frame},
          {@double, :metadata, :invalid_native_frame},
          {%{@double | "status" => 0x8034_0000}, @metadata, :bad_status},
          {%{@double | "has_value" => false}, @metadata, :missing_value},
          {Map.put(@double, "value", %{"type" => "NodeId", "array" => false, "value" => %{"x" => 1}}),
           @metadata, :unsupported_type},
          {Map.put(@double, "value", %{
             "type" => "Double",
             "array" => false,
             "value" => 1,
             "dimensions" => [1]
           }), @metadata, :unsupported_type},
          {Map.put(@double, "value", %{
             "type" => "ByteString",
             "array" => true,
             "value" => [%{"x" => 1}]
           }), @metadata, :unsupported_type},
          {%{"status" => 0}, @metadata, :invalid_result}
        ] do
      assert {:error, %Error{code: ^code}} =
               Transport.decode_frame({:value, value, metadata}, request, [])
    end

    assert {:error, %Error{code: :sequence_gap}} =
             Transport.decode_frame({:error, Error.new(:sequence_gap)}, request, [])

    assert :ignore = Transport.decode_frame({:status, :keepalive}, request, [])
  end

  test "WOP-S05 unsubscribe validates handles and releases with any credential", context do
    %{request: request, execution: execution, config: config} = context
    {:ok, runtime_context} = Context.new(request_id: "observe-3")
    owner = spawn(fn -> Process.sleep(:infinity) end)
    assert {:ok, handle} = Transport.subscribe(request, owner, execution, config)
    assert_receive {:stream_subscribed, relay, %{reference: reference}, _}

    assert {:error, %Error{code: :invalid_subscription}} =
             Transport.unsubscribe(%{handle | generation: make_ref()}, request, execution, config)

    assert {:error, %Error{code: :invalid_subscription}} =
             RuntimeRelay.close(%RuntimeHandle{pid: self(), generation: make_ref()})

    assert {:error, %Error{code: :invalid_subscription}} = GenServer.call(relay, :unknown)
    {:status, ^relay, _, [_, _, _, _, status]} = :sys.get_status(relay)
    refute inspect(status) =~ "stream_client" or inspect(status) =~ inspect(reference)
    send(relay, :unrelated)

    assert {:error, %Error{code: :invalid_transport_context}} =
             Transport.unsubscribe(
               handle,
               request,
               ExecutionContext.new(runtime_context, "secret"),
               config
             )

    assert_receive {:stream_unsubscribed, ^reference}
    assert_receive {:stream_disconnected, ^relay}
    assert :ok = Transport.unsubscribe(handle, request, execution, config)

    assert {:error, %Error{code: :invalid_subscription}} =
             Transport.unsubscribe(:handle, request, execution, config)

    for {mode, code} <- [unsubscribe_error: :cleanup_failed, disconnect_error: :cleanup_failed] do
      config = Keyword.put(config, :mode, mode)
      assert {:ok, handle} = Transport.subscribe(request, owner, execution, config)
      assert_receive {:stream_subscribed, _, _, _}

      assert {:error, %Error{code: ^code}} =
               Transport.unsubscribe(handle, request, execution, config)
    end

    assert {:ok, handle} = Transport.subscribe(request, owner, execution, config)
    assert_receive {:stream_subscribed, relay, %{reference: reference}, _}
    monitor = Process.monitor(relay)
    send(relay, {:wotex_opcua, reference, :malformed})
    assert_receive {:stream_unsubscribed, ^reference}
    assert_receive {:DOWN, ^monitor, :process, ^relay, :normal}
    assert :ok = Transport.unsubscribe(handle, request, execution, config)

    assert {:ok, _} = Transport.subscribe(request, owner, execution, config)
    assert_receive {:stream_subscribed, relay, %{reference: reference}, _}
    monitor = Process.monitor(relay)
    send(relay, {:EXIT, self(), :crashed})
    assert_receive {:DOWN, ^monitor, :process, ^relay, :normal}
    refute_received {:stream_unsubscribed, ^reference}
    Process.exit(owner, :kill)
  end

  test "WOP-S05 an Event subscription child fails in the transport without a Session", context do
    consumed = consumed(context.config)

    assert {:ok, spec} =
             ConsumedThing.event_subscription_child_spec(consumed, "alarm", context.context,
               id: :alarm,
               receiver: self(),
               restart: :temporary
             )

    owner = start_supervised!(spec)
    monitor = Process.monitor(owner)
    assert_receive {:wotex_runtime, :alarm, {:error, _}}
    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, _}}
    refute_received {:stream_connected, _, _}
  end

  defp consumed(config) do
    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:example:opcua:meter",
        "title" => "Meter",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{
          "reading" => %{
            "type" => "number",
            "observable" => true,
            "forms" => [
              %{"href" => @href, "op" => ["readproperty", "observeproperty", "unobserveproperty"]}
            ]
          }
        },
        "events" => %{
          "alarm" => %{
            "forms" => [%{"href" => @href, "op" => ["subscribeevent", "unsubscribeevent"]}]
          }
        }
      })

    {:ok, profile} =
      BindingProfile.new(
        id: :opcua_session,
        schemes: ["opc.tcp"],
        operations: [
          :readproperty,
          :observeproperty,
          :unobserveproperty,
          :subscribeevent,
          :unsubscribeevent
        ]
      )

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{opcua_session: {Transport, config}},
        credentials: {TestNosecCredentials, nil}
      )

    consumed
  end
end
