defmodule WotexLabWorkbench.MetricsOtlpTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.{Error, Telemetry}
  alias Wotex.Lab.Otlp.Exporter
  alias WotexLabWorkbench.FakeGreptime
  alias WotexLabWorkbench.Observability.Otlp

  @otlp_token "hosted-otlp-export-token-sentinel-with-43-characters"

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

  test "hosted export needs an exact HTTPS receiver, its audience and a just-in-time credential" do
    url = "https://traces.example/v1/otlp"
    audience = "https://traces.example"
    assert {:ok, opts} = Otlp.configure_hosted(url, audience, "wotex_lab")

    assert opts == [
             url: url,
             database: "wotex_lab",
             profile: :hosted,
             audience: audience,
             tls_ca_certfile: nil
           ]

    assert {:ok, _} =
             Otlp.configure_hosted(
               "https://traces.example:8443/v1/otlp",
               "https://traces.example:8443",
               nil,
               "/etc/ca.pem"
             )

    for {candidate, expected, database, ca} <- [
          {"http://traces.example/v1/otlp", "http://traces.example", nil, nil},
          {"https://traces.example/v1/otlp/v1/traces", audience, nil, nil},
          {url <> "?db=other", audience, nil, nil},
          {"https://exporter@traces.example/v1/otlp", audience, nil, nil},
          {url, "https://other.example", nil, nil},
          {url, "https://traces.example:8443", nil, nil},
          {url, audience <> "/v1/otlp", nil, nil},
          {url, nil, nil, nil},
          {url, audience, "public", nil},
          {url, audience, nil, ""}
        ] do
      assert {:error, %Error{code: :invalid_otlp_export}} =
               Otlp.configure_hosted(candidate, expected, database, ca)
    end

    for invalid <- [
          [url: "http://127.0.0.1:4000/v1/otlp", database: nil, audience: audience],
          [url: url, database: nil, profile: :hosted],
          [url: url, database: nil, profile: :remote, audience: audience]
        ] do
      assert {:error, %Error{code: :invalid_otlp_export}} = Otlp.validate(invalid)
    end

    names = ~w(WOTEX_LAB_OTLP_TOKEN WOTEX_LAB_GREPTIME_QUERY_TOKEN WOTEX_LAB_GREPTIME_ADMIN_TOKEN
               WOTEX_LAB_METRICS_TOKEN WOTEX_LAB_METRICS_QUERY_TOKEN)

    saved = Map.new(names, &{&1, System.get_env(&1)})
    Enum.each(names, &System.delete_env/1)

    try do
      assert :error = Otlp.lookup_credential()
      System.put_env("WOTEX_LAB_OTLP_TOKEN", "short")
      assert :error = Otlp.lookup_credential()
      System.put_env("WOTEX_LAB_OTLP_TOKEN", @otlp_token)
      assert {:ok, {:bearer, @otlp_token}} = Otlp.lookup_credential()

      for other <- tl(names) do
        System.put_env(other, @otlp_token)
        assert :error = Otlp.lookup_credential()
        System.delete_env(other)
      end

      {:ok, listen} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false])
      {:ok, port} = :inet.port(listen)

      {:ok, local} =
        Otlp.configure_hosted(
          "https://localhost:#{port}/v1/otlp",
          "https://localhost:#{port}",
          nil
        )

      child = Otlp.child_options(local)
      refute inspect(child) =~ @otlp_token
      exporter = start_supervised!({Exporter, Keyword.put(child, :interval_ms, 60_000)})

      # localhost resolves to loopback, so the hosted policy refuses it before connecting.
      for {token, code} <- [
            {@otlp_token, :destination_not_admitted},
            {nil, :credential_unavailable}
          ] do
        if token,
          do: System.put_env("WOTEX_LAB_OTLP_TOKEN", token),
          else: System.delete_env("WOTEX_LAB_OTLP_TOKEN")

        assert :ok = Telemetry.span(:scenario, :inference, %{profile: :thermal}, fn -> :ok end)
        assert %{traces: %{exported: 0}, last_error: ^code} = Exporter.flush(exporter)
        assert {:error, :timeout} = :gen_tcp.accept(listen, 200)
      end

      :ok = :gen_tcp.close(listen)
    after
      Enum.each(saved, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end
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
