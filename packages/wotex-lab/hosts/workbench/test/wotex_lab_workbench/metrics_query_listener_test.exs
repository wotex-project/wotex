defmodule WotexLabWorkbench.MetricsQueryListenerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Plug.Conn, only: [get_resp_header: 2]

  alias Wotex.Lab.Error
  alias Wotex.Lab.Metrics.Gateway
  alias WotexLabWorkbench.Observability.{Inspection, QueryListener, Sampler}

  @host WotexLabWorkbench.Observability.Supervisor
  @token "local-only-query-token-sentinel-with-32-bytes-min"
  @scrape_token "local-only-scrape-token-sentinel-32-bytes-minimum"
  @digest :crypto.hash(:sha256, @token)
  @auth [{"authorization", "Bearer " <> @token}]

  test "closed configuration keeps only the digest and refuses other listener options" do
    assert {:ok, opts} = QueryListener.configure("0", @token)
    assert opts == [port: 0, token_digest: @digest]
    refute inspect(opts) =~ @token
    assert :ok = QueryListener.validate(opts)

    for {port, token} <- [
          {nil, @token},
          {"80", @token},
          {"65536", @token},
          {"1x", @token},
          {"1234", "short"},
          {"1234", String.duplicate("x", 129)},
          {"1234", nil},
          {"1234", @token <> "\n"}
        ] do
      assert {:error, %Error{code: :invalid_metrics_query}} = QueryListener.configure(port, token)
    end

    for opts <- [
          [port: 0],
          [port: 0, token_digest: "short"],
          [port: 0, token_digest: @digest, ip: {0, 0, 0, 0}],
          [:bad]
        ] do
      assert {:error, %Error{code: :invalid_metrics_query}} = QueryListener.start_link(opts)
    end

    assert_raise ArgumentError, fn -> QueryListener.init(nil) end
    assert %{type: :supervisor} = QueryListener.child_spec(port: 0, token_digest: @digest)

    assert {:error, %Error{code: :metrics_query_requires_history}} =
             @host.start_link(query: [port: 0, token_digest: @digest])

    assert {:error, %Error{code: :metrics_query_requires_distinct_credential}} =
             @host.start_link(
               history: [interval_ms: 60_000],
               scrape: [port: 0, token_digest: @digest],
               query: [port: 0, token_digest: @digest]
             )

    assert {:error, %Error{code: :invalid_metrics_query}} = @host.start_link(query: [port: 0])
  end

  test "the server binds scope, answers the descriptor and revokes the scope" do
    start_supervised!({@host, history: [interval_ms: 60_000]})
    sample()
    response = request(body: Jason.encode!(query()))
    assert response.status == 200
    assert get_resp_header(response, "content-type") == ["application/json; charset=utf-8"]
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert get_resp_header(response, "connection") == ["close"]
    assert get_resp_header(response, "set-cookie") == []
    answer = Jason.decode!(response.resp_body)
    assert answer["instance"] == "workbench" and answer["source"] == "ets_history"
    assert answer["digest"] =~ "sha256:" and answer["freshness"] != nil
    assert Enum.sum(Enum.map(answer["points"], & &1["value"])) >= 1
    refute response.resp_body =~ @token
    assert Inspection.count() == 0

    for {body, status, code} <- [
          {Jason.encode!(Map.put(query(), "scope", %{"instance" => "other"})), 400,
           "invalid_request"},
          {Jason.encode!(Map.put(query(), "limits", %{"points" => 100_000})), 400,
           "invalid_request"},
          {Jason.encode!(%{query() | "aggregation" => "avg"}), 422, "unsupported_query"},
          {Jason.encode!(%{query() | "start_at" => iso(-7 * 60 * 60)}), 400, "invalid_range"},
          {Jason.encode!([query()]), 400, "invalid_request"},
          {"{", 400, "invalid_request"}
        ] do
      refused = request(body: body)
      assert refused.status == status
      assert %{"code" => ^code} = Jason.decode!(refused.resp_body)
    end

    assert Inspection.count() == 0
  end

  test "credentials, peer, path, method and framing are refused before a scope opens" do
    start_supervised!({@host, history: [interval_ms: 60_000]})
    body = Jason.encode!(query())

    for headers <- [
          [],
          @auth ++ @auth,
          [{"authorization", "Bearer wrong"}],
          [{"authorization", "Bearer " <> @scrape_token}],
          [{"authorization", "Basic " <> @token}],
          [{"cookie", "operator=" <> @token}]
        ] do
      denied = request(body: body, headers: headers ++ framing(body))
      assert denied.status == 401

      assert get_resp_header(denied, "www-authenticate") == [
               "Bearer realm=\"operator-metric-query\""
             ]
    end

    assert request(body: body, remote_ip: {203, 0, 113, 7}).status == 403
    assert request(body: body, path: "/").status == 404
    denied = request(body: body, method: "GET")
    assert denied.status == 405 and get_resp_header(denied, "allow") == ["POST"]
    assert request(body: body, path: "/query?token=" <> @token).status == 400

    for extra <- [
          [{"origin", "https://example.invalid"}],
          [{"transfer-encoding", "chunked"}],
          [{"expect", "100-continue"}],
          for(index <- 1..14, do: {"x-#{index}", "x"})
        ] do
      assert request(body: body, headers: @auth ++ framing(body) ++ extra).status == 400
    end

    for length <- [[], [{"content-length", "0"}], [{"content-length", "12a"}]] do
      headers = @auth ++ [{"content-type", "application/json"}] ++ length
      assert request(body: body, headers: headers).status == 400
    end

    too_large = @auth ++ [{"content-type", "application/json"}, {"content-length", "8193"}]
    assert request(body: body, headers: too_large).status == 413

    plain = @auth ++ [{"content-type", "text/plain"}, {"content-length", "#{byte_size(body)}"}]
    assert request(body: body, headers: plain).status == 415
    assert Inspection.count() == 0
  end

  test "unavailable history and exhausted scopes are distinct refusals" do
    body = Jason.encode!(query())
    unavailable = request(body: body)
    assert unavailable.status == 503
    assert %{"code" => "inspection_unavailable"} = Jason.decode!(unavailable.resp_body)

    start_supervised!({@host, history: [interval_ms: 60_000]})
    parent = self()

    holders =
      for _ <- 1..32 do
        spawn(fn ->
          {:ok, _} = Inspection.open()
          send(parent, :opened)
          receive do: (:release -> :ok)
        end)
      end

    for _ <- holders, do: assert_receive(:opened)
    exhausted = request(body: body)
    assert exhausted.status == 429
    assert %{"code" => "inspection_capacity"} = Jason.decode!(exhausted.resp_body)
    Enum.each(holders, &send(&1, :release))
  end

  test "a real loopback socket answers one bounded request per connection" do
    log =
      capture_log(fn ->
        start_supervised!(
          {@host, history: [interval_ms: 60_000], query: [port: 0, token_digest: @digest]}
        )

        sample()
        assert {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(QueryListener)

        response =
          Req.post!("http://127.0.0.1:#{port}/query",
            headers: @auth,
            json: query(),
            retry: false,
            receive_timeout: 3_000
          )

        assert response.status == 200
        assert response.body["instance"] == "workbench"

        {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 1_000)

        :ok =
          :gen_tcp.send(
            socket,
            "POST /query HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer " <>
              @token <> "\r\nContent-Type: application/json\r\nContent-Length: 999999999\r\n\r\n"
          )

        rejected = read_closed(socket, "", System.monotonic_time(:millisecond) + 1_000)
        assert rejected =~ "413"
        refute rejected =~ @token
        stop_supervised!(@host)

        assert {:error, :econnrefused} =
                 :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 1_000)
      end)

    refute log =~ @token
  end

  test "application activation needs history and a credential distinct from scraping" do
    Application.put_env(:wotex_lab_workbench, :metrics_query, port: 0, token_digest: @digest)

    try do
      assert {:error, :metrics_query_requires_history} =
               WotexLabWorkbench.Application.start(:normal, [])

      Application.put_env(:wotex_lab_workbench, :metrics_history_enabled, true)
      Application.put_env(:wotex_lab_workbench, :promex_enabled, true)
      Application.put_env(:wotex_lab_workbench, :metrics_scrape, port: 0, token_digest: @digest)

      assert {:error, :metrics_query_requires_distinct_credential} =
               WotexLabWorkbench.Application.start(:normal, [])
    after
      Application.put_env(:wotex_lab_workbench, :metrics_query, false)
      Application.put_env(:wotex_lab_workbench, :metrics_scrape, false)
      Application.put_env(:wotex_lab_workbench, :metrics_history_enabled, false)
      Application.put_env(:wotex_lab_workbench, :promex_enabled, false)
    end
  end

  test "a gateway deadline answers 504 and releases the scope" do
    start_supervised!({@host, history: [interval_ms: 60_000]})
    history = Process.whereis(WotexLabWorkbench.Observability.Supervisor.History)
    :ok = :sys.suspend(history)

    try do
      timed_out = request(body: Jason.encode!(query()))
      assert timed_out.status == 504
      assert %{"code" => "deadline_exceeded"} = Jason.decode!(timed_out.resp_body)
    after
      :ok = :sys.resume(history)
    end

    assert Inspection.count() == 0
    assert {:ok, gateway} = Inspection.open()
    assert %{admitted: 0} = Gateway.stats(gateway)
  end

  defp query do
    now = DateTime.utc_now()

    %{
      "schema_version" => "1.0.0",
      "metric" => "nx_operations_total",
      "aggregation" => "sum",
      "start_at" => DateTime.to_iso8601(DateTime.add(now, -10, :second)),
      "end_at" => DateTime.to_iso8601(now),
      "step_ms" => 5_000
    }
  end

  defp iso(offset_seconds),
    do: DateTime.utc_now() |> DateTime.add(offset_seconds, :second) |> DateTime.to_iso8601()

  defp sample do
    :telemetry.execute([:wotex, :lab, :nx, :encode, :stop], %{duration: 1_000}, %{
      profile: :test,
      outcome: :ok
    })

    assert {:ok, _} = Sampler.sample_now()
  end

  defp framing(body),
    do: [{"content-type", "application/json"}, {"content-length", "#{byte_size(body)}"}]

  defp request(opts) do
    body = Keyword.fetch!(opts, :body)

    conn =
      Plug.Test.conn(Keyword.get(opts, :method, "POST"), Keyword.get(opts, :path, "/query"), body)

    conn = %{
      conn
      | remote_ip: Keyword.get(opts, :remote_ip, {127, 0, 0, 1}),
        req_headers: Keyword.get(opts, :headers, @auth ++ framing(body))
    }

    QueryListener.call(conn, QueryListener.init(@digest))
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
