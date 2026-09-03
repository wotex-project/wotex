defmodule Wotex.Runtime.SubscriptionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Wotex.Runtime.{ConsumedThing, Context, Error, Subscription}
  alias Wotex.Runtime.Test.{FakeCredentials, FakeTransport, TDFactory}

  setup do
    profile = TDFactory.http_profile()

    {:ok, consumed} =
      ConsumedThing.new(TDFactory.thing_description(),
        profiles: [profile],
        transports: %{profile.id => {FakeTransport, %{test_pid: self()}}},
        credentials: {FakeCredentials, %{test_pid: self()}}
      )

    %{consumed: consumed}
  end

  test "building zero child specifications starts zero processes", %{consumed: consumed} do
    context = Context.new!(request_id: "req-zero")

    assert {:ok, %{start: {Subscription, :start_link, [_init]}}} =
             ConsumedThing.observation_child_spec(consumed, "temperature", context,
               id: :observation_zero,
               receiver: self()
             )

    refute_receive {:credentials, _, _, _}
    refute_receive {:subscribe, _, _, _}
  end

  test "one named observation forwards values and performs explicit unsubscription", %{
    consumed: consumed
  } do
    context = Context.new!(request_id: "req-one")
    name = unique_name(:observation)

    assert {:ok, spec} =
             ConsumedThing.observation_child_spec(consumed, "temperature", context,
               id: :observation_one,
               name: name,
               receiver: self(),
               restart: :temporary
             )

    pid = start_supervised!(spec)
    assert GenServer.whereis(name) == pid
    assert_receive {:credentials, _, _, "req-one"}
    assert_receive {:subscribe, %{operation: :observeproperty}, ^pid, "credential-material"}
    refute inspect(:sys.get_state(pid)) =~ "credential-material"

    send(pid, {:wotex_transport, 21.75})
    assert_receive {:wotex_runtime, :observation_one, 21.75}

    assert :ok = Subscription.stop(pid)
    assert_receive {:credentials, _, _, "req-one"}
    assert_receive {:unsubscribe, _handle, %{operation: :unobserveproperty}, "credential-material"}
  end

  test "multiple independently named Event subscriptions coexist", %{consumed: consumed} do
    context_a = Context.new!(request_id: "req-a")
    context_b = Context.new!(request_id: "req-b")

    {:ok, spec_a} =
      ConsumedThing.event_subscription_child_spec(consumed, "alarm", context_a,
        id: :alarm_a,
        name: unique_name(:alarm_a),
        receiver: self(),
        restart: :temporary
      )

    {:ok, spec_b} =
      ConsumedThing.event_subscription_child_spec(consumed, "alarm", context_b,
        id: :alarm_b,
        name: unique_name(:alarm_b),
        receiver: self(),
        restart: :temporary
      )

    pid_a = start_supervised!(spec_a)
    pid_b = start_supervised!(spec_b)
    refute pid_a == pid_b

    assert_receive {:credentials, _, _, request_id} when request_id in ["req-a", "req-b"]

    assert_receive {:subscribe, %{operation: :subscribeevent}, subscription_pid, _}
                   when subscription_pid in [pid_a, pid_b]

    assert_receive {:credentials, _, _, request_id} when request_id in ["req-a", "req-b"]

    assert_receive {:subscribe, %{operation: :subscribeevent}, subscription_pid, _}
                   when subscription_pid in [pid_a, pid_b]

    send(pid_a, {:wotex_transport, "alarm-a"})
    send(pid_b, {:wotex_transport, "alarm-b"})
    assert_receive {:wotex_runtime, :alarm_a, "alarm-a"}
    assert_receive {:wotex_runtime, :alarm_b, "alarm-b"}

    assert :ok = Subscription.stop(pid_a)
    assert :ok = Subscription.stop(pid_b)
  end

  test "subscription construction requires identity, receiver, and matching stop Form", %{
    consumed: consumed
  } do
    context = Context.new!(request_id: "req-options")

    assert {:error, %Error{code: :missing_subscription_option}} =
             ConsumedThing.observation_child_spec(consumed, "temperature", context,
               receiver: self()
             )

    assert {:error, %Error{code: :missing_subscription_option}} =
             ConsumedThing.observation_child_spec(consumed, "temperature", context,
               id: :missing_receiver
             )

    assert {:error, %Error{code: :invalid_subscription_options}} =
             ConsumedThing.observation_child_spec(consumed, "temperature", %{}, [])

    assert {:error, %Error{code: :invalid_consumed_thing}} =
             ConsumedThing.observation_child_spec(%{}, "temperature", context, [])
  end

  test "subscription port failures are normalized", %{consumed: _consumed} do
    profile = TDFactory.http_profile()
    context = Context.new!(request_id: "req-failure")

    for {mode, code} <- [error: :transport_subscribe_failed, invalid: :invalid_transport_return] do
      {:ok, consumed} =
        ConsumedThing.new(TDFactory.thing_description(),
          profiles: [profile],
          transports: %{
            profile.id => {FakeTransport, %{test_pid: self(), subscribe_mode: mode}}
          },
          credentials: {FakeCredentials, %{test_pid: self(), secret: "x"}}
        )

      {:ok, spec} =
        ConsumedThing.event_subscription_child_spec(consumed, "alarm", context,
          id: {:failure, mode},
          receiver: self(),
          restart: :temporary
        )

      capture_log(fn ->
        assert {:error, {%Error{code: ^code}, _child}} = start_supervised(spec)
      end)
    end
  end

  test "ignores unrelated messages and normalizes stop failures" do
    profile = TDFactory.http_profile()
    context = Context.new!(request_id: "req-stop-failure")

    failures = [error: :transport_unsubscribe_failed, invalid: :invalid_transport_return]

    for {mode, code} <- failures do
      {:ok, consumed} =
        ConsumedThing.new(TDFactory.thing_description(),
          profiles: [profile],
          transports: %{
            profile.id => {FakeTransport, %{test_pid: self(), unsubscribe_mode: mode}}
          },
          credentials: {FakeCredentials, %{test_pid: self()}}
        )

      {:ok, spec} =
        ConsumedThing.event_subscription_child_spec(consumed, "alarm", context,
          id: {:stop_failure, mode},
          receiver: self(),
          restart: :temporary
        )

      pid = start_supervised!(spec)
      send(pid, :unrelated)
      assert Process.alive?(pid)
      assert {:error, %Error{code: ^code}} = Subscription.stop(pid)
    end
  end

  defp unique_name(suffix),
    do: {:global, {:wotex_runtime_test, suffix, System.unique_integer([:positive])}}
end
