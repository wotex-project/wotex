defmodule WotexLabWorkbench.Observability.HostedListener do
  @moduledoc """
  Public HTTPS binding for tenant-scoped metric queries and isolated analysis.

  A digest-only tenant registry authenticates each Bearer credential and binds
  it to one durable metric instance. Request bodies cannot carry tenant, scope,
  receiver, limits, credentials or provider selection. Metric queries execute
  under fixed limits in the host. Investigations execute in a separately
  verified one-request worker VM supervised by the native custodian.
  """

  @behaviour Plug

  import Plug.Conn

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.Gateway

  alias WotexLabWorkbench.Investigation.{Answer, HostedBroker}
  alias WotexLabWorkbench.Observability.HostedAccess

  @max_query_bytes 8 * 1_024
  @max_investigation_bytes 16 * 1_024
  @max_tls_file_bytes 1 * 1_024 * 1_024
  @max_query_response_bytes 256 * 1_024
  @max_investigation_response_bytes 64 * 1_024
  @query_limits %{
    range_ms: 6 * 60 * 60 * 1_000,
    min_step_ms: 5_000,
    points: 2_000,
    output_bytes: 256 * 1_024,
    deadline_ms: 2_000,
    concurrent: 1
  }
  @routes %{
    "/v1/query" => :query,
    "/v1/investigations" => :investigation
  }

  @doc "Admits the explicit TLS listener configuration."
  @spec configure(term(), term(), term(), term()) :: {:ok, keyword()} | {:error, Error.t()}
  def configure(port, bind, certfile, keyfile) do
    with {:ok, port} <- port(port),
         {:ok, ip} <- address(bind),
         true <- regular_file?(certfile, false) and regular_file?(keyfile, true) do
      {:ok, [port: port, ip: ip, certfile: certfile, keyfile: keyfile]}
    else
      _ -> invalid()
    end
  end

  @doc false
  @spec validate(keyword()) :: :ok | {:error, Error.t()}
  def validate(opts) do
    with :ok <- Options.validate(opts, [:port, :ip, :certfile, :keyfile]),
         true <- port?(Keyword.get(opts, :port)),
         true <- ip?(Keyword.get(opts, :ip)),
         true <- regular_file?(Keyword.get(opts, :certfile), false),
         true <- regular_file?(Keyword.get(opts, :keyfile), true) do
      :ok
    else
      _ -> invalid()
    end
  end

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :supervisor}

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start() | {:error, Error.t()}
  def start_link(opts) do
    with :ok <- validate(opts) do
      Bandit.start_link(
        plug: __MODULE__,
        scheme: :https,
        ip: Keyword.fetch!(opts, :ip),
        port: Keyword.fetch!(opts, :port),
        certfile: Keyword.fetch!(opts, :certfile),
        keyfile: Keyword.fetch!(opts, :keyfile),
        cipher_suite: :strong,
        startup_log: false,
        thousand_island_options: [
          supervisor_options: [name: __MODULE__],
          num_acceptors: 2,
          num_connections: 64,
          max_connections_retry_count: 0,
          read_timeout: 2_000,
          shutdown_timeout: 2_000,
          transport_options: [
            backlog: 64,
            send_timeout: 2_000,
            send_timeout_close: true,
            versions: [:"tlsv1.3"],
            session_tickets: :disabled
          ]
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
      )
    end
  end

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("connection", "close")

    purpose = @routes[conn.request_path]
    maximum = body_limit(purpose)

    cond do
      purpose == nil ->
        refuse(conn, 404, :not_found, "only the versioned hosted routes are served")

      conn.method != "POST" ->
        conn
        |> put_resp_header("allow", "POST")
        |> refuse(405, :method_not_allowed, "only POST is served")

      content_length(conn, maximum) == :too_large ->
        refuse(conn, 413, :body_too_large, "request body exceeds its ceiling")

      not request?(conn, maximum) ->
        refuse(conn, 400, :invalid_request, "request framing is not admitted")

      not json?(conn) ->
        refuse(conn, 415, :unsupported_media_type, "application/json is required")

      true ->
        dispatch(conn, purpose, maximum)
    end
  end

  defp dispatch(conn, purpose, maximum) do
    with {:ok, token} <- bearer(conn),
         {:ok, binding} <- HostedAccess.open(token, purpose) do
      try do
        dispatch_admitted(conn, binding, purpose, maximum)
      after
        HostedAccess.release(binding.lease)
      end
    else
      :error -> unauthorized(conn)
      {:error, %Error{code: :hosted_unauthorized}} -> unauthorized(conn)
      {:error, %Error{} = error} -> failure(conn, error)
    end
  end

  defp dispatch_admitted(conn, binding, purpose, maximum) do
    with {:ok, body, conn} <-
           read_body(conn, length: maximum, read_length: maximum, read_timeout: 2_000),
         {:ok, request} when is_map(request) <- Jason.decode(body) do
      case purpose do
        :query -> query(conn, binding, request)
        :investigation -> investigate(conn, binding, request)
      end
    else
      _ -> refuse(conn, 400, :invalid_request, "body is not a JSON object")
    end
  end

  defp query(conn, binding, request) do
    options = [
      owner: self(),
      durable: binding.durable,
      scope: %{instance: binding.instance, session: session()},
      ttl_ms: 3_000,
      max_calls: 1,
      query_limits: @query_limits
    ]

    case Gateway.start_link(options) do
      {:ok, gateway} ->
        try do
          case Gateway.query(gateway, request) do
            {:ok, reference} -> await_query(conn, gateway, reference)
            {:error, error} -> failure(conn, error)
          end
        after
          _ = Gateway.revoke(gateway)
        end

      {:error, error} ->
        failure(conn, error)
    end
  end

  defp await_query(conn, gateway, reference) do
    receive do
      {:metric_query, ^gateway, ^reference, {:ok, answer}} ->
        respond(conn, 200, json(answer), @max_query_response_bytes)

      {:metric_query, ^gateway, ^reference, {:error, error}} ->
        failure(conn, error)
    after
      2_250 ->
        _ = Gateway.cancel(gateway, reference)
        refuse(conn, 504, :deadline_exceeded, "query deadline passed")
    end
  end

  defp investigate(conn, binding, request) do
    with :ok <- investigation_request?(request),
         scope = %{instance: binding.instance, durable: binding.durable},
         {:ok, reference} <-
           HostedBroker.ask(scope, request["prompt"], request["current"], request["baseline"]) do
      receive do
        {:hosted_investigation, ^reference, {:ok, result, provider}} ->
          answer = hosted_answer(Answer.from_result(result, provider))
          respond(conn, 200, json(answer), @max_investigation_response_bytes)

        {:hosted_investigation, ^reference, {:error, reason}} ->
          answer = hosted_answer(Answer.from_result({:error, reason}, %{}))
          respond(conn, 503, json(answer), @max_investigation_response_bytes)
      after
        32_000 ->
          _ = HostedBroker.cancel(reference)
          refuse(conn, 504, :investigation_timeout, "investigation deadline passed")
      end
    else
      {:error, %Error{} = error} -> failure(conn, error)
      _ -> refuse(conn, 400, :invalid_request, "investigation request is invalid")
    end
  end

  defp investigation_request?(request) do
    keys = Map.keys(request) |> Enum.sort()

    if keys == ~w(baseline current prompt) and is_binary(request["prompt"]),
      do: :ok,
      else: {:error, :invalid_request}
  end

  defp hosted_answer(answer) do
    Map.update(answer, :sources, [], fn sources ->
      Enum.map(sources, &Map.put(&1, :href, nil))
    end)
  end

  defp respond(conn, status, value, maximum) do
    case Jason.encode(value) do
      {:ok, encoded} when byte_size(encoded) <= maximum ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(status, encoded)
        |> halt()

      _ ->
        refuse(conn, 422, :output_too_large, "response exceeds its ceiling")
    end
  end

  defp failure(conn, %Error{code: code, message: message}) do
    status =
      case code do
        code when code in [:tenant_concurrency, :tenant_rate_limited, :hosted_capacity] -> 429
        code when code in [:invalid_request, :invalid_query, :invalid_range, :invalid_step] -> 400
        code when code in [:unsupported_query, :query_too_large, :output_too_large] -> 422
        :deadline_exceeded -> 504
        _ -> 503
      end

    refuse(conn, status, code, message)
  end

  defp failure(conn, _), do: refuse(conn, 503, :hosted_unavailable, "hosted service unavailable")

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", "Bearer realm=\"wotex-lab-hosted\"")
    |> refuse(401, :unauthorized, "hosted tenant credential is required")
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      [<<scheme::binary-size(6), " ", token::binary>>] when byte_size(token) <= 128 ->
        if Regex.match?(~r/\Abearer\z/i, scheme), do: {:ok, token}, else: :error

      _ ->
        :error
    end
  end

  defp request?(conn, maximum) do
    conn.query_string == "" and length(conn.req_headers) <= 16 and
      get_req_header(conn, "origin") == [] and get_req_header(conn, "cookie") == [] and
      get_req_header(conn, "transfer-encoding") == [] and
      get_req_header(conn, "expect") == [] and content_length(conn, maximum) == :ok
  end

  defp content_length(conn, maximum) do
    with [length] <- get_req_header(conn, "content-length"),
         true <- Regex.match?(~r/\A[1-9][0-9]{0,15}\z/, length) do
      if String.to_integer(length) <= maximum, do: :ok, else: :too_large
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

  defp body_limit(:query), do: @max_query_bytes
  defp body_limit(:investigation), do: @max_investigation_bytes
  defp body_limit(_), do: @max_query_bytes

  defp refuse(conn, status, code, message) do
    body = Jason.encode!(%{code: Atom.to_string(code), message: message})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
    |> halt()
  end

  defp session,
    do: "hosted-" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)

  defp json(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp json(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {json_key(key), json(item)} end)

  defp json(value) when is_list(value), do: Enum.map(value, &json/1)
  defp json(value) when is_atom(value), do: Atom.to_string(value)
  defp json(value) when is_tuple(value), do: json(Tuple.to_list(value))
  defp json(value), do: value

  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key) when is_binary(key), do: key
  defp json_key(key), do: inspect(key)

  defp port(port) when is_binary(port) and byte_size(port) in 1..5 do
    case Integer.parse(port) do
      {value, ""} when value == 0 or value in 1_024..65_535 -> {:ok, value}
      _ -> invalid()
    end
  end

  defp port(_), do: invalid()
  defp port?(port), do: is_integer(port) and (port == 0 or port in 1_024..65_535)

  defp address(text) when is_binary(text) and byte_size(text) in 1..45 do
    case :inet.parse_strict_address(String.to_charlist(text)) do
      {:ok, address} -> {:ok, address}
      _ -> invalid()
    end
  end

  defp address(_), do: invalid()

  defp ip?({a, b, c, d}), do: Enum.all?([a, b, c, d], &(&1 in 0..255))

  defp ip?({_, _, _, _, _, _, _, _} = address),
    do: Enum.all?(Tuple.to_list(address), &(is_integer(&1) and &1 in 0..65_535))

  defp ip?(_), do: false

  defp regular_file?(path, private?) when is_binary(path) do
    with true <- Path.type(path) == :absolute,
         {:ok, before} <- File.lstat(path),
         true <- before.type == :regular and before.size in 1..@max_tls_file_bytes,
         true <- Bitwise.band(before.mode, if(private?, do: 0o077, else: 0o022)) == 0,
         {:ok, after_stat} <- File.lstat(path) do
      before.type == after_stat.type and before.size == after_stat.size and
        before.inode == after_stat.inode and before.major_device == after_stat.major_device and
        before.minor_device == after_stat.minor_device and before.mode == after_stat.mode and
        before.mtime == after_stat.mtime and before.ctime == after_stat.ctime
    else
      _ -> false
    end
  end

  defp regular_file?(_, _), do: false

  defp invalid,
    do:
      {:error,
       Error.new(:invalid_hosted_listener, :hosted_access, "hosted TLS listener is invalid")}
end
