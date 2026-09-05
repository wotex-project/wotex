defmodule Wotex.Binding.HTTP.FormTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Binding.HTTP
  alias Wotex.Binding.HTTP.{Error, Form, Headers, Request}
  alias Wotex.Binding.HTTP.Test.{Factory, FakeClient}
  alias Wotex.Runtime.Result

  test "TD 1.1 and documented draft defaults map operations deterministically" do
    defaults = [
      readproperty: "GET",
      writeproperty: "PUT",
      invokeaction: "POST",
      observeproperty: "GET",
      queryaction: "GET",
      cancelaction: "DELETE",
      subscribeevent: "GET"
    ]

    for {operation, method} <- defaults do
      input = input_for(operation)
      overrides = stream_overrides(operation)
      request = Factory.request(operation, input, overrides)
      assert {:ok, built} = Form.build(request, Factory.config())
      assert Request.method(built) == method
    end
  end

  test "explicit htv method is case-sensitive and overrides a single-operation default" do
    request = Factory.request(:writeproperty, 1, %{"htv:methodName" => "PATCH"})
    assert {:ok, built} = Form.build(request, Factory.config())
    assert Request.method(built) == "PATCH"

    lowercase = Factory.request(:readproperty, nil, %{"htv:methodName" => "get"})
    assert {:ok, built} = Form.build(lowercase, Factory.config())
    assert Request.method(built) == "get"
  end

  test "explicit method is rejected on multi-operation Forms and when malformed" do
    multiple =
      Factory.request(:readproperty, nil, %{
        "op" => ["readproperty", "writeproperty"],
        "htv:methodName" => "GET"
      })

    assert {:error, %Error{code: :method_on_multi_operation_form}} =
             Form.build(multiple, Factory.config())

    invalid = Factory.request(:readproperty, nil, %{"htv:methodName" => "bad method"})
    assert {:error, %Error{code: :invalid_method}} = Form.build(invalid, Factory.config())

    wrong_type = Factory.request(:readproperty, nil, %{"htv:methodName" => 1})
    assert {:error, %Error{code: :invalid_method}} = Form.build(wrong_type, Factory.config())

    no_default = Factory.request(:unobserveproperty)
    assert {:error, %Error{code: :no_default_method}} = Form.build(no_default, Factory.config())
  end

  test "write and invoke inputs use strict JSON while an explicit marker omits action input" do
    write = Factory.request(:writeproperty, %{"on" => true})
    assert {:ok, built} = Form.build(write, Factory.config())
    assert Request.body(built) == ~s({"on":true})
    assert Headers.get(Request.headers(built), "content-type") == "application/json"

    null_action = Factory.request(:invokeaction, nil)
    assert {:ok, built} = Form.build(null_action, Factory.config())
    assert Request.body(built) == "null"

    no_input_action = Factory.request(:invokeaction, HTTP.empty_body())
    assert {:ok, built} = Form.build(no_input_action, Factory.config())
    assert Request.body(built) == nil
    assert Headers.get(Request.headers(built), "content-type") == nil

    missing_write = Factory.request(:writeproperty, HTTP.empty_body())
    assert {:error, %Error{code: :missing_input}} = Form.build(missing_write, Factory.config())

    non_json = Factory.request(:writeproperty, %{atom_key: true})
    assert {:error, %Error{code: :json_encode_failed}} = Form.build(non_json, Factory.config())
  end

  test "body and stream operations reject inputs they do not define" do
    read = Factory.request(:readproperty, %{"unexpected" => true})
    assert {:error, %Error{code: :unexpected_input}} = Form.build(read, Factory.config())

    observe = Factory.request(:observeproperty, 1, %{"subprotocol" => "sse"})
    assert {:error, %Error{code: :unexpected_input}} = Form.build(observe, Factory.config())

    assert {:error, %Error{code: :invalid_runtime_request}} = Form.build(%{}, Factory.config())
    assert {:error, %Error{code: :invalid_runtime_request}} = Form.build(read, %{})
  end

  test "request body byte limits apply after deterministic JSON encoding" do
    {:ok, config} = HTTP.config(client: {FakeClient, %{}}, max_request_bytes: 3)
    request = Factory.request(:writeproperty, "four")

    assert {:error, %Error{code: :request_body_too_large, details: %{max_bytes: 3}}} =
             Form.build(request, config)
  end

  test "Form representation is application/json with response-level validation" do
    parameterized =
      Factory.request(:readproperty, nil, %{"contentType" => "Application/JSON; charset=utf-8"})

    assert {:ok, built} = Form.build(parameterized, Factory.config())
    assert Request.media_type(built) == "application/json"

    unsupported = Factory.request(:readproperty, nil, %{"contentType" => "application/cbor"})

    assert {:error, %Error{code: :unsupported_media_type}} =
             Form.build(unsupported, Factory.config())

    invalid = Factory.request(:readproperty)

    invalid_form =
      invalid.form
      |> Wotex.Form.to_map()
      |> Map.put("contentType", 1)
      |> then(&%Wotex.Form{value: &1})

    invalid = %{invalid | form: invalid_form}
    assert {:error, %Error{code: :invalid_media_type}} = Form.build(invalid, Factory.config())

    different_response =
      Factory.request(:invokeaction, 1, %{
        "response" => %{"contentType" => "application/problem+json"}
      })

    assert {:error, %Error{code: :unsupported_media_type}} =
             Form.build(different_response, Factory.config())

    request = Factory.request(:readproperty)
    {:ok, form} = Wotex.Form.new(Map.drop(Wotex.Form.to_map(request.form), ["contentType"]))
    request = %{request | form: form}
    assert {:ok, built} = Form.build(request, Factory.config())
    assert Request.media_type(built) == "application/json"
  end

  test "htv headers are validated and Form fields override static fields" do
    {:ok, config} =
      HTTP.config(
        client: {FakeClient, %{}},
        headers: [{"X-Source", "config"}, {"X-Static", "present"}]
      )

    request =
      Factory.request(:readproperty, nil, %{
        "htv:headers" => [
          %{"htv:fieldName" => "X-Source", "htv:fieldValue" => "form"},
          %{"htv:fieldName" => "X-Empty"}
        ]
      })

    assert {:ok, built} = Form.build(request, config)
    assert Headers.get(Request.headers(built), "x-source") == "form"
    assert Headers.get(Request.headers(built), "x-static") == "present"
    assert Headers.get(Request.headers(built), "x-empty") == ""
    assert Headers.get(Request.headers(built), "accept") == "application/json"
  end

  test "malformed, duplicate, credential, framing, and conflicting Form headers fail" do
    cases = [
      {%{"htv:headers" => %{}}, :invalid_form_headers},
      {%{"htv:headers" => [%{}]}, :invalid_form_header},
      {%{"htv:headers" => [%{"htv:fieldName" => "X", "htv:fieldValue" => 1}]},
       :invalid_form_header},
      {%{
         "htv:headers" => [
           %{"htv:fieldName" => "X", "htv:fieldValue" => "1"},
           %{"htv:fieldName" => "x", "htv:fieldValue" => "2"}
         ]
       }, :duplicate_header},
      {%{"htv:headers" => [%{"htv:fieldName" => "Cookie", "htv:fieldValue" => "x"}]},
       :credential_header_forbidden},
      {%{
         "htv:headers" => [%{"htv:fieldName" => "Content-Length", "htv:fieldValue" => "1"}]
       }, :framing_header_forbidden},
      {%{
         "htv:headers" => [%{"htv:fieldName" => "Accept", "htv:fieldValue" => "text/plain"}]
       }, :conflicting_header}
    ]

    for {overrides, code} <- cases do
      request = Factory.request(:readproperty, nil, overrides)
      assert {:error, %Error{code: ^code}} = Form.build(request, Factory.config())
    end

    content_conflict =
      Factory.request(:writeproperty, true, %{
        "htv:headers" => [%{"htv:fieldName" => "Content-Type", "htv:fieldValue" => "text/plain"}]
      })

    assert {:error, %Error{code: :conflicting_header}} =
             Form.build(content_conflict, Factory.config())
  end

  test "SSE operations require an explicit sse subprotocol and event-stream acceptance" do
    for operation <- [:observeproperty, :subscribeevent] do
      missing = Factory.request(operation)

      assert {:error, %Error{code: :unsupported_subprotocol}} =
               Form.build(missing, Factory.config())

      request = Factory.request(operation, nil, %{"subprotocol" => "sse"})
      assert {:ok, built} = Form.build(request, Factory.config())
      assert Request.stream?(built)
      assert Headers.get(Request.headers(built), "accept") == "text/event-stream"
    end
  end

  test "query and cancel resolve ActionStatus targets from supported invocation values" do
    base = "https://thing.example/actions/fade"

    values = [
      {"status/1", "https://thing.example/actions/status/1"},
      {%{"href" => "/actions/fade/2"}, "https://thing.example/actions/fade/2"},
      {%{href: "https://other.example/action/3"}, "https://other.example/action/3"}
    ]

    for {input, expected} <- values do
      request = Factory.request(:queryaction, input, %{"href" => base})
      assert {:ok, built} = Form.build(request, Factory.config())
      assert Request.uri(built) == expected
      assert Request.body(built) == nil
    end

    {:ok, prior} =
      Result.new("request-0", :invokeaction, %{"status" => "pending"},
        status: 201,
        metadata: %{http: %{location: "https://thing.example/actions/fade/4"}}
      )

    request = Factory.request(:cancelaction, prior, %{"href" => base})
    assert {:ok, built} = Form.build(request, Factory.config())
    assert Request.uri(built) == "https://thing.example/actions/fade/4"

    {:ok, payload_prior} =
      Result.new("request-0", :invokeaction, %{"href" => "/actions/fade/5"}, status: 201)

    request = Factory.request(:queryaction, payload_prior, %{"href" => base})
    assert {:ok, built} = Form.build(request, Factory.config())
    assert Request.uri(built) == "https://thing.example/actions/fade/5"
  end

  test "query and cancel reject missing or unsafe ActionStatus targets" do
    missing = Factory.request(:queryaction, nil)
    assert {:error, %Error{code: :missing_action_target}} = Form.build(missing, Factory.config())

    unsafe = Factory.request(:cancelaction, "https://name:value@thing.example/action")

    assert {:error, %Error{code: :uri_credentials_forbidden}} =
             Form.build(unsafe, Factory.config())
  end

  defp input_for(operation) when operation in [:writeproperty, :invokeaction], do: true
  defp input_for(operation) when operation in [:queryaction, :cancelaction], do: "/actions/value/1"
  defp input_for(_), do: nil

  defp stream_overrides(operation) when operation in [:observeproperty, :subscribeevent],
    do: %{"subprotocol" => "sse"}

  defp stream_overrides(_), do: %{}
end
