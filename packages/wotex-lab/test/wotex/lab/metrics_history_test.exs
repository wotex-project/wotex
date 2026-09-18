defmodule Wotex.Lab.MetricsHistoryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab
  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{History, Snapshot}

  defp snapshot(sequence, opts \\ []) do
    counter = %{
      name: "wotex_lab_nx_operations_total",
      type: :counter,
      labels: [{"profile", "test"}],
      sample: %{value: Keyword.get(opts, :value, sequence)}
    }

    {:ok, snapshot} =
      Snapshot.new(%{
        source: :collector,
        instance_slot: 0,
        sequence: sequence,
        monotonic_ms: sequence * 1_000,
        wall_time_ms: 1_700_000_000_000 + sequence * 1_000,
        identity: %{started_at: 1, generation: Keyword.get(opts, :generation, 0)},
        series: [counter | Keyword.get(opts, :extra, [])]
      })

    snapshot
  end

  test "admits snapshots in order, evicts the oldest at the count ceiling and counts the loss" do
    history = start_supervised!({History, id: :count, max_snapshots: 3})

    for sequence <- 1..5 do
      assert {:ok, %{sequence: ^sequence}} = History.put(history, snapshot(sequence))
    end

    stored = History.snapshots(history)
    assert Enum.map(stored, & &1.snapshot.sequence) == [3, 4, 5]
    assert Enum.all?(stored, &(not &1.gap and not &1.reset))

    stats = History.stats(history)
    assert stats.count == 3 and stats.evicted == 2 and stats.admitted == 5
    assert stats.oldest_wall_time_ms == 1_700_000_003_000
    assert stats.newest_wall_time_ms == 1_700_000_005_000
    assert stats.bytes > 0 and stats.max_snapshots == 3
  end

  test "keeps encoded bytes under the byte budget and drops a snapshot larger than the whole budget" do
    small = snapshot(1)
    size = Snapshot.encoded_size(small)
    history = start_supervised!({History, id: :bytes, max_bytes: size * 2 + 10})

    assert {:ok, %{evicted: 0}} = History.put(history, small)
    assert {:ok, %{evicted: 0}} = History.put(history, snapshot(2))
    assert {:ok, %{evicted: 1}} = History.put(history, snapshot(3))
    assert History.stats(history).bytes <= size * 2 + 10

    padding = for index <- 1..64, do: %{(small.series |> hd()) | labels: [{"profile", "p#{index}"}]}
    huge = snapshot(4, extra: padding)
    assert {:error, %Error{code: :oversized_snapshot}} = History.put(history, huge)
    assert {:error, %Error{code: :invalid_snapshot}} = History.put(history, %{not: :a_snapshot})

    stats = History.stats(history)
    assert stats.dropped_oversized == 1 and stats.rejected == 1 and stats.count == 2
  end

  test "gaps and resets in the source stay visible on the stored rows" do
    history = start_supervised!({History, id: :gaps})
    {:ok, _} = History.put(history, snapshot(1))
    {:ok, _} = History.put(history, snapshot(2))
    {:ok, _} = History.put(history, snapshot(5))
    {:ok, _} = History.put(history, snapshot(1, generation: 1))
    {:ok, _} = History.put(history, snapshot(2, generation: 1))

    flags =
      history
      |> History.snapshots()
      |> Enum.map(&{&1.snapshot.sequence, &1.gap, &1.reset})

    assert flags == [
             {1, false, false},
             {2, false, false},
             {5, true, false},
             {1, false, true},
             {2, false, false}
           ]

    assert %{gaps: 1, resets: 1} = History.stats(history)
  end

  test "admission stays atomic under concurrent writers" do
    history = start_supervised!({History, id: :concurrent, max_snapshots: 10})

    tasks =
      for writer <- 1..25 do
        Task.async(fn ->
          for sequence <- 1..8 do
            {:ok, _} = History.put(history, snapshot(writer * 100 + sequence))
          end

          :ok
        end)
      end

    Enum.each(tasks, &Task.await/1)
    stats = History.stats(history)
    assert stats.count == 10 and stats.admitted == 200 and stats.evicted == 190
    assert length(History.snapshots(history)) == 10
  end

  test "two instances never share history and the store dies with its instance" do
    left = start_supervised!({Lab, id: "history-left", max_children: 2}, id: :left)
    right = start_supervised!({Lab, id: "history-right", max_children: 2}, id: :right)
    {:ok, left_history} = Lab.start_child(left, :sessions, {History, id: :h, max_snapshots: 2})
    {:ok, right_history} = Lab.start_child(right, :sessions, {History, id: :h, max_snapshots: 2})

    {:ok, _} = History.put(left_history, snapshot(1))
    {:ok, _} = History.put(left_history, snapshot(2))
    {:ok, _} = History.put(left_history, snapshot(3))

    assert History.stats(left_history).evicted == 1

    assert History.stats(right_history) |> Map.take([:count, :evicted, :admitted]) == %{
             count: 0,
             evicted: 0,
             admitted: 0
           }

    :ok = stop_supervised(:left)
    refute Process.alive?(left_history)
    assert Process.alive?(right_history)
    assert History.stats(right_history).count == 0
  end

  test "limits are explicit positive configuration with tested hard ceilings" do
    limits = History.limits()
    assert limits.default_snapshots == 120 and limits.default_bytes == 8 * 1_048_576
    assert {:error, %Error{code: :invalid_history}} = History.start_link(max_snapshots: 0)

    assert {:error, %Error{code: :invalid_history}} =
             History.start_link(max_snapshots: limits.max_snapshots + 1)

    assert {:error, %Error{code: :invalid_history}} =
             History.start_link(max_bytes: limits.max_bytes + 1)

    assert {:error, %Error{code: :invalid_history}} = History.start_link(max_bytes: "8MiB")
    assert {:error, %Error{code: :invalid_history}} = History.start_link(max_queries: 129)
    assert {:error, %Error{code: :invalid_history}} = History.start_link(instance_slot: -1)
    assert {:error, %Error{code: :invalid_history}} = History.start_link(instance: "Not an ID")
    assert {:error, %Error{code: :invalid_options}} = History.start_link(durable: true)
    assert %{id: {History, :h}, restart: :transient} = History.child_spec(id: :h)

    {:ok, named} = History.start_link(name: :wotex_lab_test_named_history)
    assert History.stats(named).max_snapshots == 120
    :ok = GenServer.stop(named)
  end

  test "slot substitution and forged snapshot structs are refused without mutating history" do
    history = start_supervised!({History, id: :admission, instance_slot: 7})
    assert {:error, %Error{code: :scope_denied}} = History.put(history, snapshot(1))
    admitted = %{snapshot(1) | instance_slot: 7}
    assert {:ok, _} = History.put(history, admitted)

    assert {:error, %Error{code: :invalid_snapshot}} =
             History.put(history, %{admitted | series: nil})

    assert %{count: 1, rejected: 2, instance_slot: 7} = History.stats(history)
    assert [%{snapshot: ^admitted}] = History.snapshots(history)
  end
end
