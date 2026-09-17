defmodule WotexLabWorkbench.Observability.QueryListener do
  @moduledoc """
  Explicit operator-only HTTP/1 binding of the WLB.10 metric query descriptor.

  The listener is separate from the browser host and from the scrape listener.
  Its default `:local` transport fixes the address to IPv4 loopback; the
  `:transport` option may select the mutual-TLS remote profile of
  `WotexLabWorkbench.Observability.OperatorTransport`. It admits only
  `POST /query` and `POST /durable/query` with one Bearer query credential, of
  which only the SHA-256 is retained. The
  scrape credential, cookies, browser sessions, URLs and forwarding headers
  cannot authorize a query. A request needs `Content-Type: application/json`,
  one `Content-Length` of at most 8,192 bytes and no query string, `Origin`,
  `Expect` or `Transfer-Encoding` header.

  The body is the closed field set of `Wotex.Lab.Metrics.Request`. For each
  request the listener process opens one owner-bound scope through
  `WotexLabWorkbench.Observability.Inspection`, so the instance and session
  scope come from the server, never from the body. `/query` reads the volatile
  history and `/durable/query` the durable receiver configured through
  `WotexLabWorkbench.Observability.DurableReader`. The scope admits one call
  under reduced limits (six-hour range, 2,000 points, 256 KiB output, two-second
  deadline, one worker), waits at most 2.25 seconds for the terminal result and
  is revoked before the response. Eight connections, one request per
  connection and the broker's 32-scope ceiling bound concurrent work.

  A successful answer is JSON with source, interval, unit, freshness, loss
  markers and query digest; durable answers add the template digest. Refusals
  are JSON `code`, `phase` and `message` objects with distinct statuses: 400
  malformed request, 401 credential, 403 non-loopback peer, 404 path, 405
  method, 409 clock rollback, 413 body size, 415 media type, 422 unsupported or
  oversized query, 429 scope capacity, 502 a durable receiver that refused the
  template or answered outside it, 503 an unavailable or unactivated source and
  504 deadline; 403 also covers a peer outside the remote profile's ranges.
  Neither transport is a tenant endpoint.
  """

  @behaviour Plug

  import Plug.Conn

  alias Wotex.Lab.{Error, Options}
  alias WotexLabWorkbench.Observability.OperatorTransport
  alias Wotex.Lab.Metrics.Gateway
  alias WotexLabWorkbench.Observability.Inspection

  @token ~r/\A[A-Za-z0-9_-]{43,128}\z/
  @max_body_bytes 8_192
  @sources %{"/query" => :history, "/durable/query" => :durable}
  @max_response_bytes 1_048_576
  @limits %{
    range_ms: 6 * 60 * 60 * 1_000,
    min_step_ms: 5_000,
    points: 2_000,
    output_bytes: 262_144,
    deadline_ms: 2_000,
    concurrent: 1
  }
  @statuses %{
    invalid_request: 400,
    invalid_query: 400,
    invalid_filter: 400,
    invalid_aggregation: 400,
    invalid_range: 400,
    invalid_step: 400,
    invalid_quantile: 400,
    clock_rollback: 409,
    durable_refused: 502,
    durable_invalid_response: 502,
    unsupported_query: 422,
    query_too_large: 422,
    output_too_large: 422,
    too_many_queries: 429,
    inspection_active: 429,
    inspection_capacity: 429,
    deadline_exceeded: 504
  }

  @doc "Admits an explicit decimal port and URL-safe query token, returning only its digest."
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
      {:error, _} -> raise(ArgumentError, "invalid metric query credential digest")
    end
  end

  def init(_), do: raise(ArgumentError, "invalid metric query credential digest")

  @impl Plug
  def call(conn, {digest, transport}) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("connection", "close")

    cond do
      not OperatorTransport.admitted_peer?(transport, conn.remote_ip) ->
        refuse(conn, 403, :forbidden, "only the loopback operator may query")

      not authenticated?(conn, digest) ->
        conn
        |> put_resp_header("www-authenticate", "Bearer realm=\"operator-metric-query\"")
        |> refuse(401, :unauthorized, "query credential is required")

      not Map.has_key?(@sources, conn.request_path) ->
        refuse(conn, 404, :not_found, "only /query and /durable/query are served")

      conn.method != "POST" ->
        conn
        |> put_resp_header("allow", "POST")
        |> refuse(405, :method_not_allowed, "only POST is served")

      content_length(conn) == :too_large ->
        refuse(conn, 413, :body_too_large, "body exceeds #{@max_body_bytes} bytes")

      not request?(conn) ->
        refuse(conn, 400, :invalid_request, "request framing is not admitted")

      not json?(conn) ->
        refuse(conn, 415, :unsupported_media_type, "queries accept application/json only")

      true ->
        query(conn)
    end
  end

  defp request?(conn) do
    conn.query_string == "" and length(conn.req_headers) <= 16 and
      get_req_header(conn, "origin") == [] and get_req_header(conn, "transfer-encoding") == [] and
      get_req_header(conn, "expect") == [] and content_length(conn) == :ok
  end

  defp content_length(conn) do
    with [length] <- get_req_header(conn, "content-length"),
         true <- Regex.match?(~r/\A[1-9][0-9]{0,15}\z/, length) do
      if String.to_integer(length) <= @max_body_bytes, do: :ok, else: :too_large
    else
      _ -> :invalid
    end
  end

  defp json?(conn) do
    with [content_type] <- get_req_header(conn, "content-type"),
         {:ok, "application", "json", _} <- Plug.Conn.Utils.media_type(content_type) do
      true
    else
      _ -> false
    end
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

  defp query(conn) do
    options = [length: @max_body_bytes, read_length: @max_body_bytes, read_timeout: 2_000]

    case read_body(conn, options) do
      {:ok, body, conn} ->
        case Jason.decode(body) do
          {:ok, request} when is_map(request) ->
            answer(conn, Map.fetch!(@sources, conn.request_path), request)

          _ ->
            refuse(conn, 400, :invalid_request, "body is not a JSON object")
        end

      _ ->
        refuse(conn, 400, :invalid_request, "body could not be read")
    end
  end

  defp answer(conn, source, request) do
    case Inspection.open(source: source, ttl_ms: 3_000, max_calls: 1, query_limits: @limits) do
      {:ok, gateway} ->
        monitor = Process.monitor(gateway)

        try do
          conn |> respond(await(gateway, monitor, Gateway.query(gateway, request)))
        after
          _ = Gateway.revoke(gateway)
          Process.demonitor(monitor, [:flush])
          flush(gateway)
        end

      {:error, error} ->
        failure(conn, error)
    end
  end

  defp await(_, _, {:error, error}), do: {:error, error}

  defp await(gateway, monitor, {:ok, reference}) do
    receive do
      {:metric_query, ^gateway, ^reference, result} -> result
      {:DOWN, ^monitor, :process, ^gateway, _} -> {:error, unavailable()}
    after
      @limits.deadline_ms + 250 ->
        _ = Gateway.cancel(gateway, reference)
        {:error, Error.new(:deadline_exceeded, :query, "query deadline passed")}
    end
  end

  defp respond(conn, {:ok, answer}) do
    case Jason.encode(json(answer)) do
      {:ok, encoded} when byte_size(encoded) <= @max_response_bytes ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, encoded)
        |> halt()

      _ ->
        refuse(conn, 422, :output_too_large, "answer exceeds the response ceiling")
    end
  end

  defp respond(conn, {:error, %Error{} = error}), do: failure(conn, error)

  defp failure(conn, %Error{code: code, phase: phase, message: message}),
    do: send_error(conn, Map.get(@statuses, code, 503), code, phase, message)

  defp refuse(conn, status, code, message),
    do: send_error(conn, status, code, :query_binding, message)

  defp send_error(conn, status, code, phase, message) do
    body =
      Jason.encode!(%{
        "code" => Atom.to_string(code),
        "phase" => Atom.to_string(phase),
        "message" => message
      })

    conn |> put_resp_content_type("application/json") |> send_resp(status, body) |> halt()
  end

  defp flush(gateway) do
    receive do
      {:metric_query, ^gateway, _, _} -> flush(gateway)
    after
      0 -> :ok
    end
  end

  defp json(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp json(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {json_key(key), json(item)} end)

  defp json(value) when is_list(value), do: Enum.map(value, &json/1)
  defp json(value) when is_boolean(value) or is_nil(value), do: value
  defp json(value) when is_atom(value), do: Atom.to_string(value)
  defp json(value) when is_tuple(value), do: value |> Tuple.to_list() |> json()
  defp json(value), do: value

  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key) when is_binary(key), do: key
  defp json_key(key), do: inspect(key)

  defp unavailable, do: Error.new(:history_unavailable, :query, "metric history is unavailable")

  defp port?(port), do: is_integer(port) and (port == 0 or port in 1_024..65_535)

  defp token?(token),
    do: is_binary(token) and byte_size(token) in 43..128 and Regex.match?(@token, token)

  defp invalid,
    do:
      {:error,
       Error.new(:invalid_metrics_query, :metrics, "query listener port or credential is invalid")}
end
