# Compiled only when the optional Plug package is present; the stdio transport
# and the server core need no HTTP stack.
if Code.ensure_loaded?(Plug.Conn) do
  defmodule Wotex.Lab.MCP.Plug do
    @moduledoc """
    The pinned MCP Streamable HTTP transport as a Plug.

    A host mounts it at one path with explicit options: `:server` (the
    session-agnostic base built by `Wotex.Lab.MCP.Server.new/1`), `:origins`
    (the allowed `Origin` values; a request with another origin is refused
    before any parsing), `:max_body_bytes` (1 MiB) and `:sessions` (an ETS
    table the host owns for per-session state, created with
    `sessions_table/0`). `POST` carries one JSON-RPC message and answers with
    `application/json`; `initialize` assigns an `Mcp-Session-Id`, later
    requests must present it, `DELETE` ends a session, and `GET` is refused
    because this server pushes nothing. Session ids are random and expire
    with `:session_ttl_ms` (30 minutes). Nothing here authorizes writes: the
    session inherits the host's `:writes` decision and token.
    """

    @behaviour Plug

    import Plug.Conn

    alias Wotex.Lab.MCP.Server

    @max_body_bytes 1_048_576
    @session_ttl_ms 1_800_000

    @impl Plug
    def init(opts) do
      server = Keyword.fetch!(opts, :server)
      origins = Keyword.get(opts, :origins, [])
      sessions = Keyword.fetch!(opts, :sessions)
      true = (is_map(server) and is_list(origins) and is_reference(sessions)) or is_atom(sessions)

      %{
        server: server,
        origins: origins,
        sessions: sessions,
        max_body_bytes: Keyword.get(opts, :max_body_bytes, @max_body_bytes),
        session_ttl_ms: Keyword.get(opts, :session_ttl_ms, @session_ttl_ms)
      }
    end

    @doc "Creates the host-owned session table."
    @spec sessions_table() :: :ets.tid()
    def sessions_table, do: :ets.new(:wotex_lab_mcp_sessions, [:set, :public])

    @impl Plug
    def call(%Plug.Conn{method: "POST"} = conn, config) do
      with :ok <- origin(conn, config.origins),
           {:ok, body, conn} <- body(conn, config.max_body_bytes),
           {:ok, message} <- Wotex.JSON.decode(body, max_bytes: config.max_body_bytes) do
        dispatch(conn, config, message)
      else
        {:error, :origin} ->
          refuse(conn, 403, "origin not allowed")

        {:error, :too_large} ->
          refuse(conn, 413, "body exceeds the ceiling")

        {:error, _} ->
          reply(conn, 400, %{
            "jsonrpc" => "2.0",
            "id" => nil,
            "error" => %{"code" => -32_700, "message" => "body is not a JSON object"}
          })
      end
    end

    def call(%Plug.Conn{method: "DELETE"} = conn, config) do
      with :ok <- origin(conn, config.origins),
           [id] <- get_req_header(conn, "mcp-session-id") do
        :ets.delete(config.sessions, id)
        send_resp(conn, 204, "")
      else
        {:error, :origin} -> refuse(conn, 403, "origin not allowed")
        _ -> refuse(conn, 400, "mcp-session-id required")
      end
    end

    def call(conn, _), do: refuse(conn, 405, "only POST and DELETE are served")

    defp dispatch(conn, config, %{"method" => "initialize"} = message) do
      id = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
      {reply, state} = Server.handle(config.server, message)
      expire(config)

      :ets.insert(
        config.sessions,
        {id, state, System.monotonic_time(:millisecond) + config.session_ttl_ms}
      )

      conn
      |> put_resp_header("mcp-session-id", id)
      |> reply(200, reply)
    end

    defp dispatch(conn, config, message) do
      with [id] <- get_req_header(conn, "mcp-session-id"),
           [{^id, state, expires}] <- :ets.lookup(config.sessions, id),
           true <- expires > System.monotonic_time(:millisecond) do
        {reply, state} = Server.handle(state, message)
        :ets.insert(config.sessions, {id, state, expires})
        if reply, do: reply(conn, 200, reply), else: send_resp(conn, 202, "")
      else
        _ -> refuse(conn, 404, "unknown or expired session; initialize first")
      end
    end

    defp origin(conn, origins) do
      case get_req_header(conn, "origin") do
        [] -> :ok
        [origin] -> if origin in origins, do: :ok, else: {:error, :origin}
        _ -> {:error, :origin}
      end
    end

    defp body(conn, max) do
      case read_body(conn, length: max, read_length: max) do
        {:ok, body, conn} -> {:ok, body, conn}
        {:more, _, _} -> {:error, :too_large}
        {:error, _} -> {:error, :too_large}
      end
    end

    defp expire(config) do
      now = System.monotonic_time(:millisecond)
      :ets.select_delete(config.sessions, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    end

    defp reply(conn, status, payload) do
      {:ok, json} = Wotex.JSON.encode(payload)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, json)
    end

    defp refuse(conn, status, message) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, ~s({"error":"#{message}"}))
    end
  end
end
