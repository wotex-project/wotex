defmodule Wotex.Runtime.SubscriptionTest do
  @moduledoc false

  use ExUnit.Case, async: true

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

    %{consumed: consumed, profile: profile}
  end

  test "building zero child specifications starts zero processes", %{consumed: consumed} do
    context = Context.new!(request_id: "req-zero")

    assert {:ok, %{start: {Subscription, :start_link, [_init]}, restart: :transient}} =
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

    send(pid, {:wotex_transport, {:ok, 21.75, %{topic: "t"}}})
    assert_receive {:wotex_runtime, :observation_one, {:ok, 21.75, %{topic: "t"}}}

    send(pid, {:wotex_transport, {:error, :broken}})

    assert_receive {:wotex_runtime, :observation_one,
                    {:error, %Error{code: :transport_delivery_failed}}}

    send(pid, {:wotex_transport, :bare_payload})

    assert_receive {:wotex_runtime, :observation_one,
                    {:error, %Error{code: :invalid_transport_delivery}}}

    assert :ok = Subscription.stop(pid)
    assert_receive {:credentials, _, _, "req-one"}
    assert_receive {:unsubscribe, _handle, %{operation: :unobserveproperty}, "credential-material"}
  end

  test "raw frames are decoded in the subscription process through decode_frame/3", %{
    consumed: consumed
  } do
    context = Context.new!(request_id: "req-frame")

    {:ok, spec} =
      ConsumedThing.observation_child_spec(consumed, "temperature", context,
        id: :frames,
        receiver: self(),
        restart: :temporary
      )

    pid = start_supervised!(spec)
    assert_receive {:subscribe, _, ^pid, _}

    send(pid, {:wotex_transport_frame, {:value, 3}})
    assert_receive {:decode_frame, {:value, 3}, :observeproperty, ^pid}
    assert_receive {:wotex_runtime, :frames, {:ok, 3, %{topic: "fake/topic"}}}

    send(pid, {:wotex_transport_frame, :keepalive})
    refute_receive {:wotex_runtime, :frames, _}, 50

    send(pid, {:wotex_transport_frame, :bad})

    assert_receive {:wotex_runtime, :frames,
                    {:error,
                     %Error{
                       code: :undecodable_frame,
                       class: :protocol,
                       details: %{cause: %{code: :codec_failure}}
                     }}}

    send(pid, {:wotex_transport_frame, :weird})
    assert_receive {:wotex_runtime, :frames, {:error, %Error{code: :invalid_transport_return}}}

    for mode <- [:raise, :exit, :throw] do
      send(pid, {:wotex_transport_frame, mode})
      assert_receive {:wotex_runtime, :frames, {:error, %Error{code: :port_exception}}}
    end

    assert Process.alive?(pid)
  end

  test "open failures are reported to the receiver and stop the child without blocking start", %{
    profile: profile
  } do
    context = Context.new!(request_id: "req-failure")

    for {mode, code} <- [
          error: :transport_subscribe_failed,
          invalid: :invalid_transport_return,
          raise: :port_exception,
          exit: :port_exception,
          throw: :port_exception
        ] do
      {:ok, consumed} =
        ConsumedThing.new(TDFactory.thing_description(),
          profiles: [profile],
          transports: %{profile.id => {FakeTransport, %{test_pid: self(), subscribe_mode: mode}}},
          credentials: {FakeCredentials, %{test_pid: self(), secret: "sensitive"}}
        )

      {:ok, spec} =
        ConsumedThing.event_subscription_child_spec(consumed, "alarm", context,
          id: {:failure, mode},
          receiver: self(),
          restart: :temporary
        )

      pid = start_watched(spec)
      assert_receive {:wotex_runtime, {:failure, ^mode}, {:error, %Error{code: ^code} = error}}
      refute inspect(error) =~ "sensitive"
      assert_receive {:exited, ^pid, {:shutdown, %Error{code: ^code}}}
      refute_receive {:unsubscribe, _, _, _}, 20
    end
  end

  test "a dead receiver stops the subscription and releases the handle", %{consumed: consumed} do
    context = Context.new!(request_id: "req-receiver")
    test_pid = self()

    receiver =
      spawn(fn ->
        receive do
          :quit -> :ok
        end
      end)

    {:ok, spec} =
      ConsumedThing.observation_child_spec(consumed, "temperature", context,
        id: :receiver_watch,
        receiver: receiver,
        restart: :temporary
      )

    pid = start_supervised!(spec)
    monitor = Process.monitor(pid)
    assert_receive {:subscribe, _, ^pid, _}

    send(receiver, :quit)
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, :receiver_down}}
    assert_receive {:unsubscribe, _handle, %{operation: :unobserveproperty}, _}
    assert Process.alive?(test_pid)
  end

  test "a receiver that is already dead prevents any protocol open", %{consumed: consumed} do
    context = Context.new!(request_id: "req-dead-receiver")
    dead = spawn(fn -> :ok end)
    ref = Process.monitor(dead)
    assert_receive {:DOWN, ^ref, :process, ^dead, _}

    {:ok, spec} =
      ConsumedThing.observation_child_spec(consumed, "temperature", context,
        id: :dead_receiver,
        receiver: dead,
        restart: :temporary
      )

    pid = start_watched(spec)
    assert_receive {:exited, ^pid, {:shutdown, :receiver_down}}
    refute_receive {:subscribe, _, _, _}, 20
  end

  test "a linked transport process exit is reported and stops the subscription", %{profile: profile} do
    context = Context.new!(request_id: "req-linked")

    {:ok, consumed} =
      ConsumedThing.new(TDFactory.thing_description(),
        profiles: [profile],
        transports: %{profile.id => {FakeTransport, %{test_pid: self(), subscribe_mode: :linked}}},
        credentials: {FakeCredentials, %{test_pid: self()}}
      )

    {:ok, spec} =
      ConsumedThing.event_subscription_child_spec(consumed, "alarm", context,
        id: :linked_alarm,
        receiver: self(),
        restart: :temporary
      )

    pid = start_supervised!(spec)
    monitor = Process.monitor(pid)
    assert_receive {:connection, connection}

    send(connection, {:deliver, "alarm-1"})
    assert_receive {:wotex_runtime, :linked_alarm, {:ok, "alarm-1", %{}}}

    helper = spawn_link_from(pid, fn -> :ok end)
    wait_for_exit(helper)
    assert Process.alive?(pid)
    send(pid, {:wotex_transport, {:ok, "still-alive", %{}}})
    assert_receive {:wotex_runtime, :linked_alarm, {:ok, "still-alive", %{}}}

    send(connection, :crash)
    assert_receive {:wotex_runtime, :linked_alarm, {:status, :transport_down}}
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, :transport_down}}
    assert_receive {:unsubscribe, ^connection, %{operation: :unsubscribeevent}, _}
  end

  test "transport status messages reach the receiver and session loss stops the child", %{
    consumed: consumed
  } do
    context = Context.new!(request_id: "req-status")

    {:ok, spec} =
      ConsumedThing.event_subscription_child_spec(consumed, "alarm", context,
        id: :status_alarm,
        receiver: self(),
        restart: :temporary
      )

    pid = start_supervised!(spec)
    monitor = Process.monitor(pid)
    assert_receive {:subscribe, _, ^pid, _}

    send(pid, {:wotex_transport_status, :reconnected})
    assert_receive {:wotex_runtime, :status_alarm, {:status, :reconnected}}
    assert Process.alive?(pid)

    send(pid, {:wotex_transport_status, :session_lost})
    assert_receive {:wotex_runtime, :status_alarm, {:status, :session_lost}}
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, :session_lost}}
    assert_receive {:unsubscribe, _handle, %{operation: :unsubscribeevent}, _}
  end

  test "a supervisor restart after session loss resolves fresh credentials and resubscribes", %{
    profile: profile
  } do
    context = Context.new!(request_id: "req-resubscribe")
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    {:ok, consumed} =
      ConsumedThing.new(TDFactory.thing_description(),
        profiles: [profile],
        transports: %{profile.id => {FakeTransport, %{test_pid: self()}}},
        credentials: {FakeCredentials, %{test_pid: self(), counter: counter}}
      )

    {:ok, spec} =
      ConsumedThing.event_subscription_child_spec(consumed, "alarm", context,
        id: :restarting_alarm,
        receiver: self(),
        restart: :permanent
      )

    supervisor =
      start_supervised!(%{
        id: :restart_supervisor,
        start: {Supervisor, :start_link, [[spec], [strategy: :one_for_one, max_restarts: 3]]},
        type: :supervisor
      })

    assert_receive {:subscribe, _, first_pid, _}
    send(first_pid, {:wotex_transport_status, :session_lost})
    assert_receive {:wotex_runtime, :restarting_alarm, {:status, :session_lost}}
    assert_receive {:unsubscribe, _, %{operation: :unsubscribeevent}, _}
    assert_receive {:subscribe, _, second_pid, _}
    refute second_pid == first_pid

    assert [{:restarting_alarm, ^second_pid, :worker, _modules}] =
             Supervisor.which_children(supervisor)

    assert :ok = Subscription.stop(second_pid)
  end

  test "supervisor termination releases the handle before a fresh restart", %{consumed: consumed} do
    context = Context.new!(request_id: "req-supervised")

    {:ok, spec} =
      ConsumedThing.event_subscription_child_spec(consumed, "alarm", context,
        id: :supervised_alarm,
        receiver: self(),
        restart: :transient
      )

    supervisor =
      start_supervised!(%{
        id: :subscription_supervisor,
        start: {Supervisor, :start_link, [[], [strategy: :one_for_one]]},
        type: :supervisor
      })

    assert {:ok, first_pid} = Supervisor.start_child(supervisor, spec)
    assert_receive {:subscribe, %{operation: :subscribeevent}, ^first_pid, _}
    first_handle = bound_handle(first_pid)

    assert :ok = Supervisor.terminate_child(supervisor, :supervised_alarm)
    refute Process.alive?(first_pid)
    assert_receive {:unsubscribe, ^first_handle, %{operation: :unsubscribeevent}, _}
    refute_receive {:unsubscribe, ^first_handle, _, _}

    assert {:ok, second_pid} = Supervisor.restart_child(supervisor, :supervised_alarm)
    refute second_pid == first_pid
    assert_receive {:subscribe, %{operation: :subscribeevent}, ^second_pid, _}
    second_handle = bound_handle(second_pid)

    assert :ok = Subscription.stop(second_pid)
    assert_receive {:unsubscribe, ^second_handle, %{operation: :unsubscribeevent}, _}
    refute_receive {:unsubscribe, ^second_handle, _, _}
  end

  test "a brutal kill neither crashes the receiver nor unsubscribes", %{consumed: consumed} do
    context = Context.new!(request_id: "req-kill")

    {:ok, spec} =
      ConsumedThing.event_subscription_child_spec(consumed, "alarm", context,
        id: :killed_alarm,
        receiver: self(),
        restart: :temporary
      )

    pid = start_supervised!(spec)
    monitor = Process.monitor(pid)
    assert_receive {:subscribe, _, ^pid, _}
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    refute_receive {:unsubscribe, _, _, _}, 20
    assert Process.alive?(self())
  end

  test "a bounded receiver mailbox drops or stops according to the overflow policy", %{
    consumed: consumed
  } do
    context = Context.new!(request_id: "req-overflow")
    parent = self()

    handler = fn event, measurements, metadata, _config ->
      send(parent, {:telemetry, event, measurements, metadata})
    end

    id = "overflow-#{inspect(self())}"
    :telemetry.attach(id, [:wotex, :runtime, :subscription, :drop], handler, nil)
    on_exit(fn -> :telemetry.detach(id) end)

    slow = spawn(fn -> Process.sleep(:infinity) end)
    Enum.each(1..5, &send(slow, {:backlog, &1}))

    {:ok, drop_spec} =
      ConsumedThing.observation_child_spec(consumed, "temperature", context,
        id: :dropping,
        receiver: slow,
        restart: :temporary,
        max_queue_length: 3,
        overflow: :drop
      )

    drop_pid = start_supervised!(drop_spec)
    assert_receive {:subscribe, _, ^drop_pid, _}
    send(drop_pid, {:wotex_transport, {:ok, 1, %{}}})

    assert_receive {:telemetry, [:wotex, :runtime, :subscription, :drop], %{queue_length: 5},
                    %{subscription_id: :dropping}}

    assert Process.alive?(drop_pid)
    assert {:message_queue_len, 5} = Process.info(slow, :message_queue_len)

    {:ok, stop_spec} =
      ConsumedThing.observation_child_spec(consumed, "temperature", context,
        id: :stopping,
        receiver: slow,
        restart: :temporary,
        max_queue_length: 3,
        overflow: :stop
      )

    stop_pid = start_supervised!(stop_spec)
    monitor = Process.monitor(stop_pid)
    assert_receive {:subscribe, _, ^stop_pid, _}
    send(stop_pid, {:wotex_transport, {:ok, 1, %{}}})
    assert_receive {:DOWN, ^monitor, :process, ^stop_pid, {:shutdown, :overloaded}}
    assert_receive {:unsubscribe, _, %{operation: :unobserveproperty}, _}
    Process.exit(slow, :kill)

    assert {:error, %Error{code: :invalid_max_queue_length}} =
             ConsumedThing.observation_child_spec(consumed, "temperature", context,
               id: :bad,
               receiver: self(),
               max_queue_length: 0
             )

    assert {:error, %Error{code: :invalid_overflow_policy}} =
             ConsumedThing.observation_child_spec(consumed, "temperature", context,
               id: :bad,
               receiver: self(),
               overflow: :panic
             )

    assert {:error, %Error{code: :invalid_receiver}} =
             ConsumedThing.observation_child_spec(consumed, "temperature", context,
               id: :bad,
               receiver: "not-a-process"
             )

    for {option, code} <- [
          {[name: "not-a-name"], :invalid_subscription_name},
          {[restart: :sometimes], :invalid_restart_policy},
          {[shutdown: -1], :invalid_shutdown_budget},
          {[unknown: true], :invalid_subscription_options}
        ] do
      assert {:error, %Error{code: ^code}} =
               ConsumedThing.observation_child_spec(
                 consumed,
                 "temperature",
                 context,
                 [id: :bad, receiver: self()] ++ option
               )
    end

    assert {:error, %Error{code: :invalid_subscription_options}} =
             ConsumedThing.observation_child_spec(
               consumed,
               "temperature",
               context,
               id: :bad,
               id: :duplicate,
               receiver: self()
             )

    assert {:error, %Error{code: :invalid_subscription_options}} =
             ConsumedThing.observation_child_spec(
               consumed,
               "temperature",
               context,
               [{:id, :bad}, {:receiver, self()}, :not_keyword]
             )
  end

  test "credential callback failures at close still release the transport handle", %{
    profile: profile
  } do
    for {mode, code} <- [
          error: :credential_resolution_failed,
          raise: :port_exception,
          exit: :port_exception,
          throw: :port_exception,
          invalid: :invalid_credentials_return
        ] do
      context = Context.new!(request_id: "req-close-credentials-#{mode}")
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      {:ok, consumed} =
        ConsumedThing.new(TDFactory.thing_description(),
          profiles: [profile],
          transports: %{profile.id => {FakeTransport, %{test_pid: self()}}},
          credentials:
            {FakeCredentials, %{test_pid: self(), counter: counter, mode: {:stop_only, mode}}}
        )

      {:ok, spec} =
        ConsumedThing.event_subscription_child_spec(consumed, "alarm", context,
          id: {:close_credentials, mode},
          receiver: self(),
          restart: :temporary
        )

      pid = start_supervised!(spec)
      assert_receive {:subscribe, _, ^pid, "credential-material"}
      handle = bound_handle(pid)

      assert {:error, %Error{code: ^code}} = Subscription.stop(pid)
      assert_receive {:unsubscribe, ^handle, %{operation: :unsubscribeevent}, nil}
    end
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

    assert_receive {:subscribe, %{operation: :subscribeevent}, subscription_pid, _}
                   when subscription_pid in [pid_a, pid_b]

    assert_receive {:subscribe, %{operation: :subscribeevent}, subscription_pid, _}
                   when subscription_pid in [pid_a, pid_b]

    send(pid_a, {:wotex_transport, {:ok, "alarm-a", %{}}})
    send(pid_b, {:wotex_transport, {:ok, "alarm-b", %{}}})
    assert_receive {:wotex_runtime, :alarm_a, {:ok, "alarm-a", %{}}}
    assert_receive {:wotex_runtime, :alarm_b, {:ok, "alarm-b", %{}}}

    assert :ok = Subscription.stop(pid_a)
    assert :ok = Subscription.stop(pid_b)
  end

  test "aggregate Property and Event child specifications use exact stop operations", %{
    consumed: consumed
  } do
    context = Context.new!(request_id: "req-aggregate")

    {:ok, property_spec} =
      ConsumedThing.all_properties_observation_child_spec(consumed, context,
        id: :all_properties,
        receiver: self(),
        restart: :temporary
      )

    property_pid = start_supervised!(property_spec)
    assert_receive {:subscribe, %{operation: :observeallproperties}, ^property_pid, _credential}
    assert :ok = Subscription.stop(property_pid)
    assert_receive {:unsubscribe, _handle, %{operation: :unobserveallproperties}, _credential}

    {:ok, event_spec} =
      ConsumedThing.all_events_subscription_child_spec(consumed, context,
        id: :all_events,
        receiver: self(),
        restart: :temporary
      )

    event_pid = start_supervised!(event_spec)
    assert_receive {:subscribe, %{operation: :subscribeallevents}, ^event_pid, _credential}
    assert :ok = Subscription.stop(event_pid)
    assert_receive {:unsubscribe, _handle, %{operation: :unsubscribeallevents}, _credential}
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

  test "ignores unrelated messages and normalizes stop failures" do
    profile = TDFactory.http_profile()
    context = Context.new!(request_id: "req-stop-failure")

    failures = [
      error: :transport_unsubscribe_failed,
      invalid: :invalid_transport_return,
      raise: :port_exception,
      exit: :port_exception,
      throw: :port_exception
    ]

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

  test "concurrent stop requests unsubscribe once and return typed outcomes", %{profile: profile} do
    context = Context.new!(request_id: "req-concurrent-stop")

    {:ok, consumed} =
      ConsumedThing.new(TDFactory.thing_description(),
        profiles: [profile],
        transports: %{
          profile.id => {FakeTransport, %{test_pid: self(), unsubscribe_mode: {:wait, self()}}}
        },
        credentials: {FakeCredentials, %{test_pid: self()}}
      )

    {:ok, spec} =
      ConsumedThing.event_subscription_child_spec(consumed, "alarm", context,
        id: :concurrent_stop,
        receiver: self(),
        restart: :temporary
      )

    pid = start_supervised!(spec)
    assert_receive {:subscribe, _, ^pid, _}

    first = Task.async(fn -> Subscription.stop(pid) end)
    assert_receive {:unsubscribe, _handle, %{operation: :unsubscribeevent}, _credential}
    assert_receive {:unsubscribe_waiting, ^pid}
    second = Task.async(fn -> Subscription.stop(pid) end)
    wait_for_mailbox(pid)
    send(pid, :release_unsubscribe)

    results = [Task.await(first), Task.await(second)]
    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.count(results, &match?({:error, %Error{code: :subscription_not_running}}, &1)) == 1
    refute_receive {:unsubscribe, _, _, _}
  end

  test "close telemetry exposes normalized outcome without raw termination reasons", %{
    consumed: consumed
  } do
    parent = self()
    secret = "must-not-appear"

    handler = fn event, _measurements, metadata, _config ->
      send(parent, {:close_telemetry, event, metadata})
    end

    id = "close-#{inspect(self())}"
    :telemetry.attach(id, [:wotex, :runtime, :subscription, :close], handler, nil)
    on_exit(fn -> :telemetry.detach(id) end)

    context = Context.new!(request_id: "req-close-telemetry", metadata: %{marker: secret})

    {:ok, spec} =
      ConsumedThing.event_subscription_child_spec(consumed, "alarm", context,
        id: :close_telemetry,
        receiver: self(),
        restart: :temporary
      )

    pid = start_supervised!(spec)
    assert_receive {:subscribe, _, ^pid, _}
    assert :ok = Subscription.stop(pid)

    assert_receive {:close_telemetry, [:wotex, :runtime, :subscription, :close],
                    %{outcome: :normal} = metadata}

    refute Map.has_key?(metadata, :reason)
    refute inspect(metadata) =~ secret
  end

  test "stop rejects invalid timeouts and a stopped server without exiting the caller" do
    assert {:error, %Error{code: :invalid_stop_timeout}} = Subscription.stop(self(), -1)

    blocked = spawn(fn -> Process.sleep(:infinity) end)

    assert {:error, %Error{code: :subscription_stop_timeout, class: :timeout}} =
             Subscription.stop(blocked, 0)

    Process.exit(blocked, :kill)

    stopped = spawn(fn -> :ok end)
    wait_for_exit(stopped)

    assert {:error, %Error{code: :subscription_not_running}} = Subscription.stop(stopped)
  end

  # Spawns a helper linked to `owner` from inside the owner's own process context.
  defp spawn_link_from(owner, fun) do
    parent = self()

    :sys.replace_state(owner, fn state ->
      helper =
        spawn_link(fn ->
          send(parent, {:helper, self()})
          fun.()
        end)

      send(parent, {:helper, helper})
      state
    end)

    assert_receive {:helper, helper}
    helper
  end

  # Starts the child under a trapping parent so the exact exit reason is observable.
  defp start_watched(%{start: {module, function, arguments}}) do
    parent = self()

    spawn_link(fn ->
      Process.flag(:trap_exit, true)
      {:ok, pid} = apply(module, function, arguments)
      send(parent, {:started, pid})

      receive do
        {:EXIT, ^pid, reason} -> send(parent, {:exited, pid, reason})
      end
    end)

    assert_receive {:started, pid}
    pid
  end

  defp wait_for_exit(pid) do
    monitor = Process.monitor(pid)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _reason} -> :ok
    after
      1_000 -> flunk("helper did not exit")
    end
  end

  defp wait_for_mailbox(pid, attempts \\ 100)

  defp wait_for_mailbox(_pid, 0), do: flunk("concurrent stop did not enter the mailbox")

  defp wait_for_mailbox(pid, attempts) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, length} when length > 0 ->
        :ok

      _other ->
        Process.sleep(1)
        wait_for_mailbox(pid, attempts - 1)
    end
  end

  defp unique_name(suffix),
    do: {:global, {:wotex_runtime_test, suffix, System.unique_integer([:positive])}}

  defp bound_handle(pid, remaining \\ 50) do
    case :sys.get_state(pid) do
      %{active?: true, handle: handle} ->
        handle

      _ignored_1 ->
        assert remaining > 0
        Process.sleep(1)
        bound_handle(pid, remaining - 1)
    end
  end
end
