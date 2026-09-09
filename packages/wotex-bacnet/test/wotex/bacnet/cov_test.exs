defmodule Wotex.BACnet.COVTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties
  alias BACnet.Protocol.{APDU, ApplicationTags}
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias Wotex.BACnet.{CharacterString, COV, COVRequest, Subscription, Tags}
  @request %{type: :cov, object_type: :analog_output, instance: 0, device_instance: 123}
  @corpus Jason.decode!(
            File.read!(Path.expand("../../../docs/specs/fixtures/contract-v1.json", __DIR__))
          )

  test "WBA-S04 WBA-V06 explicit device and finite subscription fields normalize before I/O" do
    assert {:ok, request} = COVRequest.new(@request, self())
    assert request.object_type == 1
    assert request.property == nil
    assert request.receiver == self()
    assert request.confirmed and request.renew
    assert request.lifetime == 60
    assert request.duplicate_window_ms == 60_000
    assert :ok = COVRequest.validate(request)

    for override <- [
          %{lifetime: 0},
          %{lifetime: 1},
          %{lifetime: 86_401},
          %{device_instance: -1},
          %{device_instance: 4_194_303},
          %{receiver: nil},
          %{confirmed: nil},
          %{renew: 0},
          %{max_queue_length: 0},
          %{max_queue_length: 10_001},
          %{duplicate_window_ms: 0},
          %{duplicate_window_ms: 60_001},
          %{property: nil},
          %{array_index: nil},
          %{cov_increment: nil},
          %{priority: 8},
          %{unexpected: true},
          %{type: :invalid}
        ] do
      assert {:error, %{effect: :none}} = COVRequest.new(Map.merge(@request, override), self())
    end

    assert {:error, _} = COVRequest.new(Map.delete(@request, :device_instance), self())
    assert {:error, _} = COVRequest.new(%{@request | type: :cov_property}, self())
    assert {:error, _} = COVRequest.new(:bad, self())
    assert {:error, _} = COVRequest.new(request, self())
    assert {:error, _} = COVRequest.validate(%{request | device_instance: nil})
    assert {:error, _} = COVRequest.validate(%{request | property: 85})
    assert {:error, _} = COVRequest.validate(:bad)
  end

  test "WBA-S04 WBA-V10 WBA-F07 cancellation omits both finite-registration fields and increment" do
    row = Enum.find(@corpus["cases"], &(&1["id"] == "WBA-F07"))
    input = row["input"]

    {:ok, request} =
      COVRequest.new(
        %{
          type: :cov,
          object_type: input["object_type"],
          instance: input["instance"],
          device_instance: 123
        },
        self()
      )

    assert {:ok, apdu} = COV.request(request, input["process_identifier"], true)

    assert Enum.map(apdu.parameters, fn {:tagged, {tag, _, _}} -> tag end) ==
             row["expectation"]["value"]["context_tags"]

    assert Base.encode16(encode_tags(apdu.parameters), case: :lower) ==
             row["expectation"]["value"]["parameters_hex"]

    assert apdu.service == :subscribe_cov
    assert apdu.max_apdu == 1476 and apdu.max_segments == 32
    assert {:ok, registration} = COV.request(request, 7)
    assert encode_tags(registration.parameters) == <<9, 7, 0x1C, 0, 64, 0, 0, 0x29, 1, 0x39, 60>>

    {:ok, property} =
      COVRequest.new(
        Map.merge(@request, %{
          type: :cov_property,
          property: :present_value,
          array_index: 0,
          cov_increment: 2.5,
          confirmed: false
        }),
        self()
      )

    assert {:ok, apdu} = COV.request(property, 0)
    assert apdu.service == :subscribe_cov_property

    assert encode_tags(apdu.parameters) ==
             <<9, 0, 0x1C, 0, 64, 0, 0, 0x29, 0, 0x39, 60, 0x4E, 9, 85, 0x19, 0, 0x4F, 0x5C,
               2.5::float-32>>

    assert {:ok, cancel} = COV.request(property, 0, true)
    assert encode_tags(cancel.parameters) == <<9, 0, 0x1C, 0, 64, 0, 0, 0x4E, 9, 85, 0x19, 0, 0x4F>>
    assert {:error, _} = COV.request(%{property | lifetime: 0}, 7)
    assert {:error, _} = COV.request(property, -1)
    assert {:error, _} = COV.request(property, 4_294_967_296)
    assert {:error, _} = COV.request(property, 0, :bad)

    for increment <- [0, -1.0, 1.0e-50, 1.0e100, :NaN] do
      assert {:error, _} =
               COVRequest.new(
                 Map.merge(@request, %{type: :cov_property, property: 85, cov_increment: increment}),
                 self()
               )
    end

    assert {:ok, %{cov_increment: 1.0}} =
             COVRequest.new(
               Map.merge(@request, %{type: :cov_property, property: 85, cov_increment: 1}),
               self()
             )
  end

  property "WBA-S04 WBA-V06 process identifiers retain all32 bits" do
    check all(identifier <- integer(0..4_294_967_295)) do
      {:ok, request} = COVRequest.new(@request, self())
      assert {:ok, apdu} = COV.request(request, identifier)
      [{:tagged, {0, bytes, length}} | _] = apdu.parameters
      assert byte_size(bytes) == length
      assert :binary.decode_unsigned(bytes) == identifier
    end
  end

  test "WBA-S04 WBA-V07 exact notification selectors retain ordered duplicate indices" do
    {:ok, request} = COVRequest.new(@request, self())
    values = property_tags(85, 0, {:real, 1.5}) ++ property_tags(85, 0, {:null, nil})
    assert {:ok, report} = COV.notification(notification(values))

    assert [
             %{property: 85, array_index: 0, priority: nil, value: %Encoding{value: 1.5}},
             %{value: %Encoding{type: :null, value: nil}}
           ] = report.values

    assert COV.matches?(report, request, 7)

    for changed <- [
          %{device_instance: 124},
          %{process_identifier: 8},
          %{object_type: 2},
          %{instance: 1},
          %{confirmed: false}
        ] do
      refute COV.matches?(Map.merge(report, changed), request, 7)
    end

    refute COV.matches?(%{}, request, 7)

    {:ok, selected} =
      COVRequest.new(
        Map.merge(@request, %{type: :cov_property, property: 85, array_index: 0}),
        self()
      )

    assert COV.matches?(report, selected, 7)
    refute COV.matches?(report, %{selected | array_index: nil}, 7)
    refute COV.matches?(report, %{selected | property: 77}, 7)
    raw = notification(property_tags(85, nil, {:unsigned_integer, 0}, 16))

    assert {:ok, %{values: [%{priority: 16, array_index: nil, value: %Encoding{value: 0}}]}} =
             COV.notification(raw)

    unconfirmed = %APDU.UnconfirmedServiceRequest{
      service: :unconfirmed_cov_notification,
      parameters: raw.parameters
    }

    assert {:ok, %{confirmed: false, invoke_id: nil}} = COV.notification(unconfirmed)
  end

  test "WBA-S04 WBA-V07 complete malformed or oversized notifications never yield partial values" do
    apdu = notification(property_tags(85, nil, {:real, 1.5}))

    for payload <- [
          [],
          tl(apdu.parameters),
          Enum.concat(apdu.parameters, [{:null, nil}]),
          List.replace_at(apdu.parameters, 0, {:tagged, {0, <<1>>, 2}}),
          List.replace_at(apdu.parameters, 1, {:tagged, {1, <<7::10, 123::22>>, 4}}),
          List.replace_at(apdu.parameters, 1, {:tagged, {1, <<8::10, 4_194_303::22>>, 4}}),
          List.replace_at(apdu.parameters, 3, {:tagged, {3, <<>>, 0}})
        ] do
      assert {:error, _} = COV.notification(%{apdu | parameters: payload})
    end

    for values <- [
          [],
          [:bad],
          property_tags(85, nil, :invalid),
          property_tags(85, nil, [:bad]),
          property_tags(4_194_304, nil, {:real, 1.0}),
          property_tags(85, nil, {:null, nil}, 17),
          Enum.concat(property_tags(85, nil, {:null, nil}), [:trailing]),
          property_tags(85, nil, {:null, nil}) ++
            property_tags(85, nil, {:character_string, <<255>>})
        ] do
      assert {:error, _} = COV.notification(notification(values))
    end

    assert {:error, _} = COV.notification(:bad)
    assert {:error, _} = COV.notification(%{apdu | invoke_id: 256})

    assert {:ok, %{values: [%{value: []}]}} =
             COV.notification(notification(property_tags(85, nil, [])))

    values = Enum.flat_map(1..1024, fn _ -> property_tags(85, nil, {:null, nil}) end)
    assert {:ok, report} = COV.notification(notification(values))
    assert length(report.values) == 1024
    assert {:ok, tags} = Tags.decode(encode_tags(notification(values).parameters))
    assert {:ok, ^report} = COV.notification(%{notification(values) | parameters: tags})

    assert {:error, %{code: :value_limit}} =
             COV.notification(notification(values ++ property_tags(85, nil, {:null, nil})))

    assert {:error, %{code: :value_limit}} =
             COV.notification(
               notification(property_tags(85, nil, {:octet_string, :binary.copy(<<0>>, 65_537)}))
             )
  end

  test "WBA-S01 WBA-S04 WBA-V07 character identity remains native in COV values" do
    string = %CharacterString{character_set: 255, bytes: <<255, 0>>}

    assert {:ok, %{values: [%{value: %Encoding{value: ^string}}]}} =
             COV.notification(notification(property_tags(85, nil, {:character_string, string})))

    assert {:error, %{code: :character_set_unavailable}} =
             COV.notification(
               notification(property_tags(85, nil, {:character_string, "SDK normalised"}))
             )

    assert {:ok, %{values: [%{value: [%Encoding{value: false}, %Encoding{value: nil}]}]}} =
             COV.notification(
               notification(property_tags(85, nil, [{:boolean, false}, {:null, nil}]))
             )
  end

  test "WBA-C05 typed handles redact references and reject forged field types" do
    handle = %Subscription{
      pid: self(),
      reference: make_ref(),
      generation: make_ref(),
      session_generation: make_ref()
    }

    assert Subscription.valid?(handle)

    for field <- [:pid, :reference, :generation, :session_generation],
        do: refute(Subscription.valid?(Map.put(handle, field, nil)))

    refute Subscription.valid?(%{})
    refute inspect(handle) =~ inspect(self())
    refute inspect(handle) =~ inspect(handle.reference)
  end

  defp notification(values),
    do: %APDU.ConfirmedServiceRequest{
      segmented_response_accepted: true,
      max_segments: 32,
      max_apdu: 1476,
      invoke_id: 5,
      sequence_number: nil,
      proposed_window_size: nil,
      service: :confirmed_cov_notification,
      parameters: [
        {:tagged, {0, <<7>>, 1}},
        {:tagged, {1, <<8::10, 123::22>>, 4}},
        {:tagged, {2, <<1::10, 0::22>>, 4}},
        {:tagged, {3, <<60>>, 1}},
        {:constructed, {4, values, 0}}
      ]
    }

  defp property_tags(identifier, index, value, priority \\ nil) do
    bytes = :binary.encode_unsigned(identifier)

    [{:tagged, {0, bytes, byte_size(bytes)}}] ++
      optional(1, index) ++ [{:constructed, {2, value, 0}}] ++ optional(3, priority)
  end

  defp optional(_, nil), do: []

  defp optional(tag, value) do
    bytes = :binary.encode_unsigned(value)
    [{:tagged, {tag, bytes, byte_size(bytes)}}]
  end

  defp encode_tags(tags),
    do:
      IO.iodata_to_binary(
        Enum.map(tags, fn tag ->
          {:ok, bytes} = ApplicationTags.encode(tag)
          bytes
        end)
      )
end
