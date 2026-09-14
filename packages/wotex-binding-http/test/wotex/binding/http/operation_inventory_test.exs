defmodule Wotex.Binding.HTTP.OperationInventoryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.HTTP
  alias Wotex.Binding.HTTP.{Error, Form, Headers, Request, Subscription, Transport}
  alias Wotex.Binding.HTTP.Test.Factory
  alias Wotex.Runtime.{BindingProfile, Context, Selection}

  @request_vectors [
    %{
      cell: "WBH-OP01",
      operation: :readproperty,
      outcome: "GET request",
      method: "GET",
      positive: "WBH-V01-P",
      negative: "WBH-V01-N",
      authority: "TD11-8.3.1-T32"
    },
    %{
      cell: "WBH-OP02",
      operation: :writeproperty,
      outcome: "PUT request",
      method: "PUT",
      positive: "WBH-V02-P",
      negative: "WBH-V02-N",
      authority: "TD11-8.3.1-T32"
    },
    %{
      cell: "WBH-OP03",
      operation: :invokeaction,
      outcome: "POST request",
      method: "POST",
      positive: "WBH-V03-P",
      negative: "WBH-V03-N",
      authority: "TD11-8.3.1-T32"
    },
    %{
      cell: "WBH-OP04",
      operation: :queryaction,
      outcome: "GET ActionStatus request",
      method: "GET",
      positive: "WBH-V04-P",
      negative: "WBH-V04-N",
      authority: "PROFILE-WD-6.2.2.2"
    },
    %{
      cell: "WBH-OP05",
      operation: :cancelaction,
      outcome: "DELETE ActionStatus request",
      method: "DELETE",
      positive: "WBH-V05-P",
      negative: "WBH-V05-N",
      authority: "PROFILE-WD-6.2.2.3"
    },
    %{
      cell: "WBH-OP06",
      operation: :observeproperty,
      outcome: "GET SSE open",
      method: "GET",
      positive: "WBH-V06-P",
      negative: "WBH-V06-N",
      authority: "PROFILE-WD-7.2.1.1"
    },
    %{
      cell: "WBH-OP08",
      operation: :subscribeevent,
      outcome: "GET SSE open",
      method: "GET",
      positive: "WBH-V08-P",
      negative: "WBH-V08-N",
      authority: "PROFILE-WD-7.2.2.1"
    }
  ]

  @stop_vectors [
    %{
      cell: "WBH-OP07",
      operation: :unobserveproperty,
      outcome: "close; no HTTP exchange",
      positive: "WBH-V07-P",
      negative: "WBH-V07-N",
      authority: "PROFILE-WD-7.2.1.2"
    },
    %{
      cell: "WBH-OP09",
      operation: :unsubscribeevent,
      outcome: "close; no HTTP exchange",
      positive: "WBH-V09-P",
      negative: "WBH-V09-N",
      authority: "PROFILE-WD-7.2.2.2"
    }
  ]

  @aggregate_vector %{
    cell: "WBH-OP10",
    operation: :thing_operations,
    outcome: "unsupported aggregate cell",
    positive: "WBH-V10-P",
    negative: "WBH-V10-N",
    authority: "WRT-THING+WBH.01"
  }

  for vector <- @request_vectors do
    @tag vector: vector.positive
    test "#{vector.positive} maps #{vector.operation} through the supplied client boundary" do
      assert_request_positive(unquote(Macro.escape(vector)))
    end

    @tag vector: vector.negative
    test "#{vector.negative} rejects an invalid #{vector.operation} before client I/O" do
      assert_request_negative(unquote(vector.operation))
    end
  end

  for vector <- @stop_vectors do
    @tag vector: vector.positive
    test "#{vector.positive} closes #{vector.operation} without an HTTP request" do
      assert_stop_positive(unquote(vector.operation))
    end

    @tag vector: vector.negative
    test "#{vector.negative} rejects an invalid #{vector.operation} close without client I/O" do
      assert_stop_negative(unquote(vector.operation))
    end
  end

  @tag vector: @aggregate_vector.positive
  test "WBH-V10-P excludes the complete Runtime Thing-operation aggregate" do
    assert {:ok, profile} = HTTP.profile()
    assert length(Wotex.Runtime.thing_operations()) == 9

    for operation <- Wotex.Runtime.thing_operations() do
      refute BindingProfile.supports_operation?(profile, operation)
    end
  end

  @tag vector: @aggregate_vector.negative
  test "WBH-V10-N defensively rejects forged aggregate selections before client I/O" do
    config = Factory.config()

    for operation <- Wotex.Runtime.thing_operations() do
      request = aggregate_request(operation)

      assert {:error, %Error{code: :unsupported_operation}} = Form.build(request, config)
    end

    refute_receive {:client_request, _, _}
    refute_receive {:client_subscribe, _, _, _}
  end

  defp assert_request_positive(vector) do
    operation = vector.operation
    config = positive_config(operation)
    request = Factory.request(operation, input(operation), form_overrides(operation))

    assert {:ok, profile} = HTTP.profile()
    assert BindingProfile.supports_operation?(profile, operation)
    assert {:ok, built} = Form.build(request, config)
    assert Request.method(built) == vector.method
    assert Request.operation(built) == operation
    assert_request_shape(built, operation)
    assert_client_path(request, built, operation, config)
  end

  defp assert_request_negative(operation) do
    config = Factory.config()
    {request, code} = negative_request(operation)

    result =
      if operation in [:observeproperty, :subscribeevent] do
        Transport.subscribe(request, self(), Factory.context(), config)
      else
        Transport.request(request, Factory.context(), config)
      end

    assert {:error, %Error{code: ^code}} = result
    refute_receive {:client_request, _, _}
    refute_receive {:client_subscribe, _, _, _}
  end

  defp assert_stop_positive(operation) do
    config = Factory.config(%{close_return: :ok})
    subscription = Subscription.new(config, :client_handle, "request-1", opening(operation))

    assert {:ok, profile} = HTTP.profile()
    assert BindingProfile.supports_operation?(profile, operation)

    assert :ok =
             Transport.unsubscribe(
               subscription,
               Factory.request(operation),
               Factory.context(:stop_credential),
               config
             )

    assert_receive {:client_close, :client_handle}
    refute_receive {:client_request, _, _}
    refute_receive {:client_subscribe, _, _, _}
  end

  defp assert_stop_negative(operation) do
    config = Factory.config(%{close_return: :ok})
    request = Factory.request(operation)

    assert {:error, %Error{code: :no_default_method}} = Form.build(request, config)

    subscription =
      Subscription.new(config, :client_handle, "request-1", mismatched_opening(operation))

    assert {:error, %Error{code: :subscription_operation_mismatch}} =
             Transport.unsubscribe(subscription, request, Factory.context(), config)

    refute_receive {:client_close, _}
    refute_receive {:client_request, _, _}
  end

  defp assert_request_shape(request, operation)
       when operation in [:observeproperty, :subscribeevent] do
    assert Request.stream?(request)
    assert Headers.get(Request.headers(request), "accept") == "text/event-stream"
    assert Request.body(request) == nil
  end

  defp assert_request_shape(request, operation)
       when operation in [:writeproperty, :invokeaction] do
    refute Request.stream?(request)
    assert Headers.get(Request.headers(request), "content-type") == "application/json"
    assert Request.body(request) == "true"
  end

  defp assert_request_shape(request, _) do
    refute Request.stream?(request)
    assert Headers.get(Request.headers(request), "accept") == "application/json"
    assert Request.body(request) == nil
  end

  defp assert_client_path(request, built, operation, config)
       when operation in [:observeproperty, :subscribeevent] do
    assert {:ok, %Subscription{}} =
             Transport.subscribe(request, self(), Factory.context(), config)

    owner = self()
    assert_receive {:client_subscribe, ^built, :credential, ^owner}
    refute_receive {:client_request, _, _}
  end

  defp assert_client_path(request, built, _, config) do
    assert {:ok, %Wotex.Runtime.Result{}} =
             Transport.request(request, Factory.context(), config)

    assert_receive {:client_request, ^built, :credential}
    refute_receive {:client_subscribe, _, _, _}
  end

  defp positive_config(operation) when operation in [:observeproperty, :subscribeevent] do
    handshake = Factory.response(200, "", [{"Content-Type", "text/event-stream"}])
    Factory.config(%{subscribe_return: {:ok, :client_handle, handshake}})
  end

  defp positive_config(_) do
    response = Factory.response(200, "null", [{"Content-Type", "application/json"}])
    Factory.config(%{request_return: {:ok, response}})
  end

  defp negative_request(:readproperty),
    do: {Factory.request(:readproperty, %{"unexpected" => true}), :unexpected_input}

  defp negative_request(:writeproperty),
    do: {Factory.request(:writeproperty, HTTP.empty_body()), :missing_input}

  defp negative_request(:invokeaction),
    do: {Factory.request(:invokeaction, %{atom_key: true}), :json_encode_failed}

  defp negative_request(:queryaction),
    do: {Factory.request(:queryaction, nil), :missing_action_target}

  defp negative_request(:cancelaction) do
    request = Factory.request(:cancelaction, "https://name:value@thing.example/action")
    {request, :uri_credentials_forbidden}
  end

  defp negative_request(:observeproperty),
    do: {Factory.request(:observeproperty), :unsupported_subprotocol}

  defp negative_request(:subscribeevent),
    do: {Factory.request(:subscribeevent), :unsupported_subprotocol}

  defp aggregate_request(operation) do
    href = "https://thing.example/interactions"

    {:ok, form} =
      Wotex.Form.new(%{
        "href" => href,
        "op" => Atom.to_string(operation),
        "contentType" => "application/json",
        "htv:methodName" => "GET"
      })

    {:ok, profile} = HTTP.profile()
    {:ok, context} = Context.new(request_id: "aggregate-#{operation}", deadline: 50_000)

    selection = %Selection{
      affordance_type: :thing,
      affordance_name: nil,
      affordance: %{},
      operation: operation,
      form: form,
      resolved_href: href,
      profile: profile,
      security: %{names: ["security"], definitions: %{}}
    }

    Wotex.Runtime.Request.from_selection(selection, context, nil)
  end

  defp input(operation) when operation in [:writeproperty, :invokeaction], do: true
  defp input(operation) when operation in [:queryaction, :cancelaction], do: "/actions/value/1"
  defp input(_), do: nil

  defp form_overrides(operation) when operation in [:observeproperty, :subscribeevent],
    do: %{"subprotocol" => "sse"}

  defp form_overrides(_), do: %{}

  defp opening(:unobserveproperty), do: :observeproperty
  defp opening(:unsubscribeevent), do: :subscribeevent
  defp mismatched_opening(:unobserveproperty), do: :subscribeevent
  defp mismatched_opening(:unsubscribeevent), do: :observeproperty
end
