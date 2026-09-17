defmodule WotexLabWorkbench.MetricsOtlpTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias Wotex.Lab.Otlp.Exporter
  alias Wotex.Lab.Telemetry
  alias WotexLabWorkbench.FakeGreptime
  alias WotexLabWorkbench.Observability.Otlp

  test "activation admits only the exact local receiver and a valid database" do
    assert {:ok, [url: "http://127.0.0.1:4000/v1/otlp", database: nil]} =
             Otlp.configure("http://127.0.0.1:4000/v1/otlp", nil)

    assert {:ok, _} = Otlp.configure("http://127.0.0.1:4000/v1/otlp", "wotex_lab")

    for {url, database} <- [
          {"https://127.0.0.1:4000/v1/otlp", nil},
          {"http://localhost:4000/v1/otlp", nil},
          {"http://127.0.0.1:4000/v1/otlp/v1/traces", nil},
          {"http://127.0.0.1:4000/v1/otlp?db=public", nil},
          {"http://user@127.0.0.1:4000/v1/otlp", nil},
          {"http://127.0.0.1:65536/v1/otlp", nil},
          {"http://127.0.0.1/v1/otlp", nil},
          {nil, nil},
          {"http://127.0.0.1:4000/v1/otlp", "public"},
          {"http://127.0.0.1:4000/v1/otlp", "Lab"}
        ] do
      assert {:error, %Error{code: :invalid_otlp_export}} = Otlp.configure(url, database)
    end

    for opts <- [[url: "http://127.0.0.1:4000/v1/otlp"], [url: "x", database: nil, extra: 1], :bad] do
      assert {:error, %Error{code: :invalid_otlp_export}} = Otlp.validate(opts)
    end
  end

  test "the host exporter sends Lab spans to the receiver with the selected database" do
    {_, port} = FakeGreptime.start(self())
    {:ok, opts} = Otlp.configure("http://127.0.0.1:#{port}/v1/otlp", "wotex_lab")
    child = Otlp.child_options(opts)
    assert child[:service_instance] == "workbench" and child[:name] == Otlp.Exporter
    exporter = start_supervised!({Exporter, child})

    assert :ok = Telemetry.span(:scenario, :inference, %{profile: :thermal}, fn -> :ok end)
    flush = Task.async(fn -> Exporter.flush(exporter) end)

    assert_receive {:fake_greptime, handler, request}, 2_000
    assert request.method == "POST" and request.path == "/v1/otlp/v1/traces"
    assert {"x-greptime-db-name", "wotex_lab"} in request.headers
    assert {"x-greptime-pipeline-name", "greptime_trace_v1"} in request.headers
    assert {"content-type", "application/x-protobuf"} in request.headers
    send(handler, {:reply, 200, ""})

    assert %{traces: %{exported: 1, failed: 0}} = Task.await(flush)
  end

  test "application activation refuses an invalid stored profile" do
    Application.put_env(:wotex_lab_workbench, :metrics_otlp,
      url: "http://10.0.0.1:4000/v1/otlp",
      database: nil
    )

    try do
      assert {:error, %Error{code: :invalid_otlp_export}} =
               WotexLabWorkbench.Application.start(:normal, [])
    after
      Application.put_env(:wotex_lab_workbench, :metrics_otlp, false)
    end
  end
end
