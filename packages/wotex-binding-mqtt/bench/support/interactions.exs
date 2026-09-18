defmodule Wotex.Binding.MQTT.Bench.Interactions do
  @moduledoc false

  # Runtime requests selected from one synthetic Thing Description with MQTT
  # Forms, JSON payloads of growing size, retained deliveries and
  # configurations around the in-memory client. Identifiers use reserved
  # example domains.

  alias Wotex.Binding.MQTT
  alias Wotex.Binding.MQTT.Bench.Client
  alias Wotex.Binding.MQTT.{Delivery, JSON, TransportConfig}
  alias Wotex.Runtime.{Context, ExecutionContext, FormSelector, Request}
  alias Wotex.ThingDescription

  @max_bytes 1_048_576
  @state_topic "things/bench/properties/state"

  @spec sizes() :: [{String.t(), pos_integer()}]
  def sizes, do: [{"1 member", 1}, {"16 members", 16}, {"256 members", 256}]

  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @spec state_topic() :: String.t()
  def state_topic, do: @state_topic

  @spec payload(pos_integer()) :: map()
  def payload(count) do
    Map.new(1..count, fn index ->
      {"sensor-#{String.pad_leading(Integer.to_string(index), 3, "0")}",
       %{"value" => 20.0 + index / 10, "unit" => "Cel", "valid" => true}}
    end)
  end

  @spec json(JSON.json_value()) :: binary()
  def json(value) do
    {:ok, json} = JSON.encode(value, @max_bytes)
    json
  end

  @spec delivery(binary(), keyword()) :: Delivery.t()
  def delivery(payload, options \\ []) do
    {:ok, delivery} =
      Delivery.new(payload, Keyword.merge([topic: @state_topic, qos: 1, retain: true], options))

    delivery
  end

  @spec request(Wotex.Runtime.interaction_type(), String.t(), atom(), term(), keyword()) ::
          Request.t()
  def request(type, name, operation, input, context_options \\ []) do
    {:ok, selection} =
      FormSelector.select(thing_description(), type, name, operation, [MQTT.profile()])

    context = Context.new!(Keyword.merge([request_id: "bench-request-1"], context_options))
    Request.from_selection(selection, context, input)
  end

  @spec execution_context() :: ExecutionContext.t()
  def execution_context do
    ExecutionContext.new(Context.new!(request_id: "bench-request-1"), nil)
  end

  @spec config(map(), keyword()) :: TransportConfig.t()
  def config(replies, options \\ []) do
    {:ok, config} = TransportConfig.new(Client, replies, options)
    config
  end

  defp thing_description do
    broker = "mqtts://broker.example:8883"

    {:ok, td} =
      ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:example:thing:mqtt-bench",
        "title" => "MQTT benchmark Thing",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{
          "state" => %{
            "type" => "object",
            "observable" => true,
            "forms" => [
              %{
                "href" => broker,
                "op" => "readproperty",
                "contentType" => "application/json",
                "mqv:retain" => true,
                "mqv:qos" => "1",
                "mqv:filter" => @state_topic
              },
              %{
                "href" => broker,
                "op" => ["observeproperty", "unobserveproperty"],
                "contentType" => "application/json",
                "mqv:qos" => "1",
                "mqv:filter" => "things/+/properties/state"
              },
              %{
                "href" => broker,
                "op" => "writeproperty",
                "contentType" => "application/json",
                "mqv:qos" => "1",
                "mqv:topic" => @state_topic <> "/set"
              }
            ]
          }
        }
      })

    td
  end
end
