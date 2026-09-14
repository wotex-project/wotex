defmodule Wotex.Binding.HTTP.StableAPIInventoryTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Binding.HTTP

  alias Wotex.Binding.HTTP.{
    Codec,
    Config,
    EmptyBody,
    Error,
    Form,
    Headers,
    Notification,
    Request,
    Response,
    Subscription,
    Transport
  }

  alias Wotex.Binding.HTTP.SSE.Event
  alias Wotex.Binding.HTTP.Test.{Factory, FakeClient}

  @operations [
    readproperty: "GET",
    writeproperty: "PUT",
    invokeaction: "POST",
    queryaction: "GET",
    cancelaction: "DELETE",
    observeproperty: "GET",
    subscribeevent: "GET"
  ]

  @documented_functions %{
    HTTP => ~w(config/1 empty_body/0 profile/0 transport/1),
    Config =>
      ~w(client/1 headers/1 instance_ref/1 max_event_bytes/1 max_header_bytes/1 max_header_count/1 max_request_bytes/1 max_response_bytes/1 max_uri_bytes/1 new/1),
    EmptyBody => ~w(new/0),
    Error => ~w(class/1),
    Headers => ~w(get/2 merge/2 new/2 put/3 token?/1),
    Notification => ~w(new/3),
    Request =>
      ~w(body/1 deadline/1 headers/1 max_event_bytes/1 max_header_bytes/1 max_header_count/1 max_response_bytes/1 max_uri_bytes/1 media_type/1 method/1 new/5 operation/1 request_id/1 stream?/1 uri/1),
    Response => ~w(body/1 headers/1 new/3 status/1),
    Event => ~w(data/1 event/1 id/1 new/2 retry/1),
    Transport => ~w(decode_frame/3)
  }

  test "WBH-K01-P freezes every documented consumer function and arity" do
    for {module, expected} <- @documented_functions do
      assert documented_functions(module) == Enum.sort(expected)
    end

    assert Code.ensure_loaded?(Headers)
    assert function_exported?(Headers, :new, 1)
    assert Code.ensure_loaded?(Event)
    assert function_exported?(Event, :new, 1)
  end

  test "WBH-K01-N keeps doc-false construction helpers outside the supported surface" do
    refute "build/2" in documented_functions(Form)
    refute "new/4" in documented_functions(Subscription)
    refute "unwrap/1" in documented_functions(Subscription)
    refute "new/5" in documented_functions(Error)
    refute "validate_limits/4" in documented_functions(Headers)
  end

  test "WBH-K02-P freezes the seven request mappings and two close pairs" do
    for {operation, method} <- @operations do
      request = Factory.request(operation, input(operation), form_overrides(operation))
      assert {:ok, built} = Form.build(request, Factory.config())
      assert Request.method(built) == method
      assert Request.operation(built) == operation
      assert Request.stream?(built) == operation in [:observeproperty, :subscribeevent]
    end

    config = Factory.config(%{close_return: :ok})

    for {opening, closing} <- [
          {:observeproperty, :unobserveproperty},
          {:subscribeevent, :unsubscribeevent}
        ] do
      subscription = Subscription.new(config, {opening, :handle}, "request-1", opening)

      assert :ok =
               Transport.unsubscribe(
                 subscription,
                 Factory.request(closing),
                 Factory.context(),
                 config
               )

      assert_receive {:client_close, {^opening, :handle}}
      refute_receive {:client_request, _, _}
    end
  end

  test "WBH-K02-N freezes the unsupported aggregate and draft-sensitive decision" do
    assert {:ok, profile} = HTTP.profile()
    assert profile.id == :http
    assert profile.schemes == MapSet.new(["http", "https"])
    assert profile.media_types == MapSet.new(["application/json"])

    assert profile.operations ==
             MapSet.new([
               :readproperty,
               :writeproperty,
               :observeproperty,
               :unobserveproperty,
               :invokeaction,
               :queryaction,
               :cancelaction,
               :subscribeevent,
               :unsubscribeevent
             ])

    assert MapSet.disjoint?(profile.operations, MapSet.new(Wotex.Runtime.thing_operations()))

    inventory = File.read!("docs/stable-api-inventory.md")
    assert inventory =~ "WoT Profiles Working\nDraft 2025-11-04"
    assert inventory =~ "future draft does not change these mappings"
  end

  test "WBH-K03-P freezes public value shapes and notification metadata" do
    config = Factory.config()
    request = built_request(:readproperty, config)
    response = Factory.response(200, "null", [{"X-Trace", "one"}])
    {:ok, event} = Event.new("null", event: "change", id: "7", retry: 500)
    error = Error.new(:invalid_uri, :request, "invalid")

    assert struct_keys(config) ==
             ~w(client_config client_module headers instance_ref max_event_bytes max_header_bytes max_header_count max_request_bytes max_response_bytes max_uri_bytes)a

    assert struct_keys(request) ==
             ~w(body deadline headers max_event_bytes max_header_bytes max_header_count max_response_bytes max_uri_bytes media_type method operation request_id stream? uri)a

    assert struct_keys(response) == ~w(body headers status)a
    assert struct_keys(event) == ~w(data event id retry)a
    assert struct_keys(error) == ~w(__exception__ class code details message phase)a
    assert Map.from_struct(HTTP.empty_body()) == %{}

    assert Notification.new(event, "request-1", :observeproperty) == %{
             event: "change",
             id: "7",
             retry: 500,
             request_id: "request-1",
             operation: :observeproperty
           }
  end

  test "WBH-K03-N preserves empty-body and subscription opacity decisions" do
    config = Factory.config()
    marker = HTTP.empty_body()
    subscription = Subscription.new(config, {:private, :handle}, "request-1", :observeproperty)

    assert marker == %EmptyBody{}
    refute marker == nil
    refute inspect(subscription) =~ "private"
    refute inspect(subscription) =~ "client_handle"
    refute inspect(subscription) =~ "instance_ref"
  end

  test "WBH-K04-P freezes defaults, byte measurement, and field precedence" do
    {:ok, config} =
      HTTP.config(
        client: {FakeClient, %{}},
        headers: [{"X-Mode", "static"}, {"X-Base", "one"}]
      )

    assert Config.max_request_bytes(config) == 1_048_576
    assert Config.max_response_bytes(config) == 4_194_304
    assert Config.max_event_bytes(config) == 1_048_576
    assert Config.max_header_count(config) == 64
    assert Config.max_header_bytes(config) == 65_536
    assert Config.max_uri_bytes(config) == 8_192

    form = %{"htv:headers" => [%{"htv:fieldName" => "X-Mode", "htv:fieldValue" => "form"}]}
    built = built_request(:readproperty, config, nil, form)

    assert Request.headers(built) == [
             {"x-mode", "form"},
             {"x-base", "one"},
             {"accept", "application/json"}
           ]

    assert {:ok, "0"} = Codec.encode(0, 1)
  end

  test "WBH-K04-N freezes positive limits and one-over rejection" do
    for option <- [
          :max_request_bytes,
          :max_response_bytes,
          :max_event_bytes,
          :max_header_count,
          :max_header_bytes,
          :max_uri_bytes
        ] do
      assert {:error, %Error{code: :invalid_limit, phase: :configuration, class: :permanent}} =
               HTTP.config([client: {FakeClient, %{}}] ++ [{option, 0}])
    end

    assert {:error,
            %Error{
              code: :request_body_too_large,
              phase: :codec,
              class: :protocol,
              details: %{max_bytes: 1}
            }} = Codec.encode(10, 1)
  end

  test "WBH-K05-P freezes supplied-client and Runtime callback arities" do
    assert Enum.sort(HTTP.Client.behaviour_info(:callbacks)) ==
             [close: 2, request: 3, subscribe: 4]

    assert Enum.sort(Wotex.Runtime.Transport.behaviour_info(:callbacks)) ==
             [decode_frame: 3, request: 3, subscribe: 4, unsubscribe: 4]

    for {name, arity} <- Wotex.Runtime.Transport.behaviour_info(:callbacks) do
      assert function_exported?(Transport, name, arity)
    end
  end

  test "WBH-K05-N freezes owner frame/status and receiver delivery tuple shapes" do
    {:ok, event} = Event.new("null")
    handshake = Factory.response(200, "", [{"Content-Type", "text/event-stream"}])

    config =
      Factory.config(%{
        frames: [event],
        subscribe_return: {:ok, :handle, handshake}
      })

    request = Factory.request(:observeproperty, nil, %{"subprotocol" => "sse"})

    assert {:ok, %Subscription{}} =
             Transport.subscribe(request, self(), Factory.context(), config)

    assert_receive {:wotex_transport_frame, ^event}

    inventory = File.read!("docs/stable-api-inventory.md")
    assert inventory =~ "{:wotex_transport_status, :reconnected | :session_lost | :transport_down}"
    assert inventory =~ "{:wotex_runtime, subscription_id, {:ok, data, meta}}"
    assert inventory =~ "{:wotex_runtime, subscription_id, {:error, %Wotex.Runtime.Error{}}}"
    assert inventory =~ "{:wotex_runtime, subscription_id, {:status, status}}"
  end

  test "WBH-K06-P freezes successful HTTP result status and metadata mapping" do
    cases = [
      {200, "null", [], :ok, nil},
      {202, "null", [{"Location", "/actions/7"}], :accepted, nil},
      {204, "", [], :ok, nil},
      {205, "", [], :ok, nil}
    ]

    for {status, body, extra_headers, result_status, payload} <- cases do
      headers =
        if body == "",
          do: extra_headers,
          else: [{"Content-Type", "application/json"} | extra_headers]

      response = Factory.response(status, body, headers)
      config = Factory.config(%{request_return: {:ok, response}})

      assert {:ok, result} =
               Transport.request(Factory.request(:readproperty), Factory.context(), config)

      assert result.status == result_status
      assert result.payload == payload
      assert result.metadata.http.method == "GET"
      assert result.metadata.http.request_uri == "https://thing.example/interactions/value"
      assert result.metadata.http.status == status
      assert result.metadata.http.headers == Response.headers(response)

      if status == 202 do
        assert result.metadata.http.location == "https://thing.example/actions/7"
      else
        refute Map.has_key?(result.metadata.http, :location)
      end

      assert_receive {:client_request, _, :credential}
    end
  end

  test "WBH-K06-N freezes every error code and all variable retry classes" do
    assert documented_error_codes() == source_error_codes()
    assert MapSet.size(source_error_codes()) == 76

    for {status, class} <- [
          {408, :timeout},
          {429, :rate_limited},
          {502, :unavailable},
          {503, :unavailable},
          {504, :unavailable},
          {302, :permanent},
          {500, :permanent}
        ] do
      config = Factory.config(%{request_return: {:ok, Factory.response(status)}})

      assert {:error, %Error{code: :http_status, phase: :response, class: ^class}} =
               Transport.request(Factory.request(:readproperty), Factory.context(), config)

      assert_receive {:client_request, _, :credential}
    end

    timeout = Factory.config(%{request_return: {:error, :timeout}})

    assert {:error, %Error{code: :client_request_failed, phase: :client, class: :timeout}} =
             Transport.request(Factory.request(:readproperty), Factory.context(), timeout)

    assert_receive {:client_request, _, :credential}
  end

  test "WBH-K07-P freezes credential separation and opaque inspection" do
    secret = {:credential, make_ref()}
    config = Factory.config(%{request_return: {:error, {:nested, secret}}})
    request = Factory.request(:readproperty)

    assert {:error, %Error{} = error} =
             Transport.request(request, Factory.context(secret), config)

    assert_receive {:client_request, %Request{} = http_request, ^secret}
    refute Map.has_key?(Map.from_struct(http_request), :credential)
    refute inspect(http_request) =~ inspect(secret)
    refute inspect(error) =~ inspect(secret)
  end

  test "WBH-K07-N freezes the no-application and no-package-owner boundary" do
    assert WotexBindingHTTP.MixProject.application() == [extra_applications: []]
    refute Code.ensure_loaded?(Wotex.Binding.HTTP.Application)
    refute function_exported?(Wotex.Binding.HTTP, :start_link, 1)
    refute function_exported?(Wotex.Binding.HTTP.Transport, :start_link, 1)
  end

  test "WBH-K08-P records an additive compatibility decision with no migration" do
    inventory = File.read!("docs/stable-api-inventory.md")

    assert inventory =~
             "No rename,\ndeprecation alias, data migration, or consumer code migration is required"

    assert inventory =~ "must update the normative\nWBH specification"

    for prior <- [
          "docs/http-operation-inventory.md",
          "docs/client-lifecycle-inventory.md",
          "docs/limits-security-inventory.md",
          "docs/reference-consumer-inventory.md",
          "docs/release-candidate-inventory.md"
        ] do
      assert File.regular?(prior)
    end
  end

  test "WBH-K08-N preserves release, matrix, serialization, and conformance nonclaims" do
    inventory = File.read!("docs/stable-api-inventory.md")
    readme = File.read!("README.md")

    assert inventory =~ "does not establish a published\nrelease"
    assert inventory =~ "serialized struct compatibility"
    assert inventory =~ "broad runtime matrix"
    assert inventory =~ "complete HTTP or WoT\nconformance"
    assert inventory =~ "permission to publish"
    refute readme =~ "The public API remains unstable"
  end

  defp built_request(operation, config, input \\ nil, form_overrides \\ %{}) do
    request =
      Factory.request(operation, input, Map.merge(form_overrides(operation), form_overrides))

    {:ok, built} = Form.build(request, config)
    built
  end

  defp input(operation) when operation in [:writeproperty, :invokeaction], do: true
  defp input(operation) when operation in [:queryaction, :cancelaction], do: "/actions/7"
  defp input(_), do: nil

  defp form_overrides(operation) when operation in [:observeproperty, :subscribeevent],
    do: %{"subprotocol" => "sse"}

  defp form_overrides(_), do: %{}

  defp struct_keys(struct) do
    struct
    |> Map.from_struct()
    |> Map.keys()
    |> Enum.sort()
  end

  defp documented_functions(module) do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)

    docs
    |> Enum.flat_map(fn
      {{:function, name, arity}, _, _, doc, _} when doc != :hidden -> ["#{name}/#{arity}"]
      _ -> []
    end)
    |> Enum.sort()
  end

  defp source_error_codes do
    "lib/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(fn file ->
      ~r/(?:Error\.new|client_error)\(\s*(:[a-z_]+)/
      |> Regex.scan(File.read!(file), capture: :all_but_first)
      |> List.flatten()
    end)
    |> MapSet.new()
  end

  defp documented_error_codes do
    inventory = File.read!("docs/stable-api-inventory.md")
    [_, rest] = String.split(inventory, "<!-- error-manifest:start -->", parts: 2)
    [manifest, _] = String.split(rest, "<!-- error-manifest:end -->", parts: 2)

    manifest
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "| `:"))
    |> Enum.flat_map(fn row ->
      cells = Enum.map(String.split(row, "|", trim: true), &String.trim/1)
      [codes | _] = cells

      ~r/`(:[a-z_]+)`/
      |> Regex.scan(codes, capture: :all_but_first)
      |> List.flatten()
    end)
    |> MapSet.new()
  end
end
