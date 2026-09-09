defmodule Wotex.BACnet.CStackRuntimeLifecycleTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.BACnet.Test.CStackPeer
  @moduletag software: true, interop: true, capture_log: true
  @moduletag requirements: ["WBA-S05", "WBA-I05", "WBA-C03", "WBA-V12"]

  for {id, stopped} <- [
        {"WBA-CP22", :runtime_owner},
        {"WBA-CP23", :receiver},
        {"WBA-CP24", :opening_worker}
      ] do
    @tag corpus_case_id: id
    test "#{id} pending Runtime setup releases accepted C state after #{stopped} death" do
      before = CStackPeer.await(&(&1["active_subscribers"] == 0 and &1["active_invoke_ids"] == 0))
      receiver = spawn(fn -> receive do: (:stop -> :ok) end)
      on_exit(fn -> Process.exit(receiver, :kill) end)
      CStackPeer.control("fault register_ack 1")
      owner = start_supervised!(CStackPeer.runtime_spec(receiver))
      accepted = CStackPeer.await(&(&1["registrations"] == before["registrations"] + 1))
      assert accepted["property_subscribers"] == 1
      assert accepted["dropped_acks"] == before["dropped_acks"] + 1

      runtime = :sys.get_state(owner)
      assert runtime.handle == nil and runtime.active? == false
      opening = :sys.get_state(runtime.opening.pid)
      assert opening.result == :pending
      {:links, links} = Process.info(opening.worker, :links)

      [relay] =
        Enum.filter(links, fn pid ->
          is_pid(pid) and
            :proc_lib.translate_initial_call(pid) == {Wotex.BACnet.RuntimeRelay, :init, 1}
        end)

      relay_state = :sys.get_state(relay)
      assert relay_state.owner == owner and relay_state.phase == :opening
      assert relay_state.subscription == nil
      session = relay_state.session
      resources = CStackPeer.resources(session)
      operation = :sys.get_state(session.handle.stack.owner)
      [subscription] = Map.keys(operation.subscriptions)
      native = :sys.get_state(subscription)
      assert native.phase == :opening and not native.established
      timers = [native.control.timer, relay_state.opening_timer]
      assert Enum.all?(timers, &(Process.read_timer(&1) != false))

      processes =
        Enum.uniq(
          resources.processes ++
            [
              owner,
              runtime.opening.pid,
              opening.worker,
              relay,
              relay_state.worker,
              subscription,
              native.listener,
              native.control.worker
            ]
        )

      monitors = Enum.map(processes, &Process.monitor/1)
      socket_monitor = :erlang.monitor(:port, resources.socket)
      targets = %{runtime_owner: owner, receiver: receiver, opening_worker: opening.worker}
      started = System.monotonic_time(:millisecond)
      Process.exit(targets[unquote(stopped)], :kill)

      for monitor <- monitors do
        remaining = max(started + 1100 - System.monotonic_time(:millisecond), 0)
        assert_receive {:DOWN, ^monitor, :process, _, _}, remaining
      end

      remaining = max(started + 1100 - System.monotonic_time(:millisecond), 0)
      assert_receive {:DOWN, ^socket_monitor, :port, _, _}, remaining
      assert System.monotonic_time(:millisecond) - started <= 1100
      assert Enum.all?(timers, &(Process.read_timer(&1) == false))
      assert :erlang.port_info(resources.socket) == :undefined
      closed = CStackPeer.await(&(&1["active_subscribers"] == 0 and &1["active_invoke_ids"] == 0))
      assert closed["cancellations"] == before["cancellations"] + 1
      assert closed["registrations"] == before["registrations"] + 1
      assert closed["dropped_acks"] == before["dropped_acks"] + 1
    end
  end
end
