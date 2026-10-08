defmodule Wotex.Zigbee.ZCLConfigurationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{DataRequest, Error, Event, Reply, Routes}
  alias Wotex.Zigbee.Interview.Result
  alias Wotex.Zigbee.ZCL.Configuration

  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>
  @route 0x1234
  @profile Path.expand("../../support/profiles/zcl-configuration-r8.json", __DIR__)

  test "reviewed revision 8 response vectors execute against the bounded decoder" do
    profile = :json.decode(File.read!(@profile))
    assert profile["source"]["revision"] == "8"

    for vector <- profile["adoption"]["response_vectors"] do
      bytes = Base.decode16!(vector["hex"], case: :mixed)
      assert {:ok, response} = Configuration.decode_response(bytes)
      assert Atom.to_string(response.command) == vector["command"]
      assert Atom.to_string(response.aggregate) == vector["aggregate"]
      assert length(response.records) == vector["records"]
    end
  end

  test "write construction is inert and preserves exact type, null and manufacturer context" do
    before = Process.info(self(), :messages)
    records = [%{id: 1, type: 0x20, value: 42}, %{id: 2, type: 0x42, value: :null}]
    assert {:ok, request} = Configuration.write_attributes(records, 7, :client_to_server)
    assert request.payload == <<0, 7, 2, 1::little-16, 0x20, 42, 2::little-16, 0x42, 0xFF>>
    assert Configuration.valid_request?(request)
    assert Enum.all?(request.records, &(&1.full_range == false))
    assert Process.info(self(), :messages) == before

    assert {:ok, request} =
             Configuration.write_attributes(
               [%{id: 1, type: 0x20, value: 255, full_range: true}],
               8,
               :server_to_client,
               0x1234
             )

    assert request.payload == <<12, 0x34, 0x12, 8, 2, 1::little-16, 0x20, 255>>
  end

  test "write rejects malformed fields, duplicate IDs, unsupported values and complete-frame overflow" do
    for records <- [
          nil,
          [],
          [%{id: 1, type: 0x20}],
          [%{id: -1, type: 0x20, value: 1}],
          [%{id: 1, type: 0x20, value: 1, key: "credential-canary"}],
          [%{id: 1, type: 0x20, value: 255}],
          [%{id: 1, type: 0xF0, value: <<>>}],
          [%{id: 1, type: 0x20, value: 1}, %{id: 1, type: 0x20, value: 2}],
          Enum.map(1..33, &%{id: &1, type: 0x20, value: 1}),
          [
            %{id: 1, type: 0x42, value: :binary.copy("x", 64)},
            %{id: 2, type: 0x42, value: :binary.copy("x", 64)}
          ]
        ] do
      assert {:error, %Error{kind: :invalid_value} = error} =
               Configuration.write_attributes(records, 7, :client_to_server)

      refute inspect(error) =~ "credential-canary"
    end

    assert {:ok, _} =
             Configuration.write_attributes(
               Enum.map(1..31, &%{id: &1, type: 0x20, value: 1}),
               7,
               :client_to_server
             )

    assert {:error, _} =
             Configuration.write_attributes(
               Enum.map(1..32, &%{id: &1, type: 0x20, value: 1}),
               7,
               :client_to_server
             )

    for {seq, direction, manufacturer} <- [
          {256, :client_to_server, nil},
          {1, :invalid, nil},
          {1, :client_to_server, -1}
        ] do
      assert {:error, _} =
               Configuration.write_attributes(
                 [%{id: 1, type: 0x20, value: 1}],
                 seq,
                 direction,
                 manufacturer
               )
    end
  end

  test "copied requests and incomplete AF or route structs fail before observation" do
    {:ok, request} = write()

    for change <- [
          %{request | payload: <<0>>},
          %{request | command: :reset},
          Map.put(request, :key, "credential-canary"),
          request
          |> Map.delete(:records)
          |> Map.put(:key, "credential-canary")
        ] do
      refute Configuration.valid_request?(change)
    end

    refute Configuration.valid_request?(nil)
    {af, routes, event} = context(request, <<8, 7, 4, 0>>)

    bad_af =
      af
      |> Map.delete(:aps_ack)
      |> Map.put(:key, "credential-canary")

    bad_routes =
      routes
      |> Map.delete(:capacity)
      |> Map.put(:key, "credential-canary")

    refute DataRequest.valid?(bad_af)
    refute Routes.valid?(bad_routes)

    assert {:error, %Error{kind: :invalid_value}} =
             Configuration.observe(request, bad_af, routes, event, 11)

    assert {:error, %Error{kind: :invalid_value}} =
             Configuration.observe(request, af, bad_routes, event, 11)

    assert {:error, _} = Configuration.observe(nil, af, routes, event, 11)
    assert {:error, _} = Configuration.observe(request, af, routes, nil, 11)

    bad_event =
      event
      |> Map.delete(:owner_epoch)
      |> Map.put(:key, "credential-canary")

    assert {:error, _} = Configuration.observe(request, af, routes, bad_event, 11)
  end

  test "reporting sends analog change, omits it for discrete types and encodes receive timeout separately" do
    records = [
      send_record(1, 0x21, 2),
      %{id: 2, report_direction: :send, type: 0x10, min_interval_s: 0, max_interval_s: 60},
      %{id: 3, report_direction: :receive, timeout_s: 0}
    ]

    assert {:ok, request} = Configuration.configure_reporting(records, 9, :client_to_server)

    assert request.payload ==
             <<0, 9, 6, 0, 1::little-16, 0x21, 0::16, 60::little-16, 2::little-16, 0, 2::little-16,
               0x10, 0::16, 60::little-16, 1, 3::little-16, 0::16>>

    assert Configuration.valid_request?(request)

    assert {:ok, request} =
             Configuration.configure_reporting([send_record(1, 0x28, -2)], 7, :client_to_server)

    assert request.payload == <<0, 7, 6, 0, 1::little-16, 0x28, 0::16, 60::little-16, 0xFE>>
  end

  test "special reporting modes retain exact interval meaning and require analog zero on transmission" do
    for {minimum, maximum} <- [{0, 0xFFFF}, {0xFFFF, 0xFFFF}, {0xFFFF, 0}, {0, 0}] do
      record = %{send_record(1, 0x20, 0) | min_interval_s: minimum, max_interval_s: maximum}
      assert {:ok, request} = Configuration.configure_reporting([record], 7, :client_to_server)

      assert request.payload ==
               <<0, 7, 6, 0, 1::little-16, 0x20, minimum::little-16, maximum::little-16, 0>>

      if maximum == 0xFFFF or minimum == 0xFFFF do
        assert {:error, _} =
                 Configuration.configure_reporting([%{record | change: 1}], 7, :client_to_server)
      end
    end
  end

  test "reporting refuses reserved directions, inapplicable fields, duplicate keys and invalid intervals" do
    good = send_record(1, 0x20, 1)

    for record <- [
          nil,
          Map.delete(good, :change),
          %{good | change: :null},
          %{good | type: 0xF0},
          %{good | report_direction: :invalid},
          %{good | min_interval_s: 61},
          %{good | max_interval_s: -1},
          %{good | max_interval_s: 65_536},
          Map.put(good, :timeout_s, 10),
          %{good | type: 0x10},
          %{id: 1, report_direction: :receive, timeout_s: nil},
          %{id: 1, report_direction: :receive, timeout_s: 10, type: 0x20}
        ] do
      assert {:error, %Error{kind: :invalid_value}} =
               Configuration.configure_reporting([record], 7, :client_to_server)
    end

    assert {:error, _} = Configuration.configure_reporting([good, good], 7, :client_to_server)

    assert {:ok, _} =
             Configuration.configure_reporting(
               [good, %{id: 1, report_direction: :receive, timeout_s: 0xFFFF}],
               7,
               :client_to_server
             )
  end

  test "read reporting uses distinct direction-ID keys and preserves header context" do
    records = [%{id: 1, report_direction: :send}, %{id: 1, report_direction: :receive}]
    assert {:ok, request} = Configuration.read_reporting(records, 7, :server_to_client, 0x1234)
    assert request.payload == <<12, 0x34, 0x12, 7, 8, 0, 1::little-16, 1, 1::little-16>>

    assert {:error, _} =
             Configuration.read_reporting([hd(records), hd(records)], 7, :client_to_server)

    assert {:error, _} =
             Configuration.read_reporting(
               [%{id: 1, report_direction: :send, timeout_s: 1}],
               7,
               :client_to_server
             )

    assert {:error, _} =
             Configuration.read_reporting(
               [%{id: 1, report_direction: :invalid}],
               7,
               :client_to_server
             )
  end

  test "reporting frame budget includes every record and the manufacturer header" do
    records = Enum.map(1..25, &%{id: &1, report_direction: :receive, timeout_s: 10})
    assert {:ok, request} = Configuration.configure_reporting(records, 7, :client_to_server)
    assert byte_size(request.payload) == 128

    assert {:error, _} =
             Configuration.configure_reporting(records, 7, :client_to_server, 0x1234)

    assert {:error, _} =
             Configuration.configure_reporting(
               [%{id: 26, report_direction: :receive, timeout_s: 10} | records],
               7,
               :client_to_server
             )
  end

  test "response decoding preserves aggregate success versus ordered duplicate failures" do
    assert {:ok,
            %{
              command: :write_response,
              aggregate: :all_success,
              records: [],
              raw: <<8, 7, 4, 0>>
            }} =
             Configuration.decode_response(<<8, 7, 4, 0>>)

    assert {:ok, %{command: :configure_response, aggregate: :all_success}} =
             Configuration.decode_response(<<8, 7, 7, 0>>)

    assert {:ok, response} =
             Configuration.decode_response(
               <<12, 0x34, 0x12, 7, 4, 0x86, 1::little-16, 0x88, 1::little-16>>
             )

    assert response.manufacturer == 0x1234
    assert response.records == [%{id: 1, status: {:error, 0x86}}, %{id: 1, status: {:error, 0x88}}]

    assert {:ok, response} =
             Configuration.decode_response(
               <<8, 7, 7, 0x86, 0, 1::little-16, 0x88, 1, 2::little-16>>
             )

    assert response.records == [
             %{id: 1, report_direction: :send, status: {:error, 0x86}},
             %{id: 2, report_direction: :receive, status: {:error, 0x88}}
           ]
  end

  test "read configuration preserves send/receive fields, unconfigured change and per-record failure" do
    bytes =
      <<8, 7, 9, 0, 0, 1::little-16, 0x21, 0xFFFF::little-16, 0xFFFF::little-16, 0xFFFF::little-16,
        0, 0, 2::little-16, 0x10, 0::16, 60::little-16, 0, 1, 3::little-16, 0xFFFF::little-16, 0x86,
        0, 4::little-16>>

    assert {:ok, response} = Configuration.decode_response(bytes)
    assert [first, second, third, fourth] = response.records
    assert first.configuration.change == :null
    assert first.configuration.raw_change == <<0xFF, 0xFF>>
    assert second.configuration.change == nil
    assert third.configuration == %{timeout_s: 0xFFFF}
    assert fourth.status == {:error, 0x86}
    assert fourth.configuration == nil
  end

  test "unknown read configuration type preserves opaque remainder without guessing record boundaries" do
    tail = <<0xF0, 1, 2, 3, 4, 0, 1, 2, 0, 0x86, 0, 3, 0>>

    assert {:ok, %{records: [%{configuration: {:unsupported, 0xF0, ^tail}}]}} =
             Configuration.decode_response(<<8, 7, 9, 0, 0, 1::little-16, tail::binary>>)
  end

  test "malformed, mixed-success, truncated, reserved and over-limit response layouts fail" do
    for bytes <- [
          <<>>,
          <<8, 7, 4>>,
          <<8, 7, 4, 0, 1, 0>>,
          <<8, 7, 4, 0x86, 1>>,
          <<8, 7, 4, 0x86, 1, 0, 0>>,
          <<8, 7, 7, 0, 0, 1, 0>>,
          <<8, 7, 7, 0x86, 2, 1, 0>>,
          <<8, 7, 9>>,
          <<8, 7, 9, 0, 2, 1, 0>>,
          <<8, 7, 9, 0, 1, 1, 0, 1>>,
          <<8, 7, 9, 0, 0, 1, 0>>,
          <<8, 7, 9, 0, 0, 1, 0, 0xF0>>,
          <<8, 7, 9, 0, 0, 1, 0, 0xF0, 1, 2, 3>>,
          <<8, 7, 9, 0, 0, 1, 0, 0x21, 0, 0, 1, 0, 1>>,
          <<8, 7, 11, 2>>,
          <<8, 7, 11, 2, 0, 1>>,
          <<9, 7, 4, 0>>,
          <<0xE8, 7, 4, 0>>,
          <<12, 0x34>>,
          <<8, 7, 10, 1, 0, 0x20, 1>>,
          :binary.copy(<<0>>, 129),
          nil
        ] do
      assert {:error, %Error{kind: :invalid_frame}} = Configuration.decode_response(bytes)
    end

    assert {:error, _} = Configuration.decode_response(<<8, 7, 4, 0>>, 0)
    assert {:error, _} = Configuration.decode_response(<<8, 7, 4, 0>>, 33)
    assert {:error, _} = Configuration.decode_response(<<8, 7, 4, 0x86, 1, 0, 0x86, 2, 0>>, 1)
    assert {:error, _} = Configuration.decode_response(<<8, 7, 7, 0x86, 0, 1, 0, 0x86, 0, 2, 0>>, 1)
    assert {:error, _} = Configuration.decode_response(<<8, 7, 9, 0x86, 0, 1, 0, 0x86, 0, 2, 0>>, 1)
  end

  test "a source-correlated write distinguishes aggregate and failure-only record outcomes" do
    {:ok, request} = write()
    {af, routes, event} = context(request, <<8, 7, 4, 0>>)
    assert {:ok, result} = Configuration.observe(request, af, routes, event, 11)
    assert result.outcome == :reported_success

    assert Enum.map(result.records, &{&1.status, &1.basis}) == [
             {:success, :aggregate},
             {:success, :aggregate}
           ]

    assert result.event == event
    assert result.event.security_used == false
    assert result.correlation_id == "configuration"
    event = %{event | payload: <<8, 7, 4, 0x86, 1::little-16>>}
    assert {:ok, result} = Configuration.observe(request, af, routes, event, 11)
    assert result.outcome == :partial

    assert Enum.map(result.records, &{&1.status, &1.basis}) == [
             {{:error, 0x86}, :record},
             {:success, :omitted_failure}
           ]
  end

  test "duplicate or unexpected failures never infer success for an omitted request key" do
    {:ok, request} = write()

    for {bytes, issue} <- [
          {<<8, 7, 4, 0x86, 1::little-16, 0x88, 1::little-16>>, :duplicate_record},
          {<<8, 7, 4, 0x86, 3::little-16>>, :unexpected_record}
        ] do
      {af, routes, event} = context(request, bytes)
      assert {:ok, result} = Configuration.observe(request, af, routes, event, 11)
      assert issue in result.issues
      assert List.last(result.records).status == :unconfirmed
      assert result.outcome == :unconfirmed
      assert result.response.raw == bytes
    end
  end

  test "configuration outcomes key the reporting direction separately from the attribute ID" do
    {:ok, request} =
      Configuration.configure_reporting(
        [send_record(1, 0x20, 1), %{id: 1, report_direction: :receive, timeout_s: 10}],
        7,
        :client_to_server
      )

    {af, routes, event} = context(request, <<8, 7, 7, 0x86, 1, 1::little-16>>)
    assert {:ok, result} = Configuration.observe(request, af, routes, event, 11)
    assert Enum.map(result.records, & &1.status) == [:success, {:error, 0x86}]
  end

  test "read-configuration omissions and unsupported types remain unconfirmed without a retry" do
    {:ok, request} =
      Configuration.read_reporting(
        [%{id: 1, report_direction: :receive}, %{id: 2, report_direction: :send}],
        7,
        :client_to_server
      )

    {af, routes, event} = context(request, <<8, 7, 9, 0, 1, 1::little-16, 0::16>>)
    assert {:ok, result} = Configuration.observe(request, af, routes, event, 11)
    assert result.outcome == :partial
    assert result.issues == [:missing_record]
    assert Enum.map(result.records, & &1.status) == [:success, :unconfirmed]
    event = %{event | payload: <<8, 7, 9, 0, 0, 2::little-16, 0xF0, 1, 2, 3, 4>>}
    assert {:ok, result} = Configuration.observe(request, af, routes, event, 11)
    assert result.outcome == :unconfirmed
    assert result.issues == [:missing_record, :unsupported_type]
  end

  test "Default Responses retain status and never claim per-record write success" do
    {:ok, request} = write()

    for status <- [0, 0x86] do
      {af, routes, event} = context(request, <<8, 7, 11, 2, status>>)
      assert {:ok, result} = Configuration.observe(request, af, routes, event, 11)
      assert result.outcome == :unconfirmed
      assert Enum.all?(result.records, &(&1.status == :unconfirmed))
      assert result.response.status == if(status == 0, do: :success, else: {:error, status})
    end
  end

  test "wrong source, envelope or request bytes cannot establish outcomes under current custody" do
    {:ok, request} = write()
    {af, routes, good} = context(request, <<8, 7, 4, 0>>)

    for event <- [
          %{good | kind: :unknown},
          %{good | source_address: 0x5678},
          %{good | source_endpoint: 2},
          %{good | endpoint: 3},
          %{good | cluster: 7},
          %{good | owner_epoch: make_ref()},
          %{good | owner_sequence: 0},
          %{good | payload: <<0, 7, 4, 0>>},
          %{good | payload: <<8, 8, 4, 0>>},
          %{good | payload: <<12, 1::little-16, 7, 4, 0>>},
          %{good | payload: <<8, 7, 7, 0>>},
          %{good | payload: <<8, 7, 11, 6, 0>>},
          %{good | payload: <<0>>}
        ] do
      assert {:error, %Error{}} = Configuration.observe(request, af, routes, event, 11)
    end

    assert {:error, _} = Configuration.observe(request, %{af | data: <<0>>}, routes, good, 11)

    assert {:error, _} =
             Configuration.observe(
               request,
               %{af | peer_ieee: <<1, 2, 3, 4, 5, 6, 7, 8>>},
               routes,
               good,
               11
             )

    assert {:error, _} = Configuration.observe(request, af, routes, good, 1_010)
  end

  defp write,
    do:
      Configuration.write_attributes(
        [%{id: 1, type: 0x20, value: 42}, %{id: 2, type: 0x10, value: true}],
        7,
        :client_to_server
      )

  defp send_record(id, type, change),
    do: %{
      id: id,
      type: type,
      change: change,
      report_direction: :send,
      min_interval_s: 0,
      max_interval_s: 60
    }

  defp context(request, payload) do
    epoch = make_ref()

    identity = %Event{
      kind: :zdo_ieee_address,
      subsystem: 5,
      id: 0x81,
      payload: <<>>,
      owner_epoch: epoch,
      owner_sequence: 1,
      received_at_ms: 10,
      status: 0,
      zdo: %{status: 0, peer_ieee: @ieee, network_address: @route}
    }

    proof = %Result{
      peer_ieee: @ieee,
      route_address: @route,
      owner_epoch: epoch,
      identity_matches: true,
      outcome: :complete,
      steps: [
        %{
          stage: :identity,
          issues: [],
          response: identity,
          admission: %Reply{subsystem: 5, id: 1, status: 0, payload: <<0>>}
        }
      ]
    }

    {:ok, routes} = Routes.new(epoch)
    {:ok, routes} = Routes.adopt(routes, proof, 10, 1_000)

    {:ok, af} =
      DataRequest.new(
        peer_ieee: @ieee,
        route_address: @route,
        destination_endpoint: 1,
        source_endpoint: 2,
        cluster: 6,
        transaction: 7,
        correlation_id: "configuration",
        data: request.payload
      )

    event = %Event{
      kind: :af_incoming,
      subsystem: 4,
      id: 0x81,
      payload: payload,
      source_address: @route,
      source_endpoint: 1,
      endpoint: 2,
      cluster: 6,
      owner_epoch: epoch,
      owner_sequence: 2,
      received_at_ms: 11,
      security_used: false
    }

    {af, routes, event}
  end
end
