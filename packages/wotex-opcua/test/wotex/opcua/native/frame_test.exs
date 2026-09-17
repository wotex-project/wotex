defmodule Wotex.OPCUA.Native.FrameTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.OPCUA.Error
  alias Wotex.OPCUA.Native.{Frame, Ready}

  test "WOP-X03 owner deadline retains the ready-to-receive delay and caps timeout" do
    ready = %Ready{clock_ms: 50}
    assert {:ok, %{deadline_ms: 60, timeout_ms: 5}} = Frame.admission(ready, 100, 110, 105, 20)
    assert {:ok, %{deadline_ms: 60, timeout_ms: 10}} = Frame.admission(ready, 100, 110, 100, 60_000)

    for now <- [110, 111] do
      assert {:error, %Error{code: :deadline_exceeded}} =
               Frame.admission(ready, 100, 110, now, 20)
    end

    assert {:error, %Error{code: :invalid_native_frame}} =
             Frame.admission(%Ready{clock_ms: 9_223_372_036_854_775_807}, 100, 110, 105, 20)
  end

  @tag case: "WOP-X-F17"
  test "WOP-X-F17 owner deadline translation matches the native contract corpus" do
    corpus = File.read!("docs/specs/fixtures/native-contract-v1.json")

    fixture = Enum.find(Jason.decode!(corpus)["cases"], &(&1["id"] == "WOP-X-F17"))

    input = fixture["input"]
    expected = fixture["expectation"]["value"]["native_deadline_ms"]
    ready = %Ready{clock_ms: input["ready_native_ms"]}
    received = input["ready_received_owner_ms"]
    deadline = input["owner_deadline_ms"]

    assert {:ok, %{deadline_ms: ^expected}} =
             Frame.admission(ready, received, deadline, received, 60_000)
  end

  test "WOP-X03 output classification separates terminal, response and mismatch lines" do
    terminal =
      ~s({"version":1,"generation":7,"event":"terminal","error":{"code":"busy","phase":"admission","effect":"none"}}\n)

    assert {:terminal, %Error{code: :busy}} = Frame.classify(terminal, 7)
    assert {:error, %Error{code: :response_mismatch}} = Frame.classify(terminal, 8)
    assert {:response, "r1"} = Frame.classify(~s({"version":1,"generation":7,"id":"r1"}\n), 7)

    for invalid <- [
          ~s({"version":1,"generation":7,"id":""}\n),
          ~s({"version":1,"generation":7,"id":"a\\u0001"}\n),
          ~s({"version":1,"generation":7,"event":"terminal","error":{}}\n),
          ~s({"version":1,"generation":7}\n{"version":1}\n),
          ~s({"version":2,"generation":7,"id":"r1"}\n)
        ] do
      assert {:error, %Error{code: :invalid_native_frame}} = Frame.classify(invalid, 7)
    end

    assert {:error, %Error{code: :invalid_native_frame}} = Frame.classify(:line, 7)

    assert {:ok, %{"target_id" => "r1", "canceled" => false}} =
             Frame.response(
               ~s({"version":1,"generation":7,"id":"c1","ok":true,"result":{"target_id":"r1","canceled":false}}\n),
               7,
               "c1",
               "cancel",
               nil
             )

    assert {:error, %Error{code: :invalid_native_frame}} =
             Frame.response(
               ~s({"version":1,"generation":7,"id":"c1","ok":true,"result":{"target_id":"r\\u0001","canceled":true}}\n),
               7,
               "c1",
               "cancel",
               nil
             )
  end

  test "WOP-S01 identity-bearing native Variants validate exact envelopes" do
    for {type, value} <- [
          {"NodeId", "ns=1;s=target"},
          {"ExpandedNodeId",
           %{"node_id" => "ns=0;i=1", "namespace_uri" => "urn:x", "server_index" => 3}},
          {"QualifiedName", %{"namespace" => 1, "name" => nil}},
          {"ExtensionObject", %{"encoding_id" => "ns=1;i=2", "encoding" => "none", "body" => nil}},
          {"ExtensionObject",
           %{
             "encoding_id" => "ns=1;i=2",
             "encoding" => "binary",
             "body" => %{"type" => "bytes", "base64" => "AQ=="}
           }}
        ] do
      for array <- [false, true] do
        payload = if array, do: [value, value], else: value
        result = %{"has_value" => true, "status" => 0, "value" => variant(type, array, payload)}
        assert {:ok, ^result} = Frame.response(response(result), 7, "r", "read", nil)
      end
    end

    for {type, value} <- [
          {"NodeId", "not a node"},
          {"ExpandedNodeId",
           %{"node_id" => "ns=1;i=1", "namespace_uri" => "urn:x", "server_index" => 0}},
          {"ExpandedNodeId", %{"node_id" => "ns=0;i=1"}},
          {"QualifiedName", %{"namespace" => 70_000, "name" => "x"}},
          {"QualifiedName", %{"namespace" => 1}},
          {"ExtensionObject",
           %{
             "encoding_id" => "ns=1;i=2",
             "encoding" => "none",
             "body" => %{"type" => "bytes", "base64" => "AQ=="}
           }},
          {"ExtensionObject",
           %{"encoding_id" => "ns=1;i=2", "encoding" => "binary", "body" => nil}},
          {"ExtensionObject",
           %{"encoding_id" => "ns=1;i=2", "encoding" => "binary", "body" => "AQ=="}},
          {"ExtensionObject", "opaque"}
        ] do
      result = %{"has_value" => true, "status" => 0, "value" => variant(type, false, value)}

      assert {:error, %Error{code: :invalid_native_frame}} =
               Frame.response(response(result), 7, "r", "read", nil)
    end
  end

  defp variant(type, array, value), do: %{"type" => type, "array" => array, "value" => value}

  defp response(result),
    do:
      Jason.encode!(%{
        "version" => 1,
        "generation" => 7,
        "id" => "r",
        "ok" => true,
        "result" => result
      }) <> "\n"

  test "WOP-X03 request contains only exact integer fields and one LF" do
    assert {:ok, frame} =
             Frame.request(
               18_446_744_073_709_551_615,
               "request-1",
               "read",
               %{},
               60_000,
               9_223_372_036_854_775_807
             )

    assert byte_size(frame) <= 131_072
    assert String.ends_with?(frame, "\n")
    assert {:ok, decoded} = Wotex.JSON.decode(binary_part(frame, 0, byte_size(frame) - 1))

    assert decoded == %{
             "version" => 1,
             "generation" => 18_446_744_073_709_551_615,
             "id" => "request-1",
             "operation" => "read",
             "parameters" => %{},
             "timeout_ms" => 60_000,
             "deadline_ms" => 9_223_372_036_854_775_807
           }
  end

  test "WOP-X03 request rejects malformed and resource-exhausting values before emission" do
    valid = [1, "a", "read", %{}, 1, 1]

    for invalid <- [
          [0, "a", "read", %{}, 1, 1],
          [18_446_744_073_709_551_616, "a", "read", %{}, 1, 1],
          [1, "", "read", %{}, 1, 1],
          [1, "a\n", "read", %{}, 1, 1],
          [1, String.duplicate("a", 65), "read", %{}, 1, 1],
          [1, "a", "eval", %{}, 1, 1],
          [1, "a", "read", [], 1, 1],
          [1, "a", "read", %{}, 0, 1],
          [1, "a", "read", %{}, 60_001, 1],
          [1, "a", "read", %{}, 1, -1],
          [1, "a", "read", %{}, 1, 9_223_372_036_854_775_808],
          [1, "a", "read", %{"payload" => String.duplicate("x", 65_537)}, 1, 1],
          [1, "a", "read", %{"bad" => self()}, 1, 1]
        ] do
      assert {:error, %Error{code: :invalid_native_frame}} = apply(Frame, :request, invalid)
    end

    assert {:ok, _} = apply(Frame, :request, valid)
  end

  test "WOP-X04 terminal control has one generation and finite error fields" do
    terminal =
      ~s({"version":1,"generation":7,"event":"terminal","error":{"code":"unsupported_protocol","phase":"validation","effect":"none"}}\n)

    assert {:ok, %Error{code: :unsupported_protocol, effect: :none} = error} =
             Frame.terminal(terminal, 7)

    assert error.details == %{phase: :validation}

    with_status =
      String.replace(terminal, ~s("effect":"none"), ~s("effect":"unknown","status":4294967295))

    assert {:ok,
            %Error{
              code: :unsupported_protocol,
              effect: :unknown,
              details: %{phase: :validation, status: 4_294_967_295}
            }} = Frame.terminal(with_status, 7)

    for invalid <- [
          terminal <> terminal,
          binary_part(terminal, 0, byte_size(terminal) - 1),
          String.replace(terminal, ~s("generation":7), ~s("generation":8)),
          String.replace(terminal, ~s("version":1), ~s("version":1.0)),
          String.replace(terminal, ~s("code":"unsupported_protocol"), ~s("code":"arbitrary")),
          String.replace(terminal, ~s("phase":"validation"), ~s("phase":"arbitrary")),
          String.replace(terminal, ~s("effect":"none"), ~s("effect":"arbitrary")),
          String.replace(terminal, ~s("effect":"none"), ~s("effect":"none","status":4294967296)),
          String.replace(terminal, ~s("effect":"none"), ~s("effect":"none","secret":"value")),
          String.replace(terminal, ~s("generation":7), ~s("generation":7,"generation":7)),
          :binary.copy(" ", 4097)
        ] do
      assert {:error, %Error{code: :invalid_native_frame}} = Frame.terminal(invalid, 7)
    end
  end

  test "WOP-X04 initial credit is exact, bounded and generation-scoped" do
    assert {:ok, frame} = Frame.credit(18_446_744_073_709_551_615, 1, 16, 262_144)
    assert String.ends_with?(frame, "\n")
    assert byte_size(frame) <= 4096
    assert {:ok, value} = Wotex.JSON.decode(binary_part(frame, 0, byte_size(frame) - 1))

    assert value == %{
             "version" => 1,
             "generation" => 18_446_744_073_709_551_615,
             "event" => "credit",
             "sequence" => 1,
             "messages" => 16,
             "bytes" => 262_144
           }

    for invalid <- [
          [0, 1, 16, 262_144],
          [1, 0, 16, 262_144],
          [1, 1, 0, 262_144],
          [1, 1, 17, 262_144],
          [1, 1, 16, 0],
          [1, 1, 16, 262_145]
        ] do
      assert {:error, %Error{code: :invalid_native_frame, field: :credit}} =
               apply(Frame, :credit, invalid)
    end
  end

  test "WOP-X03 open response requires the matching generation and bounded server metadata" do
    result = %{
      "session_generation" => 7,
      "session_timeout_ms" => 3210.5,
      "namespace_array" => ["http://opcfoundation.org/UA/", "urn:wotex:fixture"]
    }

    frame = fn payload ->
      Jason.encode!(%{
        "version" => 1,
        "generation" => 7,
        "id" => "open-1",
        "ok" => true,
        "result" => payload
      }) <>
        "\n"
    end

    assert {:ok, ^result} = Frame.response(frame.(result), 7, "open-1", "open", 5000)

    for invalid <- [
          %{result | "session_generation" => 8},
          %{result | "session_timeout_ms" => 5000.1},
          %{result | "session_timeout_ms" => 0},
          %{result | "namespace_array" => ["http://opcfoundation.org/UA/", "urn:x", "urn:x"]},
          %{result | "namespace_array" => ["urn:wrong", "urn:x"]},
          Map.put(result, "unexpected", true)
        ] do
      assert {:error, %Error{code: :invalid_native_frame}} =
               Frame.response(frame.(invalid), 7, "open-1", "open", 5000)
    end

    assert {:error, %Error{code: :invalid_native_frame}} =
             Frame.response(frame.(result), 7, "other", "open", 5000)
  end

  test "WOP-X03 read response preserves typed DataValue and rejects malformed metadata" do
    result = %{
      "has_value" => true,
      "status" => 0,
      "value" => %{"type" => "Double", "array" => false, "value" => 21.5},
      "source_timestamp" => 1
    }

    frame = fn payload ->
      Jason.encode!(%{
        "version" => 1,
        "generation" => 7,
        "id" => "read-1",
        "ok" => true,
        "result" => payload
      }) <> "\n"
    end

    assert {:ok, ^result} = Frame.response(frame.(result), 7, "read-1", "read", nil)

    for invalid <- [
          %{result | "has_value" => false},
          %{result | "status" => 0x8000_0000},
          %{result | "value" => %{"type" => "Double", "array" => false, "value" => "21.5"}},
          Map.put(result, "unexpected", true),
          Map.put(result, "source_picoseconds", 10_000)
        ] do
      assert {:error, %Error{code: :invalid_native_frame}} =
               Frame.response(frame.(invalid), 7, "read-1", "read", nil)
    end
  end

  test "WOP-X03 read response preserves null, byte arrays and localized text" do
    frame = fn result ->
      Jason.encode!(%{
        "version" => 1,
        "generation" => 7,
        "id" => "read-2",
        "ok" => true,
        "result" => result
      }) <> "\n"
    end

    results = [
      %{"has_value" => false, "status" => 0x4000_0000},
      %{
        "has_value" => true,
        "status" => 0,
        "value" => %{
          "type" => "ByteString",
          "array" => true,
          "value" => [%{"type" => "bytes", "base64" => "AP8="}, nil]
        }
      },
      %{
        "has_value" => true,
        "status" => 0,
        "value" => %{
          "type" => "LocalizedText",
          "array" => true,
          "value" => [%{"locale" => "en", "text" => "ready"}]
        }
      }
    ]

    for result <- results do
      assert {:ok, ^result} = Frame.response(frame.(result), 7, "read-2", "read", nil)
    end

    for invalid <- [
          %{"has_value" => false, "status" => 0, "value" => nil},
          %{
            "has_value" => true,
            "status" => 0,
            "value" => %{
              "type" => "ByteString",
              "array" => false,
              "value" => %{"type" => "bytes", "base64" => "not base64!"}
            }
          },
          %{
            "has_value" => true,
            "status" => 0,
            "value" => %{
              "type" => "LocalizedText",
              "array" => false,
              "value" => %{"locale" => "en", "text" => "ready", "unexpected" => true}
            }
          },
          %{
            "has_value" => true,
            "status" => 0,
            "value" => %{"type" => "Unknown", "array" => false, "value" => 1}
          }
        ] do
      assert {:error, %Error{code: :invalid_native_frame}} =
               Frame.response(frame.(invalid), 7, "read-2", "read", nil)
    end
  end

  test "WOP-S04 subscription reports and subscribe results are exact and token-bound" do
    frame = fn attributes -> Jason.encode!(attributes) <> "\n" end
    variant = %{"type" => "Double", "array" => false, "value" => 1.5}
    value = %{"has_value" => true, "status" => 0, "value" => variant}

    metadata = %{
      "sequence" => 1,
      "publish_time" => 1001,
      "client_handle" => 7,
      "overflow" => false,
      "datetime_resolution_ns" => 100,
      "raw_datetime_ticks_available" => true
    }

    base = %{
      "version" => 1,
      "generation" => 7,
      "subscription_id" => "s7",
      "event" => "data",
      "value" => value,
      "metadata" => metadata
    }

    failure = %{"code" => "sequence_gap", "phase" => "exchange", "effect" => "none"}
    error_report = %{base | "event" => "error", "value" => failure, "metadata" => %{}}

    assert {:report, "s7"} = Frame.classify(frame.(base), 7)
    assert {:data, ^value, ^metadata} = Frame.report(frame.(base), 7, "s7")

    assert {:error_report, %Error{code: :sequence_gap, effect: :none}} =
             Frame.report(frame.(error_report), 7, "s7")

    for token <- ["s0", "s01", "s4294967296", "x7", 7] do
      assert {:error, %Error{code: :invalid_native_frame}} =
               Frame.classify(frame.(%{base | "subscription_id" => token}), 7)
    end

    for invalid <- [
          Map.put(base, "extra", true),
          %{base | "event" => "status"},
          %{base | "value" => %{value | "status" => -1}},
          %{base | "value" => Map.delete(value, "value")},
          %{base | "metadata" => %{metadata | "datetime_resolution_ns" => 1}},
          %{base | "metadata" => Map.put(metadata, "extra", 1)},
          %{error_report | "value" => Map.put(failure, "secret", "x")},
          %{error_report | "metadata" => metadata},
          %{base | "subscription_id" => "s8"},
          %{base | "generation" => 8}
        ] do
      assert {:error, %Error{code: :invalid_native_frame, field: :report}} =
               Frame.report(frame.(invalid), 7, "s7")
    end

    assert {:error, %Error{field: :report}} = Frame.report(frame.(base) <> "{}\n", 7, "s7")
    assert {:error, %Error{field: :report}} = Frame.report(:line, 7, "s7")

    result = %{
      "subscription" => "s7",
      "subscription_id" => 11,
      "monitored_item_id" => 12,
      "client_handle" => 7,
      "item_status" => 0,
      "publishing_interval_ms" => 500.5,
      "sampling_interval_ms" => 250,
      "queue_size" => 10,
      "keepalive_count" => 10,
      "lifetime_count" => 30
    }

    response = %{"version" => 1, "generation" => 7, "id" => "s1", "ok" => true}
    subscribe = &Frame.response(frame.(Map.put(response, "result", &1)), 7, "s1", "subscribe", nil)

    assert {:ok, ^result} = subscribe.(result)

    assert {:ok, nil} =
             Frame.response(frame.(Map.put(response, "result", nil)), 7, "s1", "unsubscribe", nil)

    for invalid <- [
          Map.put(result, "extra", 1),
          %{result | "subscription" => "s8"},
          %{result | "subscription_id" => 0},
          %{result | "item_status" => 0x8000_0000},
          %{result | "publishing_interval_ms" => 9},
          %{result | "sampling_interval_ms" => "250"},
          %{result | "queue_size" => 1001},
          %{result | "keepalive_count" => 11},
          %{result | "lifetime_count" => 10_001},
          :result
        ] do
      assert {:error, %Error{code: :invalid_native_frame}} = subscribe.(invalid)
    end
  end

  test "WOP-X04 close and finite native failures remain correlated to one request" do
    frame = fn attributes -> Jason.encode!(attributes) <> "\n" end
    base = %{"version" => 1, "generation" => 7, "id" => "close-1"}

    assert {:ok, nil} =
             Frame.response(
               frame.(Map.merge(base, %{"ok" => true, "result" => nil})),
               7,
               "close-1",
               "close",
               nil
             )

    failure = %{
      "code" => "remote_error",
      "phase" => "exchange",
      "effect" => "none",
      "status" => 0x8034_0000
    }

    assert {:native_error, %Error{code: :remote_error, details: %{status: 0x8034_0000}}} =
             Frame.response(
               frame.(Map.merge(base, %{"ok" => false, "error" => failure})),
               7,
               "close-1",
               "close",
               nil
             )

    for invalid <- [
          Map.merge(base, %{"ok" => true, "result" => %{}}),
          Map.merge(base, %{"ok" => false, "error" => Map.put(failure, "secret", "x")}),
          Map.merge(base, %{"ok" => true, "result" => nil, "extra" => true}),
          Map.merge(%{base | "generation" => 8}, %{"ok" => true, "result" => nil})
        ] do
      assert {:error, %Error{code: :invalid_native_frame}} =
               Frame.response(frame.(invalid), 7, "close-1", "close", nil)
    end
  end

  test "WOP-X04 Write returns only a non-Bad numeric status" do
    frame = fn result ->
      Jason.encode!(%{
        "version" => 1,
        "generation" => 7,
        "id" => "write-1",
        "ok" => true,
        "result" => result
      }) <> "\n"
    end

    for status <- [0, 0x4000_0000] do
      assert {:ok, %{"status" => ^status}} =
               Frame.response(frame.(%{"status" => status}), 7, "write-1", "write", nil)
    end

    for invalid <- [
          %{"status" => 0x8000_0000},
          %{"status" => -1},
          %{"status" => 0, "unexpected" => true},
          %{}
        ] do
      assert {:error, %Error{code: :invalid_native_frame}} =
               Frame.response(frame.(invalid), 7, "write-1", "write", nil)
    end
  end

  test "WOP-X04 Call retains ordered argument statuses and typed outputs" do
    result = %{
      "status" => 0,
      "input_argument_statuses" => [0, 0x8000_0000],
      "outputs" => [%{"type" => "Double", "array" => false, "value" => 4.5}]
    }

    frame = fn payload ->
      Jason.encode!(%{
        "version" => 1,
        "generation" => 7,
        "id" => "call-1",
        "ok" => true,
        "result" => payload
      }) <> "\n"
    end

    assert {:ok, ^result} = Frame.response(frame.(result), 7, "call-1", "call", nil)

    for invalid <- [
          %{result | "status" => 0x8000_0000},
          %{result | "outputs" => [%{"type" => "Double", "array" => false, "value" => "4.5"}]},
          %{result | "outputs" => List.duplicate(hd(result["outputs"]), 65)},
          %{result | "input_argument_statuses" => [-1]},
          %{result | "input_argument_statuses" => List.duplicate(0, 65)},
          Map.put(result, "extra", true)
        ] do
      assert {:error, %Error{code: :invalid_native_frame}} =
               Frame.response(frame.(invalid), 7, "call-1", "call", nil)
    end
  end

  test "WOP-N03 complete Browse pages retain exact references and reject malformed identities" do
    reference = %{
      "reference_type_id" => "ns=0;i=35",
      "is_forward" => true,
      "node_id" => %{
        "node_id" => "ns=2;s=value",
        "namespace_uri" => nil,
        "server_index" => 0
      },
      "browse_name" => %{"namespace" => 2, "name" => "Value"},
      "display_name" => %{"locale" => nil, "text" => "Value"},
      "node_class" => 2,
      "type_definition" => %{
        "node_id" => "ns=0;i=0",
        "namespace_uri" => nil,
        "server_index" => 0
      }
    }

    frame = fn result ->
      Jason.encode!(%{
        "version" => 1,
        "generation" => 7,
        "id" => "browse-1",
        "ok" => true,
        "result" => result
      }) <> "\n"
    end

    page = %{"status" => 0, "references" => [reference], "continuation" => nil}
    assert {:ok, ^page} = Frame.response(frame.(page), 7, "browse-1", "browse", nil)

    for operation <- ["browse", "browse_next"], token <- ["c1", "c18446744073709551615"] do
      continued = %{page | "continuation" => token}
      assert {:ok, ^continued} = Frame.response(frame.(continued), 7, "browse-1", operation, nil)
    end

    assert {:ok, nil} = Frame.response(frame.(nil), 7, "browse-1", "browse_release", nil)

    for invalid <- ["server-secret", "c0", "c01", "c-1", "c18446744073709551616", "c"],
        operation <- ["browse", "browse_next"] do
      assert {:error, %Error{code: :invalid_native_frame}} =
               Frame.response(
                 frame.(%{page | "continuation" => invalid}),
                 7,
                 "browse-1",
                 operation,
                 nil
               )
    end

    for invalid <- [
          %{page | "status" => 0x8000_0000},
          %{page | "references" => ["not a reference"]},
          %{page | "references" => [Map.put(reference, "extra", true)]},
          %{page | "references" => [Map.put(reference, "node_id", %{})]},
          %{page | "references" => [Map.put(reference, "display_name", %{})]},
          %{page | "references" => [put_in(reference, ["node_id", "server_index"], -1)]},
          %{page | "references" => [put_in(reference, ["browse_name", "namespace"], 65_536)]},
          %{page | "references" => [Map.put(reference, "node_class", 3)]}
        ] do
      assert {:error, %Error{code: :invalid_native_frame}} =
               Frame.response(frame.(invalid), 7, "browse-1", "browse", nil)
    end

    assert {:error, %Error{code: :invalid_native_frame}} =
             Frame.response(frame.(page), 7, "browse-1", "browse_release", nil)
  end
end
