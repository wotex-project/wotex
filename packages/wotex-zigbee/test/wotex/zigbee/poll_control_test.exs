defmodule Wotex.Zigbee.PollControlTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee.{Error, Event, Reply, Routes}
  alias Wotex.Zigbee.Interview.Result
  alias Wotex.Zigbee.ZCL.PollControl

  @ieee <<8, 7, 6, 5, 4, 3, 2, 1>>
  @profile Path.expand("../../support/profiles/zcl-poll-control-r8.json", __DIR__)

  test "literal reviewed command vectors execute without round-trip encoding as their oracle" do
    profile = :json.decode(File.read!(@profile))

    for vector <- profile["adoption"]["vectors"] do
      bytes = Base.decode16!(vector["hex"], case: :mixed)
      assert {:ok, message} = PollControl.decode(bytes)
      assert Atom.to_string(message.command) == vector["command"]
      assert message.sequence == 7
      assert message.raw == bytes
    end

    before = Process.info(self(), :messages)
    assert {:ok, <<1, 7, 0, 0, 0, 0>>} = PollControl.checkin_response(7, false, 0)
    assert {:ok, <<1, 7, 0, 1, 40, 0>>} = PollControl.checkin_response(7, true, 40)
    assert {:ok, <<1, 7, 0, 0, 0xFF, 0xFF>>} = PollControl.checkin_response(7, false, 65_535)
    assert {:ok, <<1, 7, 1>>} = PollControl.fast_poll_stop(7)
    assert {:ok, <<1, 7, 2, 4, 0, 0, 0>>} = PollControl.set_long_poll_interval(7, 4)
    assert {:ok, <<1, 7, 2, 0, 0, 0x6E, 0>>} = PollControl.set_long_poll_interval(7, 0x6E0000)
    assert {:ok, <<1, 7, 3, 1, 0>>} = PollControl.set_short_poll_interval(7, 1)
    assert {:ok, <<1, 7, 3, 0xFF, 0xFF>>} = PollControl.set_short_poll_interval(7, 65_535)
    assert Process.info(self(), :messages) == before
  end

  test "constructor inputs neither coerce nor wrap, and zero retains its operation-specific meaning" do
    for start <- [0, 1, :null, nil, "credential-canary"] do
      assert {:error, %Error{kind: :invalid_value} = error} =
               PollControl.checkin_response(7, start, 0)

      refute inspect(error) =~ "credential-canary"
    end

    for timeout <- [-1, 65_536, :null, nil],
        do: assert({:error, _} = PollControl.checkin_response(7, true, timeout))

    for sequence <- [-1, 256, nil, "sequence"] do
      assert {:error, _} = PollControl.checkin_response(sequence, true, 1)
      assert {:error, _} = PollControl.fast_poll_stop(sequence)
      assert {:error, _} = PollControl.set_long_poll_interval(sequence, 4)
      assert {:error, _} = PollControl.set_short_poll_interval(sequence, 1)
    end

    for interval <- [0, 3, 0x6E0001, 0xFFFFFFFF, nil],
        do: assert({:error, _} = PollControl.set_long_poll_interval(7, interval))

    for interval <- [0, 65_536, :null],
        do: assert({:error, _} = PollControl.set_short_poll_interval(7, interval))

    assert {:ok, 0} = PollControl.quarterseconds_to_ms(0)
    assert {:ok, 250} = PollControl.quarterseconds_to_ms(1)
    assert {:ok, 1_802_240_000} = PollControl.quarterseconds_to_ms(0x6E0000)
    assert {:ok, 1_073_741_823_750} = PollControl.quarterseconds_to_ms(0xFFFFFFFF)

    for value <- [-1, 0x100000000, nil],
        do: assert({:error, _} = PollControl.quarterseconds_to_ms(value))
  end

  test "direction, command class and default-response flag remain visible" do
    for control <- [9, 25] do
      assert {:ok, %{command: :checkin, direction: :server_to_client} = message} =
               PollControl.decode(<<control, 255, 0>>)

      assert message.disable_default_response == (control == 25)
    end

    assert {:ok, %{parameters: %{start_fast_polling: false, timeout_qs: 65_535}}} =
             PollControl.decode(<<17, 7, 0, 0, 0xFF, 0xFF>>)

    assert {:ok, %{parameters: %{original_command: :fast_poll_stop, status: :success}}} =
             PollControl.decode(<<24, 7, 11, 1, 0>>)

    assert {:ok, %{parameters: %{original_command: :set_long_poll, status: {:error, 0x87}}}} =
             PollControl.decode(<<8, 7, 11, 2, 0x87>>)
  end

  test "unsupported extensions, reserved fields, wrong directions and incomplete payloads fail" do
    for bytes <- [
          nil,
          <<>>,
          <<25, 7>>,
          <<25, 7, 0, 0>>,
          <<25, 7, 1>>,
          <<0x1D, 0x34, 0x12, 7, 0>>,
          <<0xE9, 7, 0>>,
          <<8, 7, 0>>,
          <<1, 7, 0>>,
          <<1, 7, 0, 2, 0, 0>>,
          <<1, 7, 0, 0xFF, 0, 0>>,
          <<1, 7, 1, 0>>,
          <<1, 7, 2, 4, 0>>,
          <<1, 7, 2, 3::little-32>>,
          <<1, 7, 3, 0::16>>,
          <<1, 7, 3, 1::16, 0>>,
          <<1, 7, 4>>,
          <<8, 7, 11, 4, 0>>,
          <<0, 7, 11, 0, 0>>,
          <<9, 7, 11, 0, 0>>,
          :binary.copy(<<0>>, 129)
        ] do
      assert {:error, %Error{kind: :invalid_frame}} = PollControl.decode(bytes)
    end
  end

  test "a checked check-in retains source trust and the observed response window without sending" do
    {routes, event} = context(20_000)
    assert {:ok, observed} = PollControl.observe_checkin(routes, event, 11)
    assert observed.peer_ieee == @ieee
    assert observed.event == event
    assert observed.event.security_used == false
    assert observed.response_deadline_ms == 7_691
    assert observed.response_window == :open
    assert {:ok, %{response_window: :elapsed}} = PollControl.observe_checkin(routes, event, 7_691)

    {routes, event} = context(100)
    assert {:ok, %{response_deadline_ms: 110}} = PollControl.observe_checkin(routes, event, 11)
  end

  test "custody, epoch, source metadata and exact cluster command gate check-in observation" do
    {routes, event} = context(100)

    for copied <- [
          %{event | kind: :unknown_indication},
          %{event | cluster: 6},
          %{event | source_endpoint: 0},
          %{event | endpoint: 241},
          %{event | source_address: 0x3456},
          %{event | owner_epoch: make_ref()},
          %{event | owner_sequence: 0},
          %{event | payload: <<1, 7, 1>>},
          %{event | payload: <<0>>},
          Map.put(event, :key, "credential-canary")
        ] do
      assert {:error, %Error{} = error} = PollControl.observe_checkin(routes, copied, 11)
      refute inspect(error) =~ "credential-canary"
    end

    assert {:error, _} = PollControl.observe_checkin(routes, event, 110)
    assert {:error, _} = PollControl.observe_checkin(nil, event, 11)
    assert {:error, _} = PollControl.observe_checkin(routes, nil, 11)
  end

  defp context(lifetime) do
    epoch = make_ref()
    {:ok, routes} = Routes.new(epoch)

    proof = %Result{
      peer_ieee: @ieee,
      route_address: 0x1234,
      owner_epoch: epoch,
      outcome: :complete,
      identity_matches: true,
      steps: [
        %{
          stage: :identity,
          issues: [],
          admission: %Reply{subsystem: 5, id: 1, status: 0, payload: <<0>>},
          response: %Event{
            kind: :zdo_ieee_address,
            subsystem: 5,
            id: 0x81,
            payload: <<>>,
            owner_epoch: epoch,
            owner_sequence: 1,
            received_at_ms: 10,
            status: 0,
            zdo: %{status: 0, peer_ieee: @ieee, network_address: 0x1234}
          }
        }
      ]
    }

    {:ok, routes} = Routes.adopt(routes, proof, 10, lifetime)

    event = %Event{
      kind: :af_incoming,
      subsystem: 4,
      id: 0x81,
      payload: <<25, 7, 0>>,
      owner_epoch: epoch,
      owner_sequence: 2,
      received_at_ms: 11,
      source_address: 0x1234,
      source_endpoint: 1,
      endpoint: 2,
      cluster: 0x0020,
      security_used: false
    }

    {routes, event}
  end
end
