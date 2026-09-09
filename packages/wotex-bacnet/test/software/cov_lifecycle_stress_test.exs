defmodule Wotex.BACnet.COVLifecycleStressTest do
  @moduledoc false

  use ExUnit.Case, async: false
  alias Wotex.BACnet
  alias Wotex.BACnet.Test.CStackPeer
  @moduletag software: true, interop: true, capture_log: true, timeout: 120_000
  @moduletag requirements: ["WBA-S03", "WBA-S04", "WBA-C09", "WBA-V11", "WBA-V14"]
  @fixture Path.expand("../fixtures/cov_software_v1.json", __DIR__)
  @row Jason.decode!(File.read!(@fixture))["cases"] |> Enum.find(&(&1["id"] == "WBA-ST03"))

  test "WBA-ST03 WBA-C09 100 receiver deaths preserve an independent live COV association" do
    session = CStackPeer.connect()
    on_exit(fn -> BACnet.disconnect(session) end)
    resources = CStackPeer.resources(session)
    before = CStackPeer.await(&(&1["active_subscribers"] == 0 and &1["active_invoke_ids"] == 0))
    assert {:ok, held} = BACnet.subscribe(session, request(:cov_property, false, self()))
    held_reference = held.reference
    assert_receive {:wotex_bacnet, ^held_reference, {:ok, _, _}}, 1000
    held_state = :sys.get_state(held.pid)
    held_processes = [held.pid, held_state.listener]
    memory_before = memory(resources.processes ++ held_processes)
    parent = self()

    cycles =
      for index <- 0..(@row["input"]["receiver_death_cycles"] - 1) do
        type = if rem(index, 4) < 2, do: :cov, else: :cov_property
        confirmed = rem(index, 2) == 0
        receiver = spawn(fn -> relay(parent) end)

        try do
          assert {:ok, subscription} = BACnet.subscribe(session, request(type, confirmed, receiver))
          reference = subscription.reference
          assert_receive {:received, ^receiver, {:wotex_bacnet, ^reference, {:ok, _, _}}}, 1000
          state = :sys.get_state(subscription.pid)
          pids = [subscription.pid, state.listener]
          monitors = Enum.map(pids, &Process.monitor/1)
          timers = Enum.filter([state.expiry_timer, state.renew_timer], &is_reference/1)
          assert length(timers) == 2
          assert Enum.all?(timers, &(Process.read_timer(&1) != false))

          CStackPeer.await(&(&1["active_subscribers"] == 2 and &1["active_invoke_ids"] == 0))

          started = System.monotonic_time(:millisecond)
          Process.exit(receiver, :kill)
          for monitor <- monitors, do: assert_receive({:DOWN, ^monitor, :process, _, _}, 1100)
          local_elapsed = System.monotonic_time(:millisecond) - started

          assert local_elapsed <=
                   @row["expected"]["local_cleanup_budget_ms"] +
                     @row["expected"]["scheduler_tolerance_ms"]

          assert Enum.all?(timers, &(Process.read_timer(&1) == false))
          assert Enum.all?(held_processes, &Process.alive?/1)
          local = await_idle(session, 1)
          peer = CStackPeer.await(&(&1["active_subscribers"] == 1 and &1["active_invoke_ids"] == 0))
          assert peer["cancellations"] == before["cancellations"] + index + 1
          assert peer["registrations"] == before["registrations"] + index + 2
          assert peer["property_subscribers"] == 1 and peer["object_subscribers"] == 0

          %{
            index: index,
            mode: Enum.at(@row["input"]["modes"], rem(index, 4)),
            local_cleanup_ms: local_elapsed,
            local: local,
            captured_timers: length(timers),
            captured_timers_remaining: 0,
            subscription_processes_remaining: Enum.count(pids, &Process.alive?/1),
            tracked_memory: memory(resources.processes ++ held_processes),
            peer_max_rss_kib: peer["max_rss_kib"],
            peer_subscribers: peer["active_subscribers"],
            peer_invoke_ids: peer["active_invoke_ids"]
          }
        after
          Process.exit(receiver, :kill)
        end
      end

    assert Enum.frequencies_by(cycles, & &1.mode) ==
             Map.new(@row["input"]["modes"], &{&1, @row["expected"]["cycles_per_mode"]})

    memory_after = memory(resources.processes ++ held_processes)
    assert :ok = BACnet.unsubscribe(session, held)
    local_after = await_idle(session, 0)
    peer_after = CStackPeer.await(&(&1["active_subscribers"] == 0 and &1["active_invoke_ids"] == 0))
    CStackPeer.close(session, resources)
    assert Enum.count(resources.processes ++ held_processes, &Process.alive?/1) == 0

    result = %{
      case: "WBA-ST03",
      fixture_sha256: :crypto.hash(:sha256, File.read!(@fixture)) |> Base.encode16(case: :lower),
      cycles: cycles,
      tracked_memory_before: memory_before,
      tracked_memory_after: memory_after,
      local_before_close: local_after,
      peer_before: before,
      peer_after: peer_after,
      owned_processes_after_close: 0,
      owned_sockets_after_close: 0
    }

    directory = System.fetch_env!("WOTEX_BACNET_RESULTS_DIR")
    File.write!(Path.join(directory, "WBA-ST03.json"), Jason.encode!(result, pretty: true))
  end

  defp request(type, confirmed, receiver) do
    request = %{
      type: type,
      object_type: 1,
      instance: 1,
      device_instance: 123,
      confirmed: confirmed,
      lifetime: @row["input"]["lifetime_seconds"],
      renew: @row["input"]["renew"],
      receiver: receiver
    }

    if type == :cov_property, do: Map.put(request, :property, 85), else: request
  end

  defp relay(parent) do
    receive do
      message ->
        send(parent, {:received, self(), message})
        relay(parent)
    end
  end

  defp await_idle(session, subscriptions),
    do: await_idle(session, subscriptions, System.monotonic_time(:millisecond) + 1000)

  defp await_idle(session, subscriptions, deadline) do
    owner = :sys.get_state(session.handle.stack.owner)
    client = :sys.get_state(session.handle.stack.client)

    observed = %{
      pending_operations: map_size(owner.pending),
      pending_controls: map_size(owner.controls),
      subscriptions: map_size(owner.subscriptions),
      listeners: map_size(client.cov.filters),
      pending_apdus: map_size(client.sdk.apdu_timers),
      pending_cov_replies: map_size(client.cov.replies),
      cov_assemblies: map_size(client.cov.assemblies)
    }

    expected = %{
      pending_operations: 0,
      pending_controls: 0,
      subscriptions: subscriptions,
      listeners: subscriptions,
      pending_apdus: 0,
      pending_cov_replies: 0,
      cov_assemblies: 0
    }

    cond do
      observed == expected ->
        observed

      System.monotonic_time(:millisecond) >= deadline ->
        flunk(inspect(observed))

      true ->
        Process.sleep(1)
        await_idle(session, subscriptions, deadline)
    end
  end

  defp memory(pids) do
    values = Enum.map(pids, &Process.info(&1, [:memory, :total_heap_size]))

    %{
      process_bytes: Enum.sum(Enum.map(values, & &1[:memory])),
      heap_words: Enum.sum(Enum.map(values, & &1[:total_heap_size])),
      word_bytes: :erlang.system_info(:wordsize)
    }
  end
end
