defmodule Wotex.BACnet.DiscoveryValuesTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias BACnet.Protocol.{APDU, ObjectIdentifier}
  alias Wotex.BACnet.{Device, DiscoveryOptions, Error}

  @corpus Path.expand("../../../docs/specs/fixtures/contract-v1.json", __DIR__)
  @external_resource @corpus
  @cases Jason.decode!(File.read!(@corpus))["cases"]
  @moduletag corpus_sha256: Base.encode16(:crypto.hash(:sha256, File.read!(@corpus)), case: :lower)
  @source {{127, 0, 0, 1}, 47_808}
  @device %{
    source: @source,
    instance: 123,
    max_apdu: 1476,
    segmentation: :no_segmentation,
    vendor_id: 260
  }

  test "WBA-N04 Device validates every field and revalidates forged structs" do
    assert {:ok, device} = Device.new(@device)
    assert Map.from_struct(device) == @device
    assert {:ok, ^device} = Device.new(device)

    for change <- [
          %{source: {{256, 0, 0, 1}, 1}},
          %{source: {{127, 0, 0, 1}, 0}},
          %{source: {{127, 0, 0, 1}, 65_536}},
          %{source: {{127.0, 0, 0, 1}, 47_808}},
          %{source: :unknown},
          %{instance: -1},
          %{instance: 4_194_303},
          %{max_apdu: 0},
          %{max_apdu: 65_536},
          %{segmentation: :unknown},
          %{vendor_id: -1},
          %{vendor_id: 65_536}
        ] do
      assert {:error, %Error{code: :invalid_device}} = Device.new(Map.merge(@device, change))
      assert {:error, %Error{code: :invalid_device}} = Device.new(Map.merge(device, change))
    end

    for malformed <- [nil, %{}, Map.delete(@device, :source), Map.put(@device, :extra, true)],
        do: assert({:error, %Error{code: :invalid_device}} = Device.new(malformed))

    segmentations = [:segmented_both, :segmented_transmit, :segmented_receive, :no_segmentation]

    for segmentation <- segmentations,
        do: assert({:ok, _} = Device.new(%{@device | segmentation: segmentation}))

    assert {:ok, _} = Device.new(%{@device | instance: 0, max_apdu: 1, vendor_id: 0})

    assert {:ok, _} =
             Device.new(%{@device | instance: 4_194_302, max_apdu: 65_535, vendor_id: 65_535})
  end

  test "WBA-N04 I-Am preserves actual source and rejects wrong object, trailing tags and malformed enums" do
    apdu = %APDU.UnconfirmedServiceRequest{
      service: :i_am,
      parameters: [
        {:object_identifier, %ObjectIdentifier{type: :device, instance: 123}},
        {:unsigned_integer, 1476},
        {:enumerated, 3},
        {:unsigned_integer, 260}
      ]
    }

    assert {:ok, device} = Device.from_apdu(@source, apdu)
    assert Map.from_struct(device) == @device

    for parameters <- [
          [],
          Enum.concat(apdu.parameters, [{:null, nil}]),
          List.replace_at(
            apdu.parameters,
            0,
            {:object_identifier, %ObjectIdentifier{type: :analog_output, instance: 123}}
          ),
          List.replace_at(
            apdu.parameters,
            0,
            {:object_identifier, %ObjectIdentifier{type: :device, instance: 4_194_303}}
          ),
          List.replace_at(apdu.parameters, 1, {:unsigned_integer, 0}),
          List.replace_at(apdu.parameters, 2, {:enumerated, 4}),
          List.replace_at(apdu.parameters, 3, {:unsigned_integer, 65_536}),
          List.replace_at(apdu.parameters, 3, {:unsigned_integer, :invalid}),
          List.replace_at(apdu.parameters, 2, {:boolean, false})
        ],
        do:
          assert(
            {:error, %Error{code: :invalid_device}} =
              Device.from_apdu(@source, %{apdu | parameters: parameters})
          )

    assert {:error, %Error{code: :invalid_device}} =
             Device.from_apdu(@source, %{apdu | service: :who_is})

    assert {:error, %Error{code: :invalid_device}} = Device.from_apdu(@source, :invalid)
  end

  test "WBA-N04 discovery requires explicit bounded unicast or broadcast configuration" do
    options = %{destination: @source, timeout_ms: 1000, max_devices: 256}
    assert :ok = DiscoveryOptions.validate(nil)
    assert :ok = DiscoveryOptions.validate(options)

    for change <- [
          %{destination: {{255, 255, 255, 255}, 47_808}},
          %{destination: {{192, 0, 2, 255}, 47_808}},
          %{timeout_ms: 10, max_devices: 1},
          %{timeout_ms: 60_000, max_devices: 1024}
        ],
        do: assert(:ok = DiscoveryOptions.validate(Map.merge(options, change)))

    for change <- [
          %{destination: :default},
          %{destination: {{224, 0, 0, 1}, 47_808}},
          %{destination: {{0, 0, 0, 0}, 47_808}},
          %{destination: {{127, 0, 0, 1}, 0}},
          %{timeout_ms: 9},
          %{timeout_ms: 60_001},
          %{timeout_ms: 10.0},
          %{max_devices: 0},
          %{max_devices: 1025}
        ],
        do:
          assert(
            {:error, %Error{code: :invalid_discovery_options}} =
              DiscoveryOptions.validate(Map.merge(options, change))
          )

    for invalid <- [[], %{}, Map.delete(options, :destination), Map.put(options, :extra, true)],
        do:
          assert(
            {:error, %Error{code: :invalid_discovery_options}} = DiscoveryOptions.validate(invalid)
          )
  end

  test "WBA-N04 WBA-F05 WBA-F06 encode the fixture ranges and reject incomplete ranges" do
    for vector <- @cases, vector["id"] in ["WBA-F05", "WBA-F06"] do
      input = vector["input"]
      assert {:ok, apdu} = DiscoveryOptions.request(input["low_limit"], input["high_limit"])
      assert {:ok, bytes} = APDU.UnconfirmedServiceRequest.encode(apdu)

      encoded =
        bytes
        |> IO.iodata_to_binary()
        |> Base.encode16(case: :lower)

      assert encoded == vector["expectation"]["value"]["apdu_hex"], vector["id"]
    end

    ranges = [{nil, 1}, {1, nil}, {-1, 1}, {2, 1}, {0, 4_194_303}, {1.0, 2}, {:all, :all}]

    for {low, high} <- ranges,
        do:
          assert(
            {:error, %Error{code: :invalid_discovery_range}} = DiscoveryOptions.request(low, high)
          )

    assert {:ok, _} = DiscoveryOptions.request(0, 0)
    assert {:ok, _} = DiscoveryOptions.request(0, 4_194_302)
  end
end
