defmodule Wotex.Zigbee.ChannelMigrationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{ChannelMigration, Command, Error, Frame}
  alias Wotex.Zigbee.Network.Snapshot

  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>
  @extended <<0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8>>
  @peer %{peer_ieee: <<9::64>>, route_address: 0x1234, source_endpoint: 2, destination_endpoint: 1}
  @device <<0, @ieee::binary, 0::little-16, 7, 9, 0>>
  @profile Path.expand("../../support/profiles/zdo-channel-migration-mt-r1.14.json", __DIR__)

  test "pinned literal vectors expose only the finite broadcast and stay outside raw admission" do
    profile = :json.decode(File.read!(@profile))
    before = Process.info(self(), :messages)

    for vector <- profile["adoption"]["requests"] do
      {:ok, request} = ChannelMigration.new(options(target_channel: vector["target_channel"]))
      assert {:ok, frame} = ChannelMigration.frame(request)
      assert {:ok, bytes} = Frame.encode(frame)
      assert bytes == Base.decode16!(vector["hex"], case: :mixed)
      refute Command.admitted?(frame)
      refute bytes =~ request.correlation_id
    end

    assert Process.info(self(), :messages) == before
  end

  test "all network, time and cohort boundaries reject malformed or copied requests" do
    for {field, value} <- [
          coordinator_ieee: <<0::64>>,
          extended_pan_id: <<0xFFFFFFFFFFFFFFFF::64>>,
          pan_id: 65_535,
          channel: 10,
          target_channel: 27,
          target_channel: 15,
          settle_ms: 0,
          settle_ms: 30_001,
          peer_timeout_ms: 0,
          peer_timeout_ms: 60_001,
          correlation_id: "",
          correlation_id: :binary.copy("x", 65),
          peers: [],
          peers: [@peer, @peer],
          peers: [@peer | :bad],
          peers: List.duplicate(@peer, 33)
        ] do
      assert {:error, %Error{kind: :invalid_value}} =
               ChannelMigration.new(options([{field, value}]))
    end

    for peer <- [
          nil,
          %{},
          Map.put(@peer, :key, "credential-canary"),
          Map.delete(@peer, :peer_ieee),
          %{@peer | peer_ieee: @ieee},
          %{@peer | peer_ieee: <<0::64>>},
          %{@peer | route_address: 0},
          %{@peer | route_address: 0xFFF8},
          %{@peer | source_endpoint: 0},
          %{@peer | destination_endpoint: 241}
        ] do
      assert {:error, %Error{kind: :invalid_value} = error} =
               ChannelMigration.new(options(peers: [peer]))

      refute inspect(error) =~ "credential-canary"
    end

    duplicated_route = [@peer, %{@peer | peer_ieee: <<10::64>>}]
    duplicated_identity = [@peer, %{@peer | route_address: 2}]

    for peers <- [duplicated_route, duplicated_identity] do
      assert {:error, _} = ChannelMigration.new(options(peers: peers))
    end

    for input <- [
          nil,
          %{},
          [],
          [{:settle_ms, 1} | options()],
          [{:key, "credential-canary"} | options()],
          [1 | 2]
        ] do
      assert {:error, %Error{}} = ChannelMigration.new(input)
    end

    {:ok, request} = ChannelMigration.new(options())

    for copied <- [
          nil,
          Map.delete(request, :peers),
          Map.put(request, :key, "credential-canary"),
          %{request | peers: [@peer | :bad]}
        ] do
      refute ChannelMigration.valid?(copied)
      assert {:error, %Error{}} = ChannelMigration.frame(copied)
      refute ChannelMigration.matches_snapshot?(copied, nil, :before)
    end
  end

  test "the full cohort and endpoint limits remain finite without silently truncating input" do
    peers = for n <- 1..32, do: %{@peer | peer_ieee: <<n::64>>, route_address: n}

    assert {:ok, _} =
             ChannelMigration.new(options(peers: peers, settle_ms: 30_000, peer_timeout_ms: 60_000))

    assert {:ok, _} = ChannelMigration.new(options(pan_id: 0, channel: 26, target_channel: 11))

    assert {:ok, _} =
             ChannelMigration.new(
               options(
                 pan_id: 65_534,
                 peers: [%{@peer | source_endpoint: 240, destination_endpoint: 240}]
               )
             )
  end

  test "before and after require the exact expected network and selected channel" do
    {:ok, request} = ChannelMigration.new(options())
    assert ChannelMigration.matches_snapshot?(request, snapshot(15), :before)
    assert ChannelMigration.matches_snapshot?(request, snapshot(20), :after)
    refute ChannelMigration.matches_snapshot?(request, snapshot(15), :after)
    refute ChannelMigration.matches_snapshot?(request, snapshot(20), :before)
    refute ChannelMigration.matches_snapshot?(request, snapshot(20), :unsupported)

    for snapshot <- [
          nil,
          Map.put(snapshot(20), :key, "credential-canary"),
          snapshot(20, <<1, 0::104>>),
          snapshot(20, <<0, @ieee::binary, 0::little-16, 7, 8, 0>>)
        ] do
      refute ChannelMigration.matches_snapshot?(request, snapshot, :after)
    end
  end

  defp options(overrides \\ []),
    do:
      Keyword.merge(
        [
          coordinator_ieee: @ieee,
          extended_pan_id: @extended,
          pan_id: 0x1234,
          channel: 15,
          target_channel: 20,
          settle_ms: 3_000,
          peer_timeout_ms: 1_000,
          peers: [@peer],
          correlation_id: "migration"
        ],
        overrides
      )

  defp snapshot(channel, device \\ @device) do
    network =
      <<0::little-16, 9, 0x1234::little-16, 0::little-16, @extended::binary, @ieee::binary,
        channel>>

    issue = if binary_part(device, 0, 1) == <<0>>, do: nil, else: :status_failure
    inputs = [%{phase: :device_info, payload: device, observed_at_ms: 0}]

    inputs =
      if issue == nil,
        do: Enum.reverse([%{phase: :network_info, payload: network, observed_at_ms: 1} | inputs]),
        else: inputs

    {:ok, snapshot} = Snapshot.new(make_ref(), inputs, issue)
    snapshot
  end
end
