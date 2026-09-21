defmodule WotexLabWorkbench.HostedListenerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import Plug.Conn, only: [get_resp_header: 2]

  alias Wotex.Lab.Error

  alias WotexLabWorkbench.Observability.{
    DurableReader,
    HostedAccess,
    HostedListener
  }

  alias WotexLabWorkbench.FakeGreptime

  @token_a "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  @token_b "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  test "TLS listener configuration is explicit and closed" do
    root = temporary_directory()
    on_exit(fn -> File.rm_rf!(root) end)
    cert = Path.join(root, "cert.pem")
    key = Path.join(root, "key.pem")
    File.write!(cert, "certificate")
    File.write!(key, "key")
    File.chmod!(key, 0o600)

    assert {:ok, options} = HostedListener.configure("0", "127.0.0.1", cert, key)
    assert options == [port: 0, ip: {127, 0, 0, 1}, certfile: cert, keyfile: key]
    assert :ok = HostedListener.validate(options)
    assert %{type: :supervisor} = HostedListener.child_spec(options)

    for arguments <- [
          ["80", "127.0.0.1", cert, key],
          ["65536", "127.0.0.1", cert, key],
          ["4000", "localhost", cert, key],
          ["4000", "127.0.0.1", root, key],
          ["4000", "127.0.0.1", cert, "/missing"]
        ] do
      assert {:error, %Error{code: :invalid_hosted_listener}} =
               apply(HostedListener, :configure, arguments)
    end

    assert {:error, %Error{code: :invalid_hosted_listener}} =
             HostedListener.validate(Keyword.put(options, :unknown, true))

    link = Path.join(root, "key-link.pem")
    File.ln_s!(key, link)

    assert {:error, %Error{code: :invalid_hosted_listener}} =
             HostedListener.validate(Keyword.put(options, :keyfile, link))

    File.chmod!(key, 0o644)

    assert {:error, %Error{code: :invalid_hosted_listener}} =
             HostedListener.validate(options)
  end

  test "the public listener accepts TLS 1.3 and refuses plaintext and unauthenticated clients" do
    root = temporary_directory()
    on_exit(fn -> File.rm_rf!(root) end)
    {cert, key} = certificate(root)
    start_access(4000)

    start_supervised!({HostedListener, port: 0, ip: {127, 0, 0, 1}, certfile: cert, keyfile: key})

    assert {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(HostedListener)

    assert {:ok, socket} =
             :ssl.connect(
               {127, 0, 0, 1},
               port,
               [:binary, active: false, verify: :verify_none, versions: [:"tlsv1.3"]],
               2_000
             )

    request =
      "POST /v1/query HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n" <>
        "Content-Length: 2\r\n\r\n{}"

    :ok = :ssl.send(socket, request)
    response = read_tls(socket, "")
    assert response =~ "HTTP/1.1 401"
    assert response =~ "www-authenticate: Bearer realm=\"wotex-lab-hosted\""

    assert {:ok, plain} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 1_000)
    :ok = :gen_tcp.send(plain, request)
    refute read_plain(plain, "") =~ "HTTP/1.1"
  end

  test "authentication and framing fail before a tenant lease is opened" do
    start_access(4000)
    body = Jason.encode!(query())

    for headers <- [
          framing(body),
          auth("wrong") ++ framing(body),
          auth(@token_a) ++ auth(@token_a) ++ framing(body),
          [{"authorization", "Basic " <> @token_a}] ++ framing(body)
        ] do
      response = request("/v1/query", body, headers)
      assert response.status == 401

      assert get_resp_header(response, "www-authenticate") == [
               "Bearer realm=\"wotex-lab-hosted\""
             ]
    end

    for extra <- [
          [{"origin", "https://tenant.invalid"}],
          [{"cookie", "tenant=#{@token_a}"}],
          [{"transfer-encoding", "chunked"}],
          [{"expect", "100-continue"}]
        ] do
      assert request("/v1/query", body, auth(@token_a) ++ framing(body) ++ extra).status ==
               400
    end

    assert request("/v1/query?tenant=a", body, auth(@token_a) ++ framing(body)).status == 400
    assert request("/v1/query", body, auth(@token_a), "GET").status == 405
    assert request("/", body, auth(@token_a) ++ framing(body)).status == 404

    oversized =
      auth(@token_a) ++
        [{"content-type", "application/json"}, {"content-length", "8193"}]

    assert request("/v1/query", body, oversized).status == 413

    invalid_json = "{"

    assert request(
             "/v1/query",
             invalid_json,
             auth(@token_a) ++ framing(invalid_json)
           ).status == 400

    assert HostedAccess.stats().active_queries == 0
  end

  test "durable queries bind the authenticated tenant and release every lease" do
    {_, port} = FakeGreptime.start(self())
    start_access(port)
    body = Jason.encode!(query())

    task = Task.async(fn -> request("/v1/query", body, auth(@token_a) ++ framing(body)) end)
    assert_receive {:fake_greptime, handler, exchange}, 2_000
    promql = URI.decode_query(exchange.body)["query"]
    assert promql =~ ~s(instance="metrics-a")
    refute promql =~ "metrics-b"
    send(handler, {:reply, 200, matrix("metrics-a", [[1_767_225_605, "4"]])})

    response = Task.await(task)
    assert response.status == 200
    answer = Jason.decode!(response.resp_body)
    assert answer["instance"] == "metrics-a"
    assert answer["source"] == "durable_promql"
    assert answer["points"] == [%{"t" => 1_767_225_605_000, "value" => 4}]
    assert get_resp_header(response, "set-cookie") == []
    refute response.resp_body =~ @token_a
    assert HostedAccess.stats().active_queries == 0

    forged = Map.put(query(), "scope", %{"instance" => "metrics-b"}) |> Jason.encode!()

    denied = request("/v1/query", forged, auth(@token_a) ++ framing(forged))
    assert denied.status == 400
    assert HostedAccess.stats().active_queries == 0
    refute_received {:fake_greptime, _, _}

    task = Task.async(fn -> request("/v1/query", body, auth(@token_b) ++ framing(body)) end)
    assert_receive {:fake_greptime, handler, exchange}, 2_000
    assert URI.decode_query(exchange.body)["query"] =~ ~s(instance="metrics-b")
    send(handler, {:reply, 200, matrix("metrics-b", [])})
    assert Task.await(task).status == 200
  end

  test "investigation input cannot select tenant, provider or receiver" do
    start_access(4000)

    valid = Jason.encode!(%{"prompt" => "inspect", "current" => nil, "baseline" => nil})
    unavailable = request("/v1/investigations", valid, auth(@token_a) ++ framing(valid))
    assert unavailable.status == 503
    assert HostedAccess.stats().active_investigations == 0

    for field <- ~w(tenant provider receiver) do
      forged =
        %{"prompt" => "inspect", "current" => nil, "baseline" => nil, field => "chosen"}
        |> Jason.encode!()

      assert request("/v1/investigations", forged, auth(@token_a) ++ framing(forged)).status ==
               400
    end

    assert HostedAccess.stats().active_investigations == 0
  end

  defp start_access(port) do
    {:ok, durable} = DurableReader.configure("http://127.0.0.1:#{port}", nil)

    tenants = [
      %{id: "tenant-a", instance: "metrics-a", token_digest: :crypto.hash(:sha256, @token_a)},
      %{id: "tenant-b", instance: "metrics-b", token_digest: :crypto.hash(:sha256, @token_b)}
    ]

    start_supervised!({HostedAccess, tenants: tenants, durable: durable})
  end

  defp query do
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

  defp matrix(instance, values) do
    Jason.encode!(%{
      "status" => "success",
      "data" => %{
        "resultType" => "matrix",
        "result" => [%{"metric" => %{"instance" => instance}, "values" => values}]
      }
    })
  end

  defp request(path, body, headers, method \\ "POST") do
    conn = Plug.Test.conn(method, path, body)
    conn = %{conn | remote_ip: {203, 0, 113, 7}, req_headers: headers}
    HostedListener.call(conn, HostedListener.init([]))
  end

  defp auth(token), do: [{"authorization", "Bearer " <> token}]

  defp framing(body),
    do: [{"content-type", "application/json"}, {"content-length", "#{byte_size(body)}"}]

  defp temporary_directory do
    path =
      Path.join(
        System.tmp_dir!(),
        "wotex-hosted-listener-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(path)
    path
  end

  defp certificate(directory) do
    curve = [key: {:namedCurve, :secp256r1}, digest: :sha256]
    chain = %{root: curve, intermediates: [], peer: curve}
    server = :public_key.pkix_test_data(%{server_chain: chain, client_chain: chain}).server_config
    {key_type, private_key} = server[:key]
    cert = Path.join(directory, "server-cert.pem")
    key = Path.join(directory, "server-key.pem")
    File.write!(cert, :public_key.pem_encode([{:Certificate, server[:cert], :not_encrypted}]))
    File.write!(key, :public_key.pem_encode([{key_type, private_key, :not_encrypted}]))
    File.chmod!(key, 0o600)
    {cert, key}
  end

  defp read_tls(socket, bytes) do
    case :ssl.recv(socket, 0, 2_000) do
      {:ok, chunk} when byte_size(bytes) + byte_size(chunk) <= 65_536 ->
        read_tls(socket, bytes <> chunk)

      {:error, :closed} ->
        bytes

      _ ->
        flunk("TLS listener did not close its bounded response")
    end
  end

  defp read_plain(socket, bytes) do
    case :gen_tcp.recv(socket, 0, 1_000) do
      {:ok, chunk} when byte_size(bytes) + byte_size(chunk) <= 4_096 ->
        read_plain(socket, bytes <> chunk)

      _ ->
        bytes
    end
  end
end
