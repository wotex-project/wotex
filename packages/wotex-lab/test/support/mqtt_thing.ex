defmodule Wotex.Lab.Test.MqttThing do
  @moduledoc false

  # A Thing Description for the disposable MQTT broker. Every Form uses the
  # run's own topic prefix, so two Things on one broker never share topics.

  alias Wotex.ThingDescription

  @spec thing_description(String.t(), String.t(), keyword()) :: ThingDescription.t()
  def thing_description(href, prefix, opts \\ []) do
    scheme = Keyword.get(opts, :security, "nosec_sc")
    qos = Keyword.get(opts, :qos, 1)

    map = %{
      "@context" => Wotex.td_context_1_1(),
      "id" => "urn:wotex:lab:mqtt:room",
      "title" => "MQTT room",
      "security" => [scheme],
      "securityDefinitions" => %{
        "nosec_sc" => %{"scheme" => "nosec"},
        "basic_sc" => %{"scheme" => "basic", "in" => "header"}
      },
      "properties" => %{
        "temperature" => %{
          "type" => "number",
          "observable" => true,
          "forms" => [
            read(href, "#{prefix}/properties/temperature", qos),
            observe(href, "#{prefix}/properties/temperature", qos)
          ]
        },
        "missing" => %{
          "type" => "number",
          "forms" => [read(href, "#{prefix}/properties/missing", qos)]
        },
        "target" => %{
          "type" => "number",
          "forms" => [write(href, "#{prefix}/properties/target", qos)]
        },
        "shared" => %{
          "type" => "number",
          "observable" => true,
          "forms" => [observe(href, "$share/lab/#{prefix}/properties/shared", qos)]
        },
        "system" => %{
          "type" => "number",
          "observable" => true,
          "forms" => [observe(href, "$SYS/broker/clients/connected", 0)]
        }
      },
      "actions" => %{
        "setTarget" => %{
          "input" => %{"type" => "number"},
          "forms" => [
            %{
              "href" => href,
              "contentType" => "application/json",
              "op" => "invokeaction",
              "mqv:topic" => "#{prefix}/actions/set-target",
              "mqv:qos" => qos
            }
          ]
        }
      }
    }

    {:ok, td} = ThingDescription.from_map(map)
    td
  end

  defp read(href, filter, qos) do
    %{
      "href" => href,
      "contentType" => "application/json",
      "op" => "readproperty",
      "mqv:filter" => filter,
      "mqv:retain" => true,
      "mqv:qos" => qos
    }
  end

  defp observe(href, filter, qos) do
    %{
      "href" => href,
      "contentType" => "application/json",
      "op" => ["observeproperty", "unobserveproperty"],
      "mqv:filter" => filter,
      "mqv:qos" => qos
    }
  end

  defp write(href, topic, qos) do
    %{
      "href" => href,
      "contentType" => "application/json",
      "op" => "writeproperty",
      "mqv:topic" => topic,
      "mqv:qos" => qos
    }
  end
end
