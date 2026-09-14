defmodule Wotex.Binding.MQTT.LimitsSecurityTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.MQTT
  alias Wotex.Binding.MQTT.{Command, Delivery, Error, JSON, Topic, Transport, TransportConfig}

  alias Wotex.Binding.MQTT.Test.{
    FakeClient,
    FakeCredentials,
    LifecycleClient,
    RequestFactory,
    TDFactory
  }

  alias Wotex.Runtime.{ConsumedThing, Context, Subscription}

  @max_topic_bytes 65_535
  @max_filters 256
  @max_depth 64
  @max_nodes 100_000
  @max_string_bytes 262_144
  @max_collection_size 10_000
  @delivery_count 512

  defmodule CapturingClient do
    @moduledoc false

    @behaviour Wotex.Binding.MQTT.Client

    @impl Wotex.Binding.MQTT.Client
    def publish(command, execution_context, config) do
      send(config.test_pid, {:captured_client_input, command, execution_context.credential})
      Map.get(config, :publish_return, :ok)
    end

    @impl Wotex.Binding.MQTT.Client
    def read(_, _, _, _), do: {:error, :unused}

    @impl Wotex.Binding.MQTT.Client
    def subscribe(_, _, _, _), do: {:error, :unused}

    @impl Wotex.Binding.MQTT.Client
    def unsubscribe(_, _, _, _), do: {:error, :unused}
  end

  test "Topic Name and Topic Filter byte limits accept exact and reject one over" do
    exact = String.duplicate("t", @max_topic_bytes)
    one_over = exact <> "t"

    assert :ok = Topic.validate_name(exact)
    assert :ok = Topic.validate_filter(exact)

    assert {:error, %Error{code: :invalid_topic_name, details: %{max_bytes: @max_topic_bytes}}} =
             Topic.validate_name(one_over)

    assert {:error, %Error{code: :invalid_topic_filter, details: %{max_bytes: @max_topic_bytes}}} =
             Topic.validate_filter(one_over)
  end

  test "Topic Filter cardinality is admitted at 256 and rejected before validating item 257" do
    exact = Enum.map(1..@max_filters, &"things/#{&1}")
    sentinel = :must_not_be_validated

    assert {:ok, ^exact} = Topic.normalize_filters(exact)

    assert {:error,
            %Error{
              code: :too_many_topic_filters,
              phase: :topic,
              class: :protocol,
              details: %{max_filters: @max_filters}
            }} = Topic.normalize_filters(Enum.concat(exact, [sentinel]))
  end

  test "an excessive Form filter list is rejected before the client callback" do
    filters = Enum.map(0..@max_filters, &"things/#{&1}")

    request =
      RequestFactory.request(:observeproperty,
        form: %{
          "href" => "mqtt://broker.example",
          "op" => "observeproperty",
          "mqv:filter" => filters
        }
      )

    {:ok, config} = TransportConfig.new(FakeClient, fake_client_config(:ok))

    assert {:error, %Error{code: :too_many_topic_filters}} =
             Transport.subscribe(request, self(), RequestFactory.execution_context(), config)

    refute_received {:client_subscribe, _, _, _, _}
  end

  test "encoded and received payload byte limits accept exact and reject one over" do
    value = "payload"
    encoded = ~s("payload")
    exact = byte_size(encoded)

    assert {:ok, ^encoded} = JSON.encode(value, exact)
    assert {:error, %Error{code: :encoded_payload_too_large}} = JSON.encode(value, exact - 1)
    assert {:ok, ^value} = JSON.decode(encoded, exact)
    assert {:error, %Error{code: :received_payload_too_large}} = JSON.decode(encoded, exact - 1)
  end

  test "inherited JSON depth and string thresholds accept exact and reject one over" do
    exact_depth = String.duplicate("[", @max_depth) <> String.duplicate("]", @max_depth)
    excessive_depth = "[" <> exact_depth <> "]"

    assert {:ok, _} = JSON.decode(exact_depth, 1_048_576)

    assert {:error, %Error{code: :json_decode_failed, details: %{cause: :depth_limit_exceeded}}} =
             JSON.decode(excessive_depth, 1_048_576)

    exact_string = Jason.encode!(String.duplicate("s", @max_string_bytes))
    excessive_string = Jason.encode!(String.duplicate("s", @max_string_bytes + 1))

    assert {:ok, _} = JSON.decode(exact_string, 1_048_576)

    assert {:error, %Error{code: :json_decode_failed, details: %{cause: :string_limit_exceeded}}} =
             JSON.decode(excessive_string, 1_048_576)
  end

  test "inherited JSON collection threshold accepts exact and rejects one over" do
    exact = "[" <> String.duplicate("0,", @max_collection_size - 1) <> "0]"
    one_over = "[" <> String.duplicate("0,", @max_collection_size) <> "0]"

    assert {:ok, values} = JSON.decode(exact, 1_048_576)
    assert length(values) == @max_collection_size

    assert {:error,
            %Error{code: :json_decode_failed, details: %{cause: :collection_limit_exceeded}}} =
             JSON.decode(one_over, 1_048_576)
  end

  test "inherited JSON node threshold accepts exact and rejects one over" do
    exact = node_payload(8)
    one_over = node_payload(9)

    assert {:ok, values} = JSON.decode(exact, 1_048_576)

    assert 1 + Enum.reduce(values, 0, fn value, count -> count + 1 + length(value) end) ==
             @max_nodes

    assert {:error, %Error{code: :json_decode_failed, details: %{cause: :node_limit_exceeded}}} =
             JSON.decode(one_over, 1_048_576)
  end

  test "a Runtime owner sustains 512 admitted deliveries without binding state" do
    {:ok, state} = LifecycleClient.start_link(self())
    on_exit(fn -> if Process.alive?(state), do: Agent.stop(state) end)
    config = lifecycle_config(state)
    id = {:sustained, make_ref()}
    owner = start_observation(config, id, self())

    assert_receive {:lifecycle_subscribed, handle, ^owner}
    assert_active(owner)
    delivery = delivery!(~s({"value":21}), "things/properties/value")

    for _ <- 1..@delivery_count,
        do: send(owner, {:wotex_transport_frame, delivery})

    assert_deliveries(id, @delivery_count)
    assert Process.alive?(owner)
    assert LifecycleClient.snapshot(state).active == %{handle => owner}
    assert :ok = Subscription.stop(owner)
  end

  test "the Runtime stop-overflow policy closes the supplied-client handle" do
    {:ok, state} = LifecycleClient.start_link(self())
    on_exit(fn -> if Process.alive?(state), do: Agent.stop(state) end)
    config = lifecycle_config(state)
    receiver = spawn(fn -> blocked_receiver() end)
    on_exit(fn -> if Process.alive?(receiver), do: send(receiver, :stop) end)
    id = {:overload, make_ref()}

    owner =
      start_observation(config, id, receiver, max_queue_length: 2, overflow: :stop)

    assert_receive {:lifecycle_subscribed, handle, ^owner}
    assert_active(owner)
    monitor = Process.monitor(owner)
    send(receiver, :backlog_one)
    send(receiver, :backlog_two)
    assert {:message_queue_len, 2} = Process.info(receiver, :message_queue_len)

    send(owner, {:wotex_transport_frame, delivery!("null", "things/properties/value")})

    assert_receive {:lifecycle_unsubscribe_attempt, ^handle, ^owner, 1, _}
    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, :overloaded}}
    assert LifecycleClient.snapshot(state).active == %{}
  end

  test "the supplied client has credential and delivery authority while public values stay redacted" do
    secret = "test-credential-must-not-escape"
    {:ok, config} = TransportConfig.new(CapturingClient, %{test_pid: self()})
    context = RequestFactory.execution_context(secret)

    assert {:ok, result} = Transport.request(publish_request(), context, config)
    assert_receive {:captured_client_input, command, ^secret}
    assert Command.payload(command) == ~s({"value":21})
    refute inspect(command) =~ secret
    refute inspect(result) =~ secret
    refute inspect(config) =~ secret

    nested_failure = {:error, %{credential: secret, nested: [secret]}}
    {:ok, failing_config} = TransportConfig.new(FakeClient, fake_client_config(nested_failure))

    assert {:error, %Error{code: :client_publish_failed} = error} =
             Transport.request(publish_request(), context, failing_config)

    refute inspect(error) =~ secret

    assert Transport.decode_frame(delivery!("null"), observe_request(), lifecycle_config(self())) ==
             {:ok, nil,
              %{
                binding: :mqtt,
                control_packet: :subscribe,
                operation: :observeproperty,
                qos: 1,
                request_id: "request-1",
                retained: false,
                topic: "things/value"
              }}
  end

  defp node_payload(final_width) do
    nine = "[" <> String.duplicate("0,", 8) <> "0]"
    final = "[" <> String.duplicate("0,", final_width - 1) <> "0]"
    "[" <> String.duplicate(nine <> ",", 9_999) <> final <> "]"
  end

  defp start_observation(config, id, receiver, opts \\ []) do
    {:ok, consumed} =
      ConsumedThing.new(TDFactory.thing_description(),
        profiles: [MQTT.profile()],
        transports: %{mqtt: {Transport, config}},
        credentials: {FakeCredentials, %{test_pid: self()}}
      )

    {:ok, spec} =
      ConsumedThing.observation_child_spec(
        consumed,
        "temperature",
        Context.new!(request_id: inspect(id)),
        Keyword.merge([id: id, receiver: receiver, restart: :temporary], opts)
      )

    start_supervised!(spec)
  end

  defp lifecycle_config(state) do
    {:ok, config} = TransportConfig.new(LifecycleClient, %{state: state, test_pid: self()})
    config
  end

  defp fake_client_config(return) do
    %{test_pid: self(), client_marker: :client_state, publish_return: return}
  end

  defp assert_active(owner, attempts \\ 100)

  defp assert_active(_, 0), do: flunk("Runtime subscription did not become active")

  defp assert_active(owner, attempts) do
    case :sys.get_state(owner) do
      %{active?: true} ->
        :ok

      _ ->
        Process.sleep(1)
        assert_active(owner, attempts - 1)
    end
  end

  defp assert_deliveries(_, 0), do: :ok

  defp assert_deliveries(id, remaining) do
    assert_receive {:wotex_runtime, ^id,
                    {:ok, %{"value" => 21}, %{topic: "things/properties/value", qos: 1}}},
                   1_000

    assert_deliveries(id, remaining - 1)
  end

  defp blocked_receiver do
    receive do
      :stop -> :ok
    end
  end

  defp publish_request do
    RequestFactory.request(:writeproperty,
      input: %{"value" => 21},
      form: %{
        "href" => "mqtt://broker.example",
        "op" => "writeproperty",
        "mqv:topic" => "things/value"
      }
    )
  end

  defp observe_request do
    RequestFactory.request(:observeproperty,
      form: %{
        "href" => "mqtt://broker.example",
        "op" => ["observeproperty", "unobserveproperty"],
        "mqv:qos" => 1,
        "mqv:filter" => "things/+"
      }
    )
  end

  defp delivery!(payload, topic \\ "things/value") do
    {:ok, delivery} = Delivery.new(payload, topic: topic, qos: 1, retain: false)
    delivery
  end
end
