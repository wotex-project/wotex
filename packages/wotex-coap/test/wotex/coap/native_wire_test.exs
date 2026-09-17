defmodule Wotex.CoAP.NativeWireTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wotex.CoAP.{Error, Message, Native.Wire}

  @revision "7cf7465b784baded4de183290c547d582becfd28"
  @fixture_path Path.expand("../../../docs/specs/fixtures/native-v1.json", __DIR__)
  @fixture Jason.decode!(File.read!(@fixture_path))

  test "WCO-C07 WCO-N-F01 decodes the exact bounded ready line" do
    fixture = fixture("WCO-N-F01")

    assert {:ok, decoded} = Wire.line(fixture["input"])
    assert {:ok, ready} = Wire.ready(decoded)
    assert ready == %{event: :ready, backend: "libcoap", revision: @revision}

    maximum = Jason.encode!(String.duplicate("x", 131_069)) <> "\n"
    assert byte_size(maximum) == 131_072
    assert {:ok, value} = Wire.line(maximum)
    assert byte_size(value) == 131_069
  end

  test "WCO-C07 WCO-N-F02/F08 rejects duplicate, incomplete and oversized lines" do
    duplicate = fixture("WCO-N-F02")
    assert_protocol(Wire.line(duplicate["input"]))

    oversized = String.duplicate("x", fixture("WCO-N-F08")["input"]["bytes"] - 1) <> "\n"
    assert byte_size(oversized) == 131_073
    assert_protocol(Wire.line(oversized))

    for value <- [
          nil,
          "",
          "\n",
          "{}",
          "{}\n{}\n",
          "{}\r\n",
          <<255, ?\n>>,
          String.duplicate("x", 131_072)
        ] do
      assert_protocol(Wire.line(value))
    end
  end

  test "WCO-C07 frame parsing enforces JSON structure and the native integer domain" do
    assert {:ok, %{"minimum" => -0x8000000000000000, "maximum" => 0xFFFFFFFFFFFFFFFF}} =
             Wire.frame(~s({"minimum":-9223372036854775808,"maximum":18446744073709551615}))

    for frame <- [
          ~s({"value":-9223372036854775809}),
          ~s({"value":18446744073709551616}),
          ~s({"duplicate":1,"duplicate":2}),
          String.duplicate("[", 9) <> String.duplicate("]", 9),
          "{}\n",
          "{}\r",
          "not-json",
          nil
        ] do
      assert_protocol(Wire.frame(frame))
    end
  end

  test "WCO-N02 startup identity is exact and extension closed" do
    ready = %{
      "version" => 1,
      "event" => "ready",
      "backend" => "libcoap",
      "revision" => @revision
    }

    assert {:ok, %{event: :ready}} = Wire.ready(ready)

    for invalid <- [
          Map.put(ready, "version", 2),
          Map.put(ready, "event", "Ready"),
          Map.put(ready, "backend", "other"),
          Map.put(ready, "revision", String.duplicate("0", 40)),
          Map.put(ready, "extra", nil),
          Map.delete(ready, "backend"),
          nil
        ] do
      assert_protocol(Wire.ready(invalid))
    end
  end

  test "WCO-N-F10/F11 admits the exact inline threshold and rejects plus one" do
    accepted = :binary.copy("A", 32_768)
    rejected = accepted <> "A"

    assert {:ok, %Message{payload: ^accepted, code: 69, message_id: 1}} =
             Wire.response(:request, success(message(accepted)), "r1")

    assert_protocol(Wire.response(:request, success(message(rejected)), "r1"))
  end

  test "WCO-N-F12/F13 requires exactly one payload representation" do
    inline = message("")
    both = inline |> Map.put("body_id", "b1")
    neither = Map.delete(inline, "payload")

    assert_protocol(Wire.response(:request, success(both), "r1", %{"b1" => "body"}))
    assert_protocol(Wire.response(:request, success(neither), "r1"))
  end

  test "WCO-N03 resolves only a complete bounded body and never exposes its identifier" do
    maximum = :binary.copy(<<0xA5>>, 1_048_576)
    result = message_body("b1")

    assert {:ok, %Message{payload: ^maximum} = decoded} =
             Wire.response(:request, success(result), "r1", %{"b1" => maximum})

    refute Map.has_key?(Map.from_struct(decoded), :body_id)

    for bodies <- [
          %{},
          %{"other" => "body"},
          %{"b1" => maximum <> <<0>>},
          %{"b1" => nil},
          []
        ] do
      assert_protocol(Wire.response(:request, success(result), "r1", bodies))
    end

    for id <- ["", String.duplicate("x", 65), "line\nbreak", <<255>>] do
      assert_protocol(Wire.response(:request, success(message_body(id)), "r1", %{id => ""}))
    end
  end

  test "WCO-N03 reconstructs exact types, tokens and ordered options" do
    result =
      message("value")
      |> Map.put("type", "con")
      |> Map.put("code", 69)
      |> Map.put("message_id", 65_535)
      |> Map.put("token", bytes(<<0, 255>>))
      |> Map.put("options", [option(11, "a"), option(11, "b"), option(12, <<50>>)])

    assert {:ok,
            %Message{
              type: :con,
              code: 69,
              message_id: 65_535,
              token: <<0, 255>>,
              options: [{11, "a"}, {11, "b"}, {12, <<50>>}],
              payload: "value"
            }} = Wire.response(:request, success(result), "r1")

    for type <- ~w(con non ack rst) do
      result =
        message("")
        |> Map.put("type", type)
        |> valid_for_type(type)

      assert {:ok, %Message{type: decoded}} = Wire.response(:request, success(result), "r1")
      assert Atom.to_string(decoded) == type
    end
  end

  test "WCO-N03 rejects malformed Message scalars, options and aggregate headers" do
    baseline = message("")

    invalid = [
      Map.put(baseline, "type", "future"),
      Map.put(baseline, "code", -1),
      Map.put(baseline, "code", 256),
      Map.put(baseline, "code", 69.0),
      Map.put(baseline, "message_id", -1),
      Map.put(baseline, "message_id", 65_536),
      Map.put(baseline, "token", bytes(:binary.copy(<<1>>, 9))),
      Map.put(baseline, "options", [option(12, <<0, 0, 0>>)]),
      Map.put(baseline, "options", [option(99, <<>>)]),
      Map.put(baseline, "options", [option(12, <<>>), option(12, <<>>)]),
      Map.put(baseline, "options", List.duplicate(option(100, <<>>), 65)),
      Map.put(baseline, "options", [option(100, :binary.copy(<<0>>, 1_153))]),
      Map.put(baseline, "options", List.duplicate(option(100, :binary.copy(<<0>>, 20)), 64)),
      Map.put(baseline, "options", [Map.put(option(12, <<>>), "extra", nil)]),
      Map.put(baseline, "options", [option(12, <<>>) | :improper]),
      Map.put(baseline, "extra", nil)
    ]

    for result <- invalid,
        do: assert_protocol(Wire.response(:request, success(result), "r1"))
  end

  test "WCO-C07 byte envelopes require canonical padded RFC 4648 encoding" do
    baseline = message("")

    for envelope <- [
          %{},
          %{"type" => "text", "base64" => ""},
          %{"type" => "bytes", "base64" => "", "extra" => nil},
          %{"type" => "bytes", "base64" => nil},
          %{"type" => "bytes", "base64" => "Zg"},
          %{"type" => "bytes", "base64" => "Zh=="},
          %{"type" => "bytes", "base64" => "Zg__"},
          %{"type" => "bytes", "base64" => "Z g=="}
        ] do
      assert_protocol(
        Wire.response(:request, success(Map.put(baseline, "payload", envelope)), "r1")
      )
    end
  end

  test "WCO-N03 control and Observe success values are operation specific" do
    for operation <- [:open, :body_begin, :body_chunk, :body_end, :credit, :cancel, :close] do
      assert {:ok, nil} = Wire.response(operation, success(nil), "r1")
      assert_protocol(Wire.response(operation, success(%{}), "r1"))
    end

    observe = %{"subscription_id" => "r1", "generation" => 0xFFFFFFFFFFFFFFFF}

    assert {:ok, %{subscription_id: "r1", generation: 0xFFFFFFFFFFFFFFFF}} =
             Wire.response(:observe, success(observe), "r1")

    for invalid <- [
          Map.put(observe, "subscription_id", "other"),
          Map.put(observe, "generation", 0),
          Map.put(observe, "generation", 0x10000000000000000),
          Map.put(observe, "generation", 1.0),
          Map.put(observe, "extra", nil),
          nil
        ] do
      assert_protocol(Wire.response(:observe, success(invalid), "r1"))
    end

    assert_protocol(Wire.response(:unknown, success(nil), "r1"))
  end

  test "WCO-C07 responses require exact printable correlation identities" do
    response = success(nil)

    for {frame, expected} <- [
          {response, "other"},
          {Map.put(response, "id", ""), ""},
          {Map.put(response, "id", String.duplicate("x", 65)), String.duplicate("x", 65)},
          {Map.put(response, "id", "line\nbreak"), "line\nbreak"},
          {Map.put(response, "id", <<255>>), <<255>>},
          {Map.put(response, "extra", nil), "r1"},
          {Map.put(response, "version", 2), "r1"},
          {Map.put(response, "ok", 1), "r1"}
        ] do
      assert_protocol(Wire.response(:open, frame, expected))
    end
  end

  test "WCO-N03 native failures use a finite code vocabulary and bounded numeric status" do
    cases = [
      {"native_protocol_error", :native_protocol_error, :protocol},
      {"native_unavailable", :native_unavailable, :unavailable},
      {"context_store_locked", :context_store_locked, :rate_limited},
      {"context_store_corrupt", :context_store_corrupt, :permanent},
      {"fresh_context_required", :fresh_context_required, :permanent},
      {"invalid_observation_response", :invalid_observation_response, :protocol},
      {"sequence_exhausted", :sequence_exhausted, :permanent},
      {"timeout", :timeout, :timeout}
    ]

    for {wire, code, class} <- cases do
      response = failure(%{"code" => wire, "status" => 0xFFFFFFFFFFFFFFFF})

      assert {:error,
              %Error{
                code: ^code,
                class: ^class,
                effect: :none,
                details: %{status: 0xFFFFFFFFFFFFFFFF}
              }} = Wire.response(:request, response, "r1")
    end

    assert {:error,
            %Error{
              code: :remote_response,
              class: :protocol,
              effect: :none,
              details: %{code: 132}
            }} =
             Wire.response(:request, failure(%{"code" => "remote_response", "status" => 132}), "r1")

    for value <- [
          %{"code" => "remote_response"},
          %{"code" => "remote_response", "status" => -1},
          %{"code" => "remote_response", "status" => 256},
          %{"code" => "untrusted-secret-canary"},
          %{"code" => "timeout", "status" => nil},
          %{"code" => "timeout", "status" => 1.0},
          %{"code" => "timeout", "status" => 0x10000000000000000},
          %{"code" => "timeout", "message" => "secret-canary"},
          %{}
        ] do
      assert_protocol(Wire.response(:request, failure(value), "r1"))
    end
  end

  property "WCO-C07 canonical inline byte values round-trip through a native Message" do
    check all(payload <- binary(max_length: 1_024), token <- binary(max_length: 8)) do
      result = message(payload) |> Map.put("token", bytes(token))

      assert {:ok, %Message{payload: ^payload, token: ^token}} =
               Wire.response(:request, success(result), "r1")
    end
  end

  defp fixture(id), do: Enum.find(@fixture["cases"], &(&1["id"] == id))

  defp message(payload) do
    %{
      "type" => "ack",
      "code" => 69,
      "message_id" => 1,
      "token" => bytes(<<1>>),
      "options" => [],
      "payload" => bytes(payload)
    }
  end

  defp message_body(id) do
    message("")
    |> Map.delete("payload")
    |> Map.put("body_id", id)
  end

  defp option(number, value), do: %{"number" => number, "value" => bytes(value)}
  defp bytes(value), do: %{"type" => "bytes", "base64" => Base.encode64(value)}

  defp success(result),
    do: %{"version" => 1, "id" => "r1", "ok" => true, "result" => result}

  defp failure(error),
    do: %{"version" => 1, "id" => "r1", "ok" => false, "error" => error}

  defp valid_for_type(result, "rst"),
    do:
      result
      |> Map.put("code", 0)
      |> Map.put("token", bytes(<<>>))

  defp valid_for_type(result, _), do: result

  defp assert_protocol(result) do
    assert {:error,
            %Error{
              code: :native_protocol_error,
              class: :protocol,
              effect: :none,
              retryable: false,
              details: %{}
            }} = result
  end
end
