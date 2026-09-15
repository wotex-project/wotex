defmodule Wotex.CoAP.NativeReportTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.CoAP.{Error, Message, Native.Body, Native.Report}

  test "WCO-N03 decodes a complete correlated report and exact option metadata" do
    message =
      message("value", observe: 16_777_215, etag: <<0, 255>>, content_format: 50, max_age: 0)

    metadata = %{
      "code" => 69,
      "observe" => 16_777_215,
      "etag" => bytes(<<0, 255>>),
      "content_format" => 50,
      "max_age" => 0
    }

    assert {:ok,
            %{
              message: %Message{payload: "value", options: options},
              metadata: %{
                code: 69,
                observe: 16_777_215,
                etag: <<0, 255>>,
                content_format: 50,
                max_age: 0
              },
              report_seq: 1
            }} = Report.decode(report(message, metadata), "s1", 17)

    assert Enum.map(options, &elem(&1, 0)) == [6, 4, 12, 14]
  end

  test "WCO-N03 absent ETag, Content-Format and Max-Age retain exact defaults" do
    message = message("", observe: 0)
    metadata = metadata(0)

    assert {:ok,
            %{
              message: %Message{payload: ""},
              metadata: %{etag: nil, content_format: nil, max_age: 60, observe: 0}
            }} = Report.decode(report(message, metadata), "s1", 17)
  end

  test "WCO-N03 report metadata must equal the validated Message options" do
    message = message("value", observe: 7, etag: "tag", content_format: 50, max_age: 30)

    baseline = %{
      "code" => 69,
      "observe" => 7,
      "etag" => bytes("tag"),
      "content_format" => 50,
      "max_age" => 30
    }

    invalid = [
      Map.put(baseline, "code", 68),
      Map.put(baseline, "observe", 6),
      Map.put(baseline, "etag", bytes("other")),
      Map.put(baseline, "content_format", 0),
      Map.put(baseline, "max_age", 31),
      Map.put(baseline, "extra", nil),
      Map.delete(baseline, "etag")
    ]

    for metadata <- invalid,
        do: assert_protocol(Report.decode(report(message, metadata), "s1", 17))
  end

  test "WCO-N03 metadata scalar and ETag boundaries fail closed" do
    message = message("", observe: 0)
    baseline = metadata(0)

    invalid = [
      Map.put(baseline, "code", 63),
      Map.put(baseline, "code", 95),
      Map.put(baseline, "code", 69.0),
      Map.put(baseline, "observe", -1),
      Map.put(baseline, "observe", 16_777_216),
      Map.put(baseline, "observe", 0.0),
      Map.put(baseline, "etag", bytes("")),
      Map.put(baseline, "etag", bytes("123456789")),
      Map.put(baseline, "etag", %{"type" => "bytes", "base64" => "Zh=="}),
      Map.put(baseline, "content_format", -1),
      Map.put(baseline, "content_format", 65_536),
      Map.put(baseline, "content_format", 0.0),
      Map.put(baseline, "max_age", -1),
      Map.put(baseline, "max_age", 4_294_967_296),
      Map.put(baseline, "max_age", 60.0)
    ]

    for metadata <- invalid,
        do: assert_protocol(Report.decode(report(message, metadata), "s1", 17))
  end

  test "WCO-N03 report Messages require one Observe option and one ETag" do
    baseline = message("", observe: 0)

    invalid = [
      Map.put(baseline, "options", []),
      Map.update!(baseline, "options", &[option(6, <<1>>) | &1]),
      Map.update!(baseline, "options", &[option(4, "a"), option(4, "b") | &1]),
      Map.put(baseline, "code", 63),
      Map.put(baseline, "code", 95)
    ]

    for message <- invalid,
        do: assert_protocol(Report.decode(report(message, metadata(0)), "s1", 17))
  end

  test "WCO-N-F15 distinguishes the inline threshold from a completed streamed body" do
    inline = :binary.copy("A", 32_768)
    streamed = inline <> "A"

    assert {:ok, %{message: %Message{payload: ^inline}}} =
             Report.decode(report(message(inline, observe: 1), metadata(1)), "s1", 17)

    assert_protocol(Report.decode(report(message(streamed, observe: 1), metadata(1)), "s1", 17))

    streamed_message =
      message("", observe: 1)
      |> Map.delete("payload")
      |> Map.put("body_id", "b1")

    assert {:ok, %{message: %Message{payload: ^streamed}}} =
             Report.decode(
               report(streamed_message, metadata(1)),
               "s1",
               17,
               %{"b1" => streamed}
             )

    assert_protocol(Report.decode(report(streamed_message, metadata(1)), "s1", 17))
  end

  test "WCO-N03 reports bind exact subscription, generation, sequence and fields" do
    baseline = report(message("", observe: 0), metadata(0))

    for {frame, id, generation} <- [
          {baseline, "other", 17},
          {baseline, "s1", 18},
          {Map.put(baseline, "subscription_id", ""), "", 17},
          {Map.put(baseline, "subscription_id", "line\nbreak"), "line\nbreak", 17},
          {Map.put(baseline, "generation", 0), "s1", 0},
          {Map.put(baseline, "generation", 0x10000000000000000), "s1", 0x10000000000000000},
          {Map.put(baseline, "report_seq", 0), "s1", 17},
          {Map.put(baseline, "report_seq", 0x10000000000000000), "s1", 17},
          {Map.put(baseline, "report_seq", 1.0), "s1", 17},
          {Map.put(baseline, "event", "value"), "s1", 17},
          {Map.put(baseline, "extra", nil), "s1", 17},
          {Map.delete(baseline, "metadata"), "s1", 17}
        ] do
      assert_protocol(Report.decode(frame, id, generation))
    end
  end

  test "WCO-N03 projects exact unary body envelopes before assembly" do
    body = "ABC"
    bare = [begin_event("b1", body), chunk_event("b1", 0, body), end_event("b1")]

    frames =
      Enum.map(bare, fn event -> Map.merge(event, %{"version" => 1, "id" => "r1"}) end)

    final =
      Enum.reduce(Enum.zip(frames, bare), Body.new(), fn {frame, expected}, state ->
        assert {:ok, ^expected} = Report.body_event(frame, "r1")
        assert {:ok, next} = Body.push(state, expected)
        next
      end)

    assert {:ok, ^body, %Body{phase: :idle}} = Body.take(final, "b1")

    for invalid <- [
          Map.put(hd(frames), "id", "other"),
          Map.put(hd(frames), "generation", 17),
          Map.put(hd(frames), "extra", nil),
          Map.delete(hd(frames), "version")
        ] do
      assert_protocol(Report.body_event(invalid, "r1"))
    end
  end

  test "WCO-N03 projects report body envelopes with exact generation and credit sequence" do
    bare = begin_event("b1", "ABC")

    frame =
      Map.merge(bare, %{
        "version" => 1,
        "id" => "s1",
        "generation" => 17,
        "report_seq" => 1
      })

    assert {:ok, 1, ^bare} = Report.body_event(frame, "s1", 17)

    for invalid <- [
          Map.put(frame, "id", "other"),
          Map.put(frame, "generation", 18),
          Map.put(frame, "report_seq", 0),
          Map.put(frame, "report_seq", 0x10000000000000000),
          Map.put(frame, "report_seq", 1.0),
          Map.put(frame, "extra", nil),
          Map.delete(frame, "sha256")
        ] do
      assert_protocol(Report.body_event(invalid, "s1", 17))
    end

    for event <- [chunk_event("b1", 0, "ABC"), end_event("b1")] do
      correlated =
        Map.merge(event, %{
          "version" => 1,
          "id" => "s1",
          "generation" => 17,
          "report_seq" => 2
        })

      assert {:ok, 2, ^event} = Report.body_event(correlated, "s1", 17)
    end
  end

  test "WCO-N03 terminal errors use the reserved exact control envelope" do
    terminal = %{
      "version" => 1,
      "subscription_id" => "s1",
      "generation" => 17,
      "event" => "error",
      "value" => %{"code" => "native_unavailable", "status" => -1},
      "metadata" => %{}
    }

    assert {:error,
            %Error{
              code: :native_unavailable,
              class: :unavailable,
              details: %{status: -1}
            }} = Report.terminal(terminal, "s1", 17)

    for {frame, id, generation} <- [
          {terminal, "other", 17},
          {terminal, "s1", 18},
          {Map.put(terminal, "generation", 0), "s1", 0},
          {Map.put(terminal, "event", "report"), "s1", 17},
          {Map.put(terminal, "report_seq", 1), "s1", 17},
          {Map.put(terminal, "metadata", %{"extra" => nil}), "s1", 17},
          {put_in(terminal, ["value", "code"], "untrusted-secret-canary"), "s1", 17}
        ] do
      assert_protocol(Report.terminal(frame, id, generation))
    end
  end

  defp report(message, metadata) do
    %{
      "version" => 1,
      "subscription_id" => "s1",
      "generation" => 17,
      "report_seq" => 1,
      "event" => "report",
      "value" => message,
      "metadata" => metadata
    }
  end

  defp message(payload, options) do
    values =
      [option(6, uint(Keyword.fetch!(options, :observe)))]
      |> optional_option(4, Keyword.get(options, :etag))
      |> optional_option(12, Keyword.get(options, :content_format), &uint/1)
      |> optional_option(14, Keyword.get(options, :max_age), &uint/1)
      |> Enum.reverse()

    %{
      "type" => "ack",
      "code" => 69,
      "message_id" => 1,
      "token" => bytes(<<1>>),
      "options" => values,
      "payload" => bytes(payload)
    }
  end

  defp optional_option(options, _, nil), do: options
  defp optional_option(options, number, value), do: [option(number, value) | options]
  defp optional_option(options, _, nil, _), do: options

  defp optional_option(options, number, value, encoder),
    do: [option(number, encoder.(value)) | options]

  defp metadata(observe) do
    %{
      "code" => 69,
      "observe" => observe,
      "etag" => nil,
      "content_format" => nil,
      "max_age" => 60
    }
  end

  defp begin_event(id, body) do
    %{
      "event" => "body_begin",
      "body_id" => id,
      "length" => byte_size(body),
      "sha256" => Base.encode16(:crypto.hash(:sha256, body), case: :lower)
    }
  end

  defp chunk_event(id, offset, body) do
    %{"event" => "body_chunk", "body_id" => id, "offset" => offset, "data" => bytes(body)}
  end

  defp end_event(id), do: %{"event" => "body_end", "body_id" => id}
  defp option(number, value), do: %{"number" => number, "value" => bytes(value)}
  defp bytes(value), do: %{"type" => "bytes", "base64" => Base.encode64(value)}
  defp uint(0), do: <<>>
  defp uint(value), do: :binary.encode_unsigned(value)

  defp assert_protocol(result) do
    assert {:error,
            %Error{
              code: :native_protocol_error,
              class: :protocol,
              effect: :none,
              details: %{}
            }} = result
  end
end
