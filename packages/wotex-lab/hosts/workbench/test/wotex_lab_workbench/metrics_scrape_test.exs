defmodule WotexLabWorkbench.MetricsScrapeTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Plug.Conn, only: [get_resp_header: 2]

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.Exposition
  alias WotexLabWorkbench.Observability.Scrape

  @host WotexLabWorkbench.Observability.Supervisor
  @promex WotexLabWorkbench.Observability.PromEx
  @token "local-only-scrape-token-sentinel-32-bytes-minimum"
  @digest :crypto.hash(:sha256, @token)
  @auth [{"authorization", "Bearer " <> @token}]

  test "closed configuration keeps only the digest and refuses remote listener options" do
    assert {:ok, opts} = Scrape.configure("0", @token)
    assert opts == [port: 0, token_digest: @digest]
    refute inspect(opts) =~ @token
    assert :ok = Scrape.validate(opts)

    for {port, token} <- [
          {nil, @token},
          {"-1", @token},
          {"80", @token},
          {"65536", @token},
          {"000000", @token},
          {"1x", @token},
          {"1234", "short"},
          {"1234", String.duplicate("x", 129)},
          {"1234", nil},
          {"1234", @token <> "\n"}
        ] do
      assert {:error, %Error{code: :invalid_scrape}} = Scrape.configure(port, token)
    end

    for opts <- [
          [port: 0],
          [port: 0, token_digest: "short"],
          [port: 0, token_digest: @digest, ip: {0, 0, 0, 0}],
          [port: 0, port: 1_024, token_digest: @digest],
          [:bad],
          nil
        ] do
      assert {:error, %Error{code: :invalid_scrape}} = Scrape.start_link(opts)
    end

    assert_raise ArgumentError, fn -> Scrape.init(nil) end
    assert %{type: :supervisor} = Scrape.child_spec(port: 0, token_digest: @digest)
  end

  test "only the operator header can authorize the exact read surface" do
    start_supervised!(@host)
    emit()
    response = request()
    assert response.status == 200
    assert response.resp_body == PromEx.get_metrics(@promex)
    assert get_resp_header(response, "content-type") == [Exposition.content_type()]
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert get_resp_header(response, "connection") == ["close"]
    assert get_resp_header(response, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(response, "set-cookie") == []
    assert get_resp_header(response, "access-control-allow-origin") == []
    refute response.resp_body =~ @token
    refute response.resp_body =~ "secret-scope"
    assert request(headers: [{"authorization", "bEaReR " <> @token}]).status == 200

    for headers <- [
          [],
          @auth ++ @auth,
          [{"authorization", "Bearer wrong"}],
          [{"authorization", "Basic " <> @token}],
          [{"cookie", "operator=" <> @token}],
          [{"authorization", <<255, 255, 255, 255, 255, 255, 32>> <> @token}]
        ] do
      denied = request(headers: headers)
      assert denied.status == 401
      assert get_resp_header(denied, "www-authenticate") == ["Bearer realm=\"operator-metrics\""]
    end

    assert request(
             remote_ip: {203, 0, 113, 7},
             headers: [{"x-forwarded-for", "127.0.0.1"} | @auth]
           ).status == 403

    assert request(path: "/").status == 404
    assert request(method: "POST").status == 405
    assert request(method: "HEAD").status == 405
    assert request(path: "/metrics?token=" <> @token).status == 400

    for extra <- [
          [{"origin", "https://example.invalid"}],
          [{"content-length", "1"}],
          [{"content-length", "0"}, {"content-length", "0"}],
          [{"transfer-encoding", "chunked"}],
          [{"expect", "100-continue"}],
          for(i <- 1..16, do: {"x-#{i}", "x"})
        ] do
      assert request(headers: @auth ++ extra).status == 400
    end
  end

  test "a real loopback socket serves bounded text and refuses unread bodies without draining" do
    log =
      capture_log(fn ->
        start_supervised!({@host, scrape: [port: 0, token_digest: @digest]})
        emit()
        assert {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(Scrape)

        response =
          Req.get!("http://127.0.0.1:#{port}/metrics",
            headers: @auth,
            retry: false,
            decode_body: false,
            receive_timeout: 2_000
          )

        assert response.status == 200 and byte_size(response.body) <= 1_048_576
        assert {:ok, parsed} = Exposition.parse(response.body)
        assert parsed.series != []

        {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 1_000)

        :ok =
          :gen_tcp.send(
            socket,
            "GET /metrics HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer " <>
              @token <> "\r\nContent-Length: 999999999\r\n\r\n"
          )

        rejected = read_closed(socket, "", System.monotonic_time(:millisecond) + 1_000)
        assert rejected =~ "400 Bad Request"
        refute rejected =~ @token
        stop_supervised!(@host)

        assert {:error, :econnrefused} =
                 :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 1_000)
      end)

    refute log =~ @token
  end

  test "connection capacity is finite and stopping the listener closes idle clients" do
    listener = start_supervised!({Scrape, port: 0, token_digest: @digest})
    {:ok, {_, port}} = ThousandIsland.listener_info(listener)

    sockets =
      for _ <- 1..8 do
        {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 1_000)
        socket
      end

    await_connections(listener, 8)
    {:ok, ninth} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 1_000)
    assert {:error, :closed} = :gen_tcp.recv(ninth, 0, 1_000)
    stop_supervised!(Scrape)
    for socket <- sockets, do: assert({:error, :closed} = :gen_tcp.recv(socket, 0, 1_000))
    refute Process.alive?(listener)
  end

  test "unavailable collection is not empty success and activation needs PromEx" do
    assert request().status == 503
    assert Application.fetch_env!(:wotex_lab_workbench, :metrics_scrape) == false
    Application.put_env(:wotex_lab_workbench, :metrics_scrape, port: 0, token_digest: @digest)

    try do
      assert {:error, :metrics_scrape_requires_promex} =
               WotexLabWorkbench.Application.start(:normal, [])
    after
      Application.put_env(:wotex_lab_workbench, :metrics_scrape, false)
    end

    assert {:error, %Error{}} = @host.start_link(scrape: [])
  end

  defp request(opts \\ []) do
    conn = Plug.Test.conn(Keyword.get(opts, :method, "GET"), Keyword.get(opts, :path, "/metrics"))

    conn = %{
      conn
      | remote_ip: Keyword.get(opts, :remote_ip, {127, 0, 0, 1}),
        req_headers: Keyword.get(opts, :headers, @auth)
    }

    Scrape.call(conn, Scrape.init(@digest))
  end

  defp emit do
    :telemetry.execute(
      [:wotex, :lab, :nx, :encode, :stop],
      %{duration: System.convert_time_unit(1, :millisecond, :native)},
      %{outcome: :ok, profile: :test, scope: "secret-scope"}
    )
  end

  defp await_connections(listener, expected, attempts \\ 100) do
    {:ok, connections} = ThousandIsland.connection_pids(listener)

    cond do
      length(connections) == expected -> :ok
      attempts == 0 -> flunk("listener did not reach connection capacity")
      true -> Process.sleep(1) && await_connections(listener, expected, attempts - 1)
    end
  end

  defp read_closed(socket, bytes, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    case :gen_tcp.recv(socket, 0, remaining) do
      {:error, :closed} ->
        bytes

      {:ok, chunk} when byte_size(bytes) + byte_size(chunk) <= 4_096 ->
        read_closed(socket, bytes <> chunk, deadline)

      _ ->
        flunk("bounded refusal did not close the connection")
    end
  end
end
