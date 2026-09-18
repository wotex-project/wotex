defmodule Wotex.Lab.LoopbackTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.{Lab, ThingDescription}
  alias Wotex.Lab.Adapters.Runtime.{Loopback, NoSec, StaticRef}
  alias Wotex.Lab.Reference.Thing

  alias Wotex.Runtime.{
    BindingProfile,
    ConsumedThing,
    Context,
    Error,
    ExecutionContext,
    FormSelector,
    Request,
    Result,
    Retry,
    Subscription
  }

  @secret "room-token-7f3a"

  setup do
    lab = start_supervised!({Lab, id: "loopback", max_children: 16})
    td = fixture()

    {:ok, host} =
      Lab.start_child(
        lab,
        :things,
        {Thing,
         td: td,
         state: %{"temperature" => 20.0, "target" => 21.0},
         tokens: %{"bearer_sc" => @secret}}
      )

    {:ok, profile} =
      BindingProfile.new(
        id: :loopback,
        schemes: ["loopback"],
        operations: Wotex.Runtime.operations(),
        media_types: ["application/json"]
      )

    credentials =
      {StaticRef,
       %{
         references: %{"bearer_sc" => "vault://room/token"},
         lookup: fn "vault://room/token" -> {:ok, @secret} end
       }}

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{loopback: {Loopback, %{host: host}}},
        credentials: credentials
      )

    %{lab: lab, host: host, td: td, profile: profile, consumed: consumed}
  end

  test "requests cross the runtime seam with admission, identity and inert results", %{
    consumed: consumed,
    host: host
  } do
    context =
      Context.new!(request_id: "req-read", deadline: System.monotonic_time(:millisecond) + 1_000)

    assert {:ok,
            %Result{operation: :readproperty, request_id: "req-read", status: :ok, payload: 20.0}} =
             ConsumedThing.read_property(consumed, "temperature", context)

    assert {:ok, %Result{status: :ok, payload: nil}} =
             ConsumedThing.write_property(consumed, "target", 24.5, context)

    assert {:ok, %Result{status: :accepted, payload: %{"accepted" => true, "input" => 23.0}}} =
             ConsumedThing.invoke_action(consumed, "setTarget", 23.0, context)

    assert %{handler_calls: 3, rejected: 0, state: %{"target" => 24.5, "setTarget" => 23.0}} =
             Thing.stats(host)

    assert {:error, %Error{code: :compatible_form_not_found}} =
             ConsumedThing.write_property(consumed, "temperature", 1.0, context)

    assert {:error, %Error{code: :transport_request_failed, class: :permanent} = error} =
             ConsumedThing.write_property(consumed, "target", 99.0, context)

    assert error.details.cause.code == :input_out_of_range
    assert %{handler_calls: 3, rejected: 1} = Thing.stats(host)
    assert :stop = Retry.decision(:writeproperty, error, attempt: 1, max_attempts: 3)
  end

  test "credentials are resolved just in time and never retained", %{
    td: td,
    host: host,
    profile: profile
  } do
    wrong =
      {StaticRef,
       %{
         references: %{"bearer_sc" => "vault://room/token"},
         lookup: fn _ -> {:ok, "wrong"} end
       }}

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{loopback: {Loopback, %{host: host}}},
        credentials: wrong
      )

    context = Context.new!(request_id: "req-unauthorized")

    assert {:error, %Error{details: %{cause: %{code: :unauthorized}}} = error} =
             ConsumedThing.write_property(consumed, "target", 22.0, context)

    refute inspect(error) =~ @secret
    refute inspect(error) =~ "wrong"
    assert %{handler_calls: 0, rejected: 1} = Thing.stats(host)

    {:ok, nosec} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{loopback: {Loopback, %{host: host}}},
        credentials: {NoSec, []}
      )

    assert {:ok, %Result{payload: 20.0}} =
             ConsumedThing.read_property(nosec, "temperature", context)

    assert {:error,
            %Error{
              code: :credential_resolution_failed,
              details: %{cause: %{code: :security_scheme_not_nosec}}
            }} =
             ConsumedThing.write_property(nosec, "target", 22.0, context)

    missing =
      {StaticRef, %{references: %{}, lookup: fn _ -> {:ok, @secret} end}}

    {:ok, unresolved} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{loopback: {Loopback, %{host: host}}},
        credentials: missing
      )

    assert {:error, %Error{details: %{cause: %{code: :unresolved_reference}}} = error} =
             ConsumedThing.write_property(unresolved, "target", 22.0, context)

    refute inspect(error) =~ "vault://"
  end

  test "observations run under the instance's session role and decode frames in the owner", %{
    lab: lab,
    consumed: consumed,
    host: host
  } do
    context = Context.new!(request_id: "req-observe")

    {:ok, spec} =
      ConsumedThing.observation_child_spec(consumed, "temperature", context,
        id: :observe_temperature,
        receiver: self(),
        restart: :temporary
      )

    assert {:ok, pid} = Lab.start_child(lab, :sessions, spec)
    assert %{subscriptions: 1} = wait_until(fn -> Thing.stats(host) end, &(&1.subscriptions == 1))
    refute inspect(:sys.get_state(pid)) =~ @secret

    :ok = Thing.emit(host, "temperature", 21.5, %{observed_at: 1_000})

    assert_receive {:wotex_runtime, :observe_temperature,
                    {:ok, 21.5, %{observed_at: 1_000, affordance_name: "temperature"}}}

    :ok = Thing.keepalive(host)
    :ok = Thing.emit(host, "target", 30.0)
    refute_receive {:wotex_runtime, :observe_temperature, _}, 50

    send(pid, {:wotex_transport_frame, {:bogus}})

    assert_receive {:wotex_runtime, :observe_temperature,
                    {:error, %Error{code: :undecodable_frame, class: :protocol}}}

    assert :ok = Subscription.stop(pid)
    assert %{subscriptions: 0} = Thing.stats(host)
  end

  test "session loss, host death and receiver death all stop the subscription cleanly", %{
    lab: lab,
    consumed: consumed,
    host: host,
    td: td,
    profile: profile
  } do
    context = Context.new!(request_id: "req-loss")

    {:ok, spec} =
      ConsumedThing.event_subscription_child_spec(consumed, "alarm", context,
        id: :alarm,
        receiver: self(),
        restart: :temporary
      )

    {:ok, pid} = Lab.start_child(lab, :sessions, spec)
    monitor = Process.monitor(pid)
    wait_until(fn -> Thing.stats(host) end, &(&1.subscriptions == 1))

    :ok = Thing.raise_event(host, "alarm", "smoke", %{severity: "high"})

    assert_receive {:wotex_runtime, :alarm,
                    {:ok, "smoke", %{severity: "high", affordance_name: "alarm"}}}

    :ok = Thing.disconnect(host)
    assert_receive {:wotex_runtime, :alarm, {:status, :session_lost}}
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, :session_lost}}

    # A second host whose death must surface as a transport exit.
    {:ok, second_host} =
      Lab.start_child(
        lab,
        :things,
        {Thing, id: :second, td: td, state: %{"temperature" => 1.0}, restart: :temporary}
      )

    {:ok, second} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{loopback: {Loopback, %{host: second_host}}},
        credentials: {NoSec, []}
      )

    {:ok, spec} =
      ConsumedThing.observation_child_spec(second, "temperature", context,
        id: :host_death,
        receiver: self(),
        restart: :temporary
      )

    {:ok, pid} = Lab.start_child(lab, :sessions, spec)
    monitor = Process.monitor(pid)
    wait_until(fn -> Thing.stats(second_host) end, &(&1.subscriptions == 1))
    Process.exit(second_host, :kill)
    assert_receive {:wotex_runtime, :host_death, {:status, :transport_down}}
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, :transport_down}}

    # A receiver that dies drops the host registration through the owner's monitor.
    receiver = spawn(fn -> receive do: (:quit -> :ok) end)

    {:ok, spec} =
      ConsumedThing.observation_child_spec(consumed, "temperature", context,
        id: :receiver_death,
        receiver: receiver,
        restart: :temporary
      )

    {:ok, pid} = Lab.start_child(lab, :sessions, spec)
    monitor = Process.monitor(pid)
    wait_until(fn -> Thing.stats(host) end, &(&1.subscriptions == 1))
    send(receiver, :quit)
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, :receiver_down}}
    assert %{subscriptions: 0} = wait_until(fn -> Thing.stats(host) end, &(&1.subscriptions == 0))
  end

  test "a permanent session resubscribes with fresh credentials after session loss", %{
    lab: lab,
    consumed: consumed,
    host: host
  } do
    context = Context.new!(request_id: "req-resubscribe")

    {:ok, spec} =
      ConsumedThing.observation_child_spec(consumed, "temperature", context,
        id: :durable,
        receiver: self(),
        restart: :permanent
      )

    {:ok, first} = Lab.start_child(lab, :sessions, spec)
    wait_until(fn -> Thing.stats(host) end, &(&1.subscriptions == 1))
    :ok = Thing.disconnect(host)
    assert_receive {:wotex_runtime, :durable, {:status, :session_lost}}
    assert %{subscriptions: 1} = wait_until(fn -> Thing.stats(host) end, &(&1.subscriptions == 1))

    :ok = Thing.emit(host, "temperature", 19.0)
    assert_receive {:wotex_runtime, :durable, {:ok, 19.0, _meta}}
    refute Process.alive?(first)
  end

  test "port exceptions from a dead host are isolated and reported through telemetry", %{
    td: td,
    profile: profile
  } do
    id = "loopback-#{inspect(self())}"

    :telemetry.attach(
      id,
      [:wotex, :runtime, :port, :exception],
      &__MODULE__.forward_telemetry/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(id) end)

    dead = spawn(fn -> :ok end)
    ref = Process.monitor(dead)
    assert_receive {:DOWN, ^ref, :process, ^dead, _}

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{loopback: {Loopback, %{host: dead}}},
        credentials: {NoSec, []}
      )

    context = Context.new!(request_id: "req-dead-host")

    assert {:error, %Error{code: :port_exception, phase: :transport}} =
             ConsumedThing.read_property(consumed, "temperature", context)

    assert_receive {:telemetry, [:wotex, :runtime, :port, :exception],
                    %{callback: :request, kind: :exit}}
  end

  @doc false
  @spec forward_telemetry(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          pid()
        ) :: {:telemetry, :telemetry.event_name(), :telemetry.event_metadata()}
  def forward_telemetry(event, _, metadata, parent),
    do: send(parent, {:telemetry, event, metadata})

  defp fixture do
    path = Application.app_dir(:wotex_lab, "priv/fixtures/loopback/thing-description.json")
    {:ok, td} = ThingDescription.parse(File.read!(path))
    td
  end

  defp wait_until(read, predicate, attempts \\ 100) do
    value = read.()

    cond do
      predicate.(value) ->
        value

      attempts == 0 ->
        value

      true ->
        Process.sleep(5)
        wait_until(read, predicate, attempts - 1)
    end
  end

  test "the host admits routes, inputs and subscriptions and drops killed owners", %{
    lab: lab,
    host: host,
    td: td,
    profile: profile,
    consumed: consumed
  } do
    context = Context.new!(request_id: "req-host")

    assert {:error, %Error{details: %{cause: %{code: :invalid_input_type}}}} =
             ConsumedThing.write_property(consumed, "target", "hot", context)

    assert {:ok, %Result{status: :ok}} =
             ConsumedThing.write_property(consumed, "label", "quiet", context)

    {:ok, selection} =
      FormSelector.select(td, :property, "temperature", :observeproperty, [profile])

    request = Request.from_selection(selection, context, nil)

    assert {:error, %Wotex.Lab.Error{code: :handler_not_found, phase: :host}} =
             Thing.request(host, request, nil)

    thing_level = %{
      request
      | affordance_type: :thing,
        affordance_name: nil,
        operation: :readallproperties
    }

    assert {:error, %Wotex.Lab.Error{code: :unsupported_operation}} =
             Thing.request(host, thing_level, nil)

    {:ok, target_selection} = FormSelector.select(td, :property, "target", :readproperty, [profile])
    target_request = Request.from_selection(target_selection, context, nil)

    assert {:error, %Wotex.Lab.Error{code: :unauthorized}} =
             Thing.subscribe(host, target_request, self(), nil)

    assert {:error, %Wotex.Lab.Error{code: :unknown_subscription}} =
             Thing.unsubscribe(host, make_ref())

    {:ok, spec} =
      ConsumedThing.observation_child_spec(consumed, "temperature", context,
        id: :killed_owner,
        receiver: self(),
        restart: :temporary
      )

    {:ok, pid} = Lab.start_child(lab, :sessions, spec)
    wait_until(fn -> Thing.stats(host) end, &(&1.subscriptions == 1))
    Process.exit(pid, :kill)
    assert %{subscriptions: 0} = wait_until(fn -> Thing.stats(host) end, &(&1.subscriptions == 0))
    :ok = Thing.raise_event(host, "alarm", "quiet")

    send(host, :unrelated)
    assert %{state: %{"temperature" => 20.0}} = Thing.stats(host)
  end

  test "hosts can be named and refuse an invalid Thing Description", %{lab: lab, td: td} do
    name = {:global, {:loopback_host, make_ref()}}
    assert {:ok, named} = Lab.start_child(lab, :things, {Thing, id: :named, td: td, name: name})
    assert GenServer.whereis(name) == named

    Process.flag(:trap_exit, true)

    assert {:error, :invalid_thing_description} =
             Thing.start_link(td: %Wotex.ThingDescription{document: %{}})
  end

  test "adapters reject invalid configuration and selections without leaking anything" do
    context = Context.new!(request_id: "req-config")
    execution = ExecutionContext.new(context, nil)
    {:ok, form} = Wotex.Form.new(%{"href" => "loopback://x"})
    {:ok, profile} = BindingProfile.new(id: :x, schemes: ["loopback"], operations: [:readproperty])

    request = %Request{
      operation: :readproperty,
      affordance_type: :property,
      affordance_name: "temperature",
      form: form,
      resolved_href: "loopback://x",
      profile: profile,
      request_id: "req-config",
      deadline: nil,
      input: nil
    }

    assert {:error, %Wotex.Lab.Error{code: :invalid_transport_config}} =
             Loopback.request(request, execution, %{})

    assert {:error, %Wotex.Lab.Error{code: :invalid_transport_config}} =
             Loopback.subscribe(request, self(), execution, %{})

    assert {:error, %Wotex.Lab.Error{code: :invalid_transport_config}} =
             Loopback.unsubscribe(:handle, request, execution, %{})

    assert {:error, %Wotex.Lab.Error{code: :invalid_security_selection}} =
             NoSec.resolve(nil, nil, context, [])

    assert {:error, %Wotex.Lab.Error{code: :invalid_security_selection}} =
             StaticRef.resolve(nil, nil, context, %{})

    selection = %{names: ["bearer_sc"], definitions: %{"bearer_sc" => %{"scheme" => "bearer"}}}

    assert {:error, %Wotex.Lab.Error{code: :invalid_credential_config}} =
             StaticRef.resolve(selection, nil, context, %{})
  end

  test "a bearer definition without a configured token is never satisfied", %{
    lab: lab,
    td: td,
    profile: profile
  } do
    {:ok, host} = Lab.start_child(lab, :things, {Thing, id: :tokenless, td: td})

    {:ok, consumed} =
      ConsumedThing.new(td,
        profiles: [profile],
        transports: %{loopback: {Loopback, %{host: host}}},
        credentials:
          {StaticRef, %{references: %{"bearer_sc" => "r"}, lookup: fn _ -> {:ok, "anything"} end}}
      )

    assert {:error, %Error{details: %{cause: %{code: :unauthorized}}}} =
             ConsumedThing.write_property(
               consumed,
               "target",
               22.0,
               Context.new!(request_id: "req-tokenless")
             )
  end
end
