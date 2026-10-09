defmodule Wotex.Zigbee.BackupBoundaryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Zigbee
  alias Wotex.Zigbee.{Command, Config, Error, Frame, Owner, TestSerialPeer}

  @profile Path.expand("../../support/profiles/znp-persistence-review-mt-r1.14.json", __DIR__)

  test "source-pinned raw NV and identity mutation vectors are outside ordinary admission" do
    for vector <- profile()["review"]["raw_requests"] do
      bytes = Base.decode16!(vector["hex"], case: :mixed)
      assert {:ok, [frame], <<>>, 0} = Frame.feed(<<>>, bytes)
      assert frame.type == :sreq and frame.subsystem == 1 and frame.id == vector["id"]
      refute Command.admitted?(frame)
      assert {:ok, ^bytes} = Frame.encode(frame)
    end
  end

  test "valid raw persistence layouts and private bytes cannot bypass receiver admission" do
    {:ok, config} =
      Config.new(
        serial: TestSerialPeer,
        device_id: "simulated-coordinator",
        expected_version: {2, 0, 3, 2, 0},
        serial_options: [test_pid: self()]
      )

    {:ok, handle} = Zigbee.open(config)
    on_exit(fn -> Zigbee.close(handle) end)
    assert_receive {:serial_open, _, _}
    assert_receive {:serial_write, <<0xFE, 0, 0x21, 2, 0x23>>}
    private = :crypto.strong_rand_bytes(16)
    value = <<1, private::binary>>

    raw =
      for vector <- profile()["review"]["raw_requests"] do
        {:ok, [frame], <<>>, 0} = Frame.feed(<<>>, Base.decode16!(vector["hex"], case: :mixed))
        frame
      end

    writes =
      for vector <- profile()["review"]["transient_write_layouts"] do
        %Frame{
          type: :sreq,
          subsystem: 1,
          id: vector["id"],
          payload: Base.decode16!(vector["prefix_hex"], case: :mixed) <> value
        }
      end

    reset = %Frame{type: :areq, subsystem: 1, id: 0, payload: <<1>>}

    for frame <- [reset | raw ++ writes] do
      assert {:ok, _} = Frame.encode(frame)

      assert {:error, %Error{kind: :invalid_command} = error} =
               Owner.call(handle, :command, [frame, 100])

      assert :binary.match(:erlang.term_to_binary(error), private) == :nomatch
    end

    refute_receive {:serial_write, _}, 10
    assert :binary.match(:erlang.term_to_binary(:sys.get_state(handle.owner)), private) == :nomatch

    assert :binary.match(:erlang.term_to_binary(Process.info(handle.owner, :dictionary)), private) ==
             :nomatch

    assert {:ok, %{events: [], dropped: 0}} = Zigbee.drain_events(handle, 32)
    assert {:ok, %{status: 0}} = Zigbee.active_endpoints(handle, 0x1234, 100)
    assert_receive {:serial_write, <<0xFE, 4, 0x25, 5, 0x34, 0x12, 0x34, 0x12, 0x24>>}
  end

  defp profile, do: :json.decode(File.read!(@profile))
end
