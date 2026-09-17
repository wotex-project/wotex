defmodule Wotex.Lab.OtlpEncoderTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias Wotex.Lab.Otlp.{Encoder, Events}
  alias Wotex.Lab.Test.OtlpDecoder

  @trace_id :binary.copy(<<0xAB>>, 16)
  @span_id :binary.copy(<<0xCD>>, 8)
  @resource [{"service.name", "wotex_lab"}, {"service.instance.id", "lab-a"}]

  test "traces use the pinned OTLP field numbers and a closed span shape" do
    assert Encoder.proto_revision() == "v1.5.0"

    span = %{
      trace_id: @trace_id,
      span_id: @span_id,
      name: "nx.encode",
      start_ns: 1_700_000_000_000_000_000,
      end_ns: 1_700_000_000_001_000_000,
      attributes: [{"wotex.lab.component", "nx"}, {"wotex.lab.outcome_class", "ok"}],
      status: :ok
    }

    assert {:ok, body} = Encoder.encode_traces(@resource, [span, %{span | status: :error}])
    decoded = OtlpDecoder.traces(body)
    assert decoded.resource == @resource
    assert decoded.scope == %{name: "wotex_lab", version: "0.1.0"}

    assert [first, second] = decoded.records

    assert first == %{
             trace_id: @trace_id,
             span_id: @span_id,
             name: "nx.encode",
             kind: 1,
             start_ns: span.start_ns,
             end_ns: span.end_ns,
             attributes: span.attributes,
             status: [1],
             unknown: []
           }

    assert second.status == [2]
  end

  test "logs carry time, severity, body, attributes and event name only" do
    log = %{
      time_ns: 1_700_000_000_000_000_000,
      observed_ns: 1_700_000_000_000_000_500,
      severity: :error,
      body: "wotex.lab span exception",
      event_name: "wotex.lab.span.exception",
      attributes: [{"wotex.lab.kind", "error"}]
    }

    assert {:ok, body} =
             Encoder.encode_logs(@resource, [
               log,
               %{log | severity: :warn},
               %{log | severity: :info}
             ])

    assert [error, warn, info] = OtlpDecoder.logs(body).records

    assert error == %{
             time_ns: log.time_ns,
             observed_ns: log.observed_ns,
             severity_number: 17,
             severity_text: "ERROR",
             body: log.body,
             event_name: log.event_name,
             attributes: log.attributes,
             unknown: []
           }

    assert {warn.severity_number, warn.severity_text} == {13, "WARN"}
    assert {info.severity_number, info.severity_text} == {9, "INFO"}
  end

  test "records outside the closed shape are refused instead of truncated" do
    span = %{
      trace_id: @trace_id,
      span_id: @span_id,
      name: "nx.encode",
      start_ns: 10,
      end_ns: 20,
      attributes: [],
      status: :ok
    }

    for invalid <- [
          %{span | trace_id: <<1, 2>>},
          %{span | span_id: @trace_id},
          %{span | end_ns: 9},
          %{span | start_ns: -1},
          %{span | status: :unset},
          %{span | name: :encode},
          %{span | name: String.duplicate("n", 257)},
          %{span | name: <<255>>},
          %{span | attributes: [{"key", 1}]},
          %{span | attributes: [{"", "value"}]},
          %{span | attributes: [{String.duplicate("k", 129), "value"}]},
          %{span | attributes: for(i <- 1..33, do: {"k#{i}", "v"})},
          %{span | attributes: :none},
          Map.put(span, :parent_span_id, @span_id),
          :span
        ] do
      assert {:error, %Error{code: :invalid_otlp_record}} =
               Encoder.encode_traces(@resource, [invalid])
    end

    assert {:error, %Error{code: :invalid_otlp_record}} = Encoder.encode_traces(@resource, [])
    assert {:error, %Error{code: :invalid_otlp_record}} = Encoder.encode_traces([{"a", 1}], [span])

    log = %{
      time_ns: 1,
      observed_ns: 1,
      severity: :error,
      body: "b",
      event_name: "e",
      attributes: []
    }

    for invalid <- [
          %{log | severity: :fatal},
          %{log | body: <<255>>},
          %{log | time_ns: -1},
          Map.delete(log, :event_name)
        ] do
      assert {:error, %Error{code: :invalid_otlp_record}} =
               Encoder.encode_logs(@resource, [invalid])
    end

    assert {:error, %Error{code: :invalid_otlp_record}} = Encoder.encode_logs(@resource, nil)
  end

  test "partial success responses are decoded and malformed responses refused" do
    assert Encoder.partial_success(:traces, "") == {:ok, %{rejected: 0, message: ""}}

    partial = IO.iodata_to_binary([<<0x08, 3>>, <<0x12, 3>>, "bad"])
    response = <<0x0A, byte_size(partial)>> <> partial
    assert Encoder.partial_success(:logs, response) == {:ok, %{rejected: 3, message: "bad"}}
    assert Encoder.partial_success(:traces, <<0x0A, 0>>) == {:ok, %{rejected: 0, message: ""}}

    assert Encoder.partial_success(:traces, <<0x18, 1>> <> response) ==
             {:ok, %{rejected: 3, message: "bad"}}

    negative = <<0x08, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01>>

    for malformed <- [
          <<0x0A, 5, 0x08>>,
          <<0x0A, byte_size(negative)>> <> negative,
          <<0x0A, 3, 0x12, 1, 255>>,
          <<0x0F>>,
          <<0x00, 0x01>>,
          <<0x80>>
        ] do
      assert {:error, %Error{code: :malformed_otlp_response}} =
               Encoder.partial_success(:traces, malformed)
    end

    assert {:error, %Error{code: :malformed_otlp_response}} = Encoder.partial_success(:metrics, "")
  end

  test "telemetry events project only closed vocabularies" do
    context = %{end_ns: 5_000_000_000, trace_id: @trace_id, span_id: @span_id}
    duration = System.convert_time_unit(2, :millisecond, :native)

    metadata = %{
      outcome: :ok,
      profile: :thermal,
      thing_ref: "thing:secret",
      scenario_id: "private-scenario",
      attempt: 3
    }

    assert {:ok, span, nil} =
             Events.project(
               [:wotex, :lab, :nx, :encode, :stop],
               %{duration: duration},
               metadata,
               context
             )

    assert span.name == "nx.encode" and span.status == :ok
    assert span.end_ns - span.start_ns == 2_000_000

    assert span.attributes == [
             {"wotex.lab.component", "nx"},
             {"wotex.lab.operation", "encode"},
             {"wotex.lab.outcome_class", "ok"},
             {"wotex.lab.profile", "thermal"}
           ]

    refute inspect(span) =~ "secret" or inspect(span) =~ "private-scenario"

    assert {:ok, failed, nil} =
             Events.project(
               [:wotex, :lab, :http, :request, :stop],
               %{duration: 0},
               %{outcome: :econnrefused, profile: "caller"},
               context
             )

    assert failed.status == :error
    assert {"wotex.lab.outcome_class", "error"} in failed.attributes
    assert {"wotex.lab.profile", "other"} in failed.attributes

    assert {:ok, exception, log} =
             Events.project(
               [:wotex, :lab, :policy, :dispatch, :exception],
               %{duration: duration * 10_000_000},
               %{kind: :throw},
               context
             )

    assert exception.status == :error and exception.start_ns == 0
    assert {"wotex.lab.kind", "throw"} in exception.attributes
    assert log.severity == :error and log.body == "wotex.lab span exception"
    assert log.attributes == exception.attributes

    for {event, measurements} <- [
          {[:wotex, :lab, :nx, :encode, :start], %{duration: 1}},
          {[:wotex, :lab, :caller, :encode, :stop], %{duration: 1}},
          {[:wotex, :lab, :nx, :encode, :stop], %{duration: -1}},
          {[:wotex, :lab, :nx, :encode, :stop], %{}},
          {[:other, :event], %{duration: 1}}
        ] do
      assert Events.project(event, measurements, %{}, context) == :ignore
    end

    assert length(Events.events()) ==
             length(Wotex.Lab.Telemetry.components()) * length(Wotex.Lab.Telemetry.operations()) * 2
  end
end
