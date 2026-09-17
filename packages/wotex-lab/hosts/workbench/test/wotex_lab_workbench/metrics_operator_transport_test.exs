defmodule WotexLabWorkbench.MetricsOperatorTransportTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Lab.Error
  alias WotexLabWorkbench.Observability.{OperatorTransport, QueryListener, Sampler, Scrape}

  @host WotexLabWorkbench.Observability.Supervisor
  @scrape_token "remote-scrape-token-sentinel-with-at-least-43-bytes"
  @query_token "remote-query-token-sentinel-with-at-least-43-bytes"

  setup do
    directory =
      Path.join(System.tmp_dir!(), "wotex-lab-transport-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{pki: pki(directory, "trusted"), foreign: pki(directory, "foreign"), directory: directory}
  end

  test "remote configuration admits an explicit bind, TLS files and bounded peer ranges", %{
    pki: pki
  } do
    assert {:ok, transport} =
             OperatorTransport.configure_remote(
               "127.0.0.1",
               pki.certfile,
               pki.keyfile,
               pki.client_cacertfile,
               "127.0.0.1/32,10.0.0.0/8,2001:db8::/32"
             )

    assert transport.bind == {127, 0, 0, 1}
    assert length(transport.allow) == 3
    assert :ok = OperatorTransport.validate(transport)
    assert :ok = OperatorTransport.validate(:local)
    refute inspect(transport) =~ "PRIVATE KEY"

    valid = [
      "127.0.0.1",
      pki.certfile,
      pki.keyfile,
      pki.client_cacertfile,
      "127.0.0.1/32"
    ]

    for {index, value} <- [
          {0, "localhost"},
          {0, "999.1.1.1"},
          {0, nil},
          {1, "/nonexistent/cert.pem"},
          {2, nil},
          {3, Path.dirname(pki.certfile)},
          {4, ""},
          {4, "10.0.0.1"},
          {4, "10.0.0.0/33"},
          {4, "2001:db8::/129"},
          {4, "10.0.0.0/8,,"},
          {4, "10.0.0.0/08x"},
          {4, Enum.map_join(1..17, ",", &"10.0.0.#{&1}/32")}
        ] do
      arguments = List.replace_at(valid, index, value)

      assert {:error, %Error{code: :invalid_metrics_transport}} =
               apply(OperatorTransport, :configure_remote, arguments)
    end

    for invalid <- [nil, :remote, Map.put(transport, :extra, true), %{transport | allow: []}] do
      assert {:error, %Error{code: :invalid_metrics_transport}} =
               OperatorTransport.validate(invalid)
    end

    assert {:error, %Error{code: :invalid_scrape}} =
             Scrape.validate(port: 0, token_digest: digest(@scrape_token), transport: :remote)

    assert_raise ArgumentError, fn -> Scrape.init({digest(@scrape_token), :remote}) end
    assert_raise ArgumentError, fn -> QueryListener.init({digest(@query_token), nil}) end
  end

  test "peer ranges match IPv4 and IPv6 prefixes exactly" do
    {:ok, remote} =
      OperatorTransport.configure_remote(
        "::1",
        __ENV__.file,
        __ENV__.file,
        __ENV__.file,
        "10.1.2.0/23,2001:db8:abcd::/48,192.0.2.7/32,0.0.0.0/0"
      )

    assert OperatorTransport.admitted_peer?(:local, {127, 0, 0, 1})
    refute OperatorTransport.admitted_peer?(:local, {127, 0, 0, 2})

    {:ok, narrow} =
      OperatorTransport.configure_remote(
        "0.0.0.0",
        __ENV__.file,
        __ENV__.file,
        __ENV__.file,
        "10.1.2.0/23,2001:db8:abcd::/48,192.0.2.7/32"
      )

    for peer <- [
          {10, 1, 2, 0},
          {10, 1, 3, 255},
          {192, 0, 2, 7},
          {0x2001, 0xDB8, 0xABCD, 0, 0, 0, 0, 1}
        ] do
      assert OperatorTransport.admitted_peer?(narrow, peer)
    end

    for peer <- [
          {10, 1, 4, 0},
          {10, 1, 1, 255},
          {192, 0, 2, 8},
          {0x2001, 0xDB8, 0xABCE, 0, 0, 0, 0, 1},
          {0, 0, 0, 0, 0, 0xFFFF, 0x0A01, 0x0201},
          {256, 0, 0, 1},
          :local,
          nil
        ] do
      refute OperatorTransport.admitted_peer?(narrow, peer)
    end

    assert OperatorTransport.admitted_peer?(remote, {203, 0, 113, 9})
    refute OperatorTransport.admitted_peer?(nil, {127, 0, 0, 1})
  end

  test "mutual TLS scrape and query listeners require a trusted client certificate", %{
    pki: pki,
    foreign: foreign
  } do
    {:ok, transport} =
      OperatorTransport.configure_remote(
        "127.0.0.1",
        pki.certfile,
        pki.keyfile,
        pki.client_cacertfile,
        "127.0.0.1/32"
      )

    start_supervised!(
      {@host,
       history: [interval_ms: 60_000],
       scrape: [port: 0, token_digest: digest(@scrape_token), transport: transport],
       query: [port: 0, token_digest: digest(@query_token), transport: transport]}
    )

    :telemetry.execute([:wotex, :lab, :nx, :encode, :stop], %{duration: 1_000}, %{
      profile: :test,
      outcome: :ok
    })

    assert {:ok, _} = Sampler.sample_now()
    {:ok, {{127, 0, 0, 1}, scrape_port}} = ThousandIsland.listener_info(Scrape)
    {:ok, {{127, 0, 0, 1}, query_port}} = ThousandIsland.listener_info(QueryListener)

    scrape =
      "GET /metrics HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer #{@scrape_token}\r\n\r\n"

    assert {:ok, response} = exchange(scrape_port, pki.client, scrape)
    assert response =~ "HTTP/1.1 200"
    assert response =~ "wotex_lab_nx_operations_total"

    body = Jason.encode!(query())

    query =
      "POST /query HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer #{@query_token}\r\n" <>
        "Content-Type: application/json\r\nContent-Length: #{byte_size(body)}\r\n\r\n" <> body

    assert {:ok, answer} = exchange(query_port, pki.client, query)
    assert answer =~ "HTTP/1.1 200"
    assert answer =~ ~s("instance":"workbench")

    assert {:ok, denied} =
             exchange(
               scrape_port,
               pki.client,
               String.replace(scrape, @scrape_token, @query_token)
             )

    assert denied =~ "HTTP/1.1 401"
    assert {:error, _} = exchange(scrape_port, [], scrape)
    assert {:error, _} = exchange(scrape_port, foreign.client, scrape)

    {:ok, plain} = :gen_tcp.connect({127, 0, 0, 1}, scrape_port, [:binary, active: false], 1_000)
    :ok = :gen_tcp.send(plain, scrape)
    refute read_all(plain, "") =~ "HTTP/1.1"
  end

  test "an admitted certificate from a peer outside the ranges is refused", %{pki: pki} do
    {:ok, transport} =
      OperatorTransport.configure_remote(
        "127.0.0.1",
        pki.certfile,
        pki.keyfile,
        pki.client_cacertfile,
        "10.0.0.0/8"
      )

    start_supervised!({Scrape, port: 0, token_digest: digest(@scrape_token), transport: transport})
    {:ok, {_, port}} = ThousandIsland.listener_info(Scrape)

    request =
      "GET /metrics HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer #{@scrape_token}\r\n\r\n"

    assert {:ok, response} = exchange(port, pki.client, request)
    assert response =~ "HTTP/1.1 403"
  end

  defp exchange(port, client, request) do
    options =
      [mode: :binary, active: false, verify: :verify_none, server_name_indication: :disable] ++
        client

    case :ssl.connect(~c"127.0.0.1", port, options, 2_000) do
      {:ok, socket} ->
        case :ssl.send(socket, request) do
          :ok -> read_tls(socket, "")
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_tls(socket, acc) do
    case :ssl.recv(socket, 0, 2_000) do
      {:ok, data} when byte_size(acc) < 1_048_576 -> read_tls(socket, acc <> data)
      {:error, :closed} when acc != "" -> {:ok, acc}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_all(socket, acc) do
    case :gen_tcp.recv(socket, 0, 2_000) do
      {:ok, data} when byte_size(acc) < 65_536 -> read_all(socket, acc <> data)
      _ -> acc
    end
  end

  defp pki(directory, name) do
    curve = [key: {:namedCurve, :secp256r1}, digest: :sha256]
    chain = %{root: curve, intermediates: [], peer: curve}
    data = :public_key.pkix_test_data(%{server_chain: chain, client_chain: chain})
    server = data.server_config
    client = data.client_config

    write = fn file, entries ->
      path = Path.join(directory, "#{name}-#{file}")
      File.write!(path, :public_key.pem_encode(entries))
      path
    end

    {key_type, key} = server[:key]

    %{
      certfile: write.("cert.pem", [{:Certificate, server[:cert], :not_encrypted}]),
      keyfile: write.("key.pem", [{key_type, key, :not_encrypted}]),
      client_cacertfile:
        write.("client-ca.pem", Enum.map(server[:cacerts], &{:Certificate, &1, :not_encrypted})),
      client: [cert: client[:cert], key: client[:key]]
    }
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

  defp digest(token), do: :crypto.hash(:sha256, token)
end
