defmodule Wotex.Runtime.SubscriptionOpeningTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias Wotex.Runtime.{ConsumedThing, Context, Subscription, SubscriptionOpening}
  alias Wotex.Runtime.Test.{OpeningPort, TDFactory}

  test "WRT.01-12 receiver death interrupts pending transport establishment" do
    {owner, receiver} = start_opening()
    assert_receive {:opening, callback, ^owner, resource}
    monitor = Process.monitor(owner)
    Process.exit(receiver, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, :receiver_down}}, 500
    eventually(fn -> not Process.alive?(callback) and not Process.alive?(resource) end)
    refute_receive {:wotex_runtime, :pending, {:ok, _ignored_1, _ignored_2}}, 10
  end

  test "WRT.01-12 receiver death interrupts credential resolution before transport acquisition" do
    {owner, receiver} = start_opening(credential_wait: true)
    assert_receive {:credential_wait, callback}
    monitor = Process.monitor(owner)
    Process.exit(receiver, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, :receiver_down}}, 500
    eventually(fn -> not Process.alive?(callback) end)
    refute_receive {:opening, _ignored_3, _ignored_4, _ignored_5}, 10
  end

  test "WRT.01-10 explicit stop interrupts pending open without a provisional handle" do
    {owner, _ignored_6} = start_opening(monitor_owner: false)
    assert_receive {:opening, callback, ^owner, resource}
    monitor = Process.monitor(owner)
    assert :ok = Subscription.stop(owner, 1000)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 500
    eventually(fn -> not Process.alive?(callback) and not Process.alive?(resource) end)
    refute_received {:opening_unsubscribe, _ignored_7}
  end

  @tag capture_log: true
  test "WRT.01-10 forced owner and guardian death release the blocked worker and its links" do
    for target <- [:owner, :guardian] do
      {owner, _ignored_8} = start_opening(monitor_owner: false)
      assert_receive {:opening, callback, ^owner, resource}
      opening = :sys.get_state(owner).opening
      monitor = Process.monitor(owner)
      Process.exit(if(target == :owner, do: owner, else: opening.pid), :kill)
      assert_receive {:DOWN, ^monitor, :process, ^owner, _ignored_9}, 500

      eventually(fn ->
        not Process.alive?(callback) and not Process.alive?(resource) and
          not Process.alive?(opening.pid)
      end)
    end
  end

  test "WRT.01-12 completed handoff racing receiver death unsubscribes exactly once" do
    for _ignored_10 <- 1..25 do
      {owner, receiver} = start_opening()
      assert_receive {:opening, callback, ^owner, resource}
      opening = :sys.get_state(owner).opening
      :sys.suspend(owner)
      Process.exit(receiver, :kill)
      send(callback, :release)
      eventually(fn -> :sys.get_state(opening.pid).result != :pending end)
      :sys.resume(owner)
      monitor = Process.monitor(owner)
      assert_receive {:DOWN, ^monitor, :process, ^owner, _ignored_11}, 500
      assert_receive {:opening_unsubscribe, ^resource}, 500
      refute_received {:opening_unsubscribe, ^resource}
      eventually(fn -> not Process.alive?(callback) and not Process.alive?(resource) end)
    end
  end

  test "WRT.01-13 early frames wait for establishment and decode only in the Runtime owner" do
    {owner, _ignored_12} = start_opening(early: [0, 0])
    assert_receive {:opening, callback, ^owner, resource}
    refute_receive {:opening_decoded, _ignored_13, _ignored_14}, 10
    refute_receive {:wotex_runtime, _ignored_15, {:ok, _ignored_16, _ignored_17}}, 10
    send(owner, {:wotex_opening, make_ref(), :ready})
    send(callback, :release)

    for _ignored_18 <- 1..2 do
      assert_receive {:opening_decoded, ^owner, 0}
      assert_receive {:wotex_runtime, _ignored_19, {:ok, 0, %{source: :opening_fixture}}}
    end

    assert Process.alive?(callback)
    opening = :sys.get_state(owner).opening
    refute inspect(:sys.get_status(opening.pid)) =~ "OPENING_CREDENTIAL_CANARY"
    refute inspect(:sys.get_state(owner)) =~ "OPENING_CREDENTIAL_CANARY"
    assert :ok = Subscription.stop(owner)
    assert_receive {:opening_unsubscribe, ^resource}
    eventually(fn -> not Process.alive?(callback) and not Process.alive?(opening.pid) end)
  end

  test "WRT.01-12 early frame admission is bounded and overflow cannot establish later" do
    {owner, _ignored_20} = start_opening(early: Enum.to_list(1..65), monitor_owner: false)
    assert_receive {:opening, callback, ^owner, resource}
    monitor = Process.monitor(owner)
    assert_receive {:DOWN, ^monitor, :process, ^owner, _ignored_21}, 500
    refute_received {:opening_decoded, _ignored_22, _ignored_23}
    eventually(fn -> not Process.alive?(callback) and not Process.alive?(resource) end)
    send(callback, :release)
    refute_receive {:wotex_runtime, _ignored_24, {:ok, _ignored_25, _ignored_26}}, 10
  end

  test "WRT.01-12 linked transport exits retain their established Runtime ownership" do
    {owner, _ignored_27} = start_opening(monitor_owner: false)
    assert_receive {:opening, callback, ^owner, resource}
    send(callback, :release)
    send(owner, {:wotex_transport_frame, {:value, false}})
    assert_receive {:opening_decoded, ^owner, false}
    assert_receive {:wotex_runtime, _ignored_28, {:ok, false, _ignored_29}}
    monitor = Process.monitor(owner)
    Process.exit(resource, :connection_reset)
    assert_receive {:wotex_runtime, _ignored_30, {:status, :transport_down}}
    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, :transport_down}}, 500
    assert_receive {:opening_unsubscribe, ^resource}
    eventually(fn -> not Process.alive?(callback) end)
  end

  test "WRT.01-12 handoff tokens cannot be claimed or canceled by another caller" do
    {owner, _ignored_31} = start_opening()
    assert_receive {:opening, callback, ^owner, resource}
    opening = :sys.get_state(owner).opening
    assert :none = SubscriptionOpening.claim(opening)
    assert :none = SubscriptionOpening.cancel(opening)
    send(opening.pid, {:opening_result, make_ref(), {:ok, :forged}})
    send(opening.pid, :unrelated)
    send(callback, :release)
    send(owner, {:wotex_transport_frame, {:value, 1}})
    assert_receive {:opening_decoded, ^owner, 1}
    assert :none = SubscriptionOpening.claim(opening)
    send(callback, :unrelated)
    send(callback, {:EXIT, self(), :normal})
    assert :ok = Subscription.stop(owner)
    assert_receive {:opening_unsubscribe, ^resource}
    eventually(fn -> not Process.alive?(opening.pid) end)
    assert :none = SubscriptionOpening.cancel(opening)
  end

  test "WRT.01-12 a killed callback terminates pending establishment and linked resources" do
    {owner, _ignored_32} = start_opening(monitor_owner: false)
    assert_receive {:opening, callback, ^owner, resource}
    monitor = Process.monitor(owner)
    Process.exit(callback, :kill)
    assert_receive {:wotex_runtime, _ignored_33, {:status, :transport_down}}, 500
    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, :transport_down}}, 500
    eventually(fn -> not Process.alive?(resource) end)
    refute_received {:opening_unsubscribe, _ignored_34}
  end

  test "WRT.01-12 terminal control preempts buffered reconnection and decoded deliveries" do
    {owner, _ignored_35} = start_opening()
    assert_receive {:opening, callback, ^owner, resource}
    send(owner, {:wotex_transport_status, :reconnected})
    send(owner, {:wotex_transport, {:ok, 1, %{}}})
    send(owner, {:wotex_transport_status, :session_lost})
    assert_receive {:wotex_runtime, _ignored_36, {:status, :session_lost}}
    eventually(fn -> not Process.alive?(callback) and not Process.alive?(resource) end)
    refute_received {:wotex_runtime, _ignored_37, {:status, :reconnected}}
    refute_received {:wotex_runtime, _ignored_38, {:ok, _ignored_39, _ignored_40}}
  end

  test "WRT.01-12 cancel recovers a completed handle still queued behind the cancellation" do
    {owner, receiver} = start_opening()
    assert_receive {:opening, callback, ^owner, resource}
    opening = :sys.get_state(owner).opening
    :sys.suspend(opening.pid)
    Process.exit(receiver, :kill)

    eventually(fn ->
      {:messages, messages} = Process.info(opening.pid, :messages)
      Enum.any?(messages, &match?({:"$gen_call", _ignored_41, {_ignored_42, :cancel}}, &1))
    end)

    send(callback, :release)

    eventually(fn ->
      {:messages, messages} = Process.info(opening.pid, :messages)
      Enum.any?(messages, &match?({:opening_result, _ignored_43, _ignored_44}, &1))
    end)

    :sys.resume(opening.pid)
    assert_receive {:opening_unsubscribe, ^resource}, 500
    refute_received {:opening_unsubscribe, ^resource}
    eventually(fn -> not Process.alive?(owner) and not Process.alive?(callback) end)
  end

  test "WRT.01-12 established guardian loss ends its link endpoint and the Runtime owner" do
    {owner, _ignored_45} = start_opening(monitor_owner: false)
    assert_receive {:opening, callback, ^owner, resource}
    send(callback, :release)
    send(owner, {:wotex_transport_frame, {:value, 1}})
    assert_receive {:opening_decoded, ^owner, 1}
    opening = :sys.get_state(owner).opening
    GenServer.stop(opening.pid)
    assert_receive {:wotex_runtime, _ignored_46, {:status, :transport_down}}
    assert_receive {:opening_unsubscribe, ^resource}
    eventually(fn -> not Process.alive?(owner) and not Process.alive?(callback) end)
  end

  test "WRT.01-12 opening diagnostics redact result, message, reason and log" do
    canary = "OPENING_CREDENTIAL_CANARY"

    status = %{
      state: %{claimed?: false, result: canary},
      message: canary,
      reason: canary,
      log: [canary]
    }

    assert SubscriptionOpening.format_status(status) == %{
             state: %{claimed?: false, pending?: false},
             message: :redacted,
             reason: :redacted,
             log: []
           }
  end

  test "WRT.01-12 flushing early frames halts immediately at receiver overflow" do
    {owner, receiver} = start_opening(early: [1, 2], receiver_paused: true, receiver_limit: 1)
    assert_receive {:opening, callback, ^owner, resource}
    send(receiver, :queued)
    monitor = Process.monitor(owner)
    send(callback, :release)
    assert_receive {:opening_decoded, ^owner, 1}
    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, :overloaded}}, 500
    assert_receive {:opening_unsubscribe, ^resource}
    refute_received {:opening_decoded, ^owner, 2}
    eventually(fn -> not Process.alive?(callback) and not Process.alive?(resource) end)
  end

  defp start_opening(options \\ []) do
    profile = TDFactory.http_profile()
    config = Map.new([test_pid: self()] ++ options)

    {:ok, consumed} =
      ConsumedThing.new(TDFactory.thing_description(),
        profiles: [profile],
        transports: %{profile.id => {OpeningPort, config}},
        credentials: {OpeningPort, config}
      )

    parent = self()

    receiver =
      spawn(fn ->
        if config[:receiver_paused], do: receive(do: (:release -> :ok))
        receiver_loop(parent)
      end)

    {:ok, spec} =
      ConsumedThing.observation_child_spec(
        consumed,
        "temperature",
        Context.new!(request_id: "pending", deadline: System.monotonic_time(:millisecond) + 60_000),
        id: make_ref(),
        receiver: receiver,
        restart: :temporary,
        max_queue_length: Map.get(config, :receiver_limit, 1000),
        overflow: :stop
      )

    owner = start_supervised!(spec)

    on_exit(fn ->
      Process.exit(receiver, :kill)
      Process.exit(owner, :kill)
    end)

    {owner, receiver}
  end

  defp receiver_loop(parent) do
    receive do
      message ->
        send(parent, message)
        receiver_loop(parent)
    end
  end

  defp eventually(function, remaining \\ 50) do
    if function.() do
      :ok
    else
      assert remaining > 0
      Process.sleep(10)
      eventually(function, remaining - 1)
    end
  end
end
