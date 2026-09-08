defmodule Wotex.Lab.MetricsGatewayTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{Gateway, History, Query, Request, Snapshot}

  @scope %{instance: "inspection", session: "server-session"}
  @request %{
    "schema_version" => "1.0.0",
    "metric" => "nx_queue_depth",
    "aggregation" => "last",
    "filters" => %{"profile" => "test"},
    "start_at" => "2026-01-01T00:00:00Z",
    "end_at" => "2026-01-01T00:00:10Z",
    "step_ms" => 5_000
  }

  setup do
    history = start_supervised!({History, instance: @scope.instance})
    {:ok, %{history: history}}
  end

  defp gateway(history, opts \\ []) do
    start_supervised!(
      {Gateway, Keyword.merge([history: history, scope: @scope, owner: self()], opts)}
    )
  end

  defp store(history, offset, value) do
    {:ok, snapshot} =
      Snapshot.new(%{
        source: :collector,
        instance_slot: 0,
        sequence: div(offset, 5_000) + 1,
        monotonic_ms: offset,
        wall_time_ms: 1_767_225_600_000 + offset,
        identity: %{started_at: 1, generation: 0},
        series: [
          %{
            name: "wotex_lab_nx_queue_depth",
            type: :gauge,
            labels: [{"profile", "test"}],
            sample: %{value: value}
          }
        ]
      })

    assert {:ok, _} = History.put(history, snapshot)
  end

  defp workers(gateway, history, owner) do
    {:monitors, monitors} = Process.info(gateway, :monitors)
    for {:process, pid} <- monitors, pid not in [history, owner], do: pid
  end

  test "request fields are closed and scope, budgets and all enums stay server-bound" do
    assert {:ok, query} = Request.decode(@request, @scope, %{})
    assert query.scope == @scope and query.filters == %{profile: :test}
    assert query.limits == Query.default_limits()

    invalid = [
      nil,
      [],
      query,
      Map.put(@request, "schema_version", "2.0.0"),
      Map.put(@request, "metric", "secret-sentinel"),
      Map.put(@request, "aggregation", "SELECT * FROM private"),
      Map.put(@request, "scope", %{instance: "other", session: "other"}),
      Map.put(@request, "limits", %{deadline_ms: 30_000}),
      Map.put(@request, "endpoint", "https://secret-sentinel.invalid"),
      Map.put(@request, "filters", %{"profile" => "secret-sentinel"}),
      Map.put(@request, "filters", %{"profile" => %{"nested" => []}}),
      Map.put(@request, "start_at", "2026-01-01T00:00:00+01:00"),
      Map.put(@request, "start_at", <<255, 0, 1>>),
      Map.put(@request, "end_at", String.duplicate("0", 1_000_000)),
      Map.put(@request, :metric, :nx_queue_depth),
      Map.delete(@request, "step_ms")
    ]

    for input <- invalid do
      assert {:error, %Error{} = error} = Request.decode(input, @scope, %{})
      refute inspect(error) =~ "secret-sentinel"
    end

    assert {:error, %Error{code: :invalid_filter}} =
             Request.decode(Map.put(@request, "filters", %{"operation" => "encode"}), @scope, %{})

    histogram =
      Map.merge(@request, %{
        "metric" => "nx_duration_seconds",
        "aggregation" => "histogram_quantile",
        "quantile" => 0.95
      })

    assert {:ok, %{quantile: 0.95}} = Request.decode(histogram, @scope, %{})
  end

  test "real queries retain missing/stale/zero, provenance and the bound query digest", %{
    history: history
  } do
    store(history, 0, 0)
    store(history, 5_000, :stale)
    access = gateway(history)
    assert {:ok, reference} = Gateway.query(access, @request)
    assert_receive {:metric_query, ^access, ^reference, {:ok, answer}}, 1_000
    assert answer.source == :ets_history and answer.instance == @scope.instance
    assert Enum.map(answer.points, & &1.value) == [0]
    assert Enum.any?(answer.markers, &(&1.kind == :stale))
    assert answer.unit == :count and answer.evidence == []
    assert {:ok, descriptor} = Request.decode(@request, @scope, %{})
    assert answer.digest == Query.digest(descriptor)
    assert %{admitted: 1, completed: 1, active: 0, max_calls: 12} = Gateway.stats(access)
    refute inspect(Gateway.stats(access)) =~ @scope.session
    refute_receive {:metric_query, ^access, ^reference, _}, 30
    assert :ok = Gateway.revoke(access)
    refute Process.alive?(access)
    assert {:error, %Error{code: :scope_unavailable}} = Gateway.query(access, @request)
    assert History.stats(history).count == 2
  end

  test "no data and unsupported queries are distinct and failed calls consume budget", %{
    history: history
  } do
    access = gateway(history, max_calls: 2)
    assert {:ok, reference} = Gateway.query(access, @request)
    assert_receive {:metric_query, ^access, ^reference, {:ok, %{points: [], freshness: nil}}}
    assert {:ok, reference} = Gateway.query(access, Map.put(@request, "aggregation", "rate"))
    assert_receive {:metric_query, ^access, ^reference, {:error, %Error{code: :unsupported_query}}}
    assert {:error, %Error{code: :query_budget_exhausted}} = Gateway.query(access, @request)
    assert %{admitted: 2, completed: 1, failed: 1, active: 0} = Gateway.stats(access)
  end

  test "another process cannot use, inspect, cancel or revoke a copied capability", %{
    history: history
  } do
    access = gateway(history)

    Task.async(fn ->
      for result <- [
            Gateway.query(access, @request),
            Gateway.stats(access),
            Gateway.cancel(access, make_ref()),
            Gateway.revoke(access)
          ] do
        assert {:error, %Error{code: :scope_denied}} = result
      end
    end)
    |> Task.await()

    assert %{admitted: 0} = Gateway.stats(access)
    wrong = gateway(history, scope: %{instance: "other-instance", session: @scope.session})
    assert {:ok, reference} = Gateway.query(wrong, @request)
    assert_receive {:metric_query, ^wrong, ^reference, {:error, %Error{code: :scope_denied}}}
  end

  test "capacity refusal has no accepted-work queue; cancellation kills workers", %{
    history: history
  } do
    access = gateway(history, max_calls: 2)
    :sys.suspend(history)

    try do
      assert {:ok, first} = Gateway.query(access, @request)
      assert {:ok, second} = Gateway.query(access, @request)
      assert {:error, %Error{code: :query_budget_exhausted}} = Gateway.query(access, @request)
      pending = workers(access, history, self())
      assert length(pending) == 2
      assert :ok = Gateway.cancel(access, first)
      assert_receive {:metric_query, ^access, ^first, {:error, %Error{code: :query_cancelled}}}
      assert :ok = Gateway.cancel(access, second)
      assert_receive {:metric_query, ^access, ^second, {:error, %Error{code: :query_cancelled}}}
      assert Enum.all?(pending, &(not Process.alive?(&1)))
      assert {:error, %Error{code: :unknown_query}} = Gateway.cancel(access, first)
      send(access, {:query_result, hd(pending), first, {:ok, %{late: true}}})
      send(access, {:deadline, first})
      assert %{admitted: 2, cancelled: 2, active: 0} = Gateway.stats(access)
      refute_receive {:metric_query, ^access, ^first, _}, 30
    after
      :sys.resume(history)
    end

    assert History.stats(history).active_queries == 0
    assert :ok = Gateway.revoke(access)
  end

  test "query deadline includes a blocked history call and stops it", %{history: history} do
    access = gateway(history, query_limits: %{deadline_ms: 50, concurrent: 1})
    :sys.suspend(history)

    try do
      assert {:ok, reference} = Gateway.query(access, @request)
      assert {:error, %Error{code: :too_many_queries}} = Gateway.query(access, @request)
      [worker] = workers(access, history, self())

      assert_receive {:metric_query, ^access, ^reference,
                      {:error, %Error{code: :deadline_exceeded}}},
                     1_000

      refute Process.alive?(worker)
      assert %{timed_out: 1, active: 0} = Gateway.stats(access)
    after
      :sys.resume(history)
    end

    assert History.stats(history).active_queries == 0
  end

  test "scope expiry and explicit revocation terminate pending work", %{history: history} do
    for expiry <- [false, true] do
      access = gateway(history, ttl_ms: if(expiry, do: 100, else: 30_000))
      monitor = Process.monitor(access)
      :sys.suspend(history)

      try do
        assert {:ok, reference} = Gateway.query(access, @request)
        [worker] = workers(access, history, self())
        if not expiry, do: assert(:ok = Gateway.revoke(access))
        assert_receive {:metric_query, ^access, ^reference, {:error, %Error{code: code}}}, 1_000
        assert code in [:scope_revoked, :scope_expired, :deadline_exceeded]
        assert_receive {:DOWN, ^monitor, :process, ^access, :normal}, 1_000
        refute Process.alive?(worker)
        assert {:error, %Error{code: :scope_unavailable}} = Gateway.stats(access)
      after
        :sys.resume(history)
      end
    end

    assert History.stats(history).active_queries == 0
  end

  test "owner death, history replacement and brutal gateway death leave no workers", %{
    history: history
  } do
    parent = self()

    owner =
      spawn(fn ->
        receive do
          {:query, access} ->
            send(parent, {:admitted, Gateway.query(access, @request)})
            receive do: (:stop -> :ok)
        end
      end)

    access = gateway(history, owner: owner)
    monitor = Process.monitor(access)
    :sys.suspend(history)

    try do
      send(owner, {:query, access})
      assert_receive {:admitted, {:ok, _reference}}
      [worker] = workers(access, history, owner)
      send(owner, :stop)
      assert_receive {:DOWN, ^monitor, :process, ^access, :normal}
      refute Process.alive?(worker)
    after
      :sys.resume(history)
    end

    access = gateway(history)
    monitor = Process.monitor(access)
    stop_supervised!({History, :default})
    assert_receive {:DOWN, ^monitor, :process, ^access, :normal}
    replacement = start_supervised!({History, instance: @scope.instance})
    assert {:error, %Error{code: :scope_unavailable}} = Gateway.query(access, @request)
    access = gateway(replacement)
    :sys.suspend(replacement)

    try do
      assert {:ok, _reference} = Gateway.query(access, @request)
      [worker] = workers(access, replacement, self())
      monitor = Process.monitor(worker)
      Process.exit(access, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
    after
      :sys.resume(replacement)
    end
  end

  test "gateway config is closed, local, bounded and cannot enlarge query defaults", %{
    history: history
  } do
    defaults = [history: history, owner: self(), scope: @scope]

    for invalid <- [
          [ttl_ms: 60_001],
          [ttl_ms: 0],
          [max_calls: 129],
          [max_calls: 0],
          [history: :registered_name],
          [owner: nil],
          [scope: %{instance: "secret-sentinel"}],
          [query_limits: %{concurrent: 3}],
          [query_limits: %{min_step_ms: 1_000}],
          [query_limits: %{deadline_ms: 2_001}],
          [endpoint: "secret-sentinel"],
          [query_limits: %{output_bytes: 1_048_577}]
        ] do
      assert {:error, %Error{code: :invalid_gateway} = error} =
               Gateway.start_link(Keyword.merge(defaults, invalid))

      refute inspect(error) =~ "secret-sentinel"
    end

    assert {:error, %Error{code: :invalid_gateway}} = Gateway.start_link(nil)
    assert {:error, %Error{code: :scope_unavailable}} = Gateway.stats(:unknown)
    assert %{restart: :temporary} = Gateway.child_spec(defaults)
    limited = gateway(history, query_limits: %{points: 1})
    assert {:error, %Error{code: :query_too_large}} = Gateway.query(limited, @request)
    assert %{admitted: 0} = Gateway.stats(limited)
  end

  test "time spent waiting for gateway admission is not a fresh worker deadline", %{
    history: history
  } do
    parent = self()

    owner =
      spawn(fn ->
        receive do
          {:query, access} ->
            send(parent, :submitting)
            send(parent, {:admission, Gateway.query(access, @request)})
            receive do: (:stop -> :ok)
        end
      end)

    on_exit(fn -> Process.exit(owner, :kill) end)
    access = gateway(history, owner: owner, query_limits: %{deadline_ms: 30})
    :sys.suspend(access)
    send(owner, {:query, access})
    assert_receive :submitting
    Process.sleep(80)
    :sys.resume(access)
    assert_receive {:admission, {:error, %Error{code: :deadline_exceeded}}}
    send(owner, :stop)
    assert History.stats(history).active_queries == 0
  end

  test "worker crashes are a typed failure and do not crash the capability", %{history: history} do
    access = gateway(history)
    :sys.suspend(history)

    try do
      assert {:ok, reference} = Gateway.query(access, @request)
      [worker] = workers(access, history, self())
      Process.exit(worker, :kill)
      assert_receive {:metric_query, ^access, ^reference, {:error, %Error{code: :query_failed}}}
      assert %{active: 0, failed: 1} = Gateway.stats(access)
      assert {:error, %Error{code: :invalid_request}} = Gateway.cancel(access, "not-a-reference")
    after
      :sys.resume(history)
    end
  end
end
