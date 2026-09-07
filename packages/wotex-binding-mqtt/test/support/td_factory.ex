defmodule Wotex.Binding.MQTT.Test.TDFactory do
  @moduledoc false

  alias Wotex.ThingDescription

  @spec thing_description() :: ThingDescription.t()
  def thing_description do
    {:ok, td} =
      ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:example:sensor:1",
        "title" => "Example Sensor",
        "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
        "security" => ["nosec_sc"],
        "properties" => %{
          "temperature" => %{
            "type" => "number",
            "observable" => true,
            "forms" => [
              %{
                "href" => "mqtt://broker.example",
                "contentType" => "application/json",
                "op" => ["observeproperty", "unobserveproperty"],
                "mqv:qos" => "1",
                "mqv:filter" => "things/properties/+"
              }
            ]
          }
        }
      })

    td
  end
end
