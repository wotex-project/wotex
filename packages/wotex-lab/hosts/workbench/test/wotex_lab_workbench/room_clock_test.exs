defmodule WotexLabWorkbench.RoomClockTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Continuum.{Channel, Host}
  alias WotexContinuum.{ActionResult, Codec}
  alias WotexLabWorkbench.{Experiments, Room, Sessions}
  alias WotexLabWorkbench.Test.{ModbusRoom, ScriptedModbusPeer}

  test "observation, result and delivery times stay in the owning room's UTC window" do
    before = DateTime.add(DateTime.utc_now(), -1, :second)
    lab = start_supervised!({Wotex.Lab, id: "room-clock", max_children: 32})
    peer = ScriptedModbusPeer.start(lose_ack: false)

    options = [
      lab: lab,
      ttl_ms: 60_000,
      sweep_ms: 50,
      max_sessions: 1,
      room_profiles: [ModbusRoom.profile(peer)],
      name: __MODULE__.Registry
    ]

    registry = start_supervised!({Sessions, options})
    {:ok, session} = Sessions.open(registry)
    {:ok, session} = Sessions.admit(registry, session.token, {:start_room, "zone"})
    state = :sys.get_state(session.room)
    {:ok, experiment} = Experiments.fetch("smart_room")
    {:ok, params} = Experiments.admit(experiment, %{})
    {:ok, run} = Room.start_run(session.room, experiment.id, params)
    decision = run.decision

    approval = %{
      "decision_id" => decision["id"],
      "proposal_digest" => decision["proposal_digest"],
      "revision" => Integer.to_string(decision["state_revision"]),
      "expires_at" => Integer.to_string(decision["expires_at"])
    }

    assert {:ok, %{status: :dispatched}} = Room.approve(session.room, run.id, approval)
    eventually(fn -> length(Host.stats(state.host).received) == 3 end)
    host = Host.stats(state.host)
    assert map_size(host.observations) == 2

    values =
      Enum.map(:sys.get_state(state.channel).items, fn {_, item} ->
        assert {:ok, value} = Codec.decode(item.wire)
        value
      end)

    assert [%ActionResult{status: :succeeded} = result] =
             Enum.filter(values, &is_struct(&1, ActionResult))

    after_time = DateTime.add(DateTime.utc_now(), 1, :second)

    timestamps =
      Enum.map(host.observations, fn {_, observation} -> observation.observed_at end) ++
        [result.completed_at] ++
        Enum.flat_map(Channel.deliveries(state.channel), &[&1.emitted_at, &1.acknowledged_at])

    for timestamp <- Enum.reject(timestamps, &is_nil/1) do
      assert {:ok, at, 0} = DateTime.from_iso8601(timestamp)
      assert DateTime.compare(at, before) in [:eq, :gt], timestamp
      assert DateTime.compare(at, after_time) in [:eq, :lt], timestamp
    end
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end
end
