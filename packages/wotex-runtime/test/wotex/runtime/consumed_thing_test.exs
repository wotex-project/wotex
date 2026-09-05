defmodule Wotex.Runtime.ConsumedThingTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Runtime.{ConsumedThing, Context, Error, ExecutionContext, Request, Result}
  alias Wotex.Runtime.Test.{FakeCredentials, FakeTransport, TDFactory}

  setup do
    profile = TDFactory.http_profile()
    secret = "credential-material"

    credentials = {FakeCredentials, %{test_pid: self(), secret: secret}}
    transports = %{profile.id => {FakeTransport, %{test_pid: self()}}}

    {:ok, consumed} =
      ConsumedThing.new(TDFactory.thing_description(),
        profiles: [profile],
        transports: transports,
        credentials: credentials
      )

    %{consumed: consumed, profile: profile, secret: secret}
  end

  test "constructs from an explicit complete port table", %{consumed: consumed} do
    assert %Wotex.ThingDescription{} = ConsumedThing.thing_description(consumed)
  end

  test "rejects incomplete and ambiguous construction", %{profile: profile} do
    td = TDFactory.thing_description()
    credentials = {FakeCredentials, %{test_pid: self(), secret: "x"}}

    assert {:error, %Error{code: :invalid_profiles}} =
             ConsumedThing.new(td, profiles: [], transports: %{}, credentials: credentials)

    assert {:error, %Error{code: :duplicate_profile_id}} =
             ConsumedThing.new(td,
               profiles: [profile, profile],
               transports: %{profile.id => {FakeTransport, %{}}},
               credentials: credentials
             )

    assert {:error, %Error{code: :missing_transport}} =
             ConsumedThing.new(td, profiles: [profile], transports: %{}, credentials: credentials)

    assert {:error, %Error{code: :invalid_transports}} =
             ConsumedThing.new(td, profiles: [profile], transports: [], credentials: credentials)

    assert {:error, %Error{code: :invalid_credentials_port}} =
             ConsumedThing.new(td,
               profiles: [profile],
               transports: %{profile.id => {FakeTransport, %{}}},
               credentials: nil
             )

    assert {:error, %Error{code: :invalid_consumed_thing}} = ConsumedThing.new(%{}, [])
  end

  test "executes every short operation in the caller and resolves credentials first", %{
    consumed: consumed,
    secret: secret
  } do
    context = Context.new!(request_id: "req-sync")

    operations = [
      {:readproperty, fn -> ConsumedThing.read_property(consumed, "temperature", context) end},
      {:writeproperty,
       fn ->
         ConsumedThing.write_property(consumed, "temperature", 23.0, context)
       end},
      {:invokeaction, fn -> ConsumedThing.invoke_action(consumed, "calibrate", 0.25, context) end},
      {:queryaction, fn -> ConsumedThing.query_action(consumed, "calibrate", "inv-1", context) end},
      {:cancelaction,
       fn -> ConsumedThing.cancel_action(consumed, "calibrate", "inv-1", context) end},
      {:readallproperties, fn -> ConsumedThing.read_all_properties(consumed, context) end},
      {:readmultipleproperties,
       fn -> ConsumedThing.read_multiple_properties(consumed, ["temperature"], context) end},
      {:writeallproperties,
       fn -> ConsumedThing.write_all_properties(consumed, %{"temperature" => 23.0}, context) end},
      {:writemultipleproperties,
       fn ->
         ConsumedThing.write_multiple_properties(consumed, %{"temperature" => 23.0}, context)
       end},
      {:queryallactions, fn -> ConsumedThing.query_all_actions(consumed, context) end}
    ]

    Enum.each(operations, fn {operation, call} ->
      assert {:ok, %Result{operation: ^operation, request_id: "req-sync"}} = call.()
      assert_receive {:credentials, _security, _form, "req-sync"}
      assert_receive {:request, %Request{operation: ^operation}, "req-sync", ^secret}
    end)
  end

  test "rejects malformed aggregate Property inputs", %{consumed: consumed} do
    context = Context.new!(request_id: "req-aggregate-invalid")

    assert {:error, %Error{code: :invalid_property_names}} =
             ConsumedThing.read_multiple_properties(consumed, [], context)

    assert {:error, %Error{code: :invalid_property_names}} =
             ConsumedThing.read_multiple_properties(consumed, ["temperature", ""], context)

    assert {:error, %Error{code: :invalid_property_map}} =
             ConsumedThing.write_all_properties(consumed, %{}, context)

    assert {:error, %Error{code: :invalid_property_map}} =
             ConsumedThing.write_multiple_properties(consumed, %{temperature: 23.0}, context)
  end

  test "credentials are absent from requests, inspection, and normalized errors", %{
    consumed: consumed,
    secret: secret,
    profile: profile
  } do
    context = Context.new!(request_id: "req-secret")
    assert {:ok, _result} = ConsumedThing.read_property(consumed, "temperature", context)

    assert_receive {:credentials, _security, _form, "req-secret"}
    assert_receive {:request, request, "req-secret", ^secret}
    refute inspect(request) =~ secret

    execution_context = ExecutionContext.new(context, secret)
    refute inspect(execution_context) =~ secret

    {:ok, failed_transport} =
      ConsumedThing.new(TDFactory.thing_description(),
        profiles: [profile],
        transports: %{profile.id => {FakeTransport, %{test_pid: self(), mode: :error}}},
        credentials: {FakeCredentials, %{test_pid: self(), secret: secret}}
      )

    assert {:error, error} =
             ConsumedThing.read_property(failed_transport, "temperature", context)

    refute inspect(error) =~ secret

    {:ok, failed_credentials} =
      ConsumedThing.new(TDFactory.thing_description(),
        profiles: [profile],
        transports: %{profile.id => {FakeTransport, %{test_pid: self()}}},
        credentials: {FakeCredentials, %{test_pid: self(), secret: secret, mode: :error}}
      )

    assert {:error, credential_error} =
             ConsumedThing.read_property(failed_credentials, "temperature", context)

    refute inspect(credential_error) =~ secret
  end

  test "normalizes invalid and mismatched port returns", %{profile: profile} do
    context = Context.new!(request_id: "req-invalid")
    credentials = {FakeCredentials, %{test_pid: self(), secret: "x"}}

    failures = [mismatch: :mismatched_transport_result, invalid: :invalid_transport_return]

    for {mode, code} <- failures do
      {:ok, consumed} =
        ConsumedThing.new(TDFactory.thing_description(),
          profiles: [profile],
          transports: %{profile.id => {FakeTransport, %{test_pid: self(), mode: mode}}},
          credentials: credentials
        )

      assert {:error, %Error{code: ^code}} =
               ConsumedThing.read_property(consumed, "temperature", context)
    end

    {:ok, invalid_credentials} =
      ConsumedThing.new(TDFactory.thing_description(),
        profiles: [profile],
        transports: %{profile.id => {FakeTransport, %{test_pid: self()}}},
        credentials: {FakeCredentials, %{test_pid: self(), secret: "x", mode: :invalid}}
      )

    assert {:error, %Error{code: :invalid_credentials_return}} =
             ConsumedThing.read_property(invalid_credentials, "temperature", context)
  end

  test "returns typed failures for invalid runtime calls", %{consumed: consumed} do
    context = Context.new!(request_id: "req-error")

    assert {:error, %Error{code: :affordance_not_found}} =
             ConsumedThing.read_property(consumed, "missing", context)

    assert {:error, %Error{code: :invalid_context}} =
             ConsumedThing.read_property(consumed, "temperature", %{})

    assert {:error, %Error{code: :invalid_consumed_thing}} =
             ConsumedThing.read_property(%{}, "temperature", context)
  end

  test "rejects a nil required option and a missing selected transport", %{consumed: consumed} do
    context = Context.new!(request_id: "req-boundary")

    assert {:error, %Error{code: :missing_subscription_option}} =
             ConsumedThing.observation_child_spec(consumed, "temperature", context,
               id: nil,
               receiver: self()
             )

    without_transport = %{consumed | transports: %{}}

    assert {:error, %Error{code: :transport_not_found}} =
             ConsumedThing.read_property(without_transport, "temperature", context)
  end
end
