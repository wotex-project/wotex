defmodule Wotex.Binding.MQTT.CommandTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.MQTT.{Broker, Command, Error, JSON}

  setup do
    {:ok, broker} = Broker.new("mqtts://broker.example:8883")
    %{broker: broker}
  end

  test "builds a credential-free PUBLISH command with encoded JSON", %{broker: broker} do
    assert {:ok, command} =
             Command.publish(broker, :writeproperty, "things/value", %{"value" => 42},
               qos: "1",
               retain: true,
               content_type: "Application/JSON; charset=utf-8"
             )

    assert Command.broker(command) == broker
    assert Command.packet(command) == :publish
    assert Command.operation(command) == :writeproperty
    assert Command.topic(command) == "things/value"
    assert Command.filters(command) == []
    assert Command.qos(command) == 1
    assert Command.retain?(command)
    assert Command.content_type(command) == "application/json"
    assert Command.max_payload_bytes(command) == 1_048_576
    assert {:ok, %{"value" => 42}} = JSON.decode(Command.payload(command), 100)
    refute inspect(command) =~ Command.payload(command)
  end

  test "builds SUBSCRIBE and UNSUBSCRIBE commands", %{broker: broker} do
    assert {:ok, subscribe} =
             Command.subscribe(broker, :observeproperty, ["things/+", "events/#"], qos: 2)

    assert Command.packet(subscribe) == :subscribe
    assert Command.topic(subscribe) == nil
    assert Command.filters(subscribe) == ["things/+", "events/#"]
    assert Command.qos(subscribe) == 2
    refute Command.retain?(subscribe)
    assert Command.payload(subscribe) == nil
    assert Command.max_payload_bytes(subscribe) == 1_048_576

    assert {:ok, bounded} =
             Command.subscribe(broker, :observeproperty, "things/+", max_payload_bytes: 512)

    assert Command.max_payload_bytes(bounded) == 512
    assert inspect(bounded) =~ "max_payload_bytes: 512"

    assert {:ok, unsubscribe} =
             Command.unsubscribe(broker, :unobserveproperty, "things/+", retain: true)

    assert Command.packet(unsubscribe) == :unsubscribe
    assert Command.filters(unsubscribe) == ["things/+"]
    assert Command.qos(unsubscribe) == nil
    assert Command.retain?(unsubscribe)
  end

  test "rejects invalid publish inputs", %{broker: broker} do
    assert_error(Command.publish(nil, :writeproperty, "things/value", nil), :invalid_command)
    assert_error(Command.publish(broker, :readproperty, "things/value", nil), :invalid_command)

    assert_error(
      Command.publish(broker, :writeproperty, "things/+", nil),
      :topic_name_contains_wildcard
    )

    assert_error(Command.publish(broker, :writeproperty, "things/value", nil, qos: 4), :invalid_qos)

    assert_error(
      Command.publish(broker, :writeproperty, "things/value", nil, retain: :yes),
      :invalid_retain
    )

    assert_error(
      Command.publish(broker, :writeproperty, "things/value", nil, max_payload_bytes: 0),
      :invalid_payload_limit
    )

    assert_error(
      Command.publish(broker, :writeproperty, "things/value", nil, content_type: "text/plain"),
      :unsupported_content_type
    )

    assert_error(
      Command.publish(broker, :writeproperty, "things/value", self()),
      :json_encode_failed
    )

    assert_error(
      Command.publish(broker, :writeproperty, "things/value", "large", max_payload_bytes: 2),
      :encoded_payload_too_large
    )

    assert_error(
      Command.publish(broker, :writeproperty, "things/value", nil, :not_options),
      :invalid_command
    )
  end

  test "rejects invalid subscription inputs", %{broker: broker} do
    assert_error(Command.subscribe(nil, :observeproperty, "things/#"), :invalid_command)
    assert_error(Command.subscribe(broker, :writeproperty, "things/#"), :invalid_command)
    assert_error(Command.subscribe(broker, :observeproperty, []), :invalid_topic_filters)

    assert_error(
      Command.subscribe(broker, :observeproperty, "things/#", content_type: nil),
      :unsupported_content_type
    )

    assert_error(
      Command.subscribe(broker, :observeproperty, "things/#", retain: :yes),
      :invalid_retain
    )

    assert_error(
      Command.subscribe(broker, :observeproperty, "things/#", max_payload_bytes: 0),
      :invalid_payload_limit
    )
  end

  test "rejects invalid unsubscription inputs", %{broker: broker} do
    assert_error(Command.unsubscribe(nil, :unobserveproperty, "things/#"), :invalid_command)
    assert_error(Command.unsubscribe(broker, :observeproperty, "things/#"), :invalid_command)
    assert_error(Command.unsubscribe(broker, :unobserveproperty, []), :invalid_topic_filters)

    assert_error(
      Command.unsubscribe(broker, :unobserveproperty, "things/#", retain: :yes),
      :invalid_retain
    )

    assert_error(
      Command.unsubscribe(broker, :unobserveproperty, "things/#", max_payload_bytes: :all),
      :invalid_payload_limit
    )
  end

  defp assert_error(result, code) do
    assert {:error, %Error{code: ^code}} = result
  end
end
