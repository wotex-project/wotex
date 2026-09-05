defmodule Wotex.Runtime.Test.TDFactory do
  @moduledoc false

  alias Wotex.Runtime.BindingProfile
  alias Wotex.ThingDescription

  @spec thing_description(map()) :: ThingDescription.t()
  def thing_description(overrides \\ %{}) do
    map =
      Map.merge(
        %{
          "@context" => Wotex.td_context_1_1(),
          "id" => "urn:example:machine:1",
          "title" => "Example Machine",
          "base" => "https://example.test/machines/1/",
          "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
          "security" => ["nosec_sc"],
          "forms" => [
            %{
              "href" => "interactions",
              "contentType" => "application/json",
              "op" => Enum.map(Wotex.Runtime.thing_operations(), &Atom.to_string/1)
            }
          ],
          "properties" => %{
            "temperature" => %{
              "type" => "number",
              "observable" => true,
              "forms" => [
                %{
                  "href" => "properties/temperature",
                  "contentType" => "application/json; charset=utf-8",
                  "op" => [
                    "readproperty",
                    "writeproperty",
                    "observeproperty",
                    "unobserveproperty"
                  ]
                },
                %{
                  "href" => "mqtt://broker.example.test/machine/temperature",
                  "contentType" => "application/json",
                  "op" => ["readproperty", "observeproperty", "unobserveproperty"]
                }
              ]
            }
          },
          "actions" => %{
            "calibrate" => %{
              "input" => %{"type" => "number"},
              "forms" => [
                %{
                  "href" => "actions/calibrate",
                  "contentType" => "application/json",
                  "op" => ["invokeaction", "queryaction", "cancelaction"]
                }
              ]
            }
          },
          "events" => %{
            "alarm" => %{
              "data" => %{"type" => "string"},
              "forms" => [
                %{
                  "href" => "events/alarm",
                  "contentType" => "application/json",
                  "op" => ["subscribeevent", "unsubscribeevent"]
                }
              ]
            }
          }
        },
        overrides
      )

    {:ok, td} = ThingDescription.from_map(map)
    td
  end

  @spec http_profile(keyword()) :: BindingProfile.t()
  def http_profile(opts \\ []) do
    {:ok, profile} =
      BindingProfile.new(
        Keyword.merge(
          [
            id: :http,
            schemes: ["http", "https"],
            operations: Wotex.Runtime.operations(),
            media_types: ["application/json"]
          ],
          opts
        )
      )

    profile
  end

  @spec mqtt_profile(keyword()) :: BindingProfile.t()
  def mqtt_profile(opts \\ []) do
    {:ok, profile} =
      BindingProfile.new(
        Keyword.merge(
          [
            id: :mqtt,
            schemes: ["mqtt", "mqtts"],
            operations: Wotex.Runtime.operations(),
            media_types: ["application/json"]
          ],
          opts
        )
      )

    profile
  end
end
