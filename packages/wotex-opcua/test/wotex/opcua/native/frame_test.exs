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
end
