defmodule WotexLabWorkbench.MetricsDurableReaderTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.{DurableQuery, Query}
  alias WotexLabWorkbench.FakeGreptime
  alias WotexLabWorkbench.Observability.{DurableReader, Inspection, QueryListener}

  @host WotexLabWorkbench.Observability.Supervisor
  @token "local-only-query-token-sentinel-with-32-bytes-min"
  @digest :crypto.hash(:sha256, @token)
  @path "/v1/prometheus/api/v1/query_range"
  @reader_token "hosted-durable-reader-token-sentinel-with-43-chars"
  @empty ~s({"status":"success","data":{"resultType":"matrix","result":[]}})

  test "configuration admits an exact loopback receiver and a non-reserved database" do
    assert {:ok, [url: "http://127.0.0.1:4000", database: nil] = opts} =
             DurableReader.configure("http://127.0.0.1:4000/", nil)

    assert :ok = DurableReader.validate(opts)

    assert {:ok, [url: _, database: "lab"]} =
             DurableReader.configure("http://127.0.0.1:4000", "lab")

    for {url, database} <- [
          {"https://127.0.0.1:4000", nil},
          {"http://localhost:4000", nil},
          {"http://10.0.0.1:4000", nil},
          {"http://127.0.0.1:4000/v1/prometheus", nil},
          {"http://127.0.0.1:4000?db=lab", nil},
          {"http://operator@127.0.0.1:4000", nil},
          {"http://127.0.0.1:65536", nil},
          {"http://127.0.0.1", nil},
          {nil, nil},
          {"http://127.0.0.1:4000", "public"},
          {"http://127.0.0.1:4000", "Lab; DROP"},
          {"http://127.0.0.1:4000", 1}
        ] do
      assert {:error, %Error{code: :invalid_durable_reads}} =
               DurableReader.configure(url, database)
    end

    for opts <- [
          [url: "http://127.0.0.1:4000/", database: nil],
          [url: "http://127.0.0.1:4000"],
          [url: "http://127.0.0.1:4000", database: nil, token: "secret"],
          nil
        ] do
      assert {:error, %Error{code: :invalid_durable_reads}} = DurableReader.validate(opts)
    end

    assert {:error, %Error{code: :invalid_durable_reads}} =
             @host.start_link(durable_query: [url: "http://10.0.0.1:4000", database: nil])
  end

  test "the executor sends only the fixed template to the configured database" do
    {_, port} = FakeGreptime.start(self())
    {:ok, opts} = DurableReader.configure("http://127.0.0.1:#{port}", "lab")
    executor = DurableReader.executor(opts)
    {:ok, template} = DurableQuery.template(descriptor())
    matrix = matrix([[1_767_225_605, "4"]])

    task = Task.async(fn -> executor.(template) end)
    assert_receive {:fake_greptime, handler, request}, 2_000
    assert request.method == "POST" and request.path == @path and request.query == "db=lab"
    assert URI.decode_query(request.body) == Map.new(template.params)
    refute List.keymember?(request.headers, "authorization", 0)
    refute List.keymember?(request.headers, "x-greptime-db-name", 0)
    send(handler, {:reply, 200, matrix})
    assert {:ok, %{"status" => "success"}} = Task.await(task)

    refused = ~s({"status":"error","errorType":"bad_data","error":"receiver-secret"})

    for {status, body, expected} <- [
          {400, refused, {:ok, Jason.decode!(refused)}},
          {422, refused, {:ok, Jason.decode!(refused)}},
          {500, refused, {:error, :unavailable}},
          {200, "not json", {:error, :invalid_response}},
          {200, "[]", {:error, :invalid_response}},
          {200, String.duplicate(" ", 1_048_577), {:error, :too_large}}
        ] do
      task = Task.async(fn -> executor.(template) end)
      assert_receive {:fake_greptime, handler, _request}, 2_000
      send(handler, {:reply, status, body})
      assert Task.await(task) == expected
    end

    for template <- [%{template | path: "/v1/sql"}, %{template | params: [{"query", "up"}]}, nil] do
      assert {:error, :invalid_template} = executor.(template)
    end

    refute_received {:fake_greptime, _, _}
  end

  test "an empty answer from a selected database verifies that the database exists" do
    {_, port} = FakeGreptime.start(self())
    {:ok, template} = DurableQuery.template(descriptor())
    statement = "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'lab'"

    for {rows, expected} <- [
          {~s([["lab"]]), {:ok, Jason.decode!(@empty)}},
          {"[]", {:error, :database_missing}}
        ] do
      {:ok, opts} = DurableReader.configure("http://127.0.0.1:#{port}", "lab")
      task = Task.async(fn -> DurableReader.executor(opts).(template) end)
      assert_receive {:fake_greptime, handler, %{path: @path}}, 2_000
      send(handler, {:reply, 200, @empty})
      assert_receive {:fake_greptime, handler, check}, 2_000
      assert check.path == "/v1/sql" and check.query == "db=public"
      assert URI.decode_query(check.body) == %{"sql" => statement}

      send(
        handler,
        {:reply, 200, ~s({"output":[{"records":{"rows":#{rows},"total_rows":0}}]})}
      )

      assert Task.await(task) == expected
    end

    {:ok, public} = DurableReader.configure("http://127.0.0.1:#{port}", nil)
    task = Task.async(fn -> DurableReader.executor(public).(template) end)
    assert_receive {:fake_greptime, handler, %{query: "db=public"}}, 2_000
    send(handler, {:reply, 200, @empty})
    assert {:ok, _} = Task.await(task)
    refute_receive {:fake_greptime, _, _}, 100

    {:ok, closed} = DurableReader.configure("http://127.0.0.1:#{unused_port()}", "lab")
    assert {:error, :unavailable} = DurableReader.executor(closed).(template)
  end

  test "hosted reads need an exact HTTPS origin and a separate just-in-time credential" do
    assert {:ok, opts} = DurableReader.configure_hosted("https://metrics.example", "lab")

    assert opts == [
             url: "https://metrics.example",
             database: "lab",
             profile: :hosted,
             tls_ca_certfile: nil
           ]

    assert :ok = DurableReader.validate(opts)

    assert {:ok, _} =
             DurableReader.configure_hosted("https://metrics.example:8443", nil, "/etc/ca.pem")

    for {origin, database, ca} <- [
          {"http://metrics.example", nil, nil},
          {"https://metrics.example/", nil, nil},
          {"https://metrics.example/v1/prometheus", nil, nil},
          {"https://metrics.example?db=other", nil, nil},
          {"https://metrics.example#fragment", nil, nil},
          {"https://reader@metrics.example", nil, nil},
          {"https://metrics.example", "public", nil},
          {"https://metrics.example", nil, ""},
          {nil, nil, nil}
        ] do
      assert {:error, %Error{code: :invalid_durable_reads}} =
               DurableReader.configure_hosted(origin, database, ca)
    end

    for opts <- [
          [url: "http://127.0.0.1:4000", database: nil, tls_ca_certfile: "/etc/ca.pem"],
          [url: "http://127.0.0.1:4000", database: nil, profile: :hosted],
          [url: "https://metrics.example", database: nil, profile: :local],
          [url: "https://metrics.example", database: nil, profile: :remote]
        ] do
      assert {:error, %Error{code: :invalid_durable_reads}} = DurableReader.validate(opts)
    end

    names = ~w(WOTEX_LAB_GREPTIME_QUERY_TOKEN WOTEX_LAB_GREPTIME_TOKEN WOTEX_LAB_OTLP_TOKEN
               WOTEX_LAB_GREPTIME_ADMIN_TOKEN WOTEX_LAB_METRICS_TOKEN WOTEX_LAB_METRICS_QUERY_TOKEN)

    saved = Map.new(names, &{&1, System.get_env(&1)})
    Enum.each(names, &System.delete_env/1)

    try do
      {:ok, listen} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false])
      {:ok, port} = :inet.port(listen)
      {:ok, local} = DurableReader.configure_hosted("https://localhost:#{port}", "lab")
      {:ok, template} = DurableQuery.template(descriptor())
      executor = DurableReader.executor(local)
      refute inspect(executor) =~ @reader_token

      assert :error = DurableReader.lookup_credential()
      assert {:error, :unavailable} = executor.(template)
      System.put_env("WOTEX_LAB_GREPTIME_QUERY_TOKEN", "short")
      assert :error = DurableReader.lookup_credential()
      System.put_env("WOTEX_LAB_GREPTIME_QUERY_TOKEN", @reader_token)
      assert {:ok, {:bearer, @reader_token}} = DurableReader.lookup_credential()

      for other <- tl(names) do
        System.put_env(other, @reader_token)
        assert :error = DurableReader.lookup_credential()
        System.delete_env(other)
      end

      # localhost resolves to loopback, so the hosted policy refuses it before connecting.
      assert {:error, :unavailable} = executor.(template)
      assert {:error, :timeout} = :gen_tcp.accept(listen, 200)
      :ok = :gen_tcp.close(listen)
    after
      Enum.each(saved, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end
  end

  test "the operator listener answers durable descriptors from the server-bound scope" do
    {_, port} = FakeGreptime.start(self())
    {:ok, reader} = DurableReader.configure("http://127.0.0.1:#{port}", nil)
    start_supervised!({@host, durable_query: reader})
    body = Jason.encode!(request())

    task = Task.async(fn -> call("/durable/query", body) end)
    assert_receive {:fake_greptime, handler, fake}, 2_000
    query = URI.decode_query(fake.body)["query"]
    assert query =~ ~s(instance="workbench") and query =~ ~s(profile="thermal")
    send(handler, {:reply, 200, matrix([[1_767_225_605, "4"], [1_767_225_610, "NaN"]])})
    response = Task.await(task)
    assert response.status == 200
    answer = Jason.decode!(response.resp_body)
    assert answer["source"] == "durable_promql" and answer["instance"] == "workbench"
    assert answer["points"] == [%{"t" => 1_767_225_605_000, "value" => 4}]
    assert answer["markers"] == [%{"t" => 1_767_225_610_000, "kind" => "nonfinite"}]
    assert answer["template_digest"] =~ "sha256:"
    refute response.resp_body =~ @token

    for {status, reply, code} <- [
          {400, ~s({"status":"error","error":"receiver-secret"}), "durable_refused"},
          {200, ~s({"status":"success","data":{"resultType":"vector","result":[]}}),
           "durable_invalid_response"},
          {503, "{}", "durable_unavailable"}
        ] do
      task = Task.async(fn -> call("/durable/query", body) end)
      assert_receive {:fake_greptime, handler, _}, 2_000
      send(handler, {:reply, status, reply})
      refused = Task.await(task)
      assert %{"code" => ^code} = Jason.decode!(refused.resp_body)
      assert refused.status == if(code == "durable_unavailable", do: 503, else: 502)
      refute refused.resp_body =~ "receiver-secret"
    end

    unsupported = call("/durable/query", Jason.encode!(%{request() | "aggregation" => "avg"}))
    assert unsupported.status == 422

    history = call("/query", body)
    assert history.status == 503
    assert %{"code" => "inspection_source_unavailable"} = Jason.decode!(history.resp_body)
    assert call("/durable", body).status == 404
    assert Inspection.count() == 0
    refute_received {:fake_greptime, _, _}
  end

  test "durable reads need PromEx activation and can serve the listener without history" do
    {:ok, reader} = DurableReader.configure("http://127.0.0.1:4000", nil)

    start_supervised!({@host, durable_query: reader, query: [port: 0, token_digest: @digest]})

    assert {:ok, {{127, 0, 0, 1}, _}} = ThousandIsland.listener_info(QueryListener)
    assert {:error, %Error{code: :inspection_source_unavailable}} = Inspection.open()
    assert {:error, %Error{code: :invalid_inspection}} = Inspection.open(source: :public)
    stop_supervised!(@host)

    Application.put_env(:wotex_lab_workbench, :metrics_durable_query, reader)

    try do
      assert {:error, :metrics_durable_query_requires_promex} =
               WotexLabWorkbench.Application.start(:normal, [])
    after
      Application.put_env(:wotex_lab_workbench, :metrics_durable_query, false)
    end
  end

  defp descriptor do
    {:ok, query} =
      Query.new(
        scope: %{instance: "workbench", session: "session"},
        metric: :nx_batch_rows,
        aggregation: :last,
        filters: %{profile: :thermal},
        start_at: ~U[2026-01-01 00:00:00Z],
        end_at: ~U[2026-01-01 00:00:10Z],
        step_ms: 5_000
      )

    query
  end

  defp request do
    %{
      "schema_version" => "1.0.0",
      "metric" => "nx_batch_rows",
      "aggregation" => "last",
      "filters" => %{"profile" => "thermal"},
      "start_at" => "2026-01-01T00:00:00Z",
      "end_at" => "2026-01-01T00:00:10Z",
      "step_ms" => 5_000
    }
  end

  defp matrix(values) do
    Jason.encode!(%{
      "status" => "success",
      "data" => %{
        "resultType" => "matrix",
        "result" => [%{"metric" => %{"instance" => "workbench"}, "values" => values}]
      }
    })
  end

  defp call(path, body) do
    conn = Plug.Test.conn("POST", path, body)

    conn = %{
      conn
      | remote_ip: {127, 0, 0, 1},
        req_headers: [
          {"authorization", "Bearer " <> @token},
          {"content-type", "application/json"},
          {"content-length", "#{byte_size(body)}"}
        ]
    }

    QueryListener.call(conn, QueryListener.init(@digest))
  end

  defp unused_port do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
