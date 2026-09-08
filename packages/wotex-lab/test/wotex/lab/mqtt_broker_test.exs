defmodule Wotex.Lab.MqttBrokerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Binding.MQTT
  alias Wotex.Binding.MQTT.{Broker, Command, Delivery, Transport, TransportConfig}
  alias Wotex.Lab
  alias Wotex.Lab.Adapters.MQTT.{EmqttClient, Session}
  alias Wotex.Lab.Adapters.Runtime.{NoSec, StaticRef}
  alias Wotex.Lab.Error, as: LabError
  alias Wotex.Lab.Test.{MqttBroker, MqttThing}
  alias Wotex.Runtime.{ConsumedThing, Context, Error, ExecutionContext, Result, Subscription}

  @moduletag :broker
  @moduletag capture_log: true
  @moduletag timeout: 60_000

  @user "lab-consumer"
  @password "broker-password-4c1a"
  @reference "vault://lab/mqtt"

  setup_all do
    %{server: MqttBroker.start()}
  end

  setup do
    %{prefix: "lab/" <> MqttBroker.token()}
  end

  test "a retained Application Message becomes a Property representation", %{
    server: broker,
    prefix: prefix
  } do
    MqttBroker.publish(broker, "#{prefix}/properties/temperature", "21.5", retain: true)
    consumed = consumed_thing(broker, prefix)
    context = Context.new!(request_id: "mqtt-read")

    assert {:ok, %Result{status: :ok, payload: 21.5, operation: :readproperty} = result} =
             ConsumedThing.read_property(consumed, "temperature", context)

    assert result.metadata.binding == :mqtt
    assert result.metadata.topic == "#{prefix}/properties/temperature"
    assert result.metadata.delivery_retained
  end

  test "a Topic Filter without a retained message fails as a typed client error", %{
    server: broker,
    prefix: prefix
  } do
    consumed = consumed_thing(broker, prefix)
    context = Context.new!(request_id: "mqtt-missing")

    assert {:error, %Error{code: :transport_request_failed, class: :unavailable} = error} =
             ConsumedThing.read_property(consumed, "missing", context)

    assert error.details.cause.code == :client_read_failed

    {:ok, mqtt_broker} = Broker.new(MqttBroker.href(broker))

    {:ok, command} =
      Command.subscribe(mqtt_broker, :readproperty, "#{prefix}/properties/missing",
        qos: 1,
        retain: true
      )

    assert {:error, %LabError{code: :no_retained_message, class: :protocol}} =
             EmqttClient.read(command, 2_000, execution_context(), %{})
  end

  test "writeproperty and invokeaction reach the broker as accepted publications", %{
    server: broker,
    prefix: prefix
  } do
    listener = MqttBroker.listen(broker, "#{prefix}/#")
    consumed = consumed_thing(broker, prefix)
    context = Context.new!(request_id: "mqtt-publish")

    assert {:ok, %Result{status: :accepted, payload: nil} = written} =
             ConsumedThing.write_property(consumed, "target", 23.5, context)

    assert written.metadata.control_packet == :publish
    assert_receive {:publish, %{topic: topic, payload: "23.5"}}, 5_000
    assert topic == "#{prefix}/properties/target"

    assert {:ok, %Result{status: :accepted, operation: :invokeaction}} =
             ConsumedThing.invoke_action(consumed, "setTarget", 24, context)

    assert_receive {:publish, %{topic: action_topic, payload: "24"}}, 5_000
    assert action_topic == "#{prefix}/actions/set-target"
    :ok = :emqtt.disconnect(listener)
  end

  test "an observation delivers frames with Topic Name metadata through the envelope", %{
    server: broker,
    prefix: prefix
  } do
    {_lab, subscription} = observe(broker, prefix, "temperature", id: :observed)

    MqttBroker.publish(broker, "#{prefix}/properties/temperature", "21.5")

    assert_receive {:wotex_runtime, :observed,
                    {:ok, 21.5,
                     %{
                       topic: topic,
                       qos: 1,
                       retained: false,
                       operation: :observeproperty,
                       request_id: "mqtt-observe"
                     }}},
                   5_000

    assert topic == "#{prefix}/properties/temperature"

    MqttBroker.publish(broker, "#{prefix}/properties/temperature", "22.5")
    assert_receive {:wotex_runtime, :observed, {:ok, 22.5, %{topic: ^topic}}}, 5_000
    assert :ok = Subscription.stop(subscription)
  end

  test "an unrelated Topic Name is ignored and an oversized message never reaches the owner", %{
    server: broker,
    prefix: prefix
  } do
    {_lab, subscription} =
      observe(broker, prefix, "temperature", id: :bounded, max_payload_bytes: 8)

    send(subscription, {:wotex_transport_frame, unrelated_delivery()})
    refute_receive {:wotex_runtime, :bounded, _event}, 200
    assert Process.alive?(subscription)

    MqttBroker.publish(broker, "#{prefix}/properties/temperature", "123456789012345")
    refute_receive {:wotex_runtime, :bounded, _event}, 500
    assert Process.alive?(subscription)

    MqttBroker.publish(broker, "#{prefix}/properties/temperature", "21.5")
    assert_receive {:wotex_runtime, :bounded, {:ok, 21.5, _meta}}, 5_000
  end

  test "an explicit stop unsubscribes, disconnects and ends every session process", %{
    server: broker,
    prefix: prefix
  } do
    {_lab, subscription} = observe(broker, prefix, "temperature", id: :stopped)
    session = :sys.get_state(subscription).handle
    client = :sys.get_state(session).client
    assert is_pid(session) and is_pid(client)

    assert :ok = Subscription.stop(subscription)
    refute Process.alive?(subscription)
    refute Process.alive?(session)
    refute Process.alive?(client)

    MqttBroker.publish(broker, "#{prefix}/properties/temperature", "21.5")
    refute_receive {:wotex_runtime, :stopped, _event}, 500
  end

  test "a stopped broker container surfaces transport_down and stops the child", %{prefix: prefix} do
    broker = MqttBroker.start()
    {_lab, subscription} = observe(broker, prefix, "temperature", id: :gone)
    monitor = Process.monitor(subscription)

    :ok = MqttBroker.stop(broker.container)

    assert_receive {:wotex_runtime, :gone, {:status, :transport_down}}, 15_000
    assert_receive {:DOWN, ^monitor, :process, ^subscription, {:shutdown, :transport_down}}, 5_000
  end

  test "a permanent child resubscribes after a restart with freshly resolved credentials" do
    prefix = "lab/" <> MqttBroker.token()
    broker = MqttBroker.start(credentials: {@user, @password})
    {lab, subscription} = observe(broker, prefix, "temperature", id: :permanent, secured: true)

    assert_receive {:credential_resolved, :observeproperty}, 5_000
    Process.exit(subscription, :kill)
    assert_receive {:credential_resolved, :observeproperty}, 15_000

    restarted = await_restart(lab, subscription, 100)
    refute restarted == subscription

    MqttBroker.publish(broker, "#{prefix}/properties/temperature", "21.5",
      username: @user,
      password: @password
    )

    assert_receive {:wotex_runtime, :permanent, {:ok, 21.5, _meta}}, 5_000
  end

  test "an authenticated session keeps the password out of every process diagnostic" do
    prefix = "lab/" <> MqttBroker.token()
    broker = MqttBroker.start(credentials: {@user, @password})
    {_lab, subscription} = observe(broker, prefix, "temperature", id: :secured, secured: true)

    MqttBroker.publish(broker, "#{prefix}/properties/temperature", "21.5",
      username: @user,
      password: @password
    )

    assert_receive {:wotex_runtime, :secured, {:ok, 21.5, _meta}}, 5_000

    session = :sys.get_state(subscription).handle
    client = :sys.get_state(session).client

    for pid <- [subscription, session, client] do
      refute inspect(:sys.get_state(pid)) =~ @password
      refute inspect(Process.info(pid, :dictionary)) =~ @password
    end

    refute inspect(:sys.get_state(session)) =~ @reference
  end

  test "a receiver that cannot keep up bounds the subscription instead of its mailbox", %{
    server: broker,
    prefix: prefix
  } do
    receiver = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> Process.exit(receiver, :kill) end)
    Enum.each(1..4, &send(receiver, {:backlog, &1}))

    {_lab, subscription} =
      observe(broker, prefix, "temperature",
        id: :overloaded,
        receiver: receiver,
        max_queue_length: 1,
        overflow: :stop
      )

    monitor = Process.monitor(subscription)
    MqttBroker.publish(broker, "#{prefix}/properties/temperature", "21.5")
    assert_receive {:DOWN, ^monitor, :process, ^subscription, {:shutdown, :overloaded}}, 5_000
  end

  test "shared Topic Filters and $SYS topics are admitted with their real Topic Name", %{
    server: broker,
    prefix: prefix
  } do
    {_lab, shared} = observe(broker, prefix, "shared", id: :shared)
    MqttBroker.publish(broker, "#{prefix}/properties/shared", "42")

    assert_receive {:wotex_runtime, :shared, {:ok, 42, %{topic: topic}}}, 5_000
    assert topic == "#{prefix}/properties/shared"
    assert :ok = Subscription.stop(shared)

    {_lab, system} = observe(broker, prefix, "system", id: :system)

    assert_receive {:wotex_runtime, :system,
                    {:ok, connected, %{topic: "$SYS/broker/clients/connected"}}},
                   10_000

    assert is_integer(connected)
    assert :ok = Subscription.stop(system)
  end

  test "MQTTS verifies the fixture CA and broker hostname" do
    broker = MqttBroker.start(tls: true)
    topic = "lab/#{MqttBroker.token()}/secure"
    listener = MqttBroker.listen(broker, topic)
    {:ok, mqtt_broker} = Broker.new(MqttBroker.href(broker))
    {:ok, command} = Command.publish(mqtt_broker, :writeproperty, topic, 21.5, qos: 1)

    assert :ok =
             EmqttClient.publish(command, execution_context(), %{
               tls_ca_certfile: broker.ca_certfile,
               connect_timeout: 5_000
             })

    assert_receive {:publish, %{topic: ^topic, payload: "21.5"}}, 5_000

    {:ok, wrong_host} = Broker.new("mqtts://127.0.0.1:#{broker.port}")
    {:ok, wrong_command} = Command.publish(wrong_host, :writeproperty, topic, 22.0, qos: 1)

    assert {:error, %LabError{code: :mqtt_connect_refused}} =
             EmqttClient.publish(wrong_command, execution_context(), %{
               tls_ca_certfile: broker.ca_certfile,
               connect_timeout: 5_000
             })

    :ok = :emqtt.disconnect(listener)
  end

  test "broker ACLs isolate credentialed device prefixes" do
    user_a = "device-a"
    user_b = "device-b"
    password_a = "a-secret"
    password_b = "b-secret"

    broker =
      MqttBroker.start(
        credentials: [{user_a, password_a}, {user_b, password_b}],
        acl: %{user_a => ["lab/a/#"], user_b => ["lab/b/#"]}
      )

    {:ok, mqtt_broker} = Broker.new(MqttBroker.href(broker))

    context_a = execution_context({:password, user_a, password_a})

    {:ok, other_prefix} =
      Command.subscribe(mqtt_broker, :observeproperty, "lab/b/properties/temperature", qos: 1)

    # Mosquitto may accept the filter while enforcing the ACL on delivery.
    assert {:ok, isolated} = EmqttClient.subscribe(other_prefix, self(), context_a, %{})

    MqttBroker.publish(broker, "lab/b/properties/temperature", "22.0",
      username: user_b,
      password: password_b
    )

    refute_receive {:wotex_transport_frame, _delivery}, 500
    assert :ok = EmqttClient.unsubscribe(isolated, other_prefix, context_a, %{})

    {:ok, own_prefix} =
      Command.subscribe(mqtt_broker, :observeproperty, "lab/a/properties/temperature", qos: 1)

    assert {:ok, admitted} = EmqttClient.subscribe(own_prefix, self(), context_a, %{})

    MqttBroker.publish(broker, "lab/a/properties/temperature", "21.0",
      username: user_a,
      password: password_a
    )

    assert_receive {:wotex_transport_frame, %Delivery{topic: "lab/a/properties/temperature"}},
                   5_000

    assert :ok = EmqttClient.unsubscribe(admitted, own_prefix, context_a, %{})
  end

  test "an abrupt client loss publishes the bounded Last Will and stops the session" do
    broker = MqttBroker.start()
    will_topic = "lab/#{MqttBroker.token()}/status"
    listener = MqttBroker.listen(broker, will_topic)
    {:ok, mqtt_broker} = Broker.new(MqttBroker.href(broker))

    {:ok, command} =
      Command.subscribe(mqtt_broker, :observeproperty, "lab/power/properties/temperature", qos: 1)

    config = %{
      will: %{topic: will_topic, payload: "offline", qos: 1, retain: true},
      max_inflight: 2
    }

    assert {:ok, session} = EmqttClient.subscribe(command, self(), execution_context(), config)
    Process.unlink(session)
    client = :sys.get_state(session).client
    assert :emqtt.info(client, :max_inflight) == 2
    monitor = Process.monitor(session)
    Process.exit(client, :kill)

    assert_receive {:wotex_transport_status, :transport_down}, 5_000
    assert_receive {:DOWN, ^monitor, :process, ^session, {:shutdown, :transport_down}}, 5_000
    assert_receive {:publish, %{topic: ^will_topic, payload: "offline"}}, 5_000
    :ok = :emqtt.disconnect(listener)

    retained = MqttBroker.listen(broker, will_topic)
    assert_receive {:publish, %{topic: ^will_topic, payload: "offline", retain: true}}, 5_000
    :ok = :emqtt.disconnect(retained)
  end

  test "a stable client resumes only within its declared session expiry" do
    broker = MqttBroker.start()
    {:ok, mqtt_broker} = Broker.new(MqttBroker.href(broker))

    {:ok, command} =
      Command.subscribe(mqtt_broker, :observeproperty, "lab/session/properties/value", qos: 1)

    initial = %{
      client_id: "wotex-lab-session-expiry",
      clean_start: true,
      session_expiry_interval: 1
    }

    assert {:ok, first} = EmqttClient.subscribe(command, self(), execution_context(), initial)
    assert :ok = Session.close(first)

    resume = %{initial | clean_start: false}
    assert {:ok, second} = EmqttClient.subscribe(command, self(), execution_context(), resume)
    assert Keyword.fetch!(:emqtt.info(:sys.get_state(second).client), :session_present) == 1
    assert :ok = Session.close(second)

    Process.sleep(2_100)
    assert {:ok, expired} = EmqttClient.subscribe(command, self(), execution_context(), resume)
    assert Keyword.fetch!(:emqtt.info(:sys.get_state(expired).client), :session_present) == 0
    assert :ok = Session.close(expired)
  end

  defp observe(broker, prefix, name, opts) do
    consumed = consumed_thing(broker, prefix, opts)
    context = Context.new!(request_id: "mqtt-observe")
    lab = start_supervised!({Lab, id: "mqtt-#{Keyword.fetch!(opts, :id)}", max_children: 8})

    {:ok, spec} =
      ConsumedThing.observation_child_spec(consumed, name, context,
        id: Keyword.fetch!(opts, :id),
        receiver: Keyword.get(opts, :receiver, self()),
        restart: restart(opts),
        max_queue_length: Keyword.get(opts, :max_queue_length),
        overflow: Keyword.get(opts, :overflow, :drop)
      )

    {:ok, subscription} = Lab.start_child(lab, :sessions, spec)
    # The Runtime opens the subscription in a continuation; reading the state
    # returns only once the broker has answered the SUBSCRIBE.
    assert :sys.get_state(subscription).active?
    {lab, subscription}
  end

  defp restart(opts) do
    if Keyword.fetch!(opts, :id) == :permanent, do: :permanent, else: :temporary
  end

  defp consumed_thing(broker, prefix, opts \\ []) do
    secured = Keyword.get(opts, :secured, false)

    {:ok, mqtt_config} =
      TransportConfig.new(EmqttClient, %{connect_timeout: 5_000},
        read_timeout: 5_000,
        max_payload_bytes: Keyword.get(opts, :max_payload_bytes, 1_048_576)
      )

    td =
      MqttThing.thing_description(MqttBroker.href(broker), prefix,
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
    test = self()

    {StaticRef,
     %{
       references: %{"basic_sc" => @reference},
       lookup: fn @reference ->
         send(test, {:credential_resolved, :observeproperty})
         {:ok, {:password, @user, @password}}
       end
     }}
  end

  defp await_restart(_lab, _previous, 0), do: raise("the permanent subscription never restarted")

  defp await_restart(lab, previous, attempts) do
    children =
      lab
      |> Supervisor.which_children()
      |> Enum.find_value(fn
        {:sessions, pid, :supervisor, _modules} -> DynamicSupervisor.which_children(pid)
        _other -> nil
      end)

    case Enum.find(children, fn {_id, pid, _type, _modules} ->
           is_pid(pid) and pid != previous and subscription_active?(pid)
         end) do
      {_id, pid, _type, _modules} ->
        pid

      nil ->
        Process.sleep(50)
        await_restart(lab, previous, attempts - 1)
    end
  end

  defp subscription_active?(pid) do
    :sys.get_state(pid).active?
  catch
    :exit, _reason -> false
  end

  defp unrelated_delivery do
    {:ok, delivery} = Delivery.new("null", topic: "other/thing/value", qos: 0, retain: false)
    delivery
  end

  defp execution_context(credential \\ nil),
    do: ExecutionContext.new(Context.new!(request_id: "mqtt-client"), credential)
end
