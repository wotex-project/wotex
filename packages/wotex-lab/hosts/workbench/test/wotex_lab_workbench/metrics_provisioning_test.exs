defmodule WotexLabWorkbench.MetricsProvisioningTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.Retention
  alias WotexLabWorkbench.FakeGreptime
  alias WotexLabWorkbench.Observability.{Durable, Provisioning}

  @admin_token "hosted-retention-admin-token-sentinel-with-43-chars"
  @ddl ~s({"output":[{"affectedrows":0}],"execution_time_ms":1})

  test "only an exact loopback receiver and an admitted plan reach the network" do
    {_, port} = FakeGreptime.start(self())

    for url <- [
          "https://127.0.0.1:#{port}",
          "http://localhost:#{port}",
          "http://10.0.0.1:#{port}",
          "http://127.0.0.1:#{port}/v1/sql",
          "http://127.0.0.1:#{port}?db=public",
          "http://operator@127.0.0.1:#{port}",
          "http://127.0.0.1",
          "http://127.0.0.1:65536",
          "http://127.0.0.1:0#{port}",
          nil
        ] do
      assert {:error, %Error{code: :invalid_retention}} =
               Provisioning.provision(url, database: "wotex_lab")
    end

    for opts <- [[database: "public"], [database: "wotex_lab", ttl: "30m"], []] do
      assert {:error, %Error{code: :invalid_retention}} =
               Provisioning.provision("http://127.0.0.1:#{port}", opts)
    end

    refute_received {:fake_greptime, _handler, _request}
  end

  test "provisioning sends the generated statements and verifies the effective TTL" do
    {_, port} = FakeGreptime.start(self())

    task =
      Task.async(fn ->
        Provisioning.provision("http://127.0.0.1:#{port}/", database: "lab", ttl: "90d")
      end)

    {:ok, plan} = Retention.plan(database: "lab", ttl: "90d")

    for statement <- Retention.statements(plan) do
      assert_receive {:fake_greptime, handler, request}, 2_000
      assert request.method == "POST" and request.path == "/v1/sql" and request.query == "db=public"
      assert URI.decode_query(request.body) == %{"sql" => statement}
      refute List.keymember?(request.headers, "authorization", 0)
      send(handler, {:reply, 200, @ddl})
    end

    assert_receive {:fake_greptime, handler, request}, 2_000
    assert URI.decode_query(request.body) == %{"sql" => Retention.verification(plan)}
    send(handler, {:reply, 200, rows("'ttl'='2months 29days 2h 52m 48s'\\n")})

    assert {:ok, %{database: "lab", ttl: "90d", seconds: 7_776_000}} = Task.await(task)
  end

  test "refused, malformed, oversized and unreachable answers fail closed" do
    {_, port} = FakeGreptime.start(self())
    url = "http://127.0.0.1:#{port}"

    for {status, reply, code} <- [
          {400, ~s({"code":1004,"error":"Invalid set database option"}), :retention_refused},
          {200, "not json", :retention_unavailable},
          {200, ~s({"output":[{"records":{"rows":[]}}]}), :retention_refused},
          {200, String.duplicate("x", 70_000), :retention_unavailable}
        ] do
      task = Task.async(fn -> Provisioning.provision(url, database: "lab") end)
      assert_receive {:fake_greptime, handler, _request}, 2_000
      send(handler, {:reply, status, reply})
      assert {:error, %Error{code: ^code}} = Task.await(task)
    end

    {:ok, listener} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, closed} = :inet.port(listener)
    :ok = :gen_tcp.close(listener)

    assert {:error, %Error{code: :retention_unavailable}} =
             Provisioning.provision("http://127.0.0.1:#{closed}", database: "lab")
  end

  test "hosted provisioning needs an exact HTTPS origin and a separate administrative credential" do
    names =
      ~w(WOTEX_LAB_GREPTIME_ADMIN_TOKEN WOTEX_LAB_GREPTIME_TOKEN WOTEX_LAB_GREPTIME_QUERY_TOKEN
               WOTEX_LAB_OTLP_TOKEN WOTEX_LAB_METRICS_TOKEN WOTEX_LAB_METRICS_QUERY_TOKEN)

    saved = Map.new(names, &{&1, System.get_env(&1)})
    Enum.each(names, &System.delete_env/1)
    {:ok, listen} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false])
    {:ok, port} = :inet.port(listen)
    origin = "https://localhost:#{port}"

    try do
      for {candidate, opts} <- [
            {"http://metrics.example", [database: "lab"]},
            {"https://metrics.example/", [database: "lab"]},
            {"https://metrics.example/v1/sql", [database: "lab"]},
            {"https://metrics.example?db=public", [database: "lab"]},
            {"https://admin@metrics.example", [database: "lab"]},
            {nil, [database: "lab"]},
            {"https://metrics.example", [database: "public"]},
            {"https://metrics.example", [database: "lab", ttl: "30m"]},
            {"https://metrics.example", [database: "lab", tls_ca_certfile: ""]},
            {"https://metrics.example", [database: "lab", token: @admin_token]}
          ] do
        assert {:error, %Error{code: :invalid_retention} = error} =
                 Provisioning.provision_hosted(candidate, opts)

        refute inspect(error) =~ @admin_token
      end

      assert {:error, %Error{code: :credential_unavailable}} =
               Provisioning.provision_hosted(origin, database: "lab")

      System.put_env("WOTEX_LAB_GREPTIME_ADMIN_TOKEN", "short")
      assert :error = Provisioning.lookup_credential()
      System.put_env("WOTEX_LAB_GREPTIME_ADMIN_TOKEN", @admin_token)
      assert {:ok, {:bearer, @admin_token}} = Provisioning.lookup_credential()

      for other <- tl(names) do
        System.put_env(other, @admin_token)

        assert {:error, %Error{code: :credential_unavailable}} =
                 Provisioning.provision_hosted(origin, database: "lab")

        System.delete_env(other)
      end

      # localhost resolves to loopback, so the hosted policy refuses it before connecting.
      assert {:error, %Error{code: :retention_unavailable}} =
               Provisioning.provision_hosted(origin, database: "lab", ttl: "30d")

      assert {:error, :timeout} = :gen_tcp.accept(listen, 200)
    after
      :gen_tcp.close(listen)

      Enum.each(saved, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end
  end

  test "the exporter writes to a selected database with the database header" do
    {_, port} = FakeGreptime.start(self())
    {:ok, options} = Durable.configure("http://127.0.0.1:#{port}/v1/prometheus/write", false)
    assert options[:database] == nil
    assert {:ok, selected} = Durable.put_database(options, "wotex_lab")
    assert selected[:database] == "wotex_lab"
    assert :ok = Durable.validate(selected)

    for database <- ["public", "Lab", nil, 7] do
      assert {:error, %Error{code: :invalid_durable_metrics}} =
               Durable.put_database(options, database)
    end

    assert {:error, %Error{code: :invalid_durable_metrics}} = Durable.put_database(:bad, "lab")

    assert {:error, %Error{code: :invalid_durable_metrics}} =
             Durable.validate(Keyword.put(options, :database, "public"))

    for {opts, expected} <- [{options, nil}, {selected, "wotex_lab"}] do
      sink = Keyword.fetch!(Durable.child_options(opts, nil), :sink)
      request = %{body: "body", headers: [{"content-type", "application/x-protobuf"}]}
      task = Task.async(fn -> sink.(request, nil) end)
      assert_receive {:fake_greptime, handler, received}, 2_000
      assert received.path == "/v1/prometheus/write" and received.body == "body"

      assert List.keyfind(received.headers, "x-greptime-db-name", 0) ==
               (expected && {"x-greptime-db-name", expected})

      send(handler, {:reply, 204, ""})
      assert {:ok, %{status: 204}} = Task.await(task)
    end
  end

  defp rows(options),
    do: ~s({"output":[{"records":{"schema":{},"rows":[["#{options}"]],"total_rows":1}}]})
end
