defmodule Wotex.Lab.GreptimeOtlpTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Metrics.Retention
  alias Wotex.Lab.Otlp.{Exporter, GreptimeSink}
  alias Wotex.Lab.Telemetry
  alias Wotex.Lab.Test.Greptime

  @moduletag :greptime

  test "spans and exception logs land in a provisioned database on the pinned server" do
    greptime = Greptime.start()
    {:ok, plan} = Retention.plan(database: "wotex_lab_otlp", ttl: "2d")
    assert {:ok, %{seconds: 172_800}} = Retention.provision(plan, &Greptime.sql(greptime, &1))

    {:ok, sink} =
      GreptimeSink.new(%{
        url: greptime.base_url <> "/v1/otlp",
        database: plan.database,
        receive_timeout: 5_000
      })

    exporter =
      start_supervised!(
        {Exporter,
         id: "greptime-otlp", sink: sink, service_instance: "lab-greptime", interval_ms: 60_000}
      )

    assert :ok =
             Telemetry.span(:nx, :encode, %{profile: :thermal, thing_ref: "thing:secret"}, fn ->
               :ok
             end)

    assert :timeout = Telemetry.span(:mqtt, :request, %{profile: :mqtt}, fn -> :timeout end)

    assert_raise RuntimeError, fn ->
      Telemetry.span(:policy, :dispatch, %{}, fn -> raise "private reason" end)
    end

    stats = Exporter.flush(exporter)
    assert stats.traces == %{exported: 3, rejected: 0, failed: 0, dropped: 0}
    assert stats.logs == %{exported: 1, rejected: 0, failed: 0, dropped: 0}
    assert stats.last_error == nil

    assert Greptime.otlp_rows(greptime, :traces, plan.database) == [
             ["mqtt.request", "wotex_lab", "STATUS_CODE_ERROR", "timeout"],
             ["nx.encode", "wotex_lab", "STATUS_CODE_OK", "ok"],
             ["policy.dispatch", "wotex_lab", "STATUS_CODE_ERROR", "exception"]
           ]

    assert [["ERROR", "wotex.lab span exception", attributes]] =
             Greptime.otlp_rows(greptime, :logs, plan.database)

    assert attributes["wotex.lab.kind"] == "error" and attributes["wotex.lab.component"] == "policy"
    refute inspect(Greptime.otlp_rows(greptime, :traces, plan.database)) =~ "secret"
    assert Greptime.table_ttl(greptime, "opentelemetry_traces", plan.database) == "2days"
    assert Greptime.table_ttl(greptime, "opentelemetry_logs", plan.database) == "2days"
    stop_supervised!({Exporter, "greptime-otlp"})

    without_pipeline = fn :traces, request ->
      url = greptime.base_url <> "/v1/otlp/v1/traces"
      {:ok, response} = Wotex.Lab.Metrics.ReqSink.write(request, nil, %{url: url})
      {:ok, Map.take(response, [:status, :body])}
    end

    refused =
      start_supervised!(
        {Exporter,
         id: "greptime-otlp", sink: without_pipeline, signals: [:traces], interval_ms: 60_000}
      )

    Telemetry.span(:nx, :decode, %{}, fn -> :ok end)

    assert %{traces: %{failed: 1, exported: 0}, last_error: :rejected_status} =
             Exporter.flush(refused)
  end
end
