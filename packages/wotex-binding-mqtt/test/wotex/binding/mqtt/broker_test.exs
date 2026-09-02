defmodule Wotex.Binding.MQTT.BrokerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.MQTT.{Broker, Error}

  test "builds broker-only mqtt and mqtts values" do
    assert {:ok, mqtt} = Broker.new("mqtt://broker.example:1883")
    assert Broker.href(mqtt) == "mqtt://broker.example:1883"
    assert Broker.scheme(mqtt) == :mqtt
    assert Broker.host(mqtt) == "broker.example"
    assert Broker.port(mqtt) == 1883

    assert {:ok, mqtts} = Broker.new("MQTTS://secure.example/")
    assert Broker.scheme(mqtts) == :mqtts
    assert Broker.port(mqtts) == nil
    assert inspect(mqtts) =~ "host: \"secure.example\""
  end

  test "rejects non-string, empty, padded, and malformed href values" do
    assert_error(Broker.new(nil), :invalid_broker_href)
    assert_error(Broker.new(""), :invalid_broker_href)
    assert_error(Broker.new(" mqtt://broker.example"), :invalid_broker_href)
    assert_error(Broker.new("mqtt://broker.example:bad"), :invalid_broker_port)
  end

  test "rejects unsupported schemes and missing hosts" do
    assert_error(Broker.new("http://broker.example"), :unsupported_broker_scheme)
    assert_error(Broker.new("mqtt:topic"), :missing_broker_host)
  end

  test "rejects user information, targets, queries, and fragments" do
    assert_error(Broker.new("mqtt://user@broker.example"), :broker_credentials_forbidden)
    assert_error(Broker.new("mqtt://broker.example/things/value"), :broker_href_not_endpoint_only)
    assert_error(Broker.new("mqtt://broker.example?topic=value"), :broker_href_not_endpoint_only)
    assert_error(Broker.new("mqtt://broker.example#filter"), :broker_href_not_endpoint_only)
  end

  defp assert_error(result, code) do
    assert {:error, %Error{code: ^code, phase: :broker}} = result
  end
end
