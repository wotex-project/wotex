defmodule Wotex.Zigbee.NetworkTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{Command, Error, Frame, Network}
  alias Wotex.Zigbee.Network.Snapshot

  @device Base.decode16!("000807060504030201000007090234127856", case: :mixed)
  @network Base.decode16!("00000934120000a1a2a3a4a5a6a7a808070605040302010f", case: :mixed)
  @profile Path.expand("../../support/profiles/znp-network-mt-r1.14.json", __DIR__)

  test "reviewed exact SDK byte vectors decode without round-trip oracles" do
    profile = :json.decode(File.read!(@profile))
    before = Process.info(self(), :messages)
    assert profile["source"]["revision"] == "1.14"

    for {phase, hex} <- [{:device_info, "fe00270027"}, {:network_info, "fe00255075"}] do
      assert {:ok, frame} = Network.frame(phase)
      assert {:ok, bytes} = Frame.encode(frame)
      assert bytes == Base.decode16!(hex, case: :mixed)
      refute Command.admitted?(frame)
    end

    for vector <- profile["adoption"]["vectors"] do
      bytes = Base.decode16!(vector["hex"], case: :mixed)

      decoded =
        if vector["phase"] == "device_info",
          do: Network.device_info(bytes),
          else: Network.network_info(bytes)

      assert {:ok, value} = decoded
      assert value.network_address == vector["network_address"]
      assert value.device_state == vector["device_state"]
    end

    assert {:ok, device} = Network.device_info(@device)
    assert device.coordinator_ieee == <<8, 7, 6, 5, 4, 3, 2, 1>>
    assert device.capabilities == 7
    assert device.associated_routes == [0x1234, 0x5678]
    assert {:ok, network} = Network.network_info(@network)
    assert network.pan_id == 0x1234
    assert network.extended_pan_id == <<0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8>>
    assert network.parent_ieee == device.coordinator_ieee
    assert network.channel == 15
    refute Map.has_key?(network, :status)
    assert Process.info(self(), :messages) == before
  end

  test "uninitialized values, capability bits and duplicate associated routes remain raw evidence" do
    payload =
      <<255, 0::64, 0xFFFF::little-16, 0xFF, 0xFE, 3, 0xFFFF::little-16, 0x1234::little-16,
        0x1234::little-16>>

    assert {:ok, device} = Network.device_info(payload)
    assert device.status == 255
    assert device.coordinator_ieee == <<0::64>>
    assert device.network_address == 65_535
    assert device.device_state == 254
    assert device.associated_routes == [65_535, 0x1234, 0x1234]
    assert {:ok, network} = Network.network_info(:binary.copy(<<255>>, 24))
    assert network.pan_id == 65_535
    assert network.channel == 255
    assert network.parent_ieee == <<0xFFFFFFFFFFFFFFFF::64>>
  end

  test "exact prefix, count and complete payload bounds refuse malformed or alternative layouts" do
    for payload <- [
          nil,
          <<>>,
          <<0>>,
          binary_part(@device, 0, 13),
          <<0, 0::64, 0::16, 1, 9, 1>>,
          @device <> <<0>>,
          <<0, 0::64, 0::16, 1, 9, 65, 0::1040>>
        ] do
      assert {:error, %Error{kind: :invalid_frame}} = Network.device_info(payload)
    end

    assert {:ok, %{associated_routes: routes}} =
             Network.device_info(<<0, 0::64, 0::16, 1, 9, 64, 0::1024>>)

    assert length(routes) == 64

    for payload <- [nil, <<>>, binary_part(@network, 0, 23), @network <> <<0>>] do
      assert {:error, %Error{kind: :invalid_frame}} = Network.network_info(payload)
    end

    assert {:error, %Error{kind: :invalid_command}} = Network.frame(:keys)
  end

  test "snapshots retain sequential matching and changed observations without continuity authority" do
    epoch = make_ref()
    inputs = readings()
    assert {:ok, snapshot} = Snapshot.new(epoch, inputs)
    assert snapshot.outcome == :observed
    assert snapshot.consistency == :matching
    assert snapshot.owner_epoch == epoch
    assert snapshot.issue == nil
    assert Snapshot.valid?(snapshot)
    assert Enum.map(snapshot.readings, & &1.payload) == [@device, @network]
    [first, second] = inputs
    <<_::16, tail::binary>> = @network
    changed = %{second | payload: <<0x1234::little-16, tail::binary>>}

    assert {:ok, %{outcome: :observed, consistency: :changed} = snapshot} =
             Snapshot.new(epoch, [first, changed])

    assert Snapshot.valid?(snapshot)

    assert {:ok, %{consistency: :matching}} =
             Snapshot.new(epoch, [first, %{second | observed_at_ms: 10}])
  end

  test "partial results require explicit issues and preserve failed status without later queries" do
    epoch = make_ref()
    [first, second] = readings()

    assert {:ok, %{outcome: :partial, readings: [], consistency: :unavailable}} =
             Snapshot.new(epoch, [], :timeout)

    assert {:ok, %{outcome: :partial, readings: [_], issue: :serial}} =
             Snapshot.new(epoch, [first], :serial)

    <<_, tail::binary>> = @device
    failed = %{first | payload: <<2, tail::binary>>}

    assert {:ok, %{outcome: :partial, consistency: :unavailable} = snapshot} =
             Snapshot.new(epoch, [failed], :status_failure)

    assert hd(snapshot.readings).value.status == 2
    assert Snapshot.valid?(snapshot)

    for inputs <- [[], [first], [failed], [failed, second]] do
      assert {:error, %Error{kind: :invalid_value}} = Snapshot.new(epoch, inputs)
    end
  end

  test "copied values, foreign fields, ordering and malformed times are revalidated and redacted" do
    epoch = make_ref()
    [first, second] = readings()

    for inputs <- [
          nil,
          [second],
          [second, first],
          [first, second, second],
          [first | "credential-canary"],
          [Map.put(first, :key, "credential-canary")],
          [%{first | payload: "credential-canary"}],
          [%{first | observed_at_ms: nil}],
          [%{first | observed_at_ms: 0x8000000000000000}],
          [first, %{second | observed_at_ms: 9}]
        ] do
      assert {:error, %Error{kind: :invalid_value} = error} = Snapshot.new(epoch, inputs, :timeout)
      refute inspect(error) =~ "credential-canary"
    end

    assert {:error, _} = Snapshot.new("credential-canary", readings())
    assert {:error, _} = Snapshot.new(epoch, readings(), "credential-canary")
    {:ok, snapshot} = Snapshot.new(epoch, readings())
    [device, network] = snapshot.readings

    for copied <- [
          nil,
          Map.delete(snapshot, :issue),
          Map.put(snapshot, :key, "credential-canary"),
          %{snapshot | consistency: :changed},
          %{snapshot | outcome: :partial},
          %{snapshot | readings: [device | "credential-canary"]},
          %{snapshot | readings: [%{device | value: %{device.value | capabilities: 0}}, network]},
          %{snapshot | readings: [Map.delete(device, :value), network]}
        ] do
      refute Snapshot.valid?(copied)
    end
  end

  defp readings,
    do: [
      %{phase: :device_info, payload: @device, observed_at_ms: 10},
      %{phase: :network_info, payload: @network, observed_at_ms: 11}
    ]
end
