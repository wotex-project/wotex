defmodule Wotex.Lab.MqttTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.MQTT
  alias Wotex.Binding.MQTT.{Broker, Command, Transport, TransportConfig}
  alias Wotex.Lab
  alias Wotex.Lab.Adapters.MQTT.{EmqttClient, Session}
  alias Wotex.Lab.Adapters.Runtime.{NoSec, StaticRef}
  alias Wotex.Lab.Error, as: LabError
  alias Wotex.Lab.Test.{MqttServer, MqttThing}
  alias Wotex.Runtime.{ConsumedThing, Context, Error, ExecutionContext, Subscription}

  @password "broker-password-4c1a"
  @user "lab-consumer"
  @reference "vault://lab/mqtt"
  @closed "mqtt://127.0.0.1:1"

  @moduletag capture_log: true

  setup do
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:wotex, :runtime, :subscription, :open],
        &__MODULE__.subscription_opened/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  @doc false
  def subscription_opened(_event, _measurements, %{request_id: "mqtt-scripted"}, receiver),
    do: send(receiver, {:runtime_subscription_opened, self()})

  def subscription_opened(_event, _measurements, _metadata, _receiver), do: :ok

  test "an unreachable broker refuses a publish, a retained read and a subscription" do
    context = execution_context(nil)
    config = %{connect_timeout: 1_000}

    assert {:error, %LabError{code: :mqtt_connect_refused, class: :unavailable}} =
             EmqttClient.publish(publish_command(@closed), context, config)

    assert {:error, %LabError{code: :mqtt_connect_refused}} =
             EmqttClient.read(read_command(@closed), 1_000, context, config)

    assert {:error, %LabError{code: :mqtt_connect_refused}} =
             EmqttClient.subscribe(read_command(@closed), self(), context, config)

    refute_receive {:wotex_transport_frame, _delivery}, 10
  end

  test "an unreachable broker classifies runtime reads, writes and subscriptions" do
    consumed = consumed_thing(@closed)
    context = Context.new!(request_id: "mqtt-unreachable")

    assert {:error, %Error{code: :transport_request_failed, class: :unavailable} = read} =
             ConsumedThing.read_property(consumed, "temperature", context)

    assert read.details.cause.code == :client_read_failed

    assert {:error, %Error{code: :transport_request_failed} = write} =
             ConsumedThing.write_property(consumed, "target", 21.0, context)

    assert write.details.cause.code == :client_publish_failed

    lab = start_supervised!({Lab, id: "mqtt-unreachable", max_children: 4})

    {:ok, spec} =
      ConsumedThing.observation_child_spec(consumed, "temperature", context,
        id: :closed,
        receiver: self(),
        restart: :temporary
      )

    {:ok, pid} = Lab.start_child(lab, :sessions, spec)
    monitor = Process.monitor(pid)

    assert_receive {:wotex_runtime, :closed,
                    {:error, %Error{code: :transport_subscribe_failed} = error}},
                   5_000

    assert error.details.cause.code == :client_subscribe_failed
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, %Error{}}}, 5_000
  end

  test "a silent broker socket bounds the subscription handshake and the read budget" do
    port = silent_broker()
    href = "mqtt://127.0.0.1:#{port}"
    context = execution_context(nil)

    assert {:error, %LabError{code: :mqtt_subscribe_timeout, class: :timeout}} =
             EmqttClient.subscribe(read_command(href), self(), context, %{connect_timeout: 200})

    assert {:error, %LabError{code: :mqtt_timeout, class: :timeout}} =
             EmqttClient.read(read_command(href), 200, context, %{connect_timeout: 5_000})
  end

  test "credentials build the CONNECT packet and unsupported material never connects" do
    config = %{connect_timeout: 1_000}
    command = publish_command(@closed)

    assert {:error, %LabError{code: :mqtt_connect_refused}} =
             EmqttClient.publish(command, execution_context({:password, "lab", @password}), config)

    assert {:error, %LabError{code: :mqtt_connect_refused}} =
             EmqttClient.publish(
               command,
               execution_context(%{"basic_sc" => {:password, "lab", @password}}),
               config
             )

    assert {:error, %LabError{code: :unsupported_credential, class: :permanent} = error} =
             EmqttClient.publish(command, execution_context({:bearer, @password}), config)

    assert {:error, %LabError{code: :unsupported_credential}} =
             EmqttClient.publish(
               command,
               execution_context(%{"basic_sc" => {:bearer, @password}}),
               config
             )

    refute inspect(error) =~ @password
  end

  test "an unadmitted broker host, an alien handle and a dead session need no connection" do
    context = execution_context(nil)
    config = %{host: "broker.invalid", connect_timeout: 1_000}

    assert {:error, %LabError{code: :broker_host_not_admitted, class: :permanent}} =
             EmqttClient.publish(publish_command(@closed), context, config)

    assert {:error, %LabError{code: :invalid_handle, class: :permanent}} =
             EmqttClient.unsubscribe(:not_a_session, read_command(@closed), context, %{})

    dead = spawn(fn -> :ok end)
    ref = Process.monitor(dead)
    assert_receive {:DOWN, ^ref, :process, ^dead, _reason}
    assert :ok = EmqttClient.unsubscribe(dead, read_command(@closed), context, %{})
    assert :ok = Session.close(dead)
  end

  test "an exhausted deadline spends no time on the broker and keeps the budget positive" do
    command = publish_command(@closed)
    port = silent_broker()

    expired =
      execution_context(nil, Context.new!(request_id: "mqtt-late", deadline: expired_deadline()))

    assert {:error, %LabError{code: :mqtt_timeout, class: :timeout}} =
             EmqttClient.publish(silent_publish_command(port), expired, %{connect_timeout: 5_000})

    soon =
      execution_context(
        nil,
        Context.new!(
          request_id: "mqtt-soon",
          deadline: System.monotonic_time(:millisecond) + 1_000
        )
      )

    assert {:error, %LabError{code: :mqtt_connect_refused}} =
             EmqttClient.publish(command, soon, %{connect_timeout: 5_000})
  end

  test "configuration defaults are explicit and a malformed configuration is not adopted" do
    context = execution_context(nil)

    assert {:error, %LabError{code: :invalid_mqtt_config, class: :permanent}} =
             EmqttClient.publish(publish_command(@closed), context, :not_a_configuration)

    assert {:error, %LabError{code: :mqtt_connect_refused}} =
             EmqttClient.publish(publish_command(@closed), context, client_id_prefix: "lab")

    for config <- [
          [unknown: true],
          [connect_timeout: 0],
          [max_inflight: 0],
          [session_expiry_interval: 1],
          [clean_start: false],
          [tls_certfile: "client.pem"],
          [will: %{topic: "bad/+", payload: "offline"}],
          [maximum_packet_size: 4, will: %{topic: "lab/status", payload: "offline"}]
        ] do
      assert {:error, %LabError{code: :invalid_mqtt_config}} =
               EmqttClient.publish(publish_command(@closed), context, config)
    end
  end

  test "CONNECT carries bounded session, packet and Last Will policy" do
    server = MqttServer.start(self())
    context = execution_context(nil)

    config = %{
      client_id: "lab-stable-client",
      clean_start: false,
      session_expiry_interval: 30,
      receive_maximum: 7,
      maximum_packet_size: 1_024,
      max_inflight: 3,
      keepalive: 12,
      will: %{
        topic: "lab/status",
        payload: "offline",
        qos: 1,
        retain: true,
        delay_interval: 2
      }
    }

    assert {:ok, session} =
             EmqttClient.subscribe(read_command(MqttServer.href(server)), self(), context, config)

    assert_receive {:mqtt_connect,
                    %{
                      client_id: "lab-stable-client",
                      clean_start: false,
                      keepalive: 12,
                      properties: %{
                        session_expiry_interval: 30,
                        receive_maximum: 7,
                        maximum_packet_size: 1_024
                      },
                      will: %{
                        topic: "lab/status",
                        payload: "offline",
                        qos: 1,
                        retain: true,
                        properties: %{will_delay_interval: 2}
                      }
                    }}

    client = :sys.get_state(session).client
    assert :emqtt.info(client, :max_inflight) == 3
    assert :ok = Session.close(session)
  end

  test "the Lab client satisfies the MQTT client port and the JSON-over-MQTT profile" do
    assert {:ok, _config} = TransportConfig.new(EmqttClient, %{connect_timeout: 500})
    assert MQTT.profile().id == :mqtt
  end

  test "a scripted peer carries subscription, delivery, bounds and an explicit stop" do
    server = MqttServer.start(self())
    prefix = "lab/scripted"
    subscription = observe(server, prefix, "temperature", id: :scripted, max_payload_bytes: 8)

    assert_receive {:mqtt_connect, %{username: nil, password: nil}}
    assert_receive {:mqtt_subscribe, ["lab/scripted/properties/temperature"]}

    MqttServer.publish(server, "#{prefix}/properties/temperature", "21.5")

    assert_receive {:wotex_runtime, :scripted,
                    {:ok, 21.5, %{topic: "lab/scripted/properties/temperature", retained: false}}},
                   2_000

    MqttServer.publish(server, "#{prefix}/properties/temperature", "123456789012345")
    MqttServer.publish(server, "other/thing/value", "1")
    send(:sys.get_state(subscription).handle, {:publish, %{}})
    send(:sys.get_state(subscription).handle, :unrelated)
    refute_receive {:wotex_runtime, :scripted, _event}, 200
    assert Process.alive?(subscription)

    assert :ok = Subscription.stop(subscription)
    assert_receive {:mqtt_unsubscribe, ["lab/scripted/properties/temperature"]}, 2_000
    assert_receive :mqtt_disconnect, 2_000
  end

  test "a scripted peer answers a retained read, an empty filter and a rejected delivery" do
    prefix = "lab/retained"
    topic = "#{prefix}/properties/temperature"
    server = MqttServer.start(self(), retained: {topic, "21.5"})
    context = Context.new!(request_id: "mqtt-scripted-read")

    assert {:ok, result} =
             ConsumedThing.read_property(
               consumed_thing(MqttServer.href(server), prefix),
               "temperature",
               context
             )

    assert result.payload == 21.5
    assert result.metadata.delivery_retained
    assert_receive :mqtt_pingreq

    empty = MqttServer.start(self())

    assert {:error, %LabError{code: :no_retained_message, class: :protocol}} =
             EmqttClient.read(
               read_command(MqttServer.href(empty)),
               2_000,
               execution_context(nil),
               %{}
             )

    invalid = MqttServer.start(self(), retained: {"lab/properties/+", "21.5"})

    assert {:error, %LabError{code: :undeliverable_message, class: :protocol}} =
             EmqttClient.read(
               read_command(MqttServer.href(invalid)),
               2_000,
               execution_context(nil),
               %{}
             )
  end

  test "a scripted peer accepts a published Property and Action message" do
    server = MqttServer.start(self())
    prefix = "lab/published"
    consumed = consumed_thing(MqttServer.href(server), prefix)
    context = Context.new!(request_id: "mqtt-scripted-write")

    assert {:ok, %{status: :accepted}} =
             ConsumedThing.write_property(consumed, "target", 23.5, context)

    assert_receive {:mqtt_publish,
                    %{topic: "lab/published/properties/target", payload: "23.5", qos: 1}}

    assert {:ok, %{status: :accepted}} =
             ConsumedThing.invoke_action(consumed, "setTarget", 24, context)

    assert_receive {:mqtt_publish, %{topic: "lab/published/actions/set-target", payload: "24"}}
  end

  test "a denied Topic Filter is a permanent subscription failure" do
    server = MqttServer.start(self(), deny_subscribe: true)
    context = execution_context(nil)

    assert {:error, %LabError{code: :mqtt_subscription_denied, class: :permanent}} =
             EmqttClient.subscribe(read_command(MqttServer.href(server)), self(), context, %{})

    assert {:error, %LabError{code: :mqtt_subscription_denied}} =
             EmqttClient.read(read_command(MqttServer.href(server)), 2_000, context, %{})
  end

  test "a server DISCONNECT and a closed socket both surface transport_down" do
    disconnecting = MqttServer.start(self())
    subscription = observe(disconnecting, "lab/bye", "temperature", id: :bye)
    monitor = Process.monitor(subscription)
    MqttServer.disconnect(disconnecting)

    assert_receive {:wotex_runtime, :bye, {:status, :transport_down}}, 2_000
    assert_receive {:DOWN, ^monitor, :process, ^subscription, {:shutdown, :transport_down}}, 2_000

    closing = MqttServer.start(self())
    closed = observe(closing, "lab/gone", "temperature", id: :gone)
    closed_monitor = Process.monitor(closed)
    MqttServer.close(closing)

    assert_receive {:wotex_runtime, :gone, {:status, :transport_down}}, 2_000
    assert_receive {:DOWN, ^closed_monitor, :process, ^closed, {:shutdown, :transport_down}}, 2_000
  end

  test "a killed subscription owner tears its session and connection down" do
    server = MqttServer.start(self())
    subscription = observe(server, "lab/killed", "temperature", id: :killed)
    session = :sys.get_state(subscription).handle
    client = :sys.get_state(session).client

    session_down = Process.monitor(session)
    client_down = Process.monitor(client)
    Process.exit(subscription, :kill)

    assert_receive :mqtt_disconnect, 2_000
    assert_receive {:DOWN, ^session_down, :process, ^session, _reason}, 2_000
    assert_receive {:DOWN, ^client_down, :process, ^client, _reason}, 2_000
  end

  test "the CONNECT packet carries the resolved credential and the session keeps none of it" do
    server = MqttServer.start(self())
    subscription = observe(server, "lab/secured", "temperature", id: :secured, secured: true)

    assert_receive {:mqtt_connect, %{username: @user, password: @password}}, 2_000

    session = :sys.get_state(subscription).handle
    client = :sys.get_state(session).client

    for pid <- [subscription, session, client] do
      refute inspect(:sys.get_state(pid)) =~ @password
      refute inspect(Process.info(pid, :dictionary)) =~ @password
    end

    refute inspect(:sys.get_state(session)) =~ @reference
    assert :ok = Subscription.stop(subscription)
  end

  defp observe(server, prefix, name, opts) do
    consumed = consumed_thing(MqttServer.href(server), prefix, opts)
    lab = start_supervised!({Lab, id: "mqtt-#{Keyword.fetch!(opts, :id)}", max_children: 4})

    {:ok, spec} =
      ConsumedThing.observation_child_spec(
        consumed,
        name,
        Context.new!(request_id: "mqtt-scripted"),
        id: Keyword.fetch!(opts, :id),
        receiver: self(),
        restart: :temporary
      )

    {:ok, subscription} = Lab.start_child(lab, :sessions, spec)
    assert_receive {:runtime_subscription_opened, ^subscription}, 2_000
    subscription
  end

  defp consumed_thing(href, prefix \\ nil, opts \\ []) do
    {:ok, mqtt_config} =
      TransportConfig.new(EmqttClient, %{connect_timeout: 1_000},
        read_timeout: 2_000,
        max_payload_bytes: Keyword.get(opts, :max_payload_bytes, 1_048_576)
      )

    secured = Keyword.get(opts, :secured, false)
    prefix = prefix || "lab/#{System.unique_integer([:positive])}"

    td =
      MqttThing.thing_description(href, prefix,
        security: if(secured, do: "basic_sc", else: "nosec_sc")
      )

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [MQTT.profile()],
        transports: %{mqtt: {Transport, mqtt_config}},
        credentials: credentials(secured)
      )

    consumed
  end

  defp credentials(false), do: {NoSec, %{}}

  defp credentials(true) do
    {StaticRef,
     %{
       references: %{"basic_sc" => @reference},
       lookup: fn @reference -> {:ok, {:password, @user, @password}} end
     }}
  end

  defp publish_command(href) do
    {:ok, broker} = Broker.new(href)
    {:ok, command} = Command.publish(broker, :writeproperty, "lab/properties/target", 21.0, qos: 1)
    command
  end

  defp read_command(href) do
    {:ok, broker} = Broker.new(href)

    {:ok, command} =
      Command.subscribe(broker, :readproperty, "lab/properties/temperature", qos: 1, retain: true)

    command
  end

  defp silent_publish_command(port), do: publish_command("mqtt://127.0.0.1:#{port}")

  defp execution_context(credential, context \\ Context.new!(request_id: "mqtt-unit")),
    do: ExecutionContext.new(context, credential)

  defp expired_deadline, do: System.monotonic_time(:millisecond) - 1

  defp silent_broker do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false])
    {:ok, port} = :inet.port(listener)
    accepting = spawn(fn -> accept(listener) end)

    on_exit(fn ->
      Process.exit(accepting, :kill)
      :gen_tcp.close(listener)
    end)

    port
  end

  defp accept(listener) do
    case :gen_tcp.accept(listener) do
      {:ok, _socket} -> accept(listener)
      {:error, _reason} -> :ok
    end
  end
end
