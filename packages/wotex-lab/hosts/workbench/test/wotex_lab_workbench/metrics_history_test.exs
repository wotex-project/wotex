defmodule WotexLabWorkbench.MetricsHistoryTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{Exposition, History}
  alias WotexLabWorkbench.Observability.{Capture, Definitions, Relay, Sampler, Store}

  @promex WotexLabWorkbench.Observability.PromEx
  @host WotexLabWorkbench.Observability.Supervisor
  @stop [:wotex, :lab, :nx, :encode, :stop]

  test "public exposition carries matching reset identity, clocks and loss counters" do
    assert {:error, %Error{code: :collector_unavailable}} = Capture.sample()
    promex = start_supervised!(@promex)
    start_supervised!(Relay)
    store = store_child(promex)
    assert {:error, %Error{code: :scrape_superseded}} = Store.receipt(store, "")

    emit()
    :telemetry.execute(Definitions.event(:nx_operations_total), %{value: 2}, %{})
    assert {:ok, capture} = Capture.sample()
    assert {:ok, parsed} = Exposition.parse(PromEx.get_metrics(@promex))
    assert capture.series == parsed.series
    assert capture.source == :exposition and capture.instance_slot == 0
    assert capture.identity.generation == Store.stats(store).generation
    assert capture.counters.invalid_samples == 1
    assert capture.wall_time_ms > 0 and is_integer(capture.monotonic_ms)
    refute inspect(capture) =~ "secret-sentinel"

    assert {:error, %Error{code: :scrape_superseded}} = Store.receipt(store, "different")

    assert {:error, %Error{code: :invalid_scrape}} =
             Store.receipt(store, String.duplicate("x", 1_048_577))

    assert {:error, %Error{code: :collector_unavailable}} = Store.receipt(__MODULE__.Missing, "")

    stop_supervised!(@promex)
    start_supervised!(@promex)
    assert {:ok, fresh} = Capture.sample()
    assert fresh.series == [] and fresh.identity.generation > capture.identity.generation
  end

  test "failed capture is counted, not stored as zero, and the next row records the gap" do
    promex = start_supervised!(@promex)
    start_supervised!(Relay)
    history = start_supervised!({History, id: :gap, instance: "workbench"})
    sampler = start_supervised!({Sampler, history: history, interval_ms: 60_000})
    emit()
    assert {:ok, _} = Sampler.sample_now(sampler)
    [first] = History.snapshots(history)
    store = store_child(promex)
    :ok = :sys.suspend(store)

    try do
      assert {:error, %Error{code: :collector_unavailable}} = Sampler.sample_now(sampler)
    after
      :sys.resume(store)
    end

    assert History.snapshots(history) == [first]

    assert %{sequence: 2, stored: 1, failures: 1, last_error: :collector_unavailable} =
             Sampler.stats(sampler)

    emit()
    assert {:ok, _} = Sampler.sample_now(sampler)
    assert [_, %{gap: true, reset: false, snapshot: %{sequence: 3}}] = History.snapshots(history)
    assert %{sequence: 3, stored: 2, failures: 1, last_error: nil} = Sampler.stats(sampler)
    send(sampler, {:sample, make_ref()})
    assert Sampler.stats(sampler).sequence == 3
  end

  test "collector restart preserves reset and one-time stale markers in surviving history" do
    start_supervised!(@promex)
    start_supervised!(Relay)
    history = start_supervised!({History, id: :reset, instance: "workbench", max_snapshots: 2})
    sampler = start_supervised!({Sampler, history: history, interval_ms: 60_000})
    emit()
    assert {:ok, _} = Sampler.sample_now(sampler)
    stop_supervised!(@promex)
    start_supervised!(@promex)
    assert {:ok, _} = Sampler.sample_now(sampler)
    [_, second] = History.snapshots(history)
    assert second.reset

    assert Enum.all?(second.snapshot.series, fn series ->
             Map.get(series.sample, :stale, false) or Map.get(series.sample, :value) == :stale
           end)

    assert second.snapshot.series != []
    assert {:ok, %{evicted: 1}} = Sampler.sample_now(sampler)
    assert List.last(History.snapshots(history)).snapshot.series == []
    assert History.stats(history).count == 2
    stop_supervised!({History, :reset})
    assert {:error, %Error{code: :history_unavailable}} = Sampler.sample_now(sampler)
  end

  test "optional supervision owns periodic collection, history budgets and cleanup" do
    refute Process.whereis(@host.History)
    start_supervised!({@host, history: [interval_ms: 1_000, max_snapshots: 1]})
    sampler = Process.whereis(Sampler)
    history = Process.whereis(@host.History)
    assert is_pid(sampler) and is_pid(history)
    assert History.stats(history).instance == "workbench"
    assert History.stats(history).max_snapshots == 1
    await_samples(sampler, 2)
    assert History.stats(history).count == 1 and History.stats(history).evicted >= 1
    stop_supervised!(@host)
    refute Process.alive?(sampler)
    refute Process.alive?(history)
    refute Process.whereis(@promex)
  end

  test "history is opt-in and cannot activate without PromEx" do
    assert Application.fetch_env!(:wotex_lab_workbench, :metrics_history_enabled) == false
    start_supervised!(@host)
    refute Process.whereis(@host.History)
    refute Process.whereis(Sampler)
    stop_supervised!(@host)

    for opts <- [[history: nil], [history: [], interval_ms: 5_000], [history: [sink: :fake]]] do
      assert {:error, %Error{}} = @host.start_link(opts)
    end

    for opts <- [
          [history: nil],
          [history: self(), interval_ms: 0],
          [history: self(), interval_ms: 60_001]
        ] do
      assert {:error, %Error{code: :invalid_sampler}} = Sampler.start_link(opts)
    end

    assert {:error, %Error{code: :invalid_options}} = Sampler.start_link(sink: :fake)

    Application.put_env(:wotex_lab_workbench, :metrics_history_enabled, true)

    try do
      assert {:error, :metrics_history_requires_promex} =
               WotexLabWorkbench.Application.start(:normal, [])
    after
      Application.put_env(:wotex_lab_workbench, :metrics_history_enabled, false)
    end
  end

  defp emit do
    :telemetry.execute(@stop, %{duration: System.convert_time_unit(1, :millisecond, :native)}, %{
      outcome: :ok,
      profile: :test,
      scope: "secret-sentinel"
    })
  end

  defp store_child(supervisor) do
    Enum.find_value(Supervisor.which_children(supervisor), fn
      {_id, pid, :worker, [Store]} -> pid
      _child -> nil
    end)
  end

  defp await_samples(sampler, count, attempts \\ 400) do
    cond do
      Sampler.stats(sampler).stored >= count -> :ok
      attempts == 0 -> flunk("periodic capture did not reach history")
      true -> Process.sleep(10) && await_samples(sampler, count, attempts - 1)
    end
  end
end
