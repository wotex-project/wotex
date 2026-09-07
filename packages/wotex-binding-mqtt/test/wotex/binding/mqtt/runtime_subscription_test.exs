defmodule Wotex.Binding.MQTT.RuntimeSubscriptionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.MQTT
  alias Wotex.Binding.MQTT.{Delivery, Transport, TransportConfig}
  alias Wotex.Binding.MQTT.Test.{FakeClient, FakeCredentials, TDFactory}
  alias Wotex.Runtime.{ConsumedThing, Context, Error, Subscription}

  test "an observation decodes deliveries in the owner and reports the Topic Name" do
    owner = start_observation(:temperature, "observation-decode")
    assert_receive {:client_subscribe, _command, ^owner, _execution_context, :client_state}

    send(owner, {:wotex_transport_frame, delivery!(~s({"value":21}), "things/properties/inside")})

    assert_receive {:wotex_runtime, :temperature,
                    {:ok, %{"value" => 21},
                     %{
                       topic: "things/properties/inside",
                       qos: 0,
                       retained: false,
                       request_id: "observation-decode",
                       operation: :observeproperty
                     }}}

    send(owner, {:wotex_transport_frame, delivery!(~s({"value":22}), "things/properties/outside")})

    assert_receive {:wotex_runtime, :temperature,
                    {:ok, %{"value" => 22}, %{topic: "things/properties/outside"}}}

    assert :ok = Subscription.stop(owner)
    assert_receive {:client_unsubscribe, :client_handle, _command, _context, :client_state}
  end

  test "an unrelated Topic Name from a shared connection is ignored" do
    owner = start_observation(:ignored, "observation-ignore")
    assert_receive {:client_subscribe, _command, ^owner, _execution_context, :client_state}

    send(owner, {:wotex_transport_frame, delivery!("null", "other/thing/value")})
    refute_receive {:wotex_runtime, :ignored, _event}, 50
    assert Process.alive?(owner)
  end

  test "an oversized Application Message becomes a classified undecodable frame" do
    owner = start_observation(:oversized, "observation-oversized", max_payload_bytes: 4)
    assert_receive {:client_subscribe, _command, ^owner, _execution_context, :client_state}

    send(owner, {:wotex_transport_frame, delivery!(~s({"value":21}), "things/properties/inside")})

    assert_receive {:wotex_runtime, :oversized,
                    {:error,
                     %Error{
                       code: :undecodable_frame,
                       class: :protocol,
                       details: %{cause: %{code: :received_payload_too_large, class: :protocol}}
                     }}}

    assert Process.alive?(owner)
  end

  test "a lost MQTT Session stops the owner after unsubscription" do
    owner = start_observation(:session, "observation-session")
    assert_receive {:client_subscribe, _command, ^owner, _execution_context, :client_state}
    monitor = Process.monitor(owner)

    send(owner, {:wotex_transport_status, :reconnected})
    assert_receive {:wotex_runtime, :session, {:status, :reconnected}}
    assert Process.alive?(owner)

    send(owner, {:wotex_transport_status, :session_lost})
    assert_receive {:wotex_runtime, :session, {:status, :session_lost}}
    assert_receive {:client_unsubscribe, :client_handle, _command, _context, :client_state}
    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, :session_lost}}
  end

  test "a client that monitors the owner observes an explicit stop" do
    owner = start_observation(:watched, "observation-watch", [], %{watch_owner: true})
    assert_receive {:client_subscribe, _command, ^owner, _execution_context, :client_state}

    assert :ok = Subscription.stop(owner)
    assert_receive {:owner_down, :normal}
  end

  defp start_observation(id, request_id, opts \\ [], client_overrides \\ %{}) do
    client_config =
      Map.merge(%{test_pid: self(), client_marker: :client_state}, client_overrides)

    {:ok, transport_config} = TransportConfig.new(FakeClient, client_config, opts)

    {:ok, consumed} =
      ConsumedThing.new(TDFactory.thing_description(),
        profiles: [MQTT.profile()],
        transports: %{mqtt: {Transport, transport_config}},
        credentials: {FakeCredentials, %{test_pid: self()}}
      )

    {:ok, spec} =
      ConsumedThing.observation_child_spec(
        consumed,
        "temperature",
        Context.new!(request_id: request_id),
        id: id,
        receiver: self(),
        restart: :temporary
      )

    start_supervised!(spec)
  end

  defp delivery!(payload, topic) do
    {:ok, delivery} = Delivery.new(payload, topic: topic, qos: 0, retain: false)
    delivery
  end
end
