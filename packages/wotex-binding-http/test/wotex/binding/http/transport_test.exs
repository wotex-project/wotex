defmodule Wotex.Binding.HTTP.TransportTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.HTTP

  alias Wotex.Binding.HTTP.{
    Config,
    Error,
    Headers,
    Request,
    Response,
    Subscription,
    Transport
  }

  alias Wotex.Binding.HTTP.SSE.Event
  alias Wotex.Binding.HTTP.Test.{AlternateClient, Factory, FakeClient}
  alias Wotex.Runtime.Result

  test "one-shot request delegates credentials separately and returns decoded Runtime result" do
    response =
      Factory.response(
        201,
        ~s({"href":"/actions/fade/1","status":"pending"}),
        [
          {"Content-Type", "application/json; charset=utf-8"},
          {"Location", "/actions/fade/1"},
          {"X-Trace", "trace-1"}
        ]
      )

    config = Factory.config(%{request_return: {:ok, response}})
    request = Factory.request(:invokeaction, %{"level" => 20})

    assert {:ok, %Result{} = result} =
             Transport.request(request, Factory.context(:ephemeral_credential), config)

    assert result.status == :ok
    assert result.metadata.http.status == 201
    assert result.operation == :invokeaction
    assert result.request_id == "request-1"
    assert result.payload == %{"href" => "/actions/fade/1", "status" => "pending"}
    assert result.metadata.http.method == "POST"
    assert result.metadata.http.request_uri == "https://thing.example/interactions/value"
    assert result.metadata.http.location == "https://thing.example/actions/fade/1"
    assert Headers.get(result.metadata.http.headers, "x-trace") == "trace-1"

    assert_receive {:client_request, %Request{} = http_request, :ephemeral_credential}
    assert Request.body(http_request) == ~s({"level":20})
    refute Map.has_key?(Map.from_struct(http_request), :credential)
    refute inspect(result) =~ "ephemeral_credential"
  end

  test "empty successful responses produce nil payloads and may omit content type" do
    for {status, runtime_status} <- [{200, :ok}, {202, :accepted}, {204, :ok}, {205, :ok}] do
      config = Factory.config(%{request_return: {:ok, Factory.response(status)}})
      request = Factory.request(:readproperty)

      assert {:ok, %Result{payload: nil, status: ^runtime_status} = result} =
               Transport.request(request, Factory.context(), config)

      assert result.metadata.http.status == status
    end
  end

  test "response validation rejects non-success, wrong media, invalid JSON, and body violations" do
    cases = [
      {Factory.response(404, ~s({"error":true}), [{"Content-Type", "application/json"}]), %{},
       :http_status},
      {Factory.response(200, "plain", [{"Content-Type", "text/plain"}]), %{},
       :unexpected_response_media_type},
      {Factory.response(200, "not-json", [{"Content-Type", "application/json"}]), %{},
       :json_decode_failed},
      {Factory.response(204, "null", [{"Content-Type", "application/json"}]), %{},
       :unexpected_response_body},
      {Factory.response(200, "1234", [{"Content-Type", "application/json"}]),
       %{max_response_bytes: 3}, :response_body_too_large}
    ]

    for {response, config_overrides, code} <- cases do
      {:ok, config} =
        HTTP.config(
          [client: {FakeClient, %{owner: self(), request_return: {:ok, response}}}] ++
            Map.to_list(config_overrides)
        )

      assert {:error, %Error{code: ^code}} =
               Transport.request(Factory.request(:readproperty), Factory.context(), config)

      assert_receive {:client_request, %Request{}, :credential}
    end
  end

  test "missing response content type falls back to the selected Form representation" do
    response = Factory.response(200, ~s({"value":1}))
    config = Factory.config(%{request_return: {:ok, response}})

    assert {:ok, %Result{payload: %{"value" => 1}}} =
             Transport.request(Factory.request(:readproperty), Factory.context(), config)
  end

  test "invalid Location fails without retaining its value" do
    response =
      Factory.response(201, "null", [
        {"Content-Type", "application/json"},
        {"Location", "https://name:value@thing.example/action"}
      ])

    config = Factory.config(%{request_return: {:ok, response}})

    assert {:error, %Error{code: :invalid_location} = error} =
             Transport.request(Factory.request(:invokeaction, true), Factory.context(), config)

    refute inspect(error) =~ "name:value"
  end

  test "HTTP status codes and client failures carry their retry classification" do
    statuses = [{408, :timeout}, {429, :rate_limited}, {503, :unavailable}, {404, :permanent}]

    for {status, class} <- statuses do
      response = Factory.response(status, "", [{"Content-Type", "application/json"}])
      config = Factory.config(%{request_return: {:ok, response}})

      assert {:error, %Error{code: :http_status, class: ^class, details: %{status: ^status}}} =
               Transport.request(Factory.request(:readproperty), Factory.context(), config)
    end

    returns = [
      {{:error, :timeout}, :client_request_failed, :timeout},
      {{:error, :econnrefused}, :client_request_failed, :unavailable},
      {{:raise, RuntimeError.exception("private")}, :client_request_exception, :unavailable},
      {{:exit, :private_exit}, :client_request_exception, :unavailable},
      {{:throw, :private_throw}, :client_request_exception, :unavailable},
      {:invalid, :invalid_client_return, :protocol}
    ]

    for {returned, code, class} <- returns do
      config = Factory.config(%{request_return: returned})

      assert {:error, %Error{code: ^code, class: ^class} = error} =
               Transport.request(Factory.request(:readproperty), Factory.context(), config)

      refute inspect(error) =~ "private"
    end
  end

  test "subscribe and close isolate client exits and throws without copying the reason" do
    request = Factory.request(:subscribeevent, nil, %{"subprotocol" => "sse"})

    for returned <- [{:exit, :private_exit}, {:throw, :private_throw}] do
      config = Factory.config(%{subscribe_return: returned, close_return: returned})

      assert {:error, %Error{code: :client_subscribe_exception, class: :unavailable} = error} =
               Transport.subscribe(request, self(), Factory.context(), config)

      refute inspect(error) =~ "private"

      subscription = Subscription.new(config, :handle, "request-1", :subscribeevent)

      assert {:error, %Error{code: :client_close_exception, class: :unavailable}} =
               Transport.unsubscribe(
                 subscription,
                 Factory.request(:unsubscribeevent),
                 Factory.context(),
                 config
               )
    end
  end

  test "client failures, exceptions, malformed returns, and bypassed response values are normalized" do
    invalid_response = %Response{
      status: 200,
      headers: [{"set-cookie", "name=value"}],
      body: ""
    }

    cases = [
      {{:error, {:private_reason, "do-not-return"}}, :client_request_failed},
      {{:raise, RuntimeError.exception("private exception")}, :client_request_exception},
      {:invalid, :invalid_client_return},
      {{:ok, invalid_response}, :credential_header_forbidden}
    ]

    for {returned, code} <- cases do
      config = Factory.config(%{request_return: returned})

      assert {:error, %Error{code: ^code} = error} =
               Transport.request(Factory.request(:readproperty), Factory.context(), config)

      refute inspect(error) =~ "do-not-return"
      refute inspect(error) =~ "private exception"
      assert_receive {:client_request, %Request{}, :credential}
    end
  end

  test "request callback rejects streams and malformed transport arguments" do
    stream = Factory.request(:observeproperty, nil, %{"subprotocol" => "sse"})

    assert {:error, %Error{code: :stream_requires_subscribe}} =
             Transport.request(stream, Factory.context(), Factory.config())

    assert {:error, %Error{code: :invalid_transport_arguments}} =
             Transport.request(%{}, Factory.context(), Factory.config())

    assert {:error, %Error{code: :invalid_transport_arguments}} =
             Transport.request(Factory.request(:readproperty), %{}, Factory.config())

    assert {:error, %Error{code: :invalid_transport_arguments}} =
             Transport.request(Factory.request(:readproperty), Factory.context(), %{})
  end

  test "SSE subscribe opens explicitly, decodes notifications, and returns an opaque handle" do
    handshake = Factory.response(200, "", [{"Content-Type", "text/event-stream; charset=utf-8"}])
    config = Factory.config(%{subscribe_return: {:ok, :client_handle, handshake}})
    request = Factory.request(:subscribeevent, nil, %{"subprotocol" => "sse"})

    assert {:ok, %Subscription{} = subscription} =
             Transport.subscribe(request, self(), Factory.context(:stream_credential), config)

    assert Subscription.unwrap(subscription) ==
             {FakeClient, :client_handle, "request-1", :subscribeevent}

    owner = self()
    assert_receive {:client_subscribe, %Request{} = http_request, :stream_credential, ^owner}
    assert Request.method(http_request) == "GET"
    assert Headers.get(Request.headers(http_request), "accept") == "text/event-stream"

    {:ok, event} = Event.new(~s({"temperature":22}), event: "overheated", id: "event-1")

    assert {:ok, %{"temperature" => 22}, meta} = Transport.decode_frame(event, request, config)

    assert meta == %{
             event: "overheated",
             id: "event-1",
             retry: nil,
             request_id: "request-1",
             operation: :subscribeevent
           }

    refute_receive {:wotex_transport, _delivery}
  end

  test "frame decoding ignores keep-alives and reports oversized, malformed, and alien frames" do
    handshake = Factory.response(200, "", [{"Content-Type", "text/event-stream"}])

    {:ok, config} =
      HTTP.config(
        client:
          {FakeClient,
           %{owner: self(), subscribe_return: {:ok, :handle, handshake}, close_return: :ok}},
        max_event_bytes: 4
      )

    request = Factory.request(:observeproperty, nil, %{"subprotocol" => "sse"})
    assert {:ok, _} = Transport.subscribe(request, self(), Factory.context(), config)
    assert_receive {:client_subscribe, %Request{}, :credential, _owner}

    {:ok, keep_alive} = Event.new("")
    assert Transport.decode_frame(keep_alive, request, config) == :ignore

    {:ok, oversized} = Event.new("12345")

    assert {:error, %Error{code: :sse_event_too_large, class: :protocol}} =
             Transport.decode_frame(oversized, request, config)

    {:ok, malformed} = Event.new("bad")

    assert {:error, %Error{code: :json_decode_failed, class: :protocol}} =
             Transport.decode_frame(malformed, request, config)

    assert {:error, %Error{code: :invalid_sse_event, class: :protocol}} =
             Transport.decode_frame(%{}, request, config)

    {:ok, event} = Event.new("1")

    assert {:error, %Error{code: :invalid_sse_event}} =
             Transport.decode_frame(event, Factory.request(:readproperty), config)
  end

  test "failed SSE handshakes close the newly opened handle" do
    cases = [
      {Factory.response(201, "", [{"Content-Type", "text/event-stream"}]), :sse_handshake_status},
      {Factory.response(200, "", [{"Content-Type", "application/json"}]),
       :sse_handshake_media_type},
      {Factory.response(200, "buffered", [{"Content-Type", "text/event-stream"}]),
       :sse_handshake_body}
    ]

    for {handshake, code} <- cases do
      config = Factory.config(%{subscribe_return: {:ok, :opened_handle, handshake}})
      request = Factory.request(:observeproperty, nil, %{"subprotocol" => "sse"})

      assert {:error, %Error{code: ^code}} =
               Transport.subscribe(request, self(), Factory.context(), config)

      assert_receive {:client_subscribe, %Request{}, :credential, _owner}
      assert_receive {:client_close, :opened_handle}
    end
  end

  test "handshake cleanup tolerates a raising or exiting close callback" do
    handshake = Factory.response(201, "", [{"Content-Type", "text/event-stream"}])

    for close_return <- [{:raise, RuntimeError.exception("private")}, {:exit, :private_exit}] do
      config =
        Factory.config(%{
          subscribe_return: {:ok, :opened_handle, handshake},
          close_return: close_return
        })

      request = Factory.request(:observeproperty, nil, %{"subprotocol" => "sse"})

      assert {:error, %Error{code: :sse_handshake_status, class: :protocol}} =
               Transport.subscribe(request, self(), Factory.context(), config)

      assert_receive {:client_close, :opened_handle}
    end
  end

  test "invalid client response during SSE open also closes the handle" do
    invalid_response = %Response{status: 200, headers: [{"set-cookie", "x"}], body: ""}
    config = Factory.config(%{subscribe_return: {:ok, :opened_handle, invalid_response}})
    request = Factory.request(:observeproperty, nil, %{"subprotocol" => "sse"})

    assert {:error, %Error{code: :credential_header_forbidden}} =
             Transport.subscribe(request, self(), Factory.context(), config)

    assert_receive {:client_close, :opened_handle}
  end

  test "subscribe failures, exceptions, and malformed returns are normalized" do
    cases = [
      {{:error, :private}, :client_subscribe_failed},
      {{:raise, RuntimeError.exception("private")}, :client_subscribe_exception},
      {:invalid, :invalid_client_return}
    ]

    for {returned, code} <- cases do
      config = Factory.config(%{subscribe_return: returned})
      request = Factory.request(:subscribeevent, nil, %{"subprotocol" => "sse"})

      assert {:error, %Error{code: ^code}} =
               Transport.subscribe(request, self(), Factory.context(), config)

      assert_receive {:client_subscribe, %Request{}, :credential, _owner}
      refute_receive {:client_close, _handle}
    end
  end

  test "subscribe rejects non-streaming operations and malformed arguments" do
    assert {:error, %Error{code: :operation_is_not_streaming}} =
             Transport.subscribe(
               Factory.request(:readproperty),
               self(),
               Factory.context(),
               Factory.config()
             )

    assert {:error, %Error{code: :invalid_subscription_arguments}} =
             Transport.subscribe(%{}, self(), Factory.context(), Factory.config())

    assert {:error, %Error{code: :invalid_subscription_arguments}} =
             Transport.subscribe(
               Factory.request(:observeproperty, nil, %{"subprotocol" => "sse"}),
               :not_a_pid,
               Factory.context(),
               Factory.config()
             )
  end

  test "unsubscribe closes the exact handle without forwarding stop credentials" do
    stop_request = Factory.request(:unobserveproperty)
    config = Factory.config(%{close_return: :ok})
    subscription = Subscription.new(config, :client_handle, "request-1", :observeproperty)

    assert :ok =
             Transport.unsubscribe(
               subscription,
               stop_request,
               Factory.context(:different_stop_credential),
               config
             )

    assert_receive {:client_close, :client_handle}
  end

  test "unsubscribe rejects another instance of the same client before calling close" do
    handshake = Factory.response(200, "", [{"Content-Type", "text/event-stream"}])
    options = %{subscribe_return: {:ok, :owned_handle, handshake}}
    opening_config = Factory.config(options)
    equal_options_config = Factory.config(options)
    different_options_config = Factory.config(%{client_instance: :other})
    request = Factory.request(:observeproperty, nil, %{"subprotocol" => "sse"})

    assert {:ok, subscription} =
             Transport.subscribe(request, self(), Factory.context(), opening_config)

    for other_config <- [equal_options_config, different_options_config] do
      assert {:error, %Error{code: :subscription_client_mismatch}} =
               Transport.unsubscribe(
                 subscription,
                 Factory.request(:unobserveproperty),
                 Factory.context(),
                 other_config
               )

      refute_receive {:client_close, _}
    end

    close_task =
      Task.async(fn ->
        Transport.unsubscribe(
          subscription,
          Factory.request(:unobserveproperty),
          Factory.context(),
          opening_config
        )
      end)

    assert :ok = Task.await(close_task)
    assert_receive {:client_close, :owned_handle}
    refute_receive {:client_close, _}
  end

  test "unsubscribe validates identity, operation, and opening client" do
    base = Subscription.new(Factory.config(), :handle, "request-1", :observeproperty)

    cases = [
      {base, Factory.request(:unobserveproperty, nil, %{}, "other-request"), Factory.config(),
       :subscription_request_mismatch},
      {base, Factory.request(:unsubscribeevent), Factory.config(), :subscription_operation_mismatch}
    ]

    for {subscription, request, config, code} <- cases do
      assert {:error, %Error{code: ^code}} =
               Transport.unsubscribe(subscription, request, Factory.context(), config)

      refute_receive {:client_close, _handle}
    end

    {:ok, other_config} = Config.new(client: {AlternateClient, %{}})

    assert {:error, %Error{code: :subscription_client_mismatch}} =
             Transport.unsubscribe(
               base,
               Factory.request(:unobserveproperty),
               Factory.context(),
               other_config
             )
  end

  test "unsubscribe normalizes close errors, exceptions, malformed returns, and arguments" do
    request = Factory.request(:unsubscribeevent)

    cases = [
      {{:error, :private}, :client_close_failed},
      {{:raise, RuntimeError.exception("private")}, :client_close_exception},
      {:invalid, :invalid_client_return}
    ]

    for {returned, code} <- cases do
      config = Factory.config(%{close_return: returned})
      subscription = Subscription.new(config, :handle, "request-1", :subscribeevent)

      assert {:error, %Error{code: ^code}} =
               Transport.unsubscribe(subscription, request, Factory.context(), config)

      assert_receive {:client_close, :handle}
    end

    assert {:error, %Error{code: :invalid_unsubscribe_arguments}} =
             Transport.unsubscribe(:bad, request, Factory.context(), Factory.config())
  end
end
