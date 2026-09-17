defmodule Wotex.BACnet.ServiceBoundaryTest do
  @moduledoc false

  use ExUnit.Case, async: false
  use ExUnitProperties
  import Bitwise
  alias BACnet.Protocol.{APDU, IncompleteAPDU, ObjectIdentifier, Services}
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Stack.SegmentsStore
  alias Wotex.BACnet.{Address, BACstack, IPv4, Value, ValueBoundary}

  @moduletag :capture_log
  @corpus Path.expand("../../../priv/fixtures/contract-v1.json", __DIR__)
  @external_resource @corpus
  @cases Jason.decode!(File.read!(@corpus))["cases"]
  @corpus_sha256 Base.encode16(:crypto.hash(:sha256, File.read!(@corpus)), case: :lower)
  @message %{type: :read_property, object_type: 1, instance: 0, property: 85}

  test "WBA-S01 WBA-V01 WBA-N02 binds WBA-F01/F02/F03/F04 to real public boundaries" do
    assert byte_size(@corpus_sha256) == 64

    for id <- ["WBA-F01", "WBA-F02", "WBA-F03", "WBA-F04"] do
      fixture = Enum.find(@cases, &(&1["id"] == id))
      result = execute_fixture(fixture["operation"], fixture["input"])
      assert normalize(result) == fixture["expectation"]["value"], id
    end
  end

  test "WBA-S01 WBA-V01 forged encoders and unsupported values never run or reach the port" do
    parent = self()

    for value <- [
          %Encoding{
            encoding: :primitive,
            type: :real,
            value: 1.0,
            extras: [
              encoder: fn v ->
                send(parent, :encoder_ran)
                v
              end
            ]
          },
          %Encoding{encoding: :primitive, type: :signed_integer, value: 1 <<< 64, extras: []},
          %Encoding{encoding: :primitive, type: :real, value: 1.0e100, extras: []},
          %Encoding{encoding: :tagged, type: nil, value: <<1>>, extras: [tag_number: 256]},
          1.5,
          [Encoding.create!({:null, nil}) | :improper]
        ] do
      assert {:error, _} = Value.validate_native(value)

      assert {:error, %{effect: :none}} =
               Address.validate_message(Map.merge(@message, %{type: :write_property, value: value}))
    end

    refute_receive :encoder_ran

    assert {:error, %{code: :invalid_priority}} =
             Address.validate_message(Map.put(@message, :priority, 8))

    assert {:error, %{code: :invalid_message}} = Address.validate_message(%{})
  end

  property "WBA-S01 WBA-V01 full signed and unsigned 64-bit scalar ranges retain native tag" do
    check all(
            signed <- integer(-9_223_372_036_854_775_808..9_223_372_036_854_775_807),
            unsigned <- integer(0..18_446_744_073_709_551_615)
          ) do
      for {name, type, value} <- [
            {"Signed", :signed_integer, signed},
            {"Unsigned", :unsigned_integer, unsigned}
          ] do
        assert {:ok, encoded} = Value.encode(value, %{"@type" => "bacv:" <> name})
        assert :ok = Value.validate_native(encoded)
        assert encoded.type == type
        assert Value.result(encoded) == {value, %{bacnet_type: type}}
      end
    end
  end

  test "WBA-S01 WBA-V01 aggregate bytes elements depth and executable terms are bounded" do
    assert :ok = ValueBoundary.validate(List.duplicate(<<0>>, 1024))

    for value <- [
          List.duplicate(0, 1025),
          [String.duplicate("a", 32_769), String.duplicate("b", 32_768)],
          Enum.reduce(1..9, 0, fn _, acc -> [acc] end),
          self(),
          make_ref(),
          fn -> :ok end
        ] do
      assert {:error, %{code: :value_limit}} = ValueBoundary.validate(value)
    end

    opaque = Encoding.create!({:tagged, {7, <<0, 255>>, 2}})
    assert :ok = Value.validate_native(opaque)
    assert {^opaque, %{}} = Value.result(opaque)
    constructed = Encoding.create!({:constructed, {4, [{:unsigned_integer, 1}], 0}})
    assert :ok = Value.validate_native(constructed)
    assert :ok = ValueBoundary.validate(%{count: 1})
    assert {:error, _} = ValueBoundary.validate(List.duplicate(List.duplicate(0, 1024), 4))
    assert :ok = Value.validate_native([opaque, constructed])
    assert {:error, _} = Value.validate_native([opaque, 1])

    assert {:error, _} =
             Value.validate_native(%Encoding{
               encoding: :constructed,
               type: nil,
               value: 1,
               extras: [tag_number: 4]
             })
  end

  test "WBA-S02 WBA-V02 rejects trailing malformed and wrong service ACK fields" do
    {:ok, address} = Address.new(@message)
    apdu = read_ack(Encoding.create!({:real, 25.5}))

    for payload <- [
          Enum.concat(apdu.payload, [{:null, nil}]),
          [],
          [{:constructed, {3, :invalid, 0}}],
          List.duplicate({:null, nil}, 1025)
        ] do
      assert {:error, _} =
               BACstack.response({:ok, %{apdu | payload: payload}}, address, :read_property)
    end

    assert {:error, _} =
             BACstack.response({:ok, %{apdu | service: :write_property}}, address, :read_property)

    raw = %{
      apdu
      | payload: [
          {:tagged, {0, <<512::10, 0::22>>, 4}},
          {:tagged, {1, <<2, 0>>, 2}},
          {:tagged, {2, <<0>>, 1}},
          {:constructed, {3, {:enumerated, 65_535}, 0}}
        ]
    }

    {:ok, proprietary} =
      Address.new(%{object_type: 512, instance: 0, property: 512, array_index: 0})

    assert {:ok, %{type: :enumerated, value: 65_535}} =
             BACstack.response({:ok, raw}, proprietary, :read_property)

    array = read_ack([Encoding.create!({:unsigned_integer, 0}), Encoding.create!({:null, nil})])

    assert {:ok, [%{value: 0}, %{value: nil}]} =
             BACstack.response({:ok, array}, address, :read_property)

    invalid = %{
      apdu
      | payload: Enum.concat(Enum.take(apdu.payload, 2), [{:constructed, {3, [:invalid], 0}}])
    }

    assert {:error, _} = BACstack.response({:ok, invalid}, address, :read_property)
  end

  test "WBA-S02 WBA-V01 explicit peer limits and proprietary selectors reach the SDK unchanged" do
    parent = self()

    client =
      spawn(fn ->
        receive do
          {:"$gen_call", from, {:send, _, apdu, opts}} ->
            send(parent, {:request, apdu, opts})
            GenServer.reply(from, {:ok, %APDU.SimpleACK{invoke_id: 0, service: :write_property}})
            receive do: (:stop -> :ok)
        end
      end)

    on_exit(fn -> send(client, :stop) end)
    peer = %{max_apdu: 1024, max_segments: 16, segmentation: :segmented_receive}

    assert {:ok, handle} =
             BACstack.connect(
               stack_client: client,
               destination: {{127, 0, 0, 1}, 47_808},
               writes: true,
               peer_receive: peer
             )

    message = %{
      type: :write_property,
      object_type: 512,
      instance: 0,
      property: 512,
      array_index: 0,
      value: [Encoding.create!({:null, nil})]
    }

    assert {:ok, :written} = BACstack.request(handle, message, 1000)
    assert_receive {:request, apdu, opts}
    assert apdu.max_segments == 32
    assert apdu.max_apdu == 1476

    assert apdu.parameters == [
             {:tagged, {0, <<512::10, 0::22>>, 4}},
             {:tagged, {1, <<2, 0>>, 2}},
             {:tagged, {2, <<0>>, 1}},
             {:constructed, {3, [{:null, nil}], 0}}
           ]

    assert opts == [
             max_apdu_length: 1024,
             max_segments: 16,
             segmentation_supported: :segmented_receive
           ]

    assert {:error, %{code: :invalid_options}} =
             BACstack.request(%{handle | peer_receive: %{}}, message, 1000)

    assert {:error, %{code: :invalid_request}} = BACstack.request(%{}, message, 0)

    assert {:error, _} =
             BACstack.connect(
               stack_client: self(),
               destination: {{127, 0, 0, 1}, 47_808},
               peer_receive: %{}
             )
  end

  test "WBA-S02 WBA-V03 remote errors retain numeric status and subscription ACKs require service" do
    {:ok, address} = Address.new(@message)

    assert {:error, %{code: :remote_error, details: %{class: 2, code: 32}}} =
             BACstack.response(
               {:ok,
                %APDU.Error{
                  invoke_id: 1,
                  service: :read_property,
                  class: :property,
                  code: :unknown_property,
                  payload: []
                }},
               address,
               :read_property
             )

    for {module, code, reason} <- [
          {APDU.Abort, :remote_abort, 65_535},
          {APDU.Reject, :remote_reject, 65_534}
        ] do
      apdu = struct(module, invoke_id: 1, reason: reason)

      assert {:error, %{code: ^code, details: %{reason: ^reason}}} =
               BACstack.response({:ok, apdu}, address, :read_property)
    end

    assert {:error, %{code: :invalid_response}} =
             BACstack.response(
               {:ok, %APDU.Abort{invoke_id: 1, reason: :invalid_atom, sent_by_server: true}},
               address,
               :read_property
             )

    for service <- [:subscribe_cov, :subscribe_cov_property] do
      assert {:ok, :subscribed} =
               BACstack.response(
                 {:ok, %APDU.SimpleACK{invoke_id: 1, service: service}},
                 address,
                 service
               )

      assert {:error, _} =
               BACstack.response(
                 {:ok, %APDU.SimpleACK{invoke_id: 1, service: :write_property}},
                 address,
                 service
               )
    end
  end

  test "WBA-S02 WBA-V04 actual owned store enforces32 segments and ingress1476 bytes" do
    {:ok, handle} =
      IPv4.connect(
        local_ip: :none,
        local_port: 55_812,
        destination: {{127, 0, 0, 1}, 55_813},
        timeout: 50
      )

    on_exit(fn -> IPv4.disconnect(handle) end)
    state = :sys.get_state(handle.owner)
    assert :sys.get_state(state.segments_store).opts.max_segments == 32
    assert :sys.get_state(state.segmentator).opts.apdu_retries == 0
    :ok = :sys.suspend(state.client)

    send(
      handle.owner,
      {:bacnet_transport, {:bacnet_ipv4, BACnet.Stack.Transport.IPv4Transport}, {127, 0, 0, 1},
       {:apdu, nil, nil, :binary.copy(<<0>>, 1477)}, state.portal}
    )

    :sys.get_state(handle.owner)
    assert {:messages, []} = Process.info(state.client, :messages)
    :sys.resume(state.client)
    source = {{127, 0, 0, 1}, 55_813}

    for sequence <- 0..31 do
      result =
        SegmentsStore.segment(
          state.segments_store,
          segment(sequence, sequence < 31),
          Wotex.BACnet.Test.SegmentTransport,
          self(),
          source
        )

      if sequence < 31,
        do: assert(result == :incomplete),
        else: assert(result == {:ok, <<48, 7, 12>> <> :binary.copy(<<1>>, 32)})
    end

    assert :sys.get_state(state.segments_store).sequences == %{}

    for sequence <- 0..31 do
      result =
        SegmentsStore.segment(
          state.segments_store,
          segment(sequence, true),
          Wotex.BACnet.Test.SegmentTransport,
          self(),
          source
        )

      if sequence == 31,
        do: assert(match?({:error, _, true}, result)),
        else: assert(result == :incomplete)
    end

    assert :sys.get_state(state.segments_store).sequences == %{}

    assert :incomplete =
             SegmentsStore.segment(
               state.segments_store,
               segment(0, true),
               Wotex.BACnet.Test.SegmentTransport,
               self(),
               source
             )

    assert {:error, _, true} =
             SegmentsStore.segment(
               state.segments_store,
               segment(0, true),
               Wotex.BACnet.Test.SegmentTransport,
               self(),
               source
             )

    assert :sys.get_state(state.segments_store).sequences == %{}

    assert :incomplete =
             SegmentsStore.segment(
               state.segments_store,
               segment(0, true),
               Wotex.BACnet.Test.SegmentTransport,
               self(),
               source
             )

    assert {:error, :segments_out_of_order, false} =
             SegmentsStore.segment(
               state.segments_store,
               segment(2, false),
               Wotex.BACnet.Test.SegmentTransport,
               self(),
               source
             )

    assert map_size(:sys.get_state(state.segments_store).sequences) == 1

    SegmentsStore.cancel(state.segments_store, source, 7)
    assert :sys.get_state(state.segments_store).sequences == %{}

    assert :incomplete =
             SegmentsStore.segment(
               state.segments_store,
               segment(0, true),
               Wotex.BACnet.Test.SegmentTransport,
               self(),
               source
             )

    send(state.segments_store, {:timer, {source, 7}})
    assert :sys.get_state(state.segments_store).sequences == %{}

    assert {:error, :invalid_apdu_in_this_state, true} =
             SegmentsStore.segment(
               state.segments_store,
               segment(1, false),
               Wotex.BACnet.Test.SegmentTransport,
               self(),
               source
             )

    assert :sys.get_state(state.segments_store).sequences == %{}
  end

  defp segment(sequence, more),
    do: %IncompleteAPDU{
      header: <<48, 7, 12>>,
      server: false,
      invoke_id: 7,
      sequence_number: sequence,
      window_size: 2,
      more_follows: more,
      data: <<1>>
    }

  defp read_ack(value) do
    {:ok, apdu} =
      Services.Ack.ReadPropertyAck.to_apdu(
        %Services.Ack.ReadPropertyAck{
          object_identifier: %ObjectIdentifier{type: :analog_output, instance: 0},
          property_identifier: :present_value,
          property_array_index: nil,
          property_value: value
        },
        1
      )

    apdu
  end

  defp execute_fixture("Value.encode/2", input), do: Value.encode(input["value"], input["schema"])

  defp execute_fixture(operation, input) do
    atoms = %{
      "analog_output" => :analog_output,
      "present_value" => :present_value,
      "write_property" => :write_property
    }

    params =
      Map.new(input, fn {key, value} ->
        {String.to_existing_atom(key), Map.get(atoms, value, value)}
      end)

    case operation do
      "Address.new/1" -> Address.new(params)
      "Address.validate_message/1" -> Address.validate_message(params)
    end
  end

  defp normalize({:ok, value}),
    do: %{
      "ok" =>
        value
        |> Map.from_struct()
        |> Jason.encode!()
        |> Jason.decode!()
    }

  defp normalize({:error, error}),
    do: %{
      "error" => %{"code" => Atom.to_string(error.code), "effect" => Atom.to_string(error.effect)}
    }
end
