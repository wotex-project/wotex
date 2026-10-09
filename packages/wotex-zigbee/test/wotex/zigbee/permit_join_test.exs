defmodule Wotex.Zigbee.PermitJoinTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{Command, Credentials, Error, Event, Frame, PermitJoin}
  alias Wotex.Zigbee.Network.Snapshot

  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>
  @extended <<0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8>>
  @device <<0, @ieee::binary, 0::little-16, 7, 9, 0>>
  @network <<0::little-16, 9, 0x1234::little-16, 0::little-16, @extended::binary, @ieee::binary,
             15>>
  @profile Path.expand("../../support/profiles/zdo-permit-join-mt-r1.14.json", __DIR__)

  test "exact pinned coordinator request vectors stay inert and excluded from raw admission" do
    profile = :json.decode(File.read!(@profile))
    before = Process.info(self(), :messages)

    for vector <- profile["adoption"]["requests"] do
      request =
        request(duration_s: vector["duration_s"], tc_significance: vector["tc_significance"])

      assert {:ok, frame} = PermitJoin.frame(request)
      assert {:ok, bytes} = Frame.encode(frame)
      assert bytes == Base.decode16!(vector["hex"], case: :mixed)
      assert frame.payload == <<2, 0, 0, request.duration_s, request.tc_significance>>
      refute Command.admitted?(frame)
      refute bytes =~ request.correlation_id
    end

    assert Process.info(self(), :messages) == before
  end

  test "request boundaries and copied values refuse unknown scopes and credential fields" do
    for {field, invalid} <- [
          coordinator_ieee: <<0::64>>,
          coordinator_ieee: <<0xFFFFFFFFFFFFFFFF::64>>,
          extended_pan_id: nil,
          extended_pan_id: <<0::64>>,
          pan_id: 65_535,
          channel: 10,
          channel: 27,
          duration_s: -1,
          duration_s: 255,
          tc_significance: 2,
          correlation_id: "",
          correlation_id: :binary.copy("x", 65)
        ] do
      assert {:error, %Error{kind: :invalid_value}} = PermitJoin.new(options([{field, invalid}]))
    end

    for input <- [nil, %{}, [], [duration_s: 0], [{:key, "credential-canary"} | options()], [1 | 2]] do
      assert {:error, %Error{} = error} = PermitJoin.new(input)
      refute inspect(error) =~ "credential-canary"
    end

    for copied <- [
          nil,
          Map.delete(request(), :duration_s),
          Map.put(request(), :key, "credential-canary"),
          %{request() | duration_s: 255}
        ] do
      refute PermitJoin.valid?(copied)
      assert {:error, %Error{kind: :invalid_value}} = PermitJoin.frame(copied)
    end

    for duration <- [0, 254], pan <- [0, 65_534], channel <- [11, 26] do
      assert {:ok, _} = PermitJoin.new(options(duration_s: duration, pan_id: pan, channel: channel))
    end
  end

  test "network comparison requires exact commissioned coordinator fields without conferring authority" do
    snapshot = snapshot()
    assert PermitJoin.matches_snapshot?(request(), snapshot)

    for copied <- [
          %{request() | coordinator_ieee: <<1::64>>},
          %{request() | extended_pan_id: <<1::64>>},
          %{request() | pan_id: 1},
          %{request() | channel: 26},
          nil
        ] do
      refute PermitJoin.matches_snapshot?(copied, snapshot)
    end

    for device <- [
          <<0, @ieee::binary, 1::little-16, 7, 9, 0>>,
          <<0, @ieee::binary, 0::little-16, 7, 7, 0>>,
          <<0, @ieee::binary, 0::little-16, 2, 9, 0>>
        ] do
      refute PermitJoin.matches_snapshot?(request(), snapshot(device: device))
    end

    refute PermitJoin.matches_snapshot?(request(), %{snapshot | consistency: :changed})
    refute PermitJoin.matches_snapshot?(request(), nil)
  end

  test "management replies and local changes preserve their different raw fields" do
    assert {:ok, %{source_address: 0x1234, status: 255}} =
             PermitJoin.response(<<0x1234::little-16, 255>>)

    for duration <- [0, 254, 255] do
      assert {:ok, %{duration_s: ^duration}} = PermitJoin.indication(<<duration>>)

      event = Event.from_frame(%Frame{type: :areq, subsystem: 5, id: 0xCB, payload: <<duration>>})
      assert event.kind == :permit_join_indication
      assert event.zdo == %{duration_s: duration}
      assert event.transaction == nil
      assert event.status == nil
      assert event.security_used == nil
    end

    event =
      Event.from_frame(%Frame{type: :areq, subsystem: 5, id: 0xB6, payload: <<0, 0, 0x81>>})

    assert event.kind == :zdo_permit_join
    assert event.status == 0x81
    assert event.source_address == 0
    assert event.transaction == nil
    assert event.security_used == nil

    for {id, payload} <- [{0xB6, <<>>}, {0xB6, <<0, 0>>}, {0xCB, <<>>}, {0xCB, <<0, 0>>}] do
      assert %{kind: :malformed_indication, payload: ^payload} =
               Event.from_frame(%Frame{type: :areq, subsystem: 5, id: id, payload: payload})
    end
  end

  test "custody handles are explicit inert references and reject private configuration" do
    before = Process.info(self(), :messages)
    handle = make_ref()
    assert {:ok, port} = Credentials.new(__MODULE__, handle)
    assert Credentials.valid?(port)
    refute inspect(port) =~ inspect(handle)
    assert {:ok, _} = Credentials.new(__MODULE__, self())

    for {module, value} <- [
          {nil, handle},
          {"credential-canary", handle},
          {__MODULE__, "credential-canary"}
        ] do
      assert {:error, %Error{} = error} = Credentials.new(module, value)
      refute inspect(error) =~ "credential-canary"
    end

    for copied <- [nil, Map.delete(port, :handle), Map.put(port, :key, "credential-canary")] do
      refute Credentials.valid?(copied)
    end

    assert Process.info(self(), :messages) == before
  end

  defp options(overrides \\ []),
    do:
      Keyword.merge(
        [
          coordinator_ieee: @ieee,
          extended_pan_id: @extended,
          pan_id: 0x1234,
          channel: 15,
          duration_s: 60,
          tc_significance: 1,
          correlation_id: "joining"
        ],
        overrides
      )

  defp request(overrides \\ []) do
    {:ok, request} = PermitJoin.new(options(overrides))
    request
  end

  defp snapshot(overrides \\ []) do
    {:ok, snapshot} =
      Snapshot.new(make_ref(), [
        %{
          phase: :device_info,
          payload: Keyword.get(overrides, :device, @device),
          observed_at_ms: 0
        },
        %{phase: :network_info, payload: @network, observed_at_ms: 1}
      ])

    snapshot
  end
end
