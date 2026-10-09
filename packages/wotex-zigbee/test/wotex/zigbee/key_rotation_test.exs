defmodule Wotex.Zigbee.KeyRotationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{Command, Error, Frame, KeyRotation}
  alias Wotex.Zigbee.KeyRotation.Wire
  alias Wotex.Zigbee.Network.Snapshot

  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>
  @extended <<0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8>>
  @peer %{peer_ieee: <<9::64>>, route_address: 0x1234, source_endpoint: 2, destination_endpoint: 1}
  @device <<0, @ieee::binary, 0::little-16, 7, 9, 0>>
  @profile Path.expand("../../support/profiles/zdo-key-rotation-mt-r1.14.json", __DIR__)

  test "source-pinned update layout uses transient keys and switch vectors stay outside raw admission" do
    profile = :json.decode(File.read!(@profile))
    before = Process.info(self(), :messages)
    key = :crypto.strong_rand_bytes(16)

    for current <- [0, 128, 254] do
      {:ok, request} =
        KeyRotation.new(options(current_sequence: current, next_sequence: current + 1))

      frame = Wire.update(request, key)
      assert frame.subsystem == profile["adoption"]["update"]["subsystem"]
      assert frame.id == profile["adoption"]["update"]["id"]
      assert byte_size(frame.payload) == profile["adoption"]["update"]["payload_bytes"]
      assert frame.payload == <<0xFD, 0xFF, current + 1, key::binary>>
      assert {:ok, bytes} = Frame.encode(frame)
      assert bytes == wire(0x25, 0x4E, <<0xFD, 0xFF, current + 1, key::binary>>)
      refute Command.admitted?(frame)
      assert :binary.match(:erlang.term_to_binary(request), key) == :nomatch
    end

    for vector <- profile["adoption"]["switch_requests"] do
      {:ok, request} =
        KeyRotation.new(
          options(
            current_sequence: vector["next_sequence"] - 1,
            next_sequence: vector["next_sequence"]
          )
        )

      frame = Wire.switch(request)
      assert {:ok, bytes} = Frame.encode(frame)
      assert bytes == Base.decode16!(vector["hex"], case: :mixed)
      refute Command.admitted?(frame)
    end

    for vector <- profile["adoption"]["replies"] do
      assert {:ok, [%Frame{type: :srsp, id: id, payload: <<0>>}], <<>>, 0} =
               Frame.feed(<<>>, Base.decode16!(vector["hex"], case: :mixed))

      assert id == vector["id"]
    end

    assert Process.info(self(), :messages) == before
  end

  test "all network, time and cohort boundaries reject malformed or copied requests" do
    for {field, value} <- [
          coordinator_ieee: <<0::64>>,
          extended_pan_id: <<0xFFFFFFFFFFFFFFFF::64>>,
          pan_id: 65_535,
          channel: 10,
          current_sequence: -1,
          current_sequence: 255,
          next_sequence: 0,
          next_sequence: 2,
          next_sequence: 1.0,
          distribution_ms: 0,
          distribution_ms: 30_001,
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
               KeyRotation.new(options([{field, value}]))
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
               KeyRotation.new(options(peers: [peer]))

      refute inspect(error) =~ "credential-canary"
    end

    duplicated_route = [@peer, %{@peer | peer_ieee: <<10::64>>}]
    duplicated_identity = [@peer, %{@peer | route_address: 2}]

    for peers <- [duplicated_route, duplicated_identity] do
      assert {:error, _} = KeyRotation.new(options(peers: peers))
    end

    for input <- [
          nil,
          %{},
          [],
          [{:settle_ms, 1} | options()],
          [{:key, "credential-canary"} | options()],
          [1 | 2]
        ] do
      assert {:error, %Error{}} = KeyRotation.new(input)
    end

    {:ok, request} = KeyRotation.new(options())

    for copied <- [
          nil,
          Map.delete(request, :peers),
          Map.put(request, :key, "credential-canary"),
          %{request | peers: [@peer | :bad]}
        ] do
      refute KeyRotation.valid?(copied)
      refute KeyRotation.matches_snapshot?(copied, nil)
    end
  end

  test "the full cohort and endpoint limits remain finite without silently truncating input" do
    peers = for n <- 1..32, do: %{@peer | peer_ieee: <<n::64>>, route_address: n}

    assert {:ok, _} =
             KeyRotation.new(
               options(
                 peers: peers,
                 distribution_ms: 30_000,
                 settle_ms: 30_000,
                 peer_timeout_ms: 60_000
               )
             )

    assert {:ok, _} =
             KeyRotation.new(
               options(pan_id: 0, channel: 26, current_sequence: 254, next_sequence: 255)
             )

    assert {:ok, _} =
             KeyRotation.new(
               options(
                 pan_id: 65_534,
                 peers: [%{@peer | source_endpoint: 240, destination_endpoint: 240}]
               )
             )
  end

  test "all phases require expected network identity without inferring an active key" do
    {:ok, request} = KeyRotation.new(options())
    assert KeyRotation.matches_snapshot?(request, snapshot(15))

    for observed <- [
          nil,
          snapshot(20),
          Map.put(snapshot(15), :key, "credential-canary"),
          snapshot(15, <<1, 0::104>>),
          snapshot(15, <<0, @ieee::binary, 0::little-16, 7, 8, 0>>)
        ] do
      refute KeyRotation.matches_snapshot?(request, observed)
    end
  end

  test "retained private writer expires even in its original owner process" do
    {:ok, request} = KeyRotation.new(options())

    context = %{
      operation: :key_rotation,
      phase: :update,
      owner_epoch: make_ref(),
      request: request,
      network: snapshot(15),
      update: nil,
      now_ms: System.monotonic_time(:millisecond),
      deadline_ms: System.monotonic_time(:millisecond) + 1_000
    }

    {custodian, key} = Wotex.Zigbee.TestKeyCredentials.start(self(), key: :save)
    on_exit(fn -> send(custodian, :stop) end)
    {:ok, port} = Wotex.Zigbee.Credentials.new(Wotex.Zigbee.TestKeyCredentials, custodian)

    writer = fn _ ->
      send(self(), :unexpected_key_write)
      :ok
    end

    assert {:refused, :credentials} =
             Wotex.Zigbee.Credentials.KeyCall.dispatch(
               port,
               context,
               1_000,
               context.deadline_ms,
               self(),
               writer
             )

    assert_receive {:saved_consumer_write, consume, ^key}
    assert consume.(key) == {:error, :credentials}
    refute_receive :unexpected_key_write
    assert :binary.match(:erlang.term_to_binary(Process.info(self(), :dictionary)), key) == :nomatch
  end

  defp wire(command, id, payload) do
    body = <<byte_size(payload), command, id, payload::binary>>
    checksum = Enum.reduce(:binary.bin_to_list(body), 0, &Bitwise.bxor/2)
    <<0xFE, body::binary, checksum>>
  end

  defp options(overrides \\ []),
    do:
      Keyword.merge(
        [
          coordinator_ieee: @ieee,
          extended_pan_id: @extended,
          pan_id: 0x1234,
          channel: 15,
          current_sequence: 0,
          next_sequence: 1,
          distribution_ms: 3_000,
          settle_ms: 3_000,
          peer_timeout_ms: 1_000,
          peers: [@peer],
          correlation_id: "rotation"
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
