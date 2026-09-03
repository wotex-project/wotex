defmodule Wotex.Binding.HTTP.IntegrationTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Binding.HTTP
  alias Wotex.Binding.HTTP.{Notification, Request}
  alias Wotex.Binding.HTTP.SSE.Event
  alias Wotex.Binding.HTTP.Test.{Factory, FakeClient, FakeCredentials}
  alias Wotex.Runtime.{ConsumedThing, Context, Result, Subscription}

  test "ConsumedThing executes a one-shot interaction through the HTTP binding" do
    response = Factory.response(200, "21", [{"Content-Type", "application/json"}])
    consumed = consumed_thing(%{request_return: {:ok, response}})
    context = Context.new!(request_id: "integration-request")

    assert {:ok, %Result{payload: 21, operation: :readproperty}} =
             ConsumedThing.read_property(consumed, "temperature", context)

    assert_receive {:credential_resolve, %{names: ["nosec"]}, %Wotex.Form{}, ^context}
    assert_receive {:client_request, %Request{} = request, :resolved_credential}
    assert Request.uri(request) == "https://thing.example/properties/temperature"
  end

  test "caller-supervised observation opens and explicitly closes one SSE connection" do
    handshake = Factory.response(200, "", [{"Content-Type", "text/event-stream"}])
    consumed = consumed_thing(%{subscribe_return: {:ok, :integration_handle, handshake}})
    context = Context.new!(request_id: "stream-request")

    assert {:ok, child_spec} =
             ConsumedThing.observation_child_spec(consumed, "temperature", context,
               id: :temperature_observation,
               receiver: self(),
               restart: :temporary
             )

    pid = start_supervised!(child_spec)

    assert_receive {:client_subscribe, %Request{} = request, :resolved_credential, handler}
    assert Request.uri(request) == "https://thing.example/properties/temperature"

    {:ok, event} = Event.new("22", event: "temperature", id: "event-22")
    assert :ok = handler.(event)

    assert_receive {:wotex_runtime, :temperature_observation, notification_result}
    assert {:ok, %Notification{} = notification} = notification_result

    assert Notification.data(notification) == 22
    assert Notification.id(notification) == "event-22"

    assert :ok = Subscription.stop(pid)
    assert_receive {:client_close, :integration_handle}
    refute Process.alive?(pid)
  end

  defp consumed_thing(client_overrides) do
    {:ok, profile} = HTTP.profile()

    client_config =
      Map.merge(
        %{
          owner: self(),
          request_return: {:error, :not_configured},
          subscribe_return: {:error, :not_configured},
          close_return: :ok
        },
        client_overrides
      )

    {:ok, config} = HTTP.config(client: {FakeClient, client_config})

    credentials =
      {FakeCredentials, %{owner: self(), credential: :resolved_credential}}

    {:ok, consumed} =
      ConsumedThing.new(thing_description(),
        profiles: [profile],
        transports: %{http: HTTP.transport(config)},
        credentials: credentials
      )

    consumed
  end

  defp thing_description do
    {:ok, td} =
      Wotex.ThingDescription.from_map(%{
        "@context" => Wotex.td_context_1_1(),
        "id" => "urn:example:thing:1",
        "title" => "Example Thing",
        "base" => "https://thing.example/",
        "securityDefinitions" => %{"nosec" => %{"scheme" => "nosec"}},
        "security" => ["nosec"],
        "properties" => %{
          "temperature" => %{
            "type" => "number",
            "observable" => true,
            "forms" => [
              %{
                "href" => "properties/temperature",
                "contentType" => "application/json",
                "op" => "readproperty"
              },
              %{
                "href" => "properties/temperature",
                "contentType" => "application/json",
                "subprotocol" => "sse",
                "op" => "observeproperty"
              },
              %{
                "href" => "properties/temperature",
                "contentType" => "application/json",
                "subprotocol" => "sse",
                "op" => "unobserveproperty"
              }
            ]
          }
        }
      })

    td
  end
end
