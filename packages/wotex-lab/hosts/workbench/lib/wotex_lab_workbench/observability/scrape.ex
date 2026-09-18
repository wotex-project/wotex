defmodule WotexLabWorkbench.Observability.Scrape do
  @moduledoc """
  Explicit operator-only HTTP/1 scrape listener, separate from the browser host.

  The default `:local` transport fixes the address to IPv4 loopback; the
  `:transport` option may instead carry the mutual-TLS remote profile admitted
  by `WotexLabWorkbench.Observability.OperatorTransport`, with its bind address
  and peer ranges. Only `GET /metrics` without query or body is admitted, using
  one bounded Bearer credential. Only its SHA-256 is
  retained in configuration. Cookies, URLs, forwarding headers and browser
  sessions cannot authorize access. No CORS, HTTP/2, WebSocket or keepalive is
  enabled. Eight connections, bounded headers and two-second socket waits bound
  the listener; public PromEx collection also has its own two-second timeout.

  The local transport is a trusted-local-operator profile; neither transport is
  a tenant endpoint. It does not start PromEx, discover credentials or download
  anything. The explicit host supervisor composes it with the collector.
  """

  @behaviour Plug

  import Plug.Conn

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.Exposition
  alias WotexLabWorkbench.Observability.OperatorTransport

  @promex WotexLabWorkbench.Observability.PromEx
  @token ~r/\A[A-Za-z0-9_-]{43,128}\z/

  @doc "Admits an explicit decimal port and URL-safe token, returning only its digest."
  @spec configure(term(), term()) :: {:ok, keyword()} | {:error, Error.t()}
  def configure(port, token) when is_binary(port) and byte_size(port) in 1..5 do
    with true <- Regex.match?(~r/\A[0-9]+\z/, port),
         {number, ""} <- Integer.parse(port),
         true <- port?(number) and token?(token) do
      {:ok, [port: number, token_digest: :crypto.hash(:sha256, token)]}
    else
      _ -> invalid()
    end
  end

  def configure(_, _), do: invalid()

  @doc "Validates closed listener options without opening a socket."
  @spec validate(keyword()) :: :ok | {:error, Error.t()}
  def validate(opts) do
    with :ok <- Options.validate(opts, [:port, :token_digest, :transport]),
         :ok <- OperatorTransport.validate(Keyword.get(opts, :transport, :local)),
         true <- port?(Keyword.get(opts, :port)),
         digest when is_binary(digest) and byte_size(digest) == 32 <-
           Keyword.get(opts, :token_digest) do
      :ok
    else
      _ -> invalid()
    end
  end

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :supervisor}

  @doc "Starts the bounded listener for its transport; port 0 explicitly requests an ephemeral port."
  @spec start_link(keyword()) :: Supervisor.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <- validate(opts) do
      transport = Keyword.get(opts, :transport, :local)

      {socket, bandit} =
        transport
        |> OperatorTransport.bandit_options(
          backlog: 8,
          send_timeout: 2_000,
          send_timeout_close: true
        )
        |> Keyword.pop!(:transport_options)

      Bandit.start_link(
        bandit ++
          [
            plug: {__MODULE__, {Keyword.fetch!(opts, :token_digest), transport}},
            port: Keyword.fetch!(opts, :port),
            startup_log: false,
            thousand_island_options: [
              supervisor_options: [name: __MODULE__],
              num_acceptors: 1,
              num_connections: 8,
              max_connections_retry_count: 0,
              read_timeout: 2_000,
              shutdown_timeout: 2_000,
              transport_options: socket
            ],
            http_options: [
              compress: false,
              log_exceptions_with_status_codes: [],
              log_protocol_errors: false,
              log_client_closures: false
            ],
            http_1_options: [
              max_requests: 1,
              max_request_line_length: 1_024,
              max_header_length: 2_048,
              max_header_count: 16
            ],
            http_2_options: [enabled: false],
            websocket_options: [enabled: false]
          ]
      )
    end
  end

  @impl Plug
  def init(digest) when is_binary(digest) and byte_size(digest) == 32, do: {digest, :local}

  def init({digest, transport} = config) when is_binary(digest) and byte_size(digest) == 32 do
    case OperatorTransport.validate(transport) do
      :ok -> config
      {:error, _} -> raise(ArgumentError, "invalid scrape credential digest")
    end
  end

  def init(_), do: raise(ArgumentError, "invalid scrape credential digest")

  @impl Plug
  def call(conn, {digest, transport}) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("connection", "close")

    cond do
      not OperatorTransport.admitted_peer?(transport, conn.remote_ip) ->
        reply(conn, 403, "Forbidden\n")

      not authenticated?(conn, digest) ->
        conn
        |> put_resp_header("www-authenticate", "Bearer realm=\"operator-metrics\"")
        |> reply(401, "Unauthorized\n")

      conn.request_path != "/metrics" ->
        reply(conn, 404, "Not Found\n")

      conn.method != "GET" ->
        conn
        |> put_resp_header("allow", "GET")
        |> reply(405, "Method Not Allowed\n")

      not request?(conn) ->
        reply(conn, 400, "Bad Request\n")

      true ->
        scrape(conn)
    end
  end

  defp request?(conn) do
    conn.query_string == "" and length(conn.req_headers) <= 16 and
      get_req_header(conn, "origin") == [] and get_req_header(conn, "transfer-encoding") == [] and
      get_req_header(conn, "expect") == [] and get_req_header(conn, "content-length") in [[], ["0"]]
  end

  defp authenticated?(conn, digest) do
    case get_req_header(conn, "authorization") do
      [<<scheme::binary-size(6), " ", token::binary>>] when byte_size(token) <= 128 ->
        Regex.match?(~r/\Abearer\z/i, scheme) and token?(token) and
          Plug.Crypto.secure_compare(:crypto.hash(:sha256, token), digest)

      _ ->
        false
    end
  end

  defp scrape(conn) do
    case metrics() do
      text when is_binary(text) and byte_size(text) <= 1_048_576 ->
        conn
        |> put_resp_header("content-type", Exposition.content_type())
        |> send_resp(200, text)
        |> halt()

      _ ->
        reply(conn, 503, "Service Unavailable\n")
    end
  end

  defp metrics do
    PromEx.get_metrics(@promex)
  catch
    :exit, _ -> :prom_ex_down
  end

  defp reply(conn, status, body) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, body)
    |> halt()
  end

  defp port?(port), do: is_integer(port) and (port == 0 or port in 1_024..65_535)

  defp token?(token),
    do: is_binary(token) and byte_size(token) in 43..128 and Regex.match?(@token, token)

  defp invalid,
    do: {:error, Error.new(:invalid_scrape, :metrics, "scrape port or credential is invalid")}
end
