defmodule WotexLabWorkbench.MetricsDurableTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{GreptimeBridge, History}
  alias WotexLabWorkbench.Observability.{Durable, Sampler}

  @host WotexLabWorkbench.Observability.Supervisor
  @url "http://127.0.0.1:4000/v1/prometheus/write"
  @secret "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  test "configuration admits only the exact local remote-write endpoint" do
    assert {:ok, options} = Durable.configure(@url, false)
    assert :ok = Durable.validate(options)
    assert options[:interval_ms] == 5_000
    assert options[:queue_limit] == 16
    assert options[:deadline_ms] == 5_000

    for url <- [
          "https://127.0.0.1:4000/v1/prometheus/write",
          "http://localhost:4000/v1/prometheus/write",
          "http://10.0.0.1:4000/v1/prometheus/write",
          "http://127.0.0.1:4000/v1/sql",
          "http://caller@127.0.0.1:4000/v1/prometheus/write",
          @url <> "?token=secret",
          @url <> "#fragment"
        ] do
      assert {:error, %Error{code: :invalid_durable_metrics}} = Durable.configure(url, false)
    end

    for options <- [
          [],
          [url: @url, bearer: false, interval_ms: 999, queue_limit: 16, deadline_ms: 5_000],
          [url: @url, bearer: false, interval_ms: 5_000, queue_limit: 257, deadline_ms: 5_000],
          [url: @url, bearer: false, interval_ms: 5_000, queue_limit: 16, deadline_ms: 0],
          [
            url: @url,
            bearer: false,
            interval_ms: 5_000,
            queue_limit: 16,
            deadline_ms: 5_000,
            sink: :caller
          ],
          [
            url: @url,
            bearer: false,
            bearer: true,
            interval_ms: 5_000,
            queue_limit: 16,
            deadline_ms: 5_000
          ]
        ] do
      assert {:error, %Error{code: :invalid_durable_metrics}} = Durable.validate(options)
    end
  end

  test "bearer credentials resolve just in time and never enter child configuration" do
    previous = System.get_env("WOTEX_LAB_GREPTIME_TOKEN")
    System.put_env("WOTEX_LAB_GREPTIME_TOKEN", @secret)

    try do
      assert {:ok, options} = Durable.configure(@url, true)
      child_options = Durable.child_options(options, nil)
      refute inspect(child_options) =~ @secret
      assert {:ok, {:bearer, @secret}} = Durable.lookup_credential(:greptime_bearer)
      System.put_env("WOTEX_LAB_GREPTIME_TOKEN", "short")
      assert :error = Durable.lookup_credential(:greptime_bearer)
      assert :error = Durable.lookup_credential(:caller)
    after
      if previous,
        do: System.put_env("WOTEX_LAB_GREPTIME_TOKEN", previous),
        else: System.delete_env("WOTEX_LAB_GREPTIME_TOKEN")
    end
  end

  test "durable supervision uses the exporter as the sole optional history writer" do
    {:ok, durable} = Durable.configure(@url, false)
    durable = Keyword.put(durable, :interval_ms, 60_000)

    start_supervised!({@host, history: [interval_ms: 60_000], durable: durable})
    bridge = Process.whereis(Durable.Bridge)
    history = Process.whereis(@host.History)

    assert is_pid(bridge) and Process.alive?(bridge)
    assert is_pid(history) and Process.alive?(history)
    refute Process.whereis(Sampler)
    assert History.stats(history).count == 0
    assert {:ok, %{sequence: 1}} = GreptimeBridge.scrape_now(bridge)
    assert History.stats(history).count == 1
    assert %{admitted: 1, sequence: 1} = GreptimeBridge.stats(bridge)

    stop_supervised!(@host)
    refute Process.alive?(bridge)
    refute Process.alive?(history)
  end

  test "durable activation remains explicit and requires PromEx" do
    saved_promex = Application.fetch_env!(:wotex_lab_workbench, :promex_enabled)
    saved_durable = Application.fetch_env!(:wotex_lab_workbench, :metrics_durable)
    {:ok, durable} = Durable.configure(@url, false)

    Application.put_env(:wotex_lab_workbench, :promex_enabled, false)
    Application.put_env(:wotex_lab_workbench, :metrics_durable, durable)

    try do
      assert {:error, :metrics_durable_requires_promex} =
               WotexLabWorkbench.Application.start(:normal, [])
    after
      Application.put_env(:wotex_lab_workbench, :promex_enabled, saved_promex)
      Application.put_env(:wotex_lab_workbench, :metrics_durable, saved_durable)
    end
  end
end
