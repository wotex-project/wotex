defmodule Wotex.Lab.CookbookRunnerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Test.CookbookRunner

  @moduletag capture_log: true

  test "a completed run reclaims unlinked processes and handlers but not caller resources" do
    caller_handler = "caller-owned-#{System.unique_integer([:positive])}"
    ignore = fn _, _, _, _ -> :ok end
    :ok = :telemetry.attach(caller_handler, [:lifecycle_fixture, :caller], ignore, nil)
    on_exit(fn -> :telemetry.detach(caller_handler) end)
    caller_process = spawn(fn -> receive do: (:release -> :ok) end)
    on_exit(fn -> Process.exit(caller_process, :kill) end)

    assert {:ok, outcome} =
             CookbookRunner.run_fixture("lifecycle-leaks",
               timeout: 5_000,
               binding: [lab: caller_process]
             )

    assert outcome.cells == 4
    assert outcome.leaked == 1
    assert outcome.reclaimed == %{processes: 6, handlers: 2}
    assert Enum.all?(outcome.result.processes, &(not Process.alive?(&1)))

    handlers = attached_ids()
    assert Enum.all?(outcome.result.handlers, &(&1 not in handlers))
    refute outcome.result.detached_handler in handlers
    assert caller_handler in handlers
    assert Process.alive?(caller_process)
  end

  test "overlapping runs reclaim only their own resources" do
    outcomes =
      [1, 2]
      |> Task.async_stream(
        fn _ -> CookbookRunner.run_fixture("lifecycle-leaks", timeout: 5_000) end,
        max_concurrency: 2,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, {:ok, outcome}} -> outcome end)

    assert Enum.map(outcomes, & &1.reclaimed) == [
             %{processes: 6, handlers: 2},
             %{processes: 6, handlers: 2}
           ]

    [first, second] = Enum.map(outcomes, & &1.result.handlers)
    assert MapSet.disjoint?(MapSet.new(first), MapSet.new(second))
  end

  test "a timed-out run is stopped and its resources are reclaimed" do
    started = System.monotonic_time(:millisecond)

    assert {:error, %{kind: :timeout, reason: 300, reclaimed: reclaimed}} =
             CookbookRunner.run_fixture("lifecycle-timeout",
               timeout: 300,
               binding: [observer: self()]
             )

    assert System.monotonic_time(:millisecond) - started < 5_000
    assert_received {:timeout_fixture, unlinked, handler}
    assert reclaimed == %{processes: 1, handlers: 1}
    refute Process.alive?(unlinked)
    refute handler in attached_ids()
  end

  test "raised cells and evaluator exits still reclaim run processes" do
    assert {:error, %{cell: 2, kind: :error, reason: %ArgumentError{}, reclaimed: reclaimed}} =
             CookbookRunner.run_fixture("lifecycle-raise",
               timeout: 5_000,
               binding: [observer: self()]
             )

    assert_received {:raise_fixture, raised}
    assert reclaimed == %{processes: 1, handlers: 0}
    refute Process.alive?(raised)

    assert {:error, %{cell: nil, kind: :exit, reason: :killed, reclaimed: reclaimed}} =
             CookbookRunner.run_fixture("lifecycle-exit",
               timeout: 5_000,
               binding: [observer: self()]
             )

    assert_received {:exit_fixture, exited}
    assert reclaimed == %{processes: 1, handlers: 0}
    refute Process.alive?(exited)
  end

  test "only checked-in fixture names are accepted" do
    for name <- ["../cookbooks/lifecycle-leaks", "Lifecycle", ""] do
      assert_raise MatchError, fn -> CookbookRunner.run_fixture(name, timeout: 100) end
    end
  end

  defp attached_ids, do: Enum.map(:telemetry.list_handlers([]), & &1.id)
end
