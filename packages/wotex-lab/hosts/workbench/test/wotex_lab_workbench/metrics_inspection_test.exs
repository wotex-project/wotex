defmodule WotexLabWorkbench.MetricsInspectionTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.Gateway
  alias WotexLabWorkbench.Observability.{Inspection, Sampler}

  @host WotexLabWorkbench.Observability.Supervisor

  test "disabled history cannot open a scope; activation captures and queries real PromEx data" do
    assert {:error, %Error{code: :inspection_unavailable}} = Inspection.open()
    assert {:error, %Error{code: :inspection_unavailable}} = Inspection.count()
    start_supervised!({@host, history: [interval_ms: 60_000]})
    assert Inspection.count() == 0
    assert {:ok, gateway} = Inspection.open()
    assert Inspection.count() == 1
    assert {:error, %Error{code: :inspection_active}} = Inspection.open()
    assert %{admitted: 0} = Gateway.stats(gateway)

    :telemetry.execute([:wotex, :lab, :nx, :encode, :stop], %{duration: 1_000}, %{
      profile: :test,
      outcome: :ok
    })

    assert {:ok, _} = Sampler.sample_now()
    now = DateTime.utc_now()

    request = %{
      "schema_version" => "1.0.0",
      "metric" => "nx_operations_total",
      "aggregation" => "sum",
      "start_at" => DateTime.to_iso8601(DateTime.add(now, -10, :second)),
      "end_at" => DateTime.to_iso8601(now),
      "step_ms" => 5_000
    }

    assert {:ok, reference} = Gateway.query(gateway, request)
    assert_receive {:metric_query, ^gateway, ^reference, {:ok, answer}}, 1_000
    assert answer.instance == "workbench" and answer.source == :ets_history
    assert Enum.sum(Enum.map(answer.points, & &1.value)) >= 1
    assert answer.digest =~ "sha256:" and answer.freshness != nil
    assert :ok = Gateway.revoke(gateway)
    assert Inspection.count() == 0
    assert {:ok, replacement} = Inspection.open()
    assert replacement != gateway
    assert %{admitted: 0} = Gateway.stats(replacement)
    stop_supervised!(@host)
    refute Process.alive?(replacement)
    assert {:error, %Error{code: :inspection_unavailable}} = Inspection.open()
  end

  test "one scope per process, cross-owner rejection, expiry and restart never reuse authority" do
    start_supervised!({@host, history: [interval_ms: 60_000]})
    assert {:ok, gateway} = Inspection.open(ttl_ms: 100)
    monitor = Process.monitor(gateway)

    Task.async(fn ->
      assert {:error, %Error{code: :scope_denied}} = Gateway.stats(gateway)
      assert {:ok, own} = Inspection.open()
      assert own != gateway
      assert :ok = Gateway.revoke(own)
    end)
    |> Task.await()

    assert_receive {:DOWN, ^monitor, :process, ^gateway, :normal}, 1_000
    assert Inspection.count() == 0
    assert {:ok, next} = Inspection.open()
    stop_supervised!(@host)
    refute Process.alive?(next)
    start_supervised!({@host, history: [interval_ms: 60_000]})
    assert Inspection.count() == 0
    assert {:error, %Error{code: :scope_unavailable}} = Gateway.stats(next)
  end

  test "global scope capacity is bounded and owner death releases admission" do
    start_supervised!({@host, history: [interval_ms: 60_000]})
    parent = self()

    owners =
      for _ <- 1..32 do
        spawn(fn ->
          send(parent, {:opened, self(), Inspection.open()})
          receive do: (:stop -> :ok)
        end)
      end

    on_exit(fn -> Enum.each(owners, &Process.exit(&1, :kill)) end)
    for owner <- owners, do: assert_receive({:opened, ^owner, {:ok, _gateway}}, 1_000)
    assert Inspection.count() == 32
    assert {:error, %Error{code: :inspection_capacity}} = Inspection.open()
    Enum.each(owners, &send(&1, :stop))
    assert eventually(fn -> Inspection.count() == 0 end)
    assert {:ok, gateway} = Inspection.open()
    assert :ok = Gateway.revoke(gateway)
  end

  test "operator text cannot bind owner, scope, history or an endpoint" do
    for opts <- [
          [scope: %{instance: "secret-sentinel"}],
          [owner: self()],
          [history: self()],
          [endpoint: "secret-sentinel"],
          [ttl_ms: 1, ttl_ms: 2],
          nil
        ] do
      assert {:error, %Error{code: :invalid_options} = error} = Inspection.open(opts)
      refute inspect(error) =~ "secret-sentinel"
    end

    assert {:error, %Error{code: :invalid_options}} = Inspection.start_link(endpoint: "sentinel")
    assert {:error, %Error{code: :history_unavailable}} = Inspection.start_link(history: nil)
    start_supervised!({@host, history: [interval_ms: 60_000]})
    assert {:error, %Error{code: :invalid_gateway}} = Inspection.open(ttl_ms: 60_001)
    assert Inspection.count() == 0
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(5)
      eventually(fun, attempts - 1)
    end
  end
end
