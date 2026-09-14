defmodule Wotex.Binding.MQTT.ClientLifecycleTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.MQTT
  alias Wotex.Binding.MQTT.{Delivery, Transport, TransportConfig}

  alias Wotex.Binding.MQTT.Test.{
    FakeClient,
    FakeCredentials,
    LifecycleClient,
    RequestFactory,
    TDFactory
  }

  alias Wotex.Runtime.{ConsumedThing, Context, Error, Subscription}

  test "a supplied client enforces the finite retained-read timeout" do
    {:ok, state} = start_supervised({Agent, fn -> %{} end})
    delivery = delivery!(~s({"value":21}), retain: true)
    timeout = 20

    config =
      lifecycle_config(state, %{read_mode: {:delay, 200, delivery}}, read_timeout: timeout)

    started_at = System.monotonic_time(:millisecond)

    assert {:error,
            %Wotex.Binding.MQTT.Error{
              code: :client_read_failed,
              phase: :client,
              class: :unavailable
            }} = Transport.request(read_request(), execution_context(), config)

    elapsed = System.monotonic_time(:millisecond) - started_at
    assert elapsed >= timeout
    assert elapsed < 500
    assert_receive {:lifecycle_read, ^timeout, ["things/value"]}
  end

  test "all four callbacks normalize invalid, raised, thrown, and exited client results" do
    context = execution_context()

    callbacks = [
      {:publish_return, :client_publish_failed,
       fn config -> Transport.request(publish_request(), context, config) end},
      {:read_return, :client_read_failed,
       fn config -> Transport.request(read_request(), context, config) end},
      {:subscribe_return, :client_subscribe_failed,
       fn config -> Transport.subscribe(observe_request(), self(), context, config) end},
      {:unsubscribe_return, :client_unsubscribe_failed,
       fn config -> Transport.unsubscribe(:handle, stop_request(), context, config) end}
    ]

    for {option, failure_code, invoke} <- callbacks do
      assert {:error, %Wotex.Binding.MQTT.Error{code: :invalid_client_return, class: :protocol}} =
               invoke.(fake_config(%{option => :invalid}))

      for exceptional <- [:raise, :throw, :exit] do
        assert {:error,
                %Wotex.Binding.MQTT.Error{
                  code: ^failure_code,
                  phase: :client,
                  class: :unavailable
                }} = invoke.(fake_config(%{option => exceptional}))
      end
    end
  end

  test "an open failure is classified without creating consumer session state" do
    {:ok, state} = LifecycleClient.start_link(self())
    on_exit(fn -> if Process.alive?(state), do: Agent.stop(state) end)

    config = lifecycle_config(state, %{subscribe_return: {:error, :broker_unavailable}})
    id = {:open_failure, make_ref()}
    owner = start_observation(config, id, restart: :temporary)
    monitor = Process.monitor(owner)

    assert_receive {:lifecycle_subscribe_attempt, ^owner, ["things/properties/+"]}

    assert_receive {:wotex_runtime, ^id,
                    {:error,
                     %Error{
                       code: :transport_subscribe_failed,
                       class: :unavailable,
                       details: %{cause: %{code: :client_subscribe_failed, phase: :client}}
                     }}}

    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, %Error{}}}
    assert LifecycleClient.snapshot(state).active == %{}
  end

  test "a close failure is returned while ownership stays with the supplied client" do
    {:ok, state} = LifecycleClient.start_link(self())
    on_exit(fn -> if Process.alive?(state), do: Agent.stop(state) end)

    config = lifecycle_config(state, %{unsubscribe_return: {:error, :broker_unavailable}})
    id = {:close_failure, make_ref()}
    owner = start_observation(config, id, restart: :temporary)

    assert_receive {:lifecycle_subscribed, handle, ^owner}

    assert {:error,
            %Error{
              code: :transport_unsubscribe_failed,
              class: :unavailable,
              details: %{cause: %{code: :client_unsubscribe_failed, phase: :client}}
            }} = Subscription.stop(owner)

    assert_receive {:lifecycle_unsubscribe_attempt, ^handle, ^owner, 1, ["things/properties/+"]}
    snapshot = LifecycleClient.snapshot(state)
    assert snapshot.active == %{handle => owner}
    assert snapshot.close_attempts == %{handle => 1}
  end

  test "concurrent owners receive distinct handles and each handle closes exactly once" do
    {:ok, state} = LifecycleClient.start_link(self())
    on_exit(fn -> if Process.alive?(state), do: Agent.stop(state) end)
    config = lifecycle_config(state)

    first_id = {:concurrent_first, make_ref()}
    second_id = {:concurrent_second, make_ref()}
    first_owner = start_observation(config, first_id, restart: :temporary)
    second_owner = start_observation(config, second_id, restart: :temporary)

    handles = await_handles(%{first_owner => nil, second_owner => nil}, 2)
    first_handle = Map.fetch!(handles, first_owner)
    second_handle = Map.fetch!(handles, second_owner)
    refute first_handle == second_handle
    assert LifecycleClient.snapshot(state).active == handles_by_handle(handles)

    callers = Enum.map([first_owner, second_owner], &Task.async(fn -> Subscription.stop(&1) end))
    assert Enum.map(callers, &Task.await/1) == [:ok, :ok]

    assert_receive {:lifecycle_unsubscribe_attempt, ^first_handle, ^first_owner, 1, _}
    assert_receive {:lifecycle_unsubscribe_attempt, ^second_handle, ^second_owner, 1, _}
    refute_receive {:lifecycle_unsubscribe_attempt, _, _, 2, _}

    snapshot = LifecycleClient.snapshot(state)
    assert snapshot.active == %{}
    assert snapshot.close_attempts == %{first_handle => 1, second_handle => 1}
  end

  @tag capture_log: true
  test "session loss closes the old handle and a permanent child opens fresh client state" do
    {:ok, state} = LifecycleClient.start_link(self())
    on_exit(fn -> if Process.alive?(state), do: Agent.stop(state) end)
    config = lifecycle_config(state)
    id = {:restart, make_ref()}
    spec = observation_spec(config, id, restart: :permanent)

    supervisor =
      start_supervised!(%{
        id: {:restart_supervisor, make_ref()},
        start: {Supervisor, :start_link, [[spec], [strategy: :one_for_one, max_restarts: 3]]},
        type: :supervisor
      })

    assert_receive {:lifecycle_subscribed, first_handle, first_owner}
    send(first_owner, {:wotex_transport_status, :session_lost})
    assert_receive {:wotex_runtime, ^id, {:status, :session_lost}}
    assert_receive {:lifecycle_unsubscribe_attempt, ^first_handle, ^first_owner, 1, _}
    assert_receive {:lifecycle_subscribed, second_handle, second_owner}
    refute first_owner == second_owner
    refute first_handle == second_handle

    assert [{^id, ^second_owner, :worker, _}] = Supervisor.which_children(supervisor)

    snapshot = LifecycleClient.snapshot(state)
    assert snapshot.active == %{second_handle => second_owner}
    assert snapshot.close_attempts == %{first_handle => 1}
    refute inspect(snapshot) =~ "ephemeral_credential"

    assert :ok = Supervisor.terminate_child(supervisor, id)
    assert_receive {:lifecycle_unsubscribe_attempt, ^second_handle, ^second_owner, 1, _}
    assert LifecycleClient.snapshot(state).active == %{}
  end

  defp start_observation(config, id, opts) do
    spec = observation_spec(config, id, opts)
    start_supervised!(spec)
  end

  defp observation_spec(config, id, opts) do
    {:ok, consumed} =
      ConsumedThing.new(TDFactory.thing_description(),
        profiles: [MQTT.profile()],
        transports: %{mqtt: {Transport, config}},
        credentials: {FakeCredentials, %{test_pid: self()}}
      )

    {:ok, spec} =
      ConsumedThing.observation_child_spec(
        consumed,
        "temperature",
        Context.new!(request_id: inspect(id)),
        Keyword.merge([id: id, receiver: self()], opts)
      )

    spec
  end

  defp await_handles(owners, 0), do: owners

  defp await_handles(owners, remaining) do
    receive do
      {:lifecycle_subscribed, handle, owner} ->
        await_handles(Map.replace!(owners, owner, handle), remaining - 1)
    after
      500 -> flunk("timed out waiting for lifecycle handles")
    end
  end

  defp handles_by_handle(handles) do
    Map.new(handles, fn {owner, handle} -> {handle, owner} end)
  end

  defp lifecycle_config(state, overrides \\ %{}, opts \\ []) do
    client_config = Map.merge(%{state: state, test_pid: self()}, overrides)
    {:ok, config} = TransportConfig.new(LifecycleClient, client_config, opts)
    config
  end

  defp fake_config(overrides) do
    client_config = Map.merge(%{test_pid: self(), client_marker: :client_state}, overrides)
    {:ok, config} = TransportConfig.new(FakeClient, client_config)
    config
  end

  defp execution_context, do: RequestFactory.execution_context(:ephemeral_credential)

  defp publish_request do
    RequestFactory.request(:writeproperty,
      input: %{"value" => 21},
      form: %{
        "href" => "mqtt://broker.example",
        "op" => "writeproperty",
        "mqv:topic" => "things/value"
      }
    )
  end

  defp read_request do
    RequestFactory.request(:readproperty,
      form: %{
        "href" => "mqtt://broker.example",
        "op" => "readproperty",
        "mqv:retain" => true,
        "mqv:filter" => "things/value"
      }
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

  defp delivery!(payload, opts) do
    {:ok, delivery} =
      Delivery.new(payload,
        topic: "things/value",
        qos: 1,
        retain: Keyword.fetch!(opts, :retain)
      )

    delivery
  end
end
