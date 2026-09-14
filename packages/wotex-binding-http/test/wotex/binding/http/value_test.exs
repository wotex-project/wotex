defmodule Wotex.Binding.HTTP.ValueTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.HTTP

  alias Wotex.Binding.HTTP.{
    Codec,
    Config,
    EmptyBody,
    Error,
    Headers,
    Notification,
    Request,
    Response,
    Subscription
  }

  alias Wotex.Binding.HTTP.SSE.Event
  alias Wotex.Binding.HTTP.Test.{AlternateClient, FakeClient}
  alias Wotex.Runtime.BindingProfile

  test "profile declares only the binding's pinned operation surface" do
    assert {:ok, profile} = HTTP.profile()
    assert BindingProfile.id(profile) == :http
    assert BindingProfile.supports_scheme?(profile, "http")
    assert BindingProfile.supports_scheme?(profile, "HTTPS")
    assert BindingProfile.supports_media_type?(profile, "application/json; charset=utf-8")

    operations =
      ~w(readproperty writeproperty observeproperty unobserveproperty invokeaction queryaction cancelaction subscribeevent unsubscribeevent)a

    for operation <- operations do
      assert BindingProfile.supports_operation?(profile, operation)
    end

    for operation <- Wotex.Runtime.thing_operations() do
      refute BindingProfile.supports_operation?(profile, operation)
    end
  end

  test "configuration validates the client, headers, limits, and inspection boundary" do
    assert {:ok, config} =
             HTTP.config(
               client: {FakeClient, %{token_like_value: "not-inspected"}},
               headers: [{"User-Agent", "consumer-host"}],
               max_request_bytes: 10,
               max_response_bytes: 20,
               max_event_bytes: 30,
               max_header_count: 4,
               max_header_bytes: 80,
               max_uri_bytes: 120
             )

    assert Config.client(config) == {FakeClient, %{token_like_value: "not-inspected"}}
    assert Config.headers(config) == [{"user-agent", "consumer-host"}]
    assert Config.max_request_bytes(config) == 10
    assert Config.max_response_bytes(config) == 20
    assert Config.max_event_bytes(config) == 30
    assert Config.max_header_count(config) == 4
    assert Config.max_header_bytes(config) == 80
    assert Config.max_uri_bytes(config) == 120
    refute inspect(config) =~ "not-inspected"
    assert HTTP.transport(config) == {Wotex.Binding.HTTP.Transport, config}
  end

  test "configuration rejects malformed options, clients, limits, and static headers" do
    assert {:error, %Error{code: :invalid_config_options}} = Config.new(%{})
    assert {:error, %Error{code: :invalid_config_options}} = Config.new([:not_keyword])
    assert {:error, %Error{code: :invalid_client}} = Config.new([])
    assert {:error, %Error{code: :invalid_client}} = Config.new(client: {String, %{}})

    for option <- [
          :max_request_bytes,
          :max_response_bytes,
          :max_event_bytes,
          :max_header_count,
          :max_header_bytes,
          :max_uri_bytes
        ] do
      assert {:error, %Error{code: :invalid_limit, details: %{option: ^option}}} =
               Config.new([client: {FakeClient, %{}}] ++ [{option, 0}])
    end

    assert {:error, %Error{code: :credential_header_forbidden}} =
             Config.new(client: {FakeClient, %{}}, headers: [{"Authorization", "value"}])
  end

  test "header values are normalized, composed, and retrieved deterministically" do
    assert {:ok, base} = Headers.new([{"Accept", "application/json"}, {"X-One", "1"}])
    assert base == [{"accept", "application/json"}, {"x-one", "1"}]
    assert Headers.get(base, "ACCEPT") == "application/json"
    assert Headers.get(base, "missing") == nil

    merged = Headers.merge(base, [{"x-one", "2"}, {"x-two", "3"}])
    assert merged == [{"accept", "application/json"}, {"x-one", "2"}, {"x-two", "3"}]

    assert Headers.put(merged, "Accept", "text/event-stream") |> Headers.get("accept") ==
             "text/event-stream"

    assert Headers.token?("PATCH")
    assert Headers.token?("X-Method")
    refute Headers.token?("")
    refute Headers.token?("bad method")
  end

  test "header validation rejects ambiguous, credential, framing, and unsafe fields" do
    assert {:error, %Error{code: :duplicate_header}} =
             Headers.new([{"X-A", "1"}, {"x-a", "2"}])

    assert {:error, %Error{code: :invalid_header_name}} = Headers.new([{"bad name", "x"}])
    assert {:error, %Error{code: :invalid_header_value}} = Headers.new([{"x-a", "a\rb"}])
    assert {:error, %Error{code: :invalid_header}} = Headers.new([:invalid])
    assert {:error, %Error{code: :invalid_headers}} = Headers.new(%{})

    for name <- ["authorization", "proxy-authorization", "cookie", "set-cookie"] do
      assert {:error, %Error{code: :credential_header_forbidden}} = Headers.new([{name, "x"}])
    end

    for name <- ["connection", "content-length", "host", "transfer-encoding", "upgrade"] do
      assert {:error, %Error{code: :framing_header_forbidden}} = Headers.new([{name, "x"}])
    end

    assert {:ok, [{"content-length", "0"}]} = Headers.new([{"Content-Length", "0"}], :response)
  end

  test "request is immutable, credential-free, and exposes client-facing accessors" do
    assert {:ok, request} =
             Request.new(
               "GET",
               "HTTPS://thing.example/value",
               [{"Accept", "application/json"}],
               nil,
               request_id: "request-1",
               deadline: 100,
               operation: :readproperty,
               media_type: "application/json",
               stream?: false,
               max_response_bytes: 4_194_304,
               max_event_bytes: 1_048_576,
               max_header_count: 64,
               max_header_bytes: 65_536,
               max_uri_bytes: 8_192
             )

    assert Request.method(request) == "GET"
    assert Request.uri(request) == "HTTPS://thing.example/value"
    assert Request.headers(request) == [{"accept", "application/json"}]
    assert Request.body(request) == nil
    assert Request.request_id(request) == "request-1"
    assert Request.deadline(request) == 100
    assert Request.operation(request) == :readproperty
    assert Request.media_type(request) == "application/json"
    assert Request.max_response_bytes(request) == 4_194_304
    assert Request.max_event_bytes(request) == 1_048_576
    assert Request.max_header_count(request) == 64
    assert Request.max_header_bytes(request) == 65_536
    assert Request.max_uri_bytes(request) == 8_192
    refute Request.stream?(request)
    refute Map.has_key?(Map.from_struct(request), :credential)
  end

  test "request validation rejects malformed methods, URIs, headers, bodies, and identity" do
    opts = [
      request_id: "request-1",
      operation: :readproperty,
      max_response_bytes: 20,
      max_event_bytes: 10
    ]

    assert {:error, %Error{code: :invalid_method}} =
             Request.new("bad method", valid_uri(), [], nil, opts)

    assert {:error, %Error{code: :unsupported_scheme}} =
             Request.new("GET", "ftp://thing.example", [], nil, opts)

    assert {:error, %Error{code: :invalid_uri}} =
             Request.new("GET", "https:///missing", [], nil, opts)

    assert {:error, %Error{code: :uri_credentials_forbidden}} =
             Request.new("GET", "https://name:value@thing.example", [], nil, opts)

    assert {:error, %Error{code: :uri_fragment_forbidden}} =
             Request.new("GET", "https://thing.example/value#part", [], nil, opts)

    assert {:error, %Error{code: :invalid_uri}} =
             Request.new("GET", "https://thing.example/a b", [], nil, opts)

    assert {:error, %Error{code: :invalid_uri}} =
             Request.new("GET", "https://thing.example/{variable}", [], nil, opts)

    assert {:error, %Error{code: :invalid_uri}} = Request.new("GET", 42, [], nil, opts)
    assert {:error, %Error{code: :invalid_body}} = Request.new("GET", valid_uri(), [], %{}, opts)

    assert {:error, %Error{code: :invalid_request_identity}} =
             Request.new("GET", valid_uri(), [], nil, [])

    for option <- [:max_response_bytes, :max_event_bytes] do
      assert {:error, %Error{code: :invalid_byte_limit, details: %{option: ^option}}} =
               Request.new("GET", valid_uri(), [], nil, Keyword.put(opts, option, 0))
    end

    for option <- [:max_header_count, :max_header_bytes, :max_uri_bytes] do
      assert {:error, %Error{code: :invalid_admission_limit, details: %{option: ^option}}} =
               Request.new("GET", valid_uri(), [], nil, Keyword.put(opts, option, 0))
    end

    assert {:error, %Error{code: :invalid_request_identity}} =
             Request.new("GET", valid_uri(), [], nil,
               request_id: "request-1",
               operation: :unknown
             )

    assert {:error, %Error{code: :invalid_deadline}} =
             Request.new("GET", valid_uri(), [], nil, Keyword.put(opts, :deadline, :later))

    assert {:error, %Error{code: :invalid_media_type}} =
             Request.new("GET", valid_uri(), [], nil, Keyword.put(opts, :media_type, nil))

    assert {:error, %Error{code: :invalid_stream_flag}} =
             Request.new("GET", valid_uri(), [], nil, Keyword.put(opts, :stream?, :yes))

    assert {:error, %Error{code: :invalid_request}} = Request.new("GET", valid_uri(), [], nil, %{})

    assert {:error, %Error{code: :invalid_request}} =
             Request.new("GET", valid_uri(), [], nil, [:not_keyword])
  end

  test "response validates status, fields, body, and exposes accessors" do
    assert {:ok, response} =
             Response.new(200, [{"Content-Type", "application/json"}], ~s({"ok":true}))

    assert Response.status(response) == 200
    assert Response.headers(response) == [{"content-type", "application/json"}]
    assert Response.body(response) == ~s({"ok":true})
    refute Map.has_key?(Map.from_struct(response), :credential)

    assert {:error, %Error{code: :invalid_response}} = Response.new(99, [], "")
    assert {:error, %Error{code: :invalid_response}} = Response.new(200, [], :body)
    assert {:error, %Error{code: :invalid_headers}} = Response.new(200, %{}, "")

    assert {:error, %Error{code: :credential_header_forbidden}} =
             Response.new(200, [{"Set-Cookie", "name=value"}], "")
  end

  test "empty body marker is distinct from JSON null" do
    assert %EmptyBody{} = HTTP.empty_body()
    assert HTTP.empty_body() == EmptyBody.new()
  end

  test "JSON codec enforces value and byte boundaries" do
    assert {:ok, ~s({"a":1})} = Codec.encode(%{"a" => 1}, 20)
    assert {:error, %Error{code: :json_encode_failed}} = Codec.encode(%{a: 1}, 20)
    assert {:error, %Error{code: :request_body_too_large}} = Codec.encode("long", 2)
    assert {:error, %Error{code: :invalid_encode_limit}} = Codec.encode(nil, 0)

    assert {:ok, %{"a" => 1}} = Codec.decode(~s({"a":1}), 20)
    assert {:error, %Error{code: :json_decode_failed}} = Codec.decode("bad", 20)
    assert {:error, %Error{code: :response_body_too_large}} = Codec.decode("123", 2)
    assert {:error, %Error{code: :invalid_decode_input}} = Codec.decode(:bad, 2)

    assert {:error, %Error{code: :json_decode_failed}} =
             Codec.decode(~s({"a":1,"a":2}), 20)

    nested = String.duplicate("[", 65) <> String.duplicate("]", 65)

    assert {:error, %Error{code: :json_limit_exceeded, details: details}} =
             Codec.decode(nested, 200)

    assert details == %{limit: :depth_limit_exceeded}

    assert %Error{code: :example, phase: :client, message: "example", details: %{safe: true}} =
             Error.new(:example, :client, "example", %{safe: true})
  end

  test "SSE event validates framing outputs and notification exposes decoded data" do
    assert {:ok, event} = Event.new(~s({"temperature":21}), event: "change", id: "7", retry: 500)
    assert Event.data(event) == ~s({"temperature":21})
    assert Event.event(event) == "change"
    assert Event.id(event) == "7"
    assert Event.retry(event) == 500

    assert Notification.new(event, "request-1", :observeproperty) == %{
             event: "change",
             id: "7",
             retry: 500,
             request_id: "request-1",
             operation: :observeproperty
           }

    assert {:error, %Error{code: :invalid_sse_event}} = Event.new(:invalid)
    assert {:error, %Error{code: :invalid_sse_event}} = Event.new("data", %{})
    assert {:error, %Error{code: :invalid_sse_event}} = Event.new("data", [:not_keyword])
    assert {:error, %Error{code: :invalid_sse_field}} = Event.new("data", event: "bad\nevent")
    assert {:error, %Error{code: :invalid_sse_field}} = Event.new("data", id: 1)
    assert {:error, %Error{code: :invalid_sse_retry}} = Event.new("data", retry: -1)
  end

  test "subscription handle inspection omits the opaque client handle" do
    {:ok, config} = Config.new(client: {AlternateClient, %{private_option: "not-retained"}})

    subscription =
      Subscription.new(config, {:opaque, "hidden"}, "request-1", :subscribeevent)

    assert Subscription.unwrap(subscription) ==
             {AlternateClient, {:opaque, "hidden"}, "request-1", :subscribeevent}

    refute inspect(subscription) =~ "hidden"
    assert subscription.instance_ref == Config.instance_ref(config)
    assert is_reference(subscription.instance_ref)
    refute :erlang.term_to_binary(subscription) =~ "not-retained"
    refute Map.has_key?(Map.from_struct(subscription), :credential)
  end

  defp valid_uri, do: "https://thing.example/value"
end
