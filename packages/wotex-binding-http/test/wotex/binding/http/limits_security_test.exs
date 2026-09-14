defmodule Wotex.Binding.HTTP.LimitsSecurityTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Binding.HTTP

  alias Wotex.Binding.HTTP.{Codec, Config, Error, Form, Request}
  alias Wotex.Binding.HTTP.{Response, Subscription, Transport}
  alias Wotex.Binding.HTTP.SSE.Event
  alias Wotex.Binding.HTTP.Test.{Factory, FakeClient}

  @expected_cells [
    {"WBH-S01", ["WBH-S01-P", "WBH-S01-N"]},
    {"WBH-S02", ["WBH-S02-P", "WBH-S02-N"]},
    {"WBH-S03", ["WBH-S03-P", "WBH-S03-N"]},
    {"WBH-S04", ["WBH-S04-P", "WBH-S04-N"]},
    {"WBH-S05", ["WBH-S05-P", "WBH-S05-N"]},
    {"WBH-S06", ["WBH-S06-P", "WBH-S06-N"]},
    {"WBH-S07", ["WBH-S07-P", "WBH-S07-N"]},
    {"WBH-S08", ["WBH-S08-P", "WBH-S08-N"]},
    {"WBH-S09", ["WBH-S09-P", "WBH-S09-N"]},
    {"WBH-S10", ["WBH-S10-P", "WBH-S10-N"]},
    {"WBH-S11", ["WBH-S11-N"]},
    {"WBH-S12", ["WBH-S12-P"]},
    {"WBH-S13", ["WBH-S13-P"]}
  ]

  @evidence_files [
    "test/wotex/binding/http/limits_security_test.exs",
    "test/wotex/binding/http/integration_test.exs"
  ]

  test "the public limits/security inventory maps every cell to a named vector" do
    documented =
      "docs/limits-security-inventory.md"
      |> File.read!()
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "| WBH-S"))
      |> Enum.map(&documented_cell/1)

    assert documented == @expected_cells

    test_names =
      @evidence_files
      |> Enum.map_join("\n", &File.read!/1)
      |> then(&Regex.scan(~r/test "([^"]+)"/, &1, capture: :all_but_first))
      |> List.flatten()

    for {_, vectors} <- @expected_cells, vector <- vectors do
      assert Enum.any?(test_names, &String.contains?(&1, vector)),
             "#{vector} has no executable test"
    end
  end

  test "WBH-S01-P and WBH-S01-N defaults are exact and every limit stays positive" do
    assert {:ok, config} = HTTP.config(client: {FakeClient, %{}})
    assert Config.max_request_bytes(config) == 1_048_576
    assert Config.max_response_bytes(config) == 4_194_304
    assert Config.max_event_bytes(config) == 1_048_576
    assert Config.max_header_count(config) == 64
    assert Config.max_header_bytes(config) == 65_536
    assert Config.max_uri_bytes(config) == 8_192

    options = [
      :max_request_bytes,
      :max_response_bytes,
      :max_event_bytes,
      :max_header_count,
      :max_header_bytes,
      :max_uri_bytes
    ]

    for option <- options do
      assert {:error, %Error{code: :invalid_limit, details: %{option: ^option}}} =
               HTTP.config([client: {FakeClient, %{}}] ++ [{option, 0}])
    end
  end

  test "WBH-S02-P and WBH-S02-N request bytes admit exact and reject one over before I/O" do
    config = request_config(max_request_bytes: 1)

    assert {:ok, _} =
             Transport.request(Factory.request(:writeproperty, 0), Factory.context(), config)

    assert_receive {:client_request, %Request{body: "0"}, :credential}

    assert {:error,
            %Error{code: :request_body_too_large, details: %{max_bytes: 1}, class: :protocol}} =
             Transport.request(Factory.request(:writeproperty, 10), Factory.context(), config)

    refute_receive {:client_request, _, _}
  end

  test "WBH-S03-P and WBH-S03-N response bytes admit exact and reject one over" do
    exact = request_config(response: response(200, "null"), max_response_bytes: 4)

    assert {:ok, %{payload: nil}} =
             Transport.request(Factory.request(:readproperty), Factory.context(), exact)

    assert_receive {:client_request, _, :credential}

    over = request_config(response: response(200, "false"), max_response_bytes: 4)

    assert {:error, %Error{code: :response_body_too_large, details: %{max_bytes: 4}}} =
             Transport.request(Factory.request(:readproperty), Factory.context(), over)

    assert_receive {:client_request, _, :credential}
  end

  test "WBH-S04-P and WBH-S04-N event bytes admit exact and reject one over" do
    {:ok, config} = HTTP.config(client: {FakeClient, %{}}, max_event_bytes: 4)
    request = Factory.request(:observeproperty, nil, %{"subprotocol" => "sse"})
    assert {:ok, exact} = Event.new("null")
    assert {:ok, nil, _} = Transport.decode_frame(exact, request, config)

    assert {:ok, over} = Event.new("false")

    assert {:error,
            %Error{
              code: :sse_event_too_large,
              details: %{max_bytes: 4},
              class: :protocol
            }} =
             Transport.decode_frame(over, request, config)
  end

  test "WBH-S05-P and WBH-S05-N request/response field count is exact" do
    assert {:ok, _} =
             HTTP.config(
               client: {FakeClient, %{}},
               headers: [{"X", ""}],
               max_header_count: 1
             )

    assert {:error, %Error{code: :header_count_exceeded, phase: :configuration}} =
             HTTP.config(
               client: {FakeClient, %{}},
               headers: [{"X", ""}, {"Y", ""}],
               max_header_count: 1
             )

    exact = request_config(max_header_count: 1)

    assert {:ok, %Request{headers: [{"accept", "application/json"}]}} =
             Form.build(Factory.request(:readproperty), exact)

    over_request =
      Factory.request(:readproperty, nil, %{
        "htv:headers" => [%{"htv:fieldName" => "X", "htv:fieldValue" => ""}]
      })

    assert {:error,
            %Error{
              code: :header_count_exceeded,
              phase: :request,
              details: %{max_count: 1}
            }} =
             Form.build(over_request, exact)

    exact_response =
      request_config(response: response(200, "null"), max_header_count: 1)

    assert {:ok, _} =
             Transport.request(Factory.request(:readproperty), Factory.context(), exact_response)

    assert_receive {:client_request, _, :credential}

    over =
      request_config(
        response: response(200, "null", [{"Content-Type", "application/json"}, {"X", ""}]),
        max_header_count: 1
      )

    assert {:error, %Error{code: :header_count_exceeded, phase: :response}} =
             Transport.request(Factory.request(:readproperty), Factory.context(), over)
  end

  test "WBH-S06-P and WBH-S06-N request/response aggregate field bytes are exact" do
    assert {:ok, _} =
             HTTP.config(
               client: {FakeClient, %{}},
               headers: [{"X", ""}],
               max_header_bytes: 1
             )

    assert {:error, %Error{code: :header_bytes_exceeded, phase: :configuration}} =
             HTTP.config(
               client: {FakeClient, %{}},
               headers: [{"X", "1"}],
               max_header_bytes: 1
             )

    exact_request = request_config(max_header_bytes: 22)
    assert {:ok, _} = Form.build(Factory.request(:readproperty), exact_request)

    one_over =
      Factory.request(:readproperty, nil, %{
        "htv:headers" => [%{"htv:fieldName" => "X", "htv:fieldValue" => ""}]
      })

    assert {:error,
            %Error{code: :header_bytes_exceeded, phase: :request, details: %{max_bytes: 22}}} =
             Form.build(one_over, exact_request)

    exact_response = request_config(response: response(200, "null"), max_header_bytes: 28)

    assert {:ok, _} =
             Transport.request(Factory.request(:readproperty), Factory.context(), exact_response)

    assert_receive {:client_request, _, :credential}

    over_response =
      request_config(
        response: response(200, "null", [{"Content-Type", "application/json"}, {"X", ""}]),
        max_header_bytes: 28
      )

    assert {:error, %Error{code: :header_bytes_exceeded, phase: :response}} =
             Transport.request(Factory.request(:readproperty), Factory.context(), over_response)
  end

  test "WBH-S07-P and WBH-S07-N request URI bytes are admitted exactly" do
    uri = "https://a.example/x"
    exact = request_config(max_uri_bytes: byte_size(uri))
    request = Factory.request(:readproperty, nil, %{"href" => uri})

    assert {:ok, %Request{} = built} = Form.build(request, exact)
    assert Request.uri(built) == uri
    assert Request.max_uri_bytes(built) == byte_size(uri)

    over = Factory.request(:readproperty, nil, %{"href" => uri <> "x"})

    assert {:error, %Error{code: :uri_too_large, details: %{max_bytes: max_bytes}}} =
             Form.build(over, exact)

    assert max_bytes == byte_size(uri)
  end

  test "WBH-S08-P and WBH-S08-N native JSON is rejected before bounded output materialization" do
    assert {:ok, ~s("")} = Codec.encode("", 2)

    assert {:error, %Error{code: :request_body_too_large, details: %{max_bytes: 1}}} =
             Codec.encode("", 1)

    assert {:error, %Error{code: :request_body_too_large, details: %{max_bytes: 8}}} =
             Codec.encode(String.duplicate("\"", 9), 8)

    deeply_nested = Enum.reduce(1..65, nil, fn _, value -> [value] end)

    assert {:error,
            %Error{
              code: :json_limit_exceeded,
              details: %{limit: :depth_limit_exceeded}
            }} =
             Codec.encode(deeply_nested, 1_024)
  end

  test "WBH-S09-P and WBH-S09-N deadlines cross unchanged; client timeout is classified" do
    deadline_values = [nil, 123_456, ~U[2030-01-01 00:00:00Z]]

    for deadline <- deadline_values do
      config = request_config()
      request = %{Factory.request(:readproperty) | deadline: deadline}
      assert {:ok, _} = Transport.request(request, Factory.context(), config)
      assert_receive {:client_request, %Request{} = built, :credential}
      assert Request.deadline(built) == deadline
    end

    timeout = request_config(request_return: {:error, :timeout})

    assert {:error, %Error{code: :client_request_failed, class: :timeout}} =
             Transport.request(Factory.request(:readproperty), Factory.context(), timeout)

    assert_receive {:client_request, _, :credential}
  end

  test "WBH-S10-P and WBH-S10-N redirects are not followed and audience policy stays client-owned" do
    redirect =
      response(302, "", [{"Location", "https://other.example/private"}])

    config = request_config(response: redirect)

    assert {:error, %Error{code: :http_status, details: %{status: 302}}} =
             Transport.request(Factory.request(:readproperty), Factory.context(), config)

    assert_receive {:client_request, %Request{}, :credential}
    refute_receive {:client_request, _, _}

    secret = "credential-audience-secret"
    nested_rejection = {:audience_rejected, %{credential: secret}}
    rejecting = request_config(request_return: {:error, nested_rejection})
    action = Factory.request(:queryaction, "https://other.example/actions/1")

    assert {:error, %Error{code: :client_request_failed} = error} =
             Transport.request(action, Factory.context(secret), rejecting)

    assert_receive {:client_request, %Request{} = built, ^secret}
    assert Request.uri(built) == "https://other.example/actions/1"
    refute encoded(error) =~ secret
  end

  test "WBH-S11-N every callback redacts nested external failures" do
    secret = "nested-client-secret"
    nested = {:outer, [%{credential: secret}, {:connection, self(), make_ref()}]}
    stream = Factory.request(:subscribeevent, nil, %{"subprotocol" => "sse"})

    for returned <- [
          {:error, nested},
          {:raise, RuntimeError.exception(secret)},
          {:exit, nested},
          {:throw, nested}
        ] do
      config =
        request_config(
          request_return: returned,
          subscribe_return: returned,
          close_return: returned
        )

      assert {:error, %Error{} = request_error} =
               Transport.request(Factory.request(:readproperty), Factory.context(), config)

      assert {:error, %Error{} = subscribe_error} =
               Transport.subscribe(stream, self(), Factory.context(), config)

      subscription = Subscription.new(config, :handle, "request-1", :subscribeevent)

      assert {:error, %Error{} = close_error} =
               Transport.unsubscribe(
                 subscription,
                 Factory.request(:unsubscribeevent),
                 Factory.context(),
                 config
               )

      for error <- [request_error, subscribe_error, close_error] do
        refute inspect(error) =~ secret
        refute encoded(error) =~ secret
      end
    end
  end

  defp request_config(opts \\ []) do
    response = Keyword.get(opts, :response, response(204, "", []))

    client_config = %{
      owner: self(),
      request_return: Keyword.get(opts, :request_return, {:ok, response}),
      subscribe_return: Keyword.get(opts, :subscribe_return, {:error, :not_configured}),
      close_return: Keyword.get(opts, :close_return, :ok)
    }

    config_opts =
      opts
      |> Keyword.drop([:response, :request_return, :subscribe_return, :close_return])
      |> Keyword.put(:client, {FakeClient, client_config})

    {:ok, config} = HTTP.config(config_opts)
    config
  end

  defp response(status, body, headers \\ [{"Content-Type", "application/json"}]) do
    {:ok, response} = Response.new(status, headers, body)
    response
  end

  defp encoded(term), do: :erlang.term_to_binary(term)

  defp documented_cell(line) do
    [cell, _, vectors] =
      line
      |> String.split("|", trim: true)
      |> Enum.map(&String.trim/1)

    {cell, String.split(vectors, ", ")}
  end
end
