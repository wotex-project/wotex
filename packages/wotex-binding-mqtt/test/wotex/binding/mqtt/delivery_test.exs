defmodule Wotex.Binding.MQTT.DeliveryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.MQTT.{Delivery, Error}

  test "builds an immutable delivery without exposing its payload in inspection" do
    assert {:ok, delivery} =
             Delivery.new(~s({"value":42}), topic: "things/value", qos: "2", retain: true)

    assert Delivery.payload(delivery) == ~s({"value":42})
    assert Delivery.topic(delivery) == "things/value"
    assert Delivery.qos(delivery) == 2
    assert Delivery.retained?(delivery)
    refute inspect(delivery) =~ ~s({"value":42})
  end

  test "rejects invalid delivery input and metadata" do
    assert {:error, %Error{code: :invalid_delivery}} = Delivery.new(:payload, [])
    assert {:error, %Error{code: :invalid_delivery}} = Delivery.new("{}", :options)
    assert {:error, %Error{code: :invalid_topic_name}} = Delivery.new("{}", topic: nil)
    assert {:error, %Error{code: :invalid_qos}} = Delivery.new("{}", topic: "things/value", qos: 3)

    assert {:error, %Error{code: :invalid_delivery_retain}} =
             Delivery.new("{}", topic: "things/value", retain: :yes)
  end

  test "normalizes only complete deliveries that preserve constructor validation" do
    {:ok, delivery} = Delivery.new("private-canary", topic: "things/value", qos: 1)
    assert {:ok, ^delivery} = Delivery.normalize(delivery)

    for invalid <- [
          Map.put(delivery, :qos, "1"),
          Map.put(delivery, :retain, nil),
          Map.put(delivery, :payload, :not_bytes),
          Map.put(delivery, :topic, "things/+"),
          Map.put(delivery, :extra, :field),
          Map.delete(delivery, :payload)
        ] do
      assert {:error, %Error{code: :invalid_delivery} = error} = Delivery.normalize(invalid)
      refute inspect(error) =~ "private-canary"
    end
  end
end
