defmodule Wotex.Binding.MQTT.TransportTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.MQTT.{Command, Delivery, Error, Transport, TransportConfig}
  alias Wotex.Binding.MQTT.Test.{FakeClient, RequestFactory}
  alias Wotex.Runtime.Result

  test "publishes encoded JSON through the caller-owned client port" do
    request = publish_request(%{"value" => 42})
    execution_context = RequestFactory.execution_context(:one_use_credential)
    config = config()

    assert {:ok, %Result{} = result} = Transport.request(request, execution_context, config)
    assert result.request_id == "request-1"
    assert result.operation == :writeproperty
    assert result.status == :accepted
    assert result.payload == nil
    assert result.metadata.control_packet == :publish

    assert_receive {:client_publish, command, ^execution_context, :client_state}
    assert Command.packet(command) == :publish
    assert Command.payload(command) == ~s({"value":42})
  end

  test "normalizes publish failures, invalid returns, and exceptions" do
    request = publish_request(nil)
    execution_context = RequestFactory.execution_context(:one_use_credential)

    for return <- [{:error, {:external, :one_use_credential}}, :invalid, :raise, :throw] do
      result = Transport.request(request, execution_context, config(%{publish_return: return}))
      assert {:error, %Error{} = error} = result
      refute inspect(error) =~ "one_use_credential"
    end
  end

  test "performs a bounded retained Property read and decodes JSON" do
    request = read_request()
    execution_context = RequestFactory.execution_context(:one_use_credential)
    delivery = delivery!(~s({"value":21}), "things/value", retain: true, qos: 1)

    config =
      config(%{read_return: {:ok, delivery}}, read_timeout: 275, max_payload_bytes: 100)

    assert {:ok, %Result{} = result} = Transport.request(request, execution_context, config)
    assert result.status == :ok
    assert result.payload == %{"value" => 21}
    assert result.metadata.delivery_qos == 1
    assert result.metadata.delivery_retained

    assert_receive {:client_read, command, 275, ^execution_context, :client_state}
    assert Command.packet(command) == :subscribe
    assert Command.retain?(command)
  end

  test "rejects non-retained, mismatched, malformed, and oversized read deliveries" do
    request = read_request()
    execution_context = RequestFactory.execution_context()

    cases = [
      {delivery!("null", "things/value", retain: false), :non_retained_property_read, 100},
      {delivery!("null", "other/value", retain: true), :delivery_topic_mismatch, 100},
      {delivery!("{", "things/value", retain: true), :json_decode_failed, 100},
      {delivery!(~s({"large":true}), "things/value", retain: true), :received_payload_too_large, 2}
    ]

    for {delivery, code, max_bytes} <- cases do
      transport_config = config(%{read_return: {:ok, delivery}}, max_payload_bytes: max_bytes)

      assert {:error, %Error{code: ^code}} =
               Transport.request(request, execution_context, transport_config)
    end
  end

  test "normalizes read client failures and invalid returns" do
    request = read_request()
    execution_context = RequestFactory.execution_context()

    assert {:error, %Error{code: :client_read_failed}} =
             Transport.request(
               request,
               execution_context,
               config(%{read_return: {:error, :external}})
             )

    assert {:error, %Error{code: :invalid_client_return}} =
             Transport.request(request, execution_context, config(%{read_return: :invalid}))

    assert {:error, %Error{code: :client_read_failed}} =
             Transport.request(request, execution_context, config(%{read_return: :raise}))
  end

  test "request rejects unsupported callback packets and invalid input" do
    observe = observe_request()
    execution_context = RequestFactory.execution_context()

    assert {:error, %Error{code: :unsupported_request_packet}} =
             Transport.request(observe, execution_context, config())

    assert {:error, %Error{code: :invalid_transport_input}} =
             Transport.request(:request, execution_context, config())

    assert {:error, %Error{code: :invalid_transport_input}} =
             Transport.request(publish_request(nil), :context, config())
  end

  test "classifies every failure for a consumer retry decision" do
    execution_context = RequestFactory.execution_context()
    non_retained = delivery!("null", "things/value", retain: false)

    assert {:error, %Error{code: :client_publish_failed, class: :unavailable}} =
             Transport.request(
               publish_request(nil),
               execution_context,
               config(%{publish_return: {:error, :external}})
             )

    assert {:error, %Error{code: :client_publish_failed, class: :unavailable}} =
             Transport.request(
               publish_request(nil),
               execution_context,
               config(%{publish_return: :raise})
             )

    assert {:error, %Error{code: :unsupported_request_packet, class: :protocol}} =
             Transport.request(observe_request(), execution_context, config())

    assert {:error, %Error{code: :non_retained_property_read, class: :protocol}} =
             Transport.request(
               read_request(),
               execution_context,
               config(%{read_return: {:ok, non_retained}})
             )

    assert {:error, %Error{code: :invalid_client_return, class: :protocol}} =
             Transport.request(
               read_request(),
               execution_context,
               config(%{read_return: :invalid})
             )

    assert {:error, %Error{code: :invalid_transport_input, class: :permanent}} =
             Transport.request(:request, execution_context, config())

    assert {:error, %Error{code: :invalid_transport_option, class: :permanent}} =
             TransportConfig.new(FakeClient, %{}, read_timeout: 0)
  end

  test "hands the client only the subscription owner and a credential-free command" do
    request = observe_request()
    execution_context = RequestFactory.execution_context(:one_use_credential)
    owner = self()

    assert {:ok, :client_handle} = Transport.subscribe(request, owner, execution_context, config())

    assert_receive {:client_subscribe, command, delivered_owner, ^execution_context, :client_state}
    assert delivered_owner == owner
    refute is_function(delivered_owner)
    assert Command.filters(command) == ["things/+"]
    assert Command.max_payload_bytes(command) == 1_048_576
    refute inspect({command, delivered_owner}) =~ "one_use_credential"
  end

  test "decodes an owner frame with Topic Name, QoS, and retained metadata" do
    frame = delivery!(~s({"value":34}), "things/value", qos: "2")

    assert {:ok, payload, meta} = Transport.decode_frame(frame, observe_request(), config())
    assert payload == %{"value" => 34}
    assert meta.topic == "things/value"
    assert meta.qos == 2
    refute meta.retained
    assert meta.request_id == "request-1"
    assert meta.operation == :observeproperty
    assert meta.control_packet == :subscribe
  end

  test "ignores a frame whose Topic Name matches no command Topic Filter" do
    frame = delivery!(~s({"value":34}), "other/value")

    assert :ignore = Transport.decode_frame(frame, observe_request(), config())
  end

  test "rejects malformed, oversized, and non-delivery frames" do
    request = observe_request()

    assert {:error, %Error{code: :json_decode_failed, class: :protocol}} =
             Transport.decode_frame(delivery!("{", "things/value"), request, config())

    assert {:error, %Error{code: :received_payload_too_large, class: :protocol}} =
             Transport.decode_frame(
               delivery!(~s({"value":34}), "things/value"),
               request,
               config(%{}, max_payload_bytes: 4)
             )

    assert {:error, %Error{code: :invalid_delivery, class: :protocol}} =
             Transport.decode_frame(:invalid, request, config())

    assert {:error, %Error{code: :invalid_subscription_packet, class: :protocol}} =
             Transport.decode_frame(
               delivery!("null", "things/value"),
               publish_request(nil),
               config()
             )

    assert {:error, %Error{code: :invalid_transport_input, class: :permanent}} =
             Transport.decode_frame(:frame, :request, config())
  end

  test "bounds a retained read by the remaining request deadline" do
    execution_context = RequestFactory.execution_context()
    delivery = delivery!(~s({"value":21}), "things/value", retain: true, qos: 1)
    read_config = config(%{read_return: {:ok, delivery}}, read_timeout: 5_000)

    monotonic = read_request(deadline: System.monotonic_time(:millisecond) + 40)

    assert {:ok, %Result{status: :ok}} =
             Transport.request(monotonic, execution_context, read_config)

    assert_receive {:client_read, _command, bounded, _execution_context, :client_state}
    assert bounded > 0 and bounded <= 40

    wall_clock = read_request(deadline: DateTime.add(DateTime.utc_now(), 60, :second))

    assert {:ok, %Result{status: :ok}} =
             Transport.request(wall_clock, execution_context, read_config)

    assert_receive {:client_read, _command, 5_000, _execution_context, :client_state}
  end

  test "refuses a read with no remaining deadline and rejects a mismatched clock" do
    execution_context = RequestFactory.execution_context()

    elapsed = read_request(deadline: System.monotonic_time(:millisecond) - 1)

    assert {:error, %Error{code: :deadline_exceeded, class: :timeout, phase: :client}} =
             Transport.request(elapsed, execution_context, config())

    mismatched = read_request(deadline: :soon)

    assert {:error, %Error{code: :invalid_deadline_clock, class: :permanent}} =
             Transport.request(mismatched, execution_context, config())

    refute_received {:client_read, _command, _timeout, _execution_context, _marker}
  end

  test "normalizes subscribe client returns and rejects wrong callback packets" do
    execution_context = RequestFactory.execution_context()

    assert {:error, %Error{code: :client_subscribe_failed}} =
             Transport.subscribe(
               observe_request(),
               self(),
               execution_context,
               config(%{subscribe_return: {:error, :external}})
             )

    assert {:error, %Error{code: :invalid_client_return}} =
             Transport.subscribe(
               observe_request(),
               self(),
               execution_context,
               config(%{subscribe_return: :invalid})
             )

    assert {:error, %Error{code: :client_subscribe_failed}} =
             Transport.subscribe(
               observe_request(),
               self(),
               execution_context,
               config(%{subscribe_return: :raise})
             )

    assert {:error, %Error{code: :invalid_subscription_packet}} =
             Transport.subscribe(publish_request(nil), self(), execution_context, config())

    assert {:error, %Error{code: :invalid_transport_input}} =
             Transport.subscribe(observe_request(), :not_a_pid, execution_context, config())
  end

  test "unsubscribes caller-owned handles through the client port" do
    request = stop_request()
    execution_context = RequestFactory.execution_context(:one_use_credential)

    assert :ok = Transport.unsubscribe(:client_handle, request, execution_context, config())

    assert_receive {:client_unsubscribe, :client_handle, command, ^execution_context, :client_state}
    assert Command.packet(command) == :unsubscribe
    assert Command.filters(command) == ["things/+"]
  end

  test "normalizes unsubscribe returns and rejects wrong callback packets" do
    execution_context = RequestFactory.execution_context()

    assert {:error, %Error{code: :client_unsubscribe_failed}} =
             Transport.unsubscribe(
               :handle,
               stop_request(),
               execution_context,
               config(%{unsubscribe_return: {:error, :external}})
             )

    assert {:error, %Error{code: :invalid_client_return}} =
             Transport.unsubscribe(
               :handle,
               stop_request(),
               execution_context,
               config(%{unsubscribe_return: :invalid})
             )

    assert {:error, %Error{code: :client_unsubscribe_failed}} =
             Transport.unsubscribe(
               :handle,
               stop_request(),
               execution_context,
               config(%{unsubscribe_return: :throw})
             )

    assert {:error, %Error{code: :invalid_unsubscription_packet}} =
             Transport.unsubscribe(:handle, observe_request(), execution_context, config())

    assert {:error, %Error{code: :invalid_transport_input}} =
             Transport.unsubscribe(:handle, :request, execution_context, config())
  end

  defp config(client_overrides \\ %{}, opts \\ []) do
    client_config =
      Map.merge(
        %{test_pid: self(), client_marker: :client_state},
        client_overrides
      )

    {:ok, config} = TransportConfig.new(FakeClient, client_config, opts)
    config
  end

  defp publish_request(input) do
    RequestFactory.request(:writeproperty,
      input: input,
      form: %{
        "href" => "mqtt://broker.example",
        "op" => "writeproperty",
        "mqv:qos" => "1",
        "mqv:topic" => "things/value"
      }
    )
  end

  defp read_request(opts \\ []) do
    RequestFactory.request(
      :readproperty,
      Keyword.merge(
        [
          form: %{
            "href" => "mqtt://broker.example",
            "op" => ["readproperty", "observeproperty"],
            "mqv:retain" => true,
            "mqv:filter" => "things/value"
          }
        ],
        opts
      )
    )
  end

  defp observe_request do
    RequestFactory.request(:observeproperty,
      form: %{
        "href" => "mqtt://broker.example",
        "op" => ["observeproperty", "unobserveproperty"],
        "mqv:filter" => "things/+"
      }
    )
  end

  defp stop_request do
    RequestFactory.request(:unobserveproperty,
      form: %{
        "href" => "mqtt://broker.example",
        "op" => ["observeproperty", "unobserveproperty"],
        "mqv:filter" => "things/+"
      }
    )
  end

  defp delivery!(payload, topic, opts \\ []) do
    {:ok, delivery} =
      Delivery.new(payload,
        topic: topic,
        qos: Keyword.get(opts, :qos, 0),
        retain: Keyword.get(opts, :retain, false)
      )

    delivery
  end
end
