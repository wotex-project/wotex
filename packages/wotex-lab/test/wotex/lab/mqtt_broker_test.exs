defmodule Wotex.Lab.MqttBrokerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Binding.MQTT
  alias Wotex.Binding.MQTT.{Broker, Command, Delivery, Transport, TransportConfig}
  alias Wotex.Lab
  alias Wotex.Lab.Adapters.MQTT.EmqttClient
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

    case Enum.find(children, fn {_id, pid, _type, _modules} -> is_pid(pid) and pid != previous end) do
      {_id, pid, _type, _modules} ->
        pid

      nil ->
        Process.sleep(50)
        await_restart(lab, previous, attempts - 1)
    end
  end

  defp unrelated_delivery do
    {:ok, delivery} = Delivery.new("null", topic: "other/thing/value", qos: 0, retain: false)
    delivery
  end

  defp execution_context,
    do: ExecutionContext.new(Context.new!(request_id: "mqtt-client"), nil)
end
