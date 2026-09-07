defmodule Wotex.Binding.MQTT.MappingTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.MQTT.{Command, Error, Mapping}
  alias Wotex.Binding.MQTT.Test.RequestFactory

  test "provides the editor-draft default Control Packet mappings" do
    for operation <- [:readproperty, :observeproperty, :subscribeevent] do
      assert {:ok, :subscribe} = Mapping.default_control_packet(operation)
    end

    for operation <- [:writeproperty, :invokeaction] do
      assert {:ok, :publish} = Mapping.default_control_packet(operation)
    end

    for operation <- [:unobserveproperty, :unsubscribeevent] do
      assert {:ok, :unsubscribe} = Mapping.default_control_packet(operation)
    end

    assert_error(Mapping.default_control_packet(:queryaction), :unsupported_operation)
  end

  test "maps publish terms and normalizes string QoS" do
    request =
      RequestFactory.request(:invokeaction,
        affordance_type: :action,
        input: %{"mode" => "safe"},
        form: %{
          "href" => "mqtts://broker.example:8883",
          "op" => "invokeaction",
          "contentType" => "application/json; charset=utf-8",
          "mqv:controlPacket" => "publish",
          "mqv:qos" => "2",
          "mqv:retain" => false,
          "mqv:topic" => "things/actions/mode"
        }
      )

    assert {:ok, command} = Mapping.command(request, 1_000)
    assert Command.packet(command) == :publish
    assert Command.operation(command) == :invokeaction
    assert Command.topic(command) == "things/actions/mode"
    assert Command.qos(command) == 2
  end

  test "maps retained Property reads to subscribe commands" do
    request =
      RequestFactory.request(:readproperty,
        form: %{
          "href" => "mqtt://broker.example",
          "op" => ["readproperty", "observeproperty"],
          "mqv:retain" => true,
          "mqv:qos" => 1,
          "mqv:filter" => "things/properties/value"
        }
      )

    assert {:ok, command} = Mapping.command(request, 100)
    assert Command.packet(command) == :subscribe
    assert Command.filters(command) == ["things/properties/value"]
    assert Command.retain?(command)
  end

  test "maps observation and stop operations using dedicated filters" do
    observe =
      RequestFactory.request(:subscribeevent,
        affordance_type: :event,
        form: %{
          "href" => "mqtt://broker.example/",
          "op" => "subscribeevent",
          "mqv:filter" => ["things/events/+", "things/alerts/#"]
        }
      )

    stop =
      RequestFactory.request(:unsubscribeevent,
        affordance_type: :event,
        form: %{
          "href" => "mqtt://broker.example/",
          "op" => "unsubscribeevent",
          "mqv:controlPacket" => "unsubscribe",
          "mqv:qos" => "0",
          "mqv:filter" => "things/events/+"
        }
      )

    assert {:ok, subscribe} = Mapping.command(observe, 100)
    assert Command.packet(subscribe) == :subscribe
    assert Command.filters(subscribe) == ["things/events/+", "things/alerts/#"]
    assert Command.max_payload_bytes(subscribe) == 100

    assert {:ok, unsubscribe} = Mapping.command(stop, 100)
    assert Command.packet(unsubscribe) == :unsubscribe
    assert Command.qos(unsubscribe) == nil
    assert Command.max_payload_bytes(unsubscribe) == 100
  end

  test "requires retained semantics for readproperty" do
    request =
      RequestFactory.request(:readproperty,
        form: %{
          "href" => "mqtt://broker.example",
          "op" => "readproperty",
          "mqv:filter" => "things/value"
        }
      )

    assert_error(Mapping.command(request, 100), :retained_read_required)
  end

  test "rejects href targets and mixed or missing target terms" do
    path_request =
      RequestFactory.request(:writeproperty,
        resolved_href: "mqtt://broker.example/things/value",
        form: %{
          "href" => "mqtt://broker.example/things/value",
          "op" => "writeproperty",
          "mqv:topic" => "things/value"
        }
      )

    assert_error(Mapping.command(path_request, 100), :broker_href_not_endpoint_only)

    missing =
      RequestFactory.request(:writeproperty,
        form: %{"href" => "mqtt://broker.example", "op" => "writeproperty"}
      )

    assert_error(Mapping.command(missing, 100), :missing_mqtt_target)

    mixed =
      RequestFactory.request(:writeproperty,
        form: %{
          "href" => "mqtt://broker.example",
          "op" => "writeproperty",
          "mqv:topic" => "things/value",
          "mqv:filter" => "things/value"
        }
      )

    assert_error(Mapping.command(mixed, 100), :mixed_mqtt_targets)
  end

  test "rejects explicit Control Packet conflicts and invalid terms" do
    conflict =
      RequestFactory.request(:writeproperty,
        form: %{
          "href" => "mqtt://broker.example",
          "op" => "writeproperty",
          "mqv:controlPacket" => "subscribe",
          "mqv:topic" => "things/value"
        }
      )

    invalid =
      RequestFactory.request(:writeproperty,
        form: %{
          "href" => "mqtt://broker.example",
          "op" => "writeproperty",
          "mqv:controlPacket" => 3,
          "mqv:topic" => "things/value"
        }
      )

    assert_error(Mapping.command(conflict, 100), :control_packet_mismatch)
    assert_error(Mapping.command(invalid, 100), :control_packet_mismatch)
  end

  test "rejects invalid mapping input, filters, content types, and unsubscribe QoS" do
    assert_error(Mapping.command(:request, 100), :invalid_mapping_input)
    assert_error(Mapping.command(RequestFactory.request(:writeproperty), 0), :invalid_mapping_input)

    invalid_filter =
      RequestFactory.request(:observeproperty,
        form: %{
          "href" => "mqtt://broker.example",
          "op" => "observeproperty",
          "mqv:filter" => "things/value+"
        }
      )

    assert_error(Mapping.command(invalid_filter, 100), :invalid_topic_filter_wildcard)

    invalid_content =
      RequestFactory.request(:writeproperty,
        form: %{
          "href" => "mqtt://broker.example",
          "op" => "writeproperty",
          "contentType" => "text/plain",
          "mqv:topic" => "things/value"
        }
      )

    assert_error(Mapping.command(invalid_content, 100), :unsupported_content_type)

    invalid_qos =
      RequestFactory.request(:unobserveproperty,
        form: %{
          "href" => "mqtt://broker.example",
          "op" => "unobserveproperty",
          "mqv:qos" => "3",
          "mqv:filter" => "things/value"
        }
      )

    assert_error(Mapping.command(invalid_qos, 100), :invalid_qos)
  end

  defp assert_error(result, code) do
    assert {:error, %Error{code: ^code}} = result
  end
end
