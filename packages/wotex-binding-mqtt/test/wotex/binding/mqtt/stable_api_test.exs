defmodule Wotex.Binding.MQTT.StableAPITest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.MQTT

  alias Wotex.Binding.MQTT.{
    Broker,
    Client,
    Command,
    Delivery,
    Error,
    JSON,
    Mapping,
    QoS,
    Topic,
    Transport,
    TransportConfig
  }

  alias Wotex.Binding.MQTT.Test.RequestFactory
  alias Wotex.Runtime.{BindingProfile, Result}

  defmodule StableClient do
    @moduledoc false
    @behaviour Client

    @impl Wotex.Binding.MQTT.Client
    def publish(command, execution_context, config) do
      send(config.observer, {:stable_publish, command, execution_context})
      :ok
    end

    @impl Wotex.Binding.MQTT.Client
    def read(command, timeout, execution_context, config) do
      send(config.observer, {:stable_read, command, timeout, execution_context})
      Delivery.new(~s({"value":21}), topic: "things/value", qos: 1, retain: true)
    end

    @impl Wotex.Binding.MQTT.Client
    def subscribe(command, owner, execution_context, config) do
      send(config.observer, {:stable_subscribe, command, owner, execution_context})
      {:ok, {:stable_handle, owner}}
    end

    @impl Wotex.Binding.MQTT.Client
    def unsubscribe(handle, command, execution_context, config) do
      send(config.observer, {:stable_unsubscribe, handle, command, execution_context})
      :ok
    end
  end

  @operations [
    :readproperty,
    :writeproperty,
    :observeproperty,
    :unobserveproperty,
    :invokeaction,
    :subscribeevent,
    :unsubscribeevent
  ]

  @rows [
    {:readproperty, :property, :subscribe, "mqv:filter", true},
    {:writeproperty, :property, :publish, "mqv:topic", false},
    {:invokeaction, :action, :publish, "mqv:topic", false},
    {:observeproperty, :property, :subscribe, "mqv:filter", false},
    {:subscribeevent, :event, :subscribe, "mqv:filter", false},
    {:unobserveproperty, :property, :unsubscribe, "mqv:filter", false},
    {:unsubscribeevent, :event, :unsubscribe, "mqv:filter", false}
  ]

  test "WBM-S01 freezes callable convenience arities and client callbacks" do
    for {module, function, arity} <- [
          {MQTT, :profile, 0},
          {Broker, :new, 1},
          {Command, :publish, 4},
          {Command, :publish, 5},
          {Command, :subscribe, 3},
          {Command, :subscribe, 4},
          {Command, :unsubscribe, 3},
          {Command, :unsubscribe, 4},
          {Delivery, :new, 2},
          {JSON, :encode, 2},
          {Mapping, :command, 2},
          {QoS, :normalize, 1},
          {Topic, :matches?, 2},
          {Transport, :request, 3},
          {TransportConfig, :new, 2},
          {TransportConfig, :new, 3}
        ] do
      assert function_exported?(module, function, arity)
    end

    assert Client.behaviour_info(:callbacks) |> Enum.sort() ==
             [publish: 3, read: 4, subscribe: 4, unsubscribe: 4] |> Enum.sort()
  end

  test "WBM-S02 freezes the exact MQTT profile cells" do
    profile = MQTT.profile()
    assert BindingProfile.id(profile) == :mqtt

    for scheme <- ["mqtt", "mqtts", "MQTT", "MQTTS"] do
      assert BindingProfile.supports_scheme?(profile, scheme)
    end

    refute BindingProfile.supports_scheme?(profile, "http")
    assert BindingProfile.supports_media_type?(profile, "application/json")
    assert BindingProfile.supports_media_type?(profile, "Application/JSON; charset=utf-8")
    refute BindingProfile.supports_media_type?(profile, "application/cbor")

    assert Enum.filter(Wotex.Runtime.operations(), &BindingProfile.supports_operation?(profile, &1))
           |> Enum.sort() == Enum.sort(@operations)
  end

  test "WBM-S03 freezes immutable values, bounds, defaults, and inspection redaction" do
    assert {:ok, broker} = Broker.new("mqtts://broker.example:8883")

    assert {Broker.href(broker), Broker.scheme(broker), Broker.host(broker), Broker.port(broker)} ==
             {"mqtts://broker.example:8883", :mqtts, "broker.example", 8883}

    refute inspect(broker) =~ "mqtts://"

    assert {:ok, command} =
             Command.publish(broker, :writeproperty, "things/value", %{"b" => 2, "a" => 1})

    assert {Command.packet(command), Command.qos(command), Command.retain?(command)} ==
             {:publish, 0, false}

    assert Command.content_type(command) == "application/json"
    assert Command.max_payload_bytes(command) == 1_048_576
    assert Command.payload(command) == ~s({"a":1,"b":2})
    refute inspect(command) =~ Command.payload(command)

    assert {:ok, delivery} = Delivery.new("secret-payload", topic: "things/value")

    assert {Delivery.topic(delivery), Delivery.qos(delivery), Delivery.retained?(delivery)} ==
             {"things/value", 0, false}

    refute inspect(delivery) =~ "secret-payload"

    assert {:ok, config} = TransportConfig.new(StableClient, %{secret: "client-secret"})
    assert TransportConfig.read_timeout(config) == 5_000
    assert TransportConfig.max_payload_bytes(config) == 1_048_576
    refute inspect(config) =~ "client-secret"

    assert :ok = Topic.validate_name(String.duplicate("a", 65_535))

    assert_error(
      Topic.validate_name(String.duplicate("a", 65_536)),
      :invalid_topic_name,
      :topic,
      :protocol
    )

    assert {:ok, filters} = Topic.normalize_filters(List.duplicate("things/+", 256))
    assert length(filters) == 256

    assert {:error, %Error{code: :too_many_topic_filters, details: %{max_filters: 256}}} =
             Topic.normalize_filters(List.duplicate("things/+", 257))
  end

  test "WBM-S04 freezes all seven draft-sensitive mapping rows and defaults" do
    for {operation, affordance_type, packet, target, retain} <- @rows do
      form = %{
        "href" => "mqtt://broker.example",
        "op" => Atom.to_string(operation),
        target => "things/value"
      }

      form = if operation == :readproperty, do: Map.put(form, "mqv:retain", true), else: form
      request = RequestFactory.request(operation, affordance_type: affordance_type, form: form)

      assert Mapping.default_control_packet(operation) == {:ok, packet}
      assert {:ok, command} = Mapping.command(request, 4_096)
      assert Command.packet(command) == packet
      assert Command.operation(command) == operation
      assert Command.retain?(command) == retain
      assert Command.content_type(command) == "application/json"
      assert Command.max_payload_bytes(command) == 4_096
      assert Command.qos(command) == if(packet == :unsubscribe, do: nil, else: 0)
    end
  end

  test "WBM-S05 freezes matchable error tuples while leaving messages evolvable" do
    assert_error(Broker.new(nil), :invalid_broker_href, :broker, :protocol)

    assert_error(
      Broker.new("http://broker.example"),
      :unsupported_broker_scheme,
      :broker,
      :protocol
    )

    assert_error(
      Topic.validate_filter("things/#/bad"),
      :invalid_topic_filter_wildcard,
      :topic,
      :protocol
    )

    assert_error(QoS.normalize(3), :invalid_qos, :command, :protocol)
    assert_error(JSON.decode("not-json", 100), :json_decode_failed, :codec, :protocol)
    assert_error(JSON.decode("{}", 0), :invalid_payload_limit, :codec, :permanent)

    assert_error(
      TransportConfig.new(StableClient, %{}, unknown: true),
      :invalid_transport_options,
      :configuration,
      :permanent
    )

    unsupported = RequestFactory.request(:readallproperties, affordance_type: :thing)
    assert_error(Mapping.command(unsupported, 100), :unsupported_operation, :mapping, :protocol)
  end

  test "WBM-S06 freezes supplied-client tuples, owner identity, and opaque handles" do
    assert {:ok, config} = TransportConfig.new(StableClient, %{observer: self()})
    context = RequestFactory.execution_context()

    request =
      RequestFactory.request(:observeproperty,
        form: %{
          "href" => "mqtt://broker.example",
          "op" => "observeproperty",
          "mqv:filter" => "things/+"
        }
      )

    assert Transport.subscribe(request, self(), context, config) ==
             {:ok, {:stable_handle, self()}}

    assert_receive {:stable_subscribe, command, owner, ^context}
    assert owner == self()
    assert Command.filters(command) == ["things/+"]

    assert Transport.unsubscribe({:stable_handle, self()}, unobserve_request(), context, config) ==
             :ok

    assert_receive {:stable_unsubscribe, {:stable_handle, owner}, _, ^context}
    assert owner == self()
  end

  test "WBM-S07 freezes Runtime publish/read statuses and MQTT metadata" do
    assert {:ok, config} = TransportConfig.new(StableClient, %{observer: self()})
    context = RequestFactory.execution_context()

    publish = RequestFactory.request(:writeproperty, input: %{"value" => 22})
    assert {:ok, %Result{} = publish_result} = Transport.request(publish, context, config)
    assert publish_result.status == :accepted
    assert publish_result.payload == nil

    assert publish_result.metadata == %{
             binding: :mqtt,
             control_packet: :publish,
             qos: 0,
             retain: false
           }

    assert_receive {:stable_publish, _, ^context}

    read =
      RequestFactory.request(:readproperty,
        form: %{
          "href" => "mqtt://broker.example",
          "op" => "readproperty",
          "mqv:filter" => "things/+",
          "mqv:retain" => true
        }
      )

    assert {:ok, %Result{} = read_result} = Transport.request(read, context, config)
    assert read_result.status == :ok
    assert read_result.payload == %{"value" => 21}

    assert read_result.metadata == %{
             binding: :mqtt,
             control_packet: :subscribe,
             delivery_qos: 1,
             delivery_retained: true,
             qos: 0,
             retain: true,
             topic: "things/value"
           }

    assert_receive {:stable_read, _, 5_000, ^context}
  end

  test "WBM-S08 freezes prefixed vocabulary and explicit migration seams" do
    unprefixed =
      RequestFactory.request(:writeproperty,
        form: %{
          "href" => "mqtt://broker.example",
          "op" => "writeproperty",
          "topic" => "things/value"
        }
      )

    assert_error(Mapping.command(unprefixed, 100), :missing_mqtt_target, :mapping, :protocol)

    conflicting =
      RequestFactory.request(:writeproperty,
        form: %{
          "href" => "mqtt://broker.example",
          "op" => "writeproperty",
          "mqv:controlPacket" => "subscribe",
          "mqv:topic" => "things/value"
        }
      )

    assert_error(Mapping.command(conflicting, 100), :control_packet_mismatch, :mapping, :protocol)
  end

  defp unobserve_request do
    RequestFactory.request(:unobserveproperty,
      form: %{
        "href" => "mqtt://broker.example",
        "op" => "unobserveproperty",
        "mqv:filter" => "things/+"
      }
    )
  end

  defp assert_error(result, code, phase, class) do
    assert {:error, %Error{code: ^code, phase: ^phase, class: ^class} = error} = result
    assert Error.class(error) == class
    assert is_binary(error.message)
    assert is_map(error.details)
  end
end
