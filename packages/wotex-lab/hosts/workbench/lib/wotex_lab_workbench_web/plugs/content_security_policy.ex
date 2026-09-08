defmodule WotexLabWorkbenchWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  A restrictive Content Security Policy with a per-request script nonce.

  Scripts load from this origin with the request nonce only, styles and
  images from this origin, connections to this origin and its WebSocket,
  no frames, no objects, no form targets elsewhere and no base URI change.
  """

  @behaviour Plug

  import Plug.Conn

  @host ~r/\A(?:[A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\])(?::[0-9]{1,5})?\z/

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    nonce = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    socket = if(conn.scheme == :https, do: "wss", else: "ws") <> "://" <> host(conn)

    policy =
      [
        "default-src 'self'",
        "script-src 'self' 'nonce-#{nonce}'",
        "style-src 'self'",
        "img-src 'self' data:",
        "font-src 'self'",
        "connect-src 'self' #{socket}",
        "frame-ancestors 'none'",
        "form-action 'self'",
        "base-uri 'self'",
        "object-src 'none'"
      ]
      |> Enum.join("; ")

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy)
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("permissions-policy", "camera=(), microphone=(), geolocation=()")
  end

  defp host(conn) do
    case get_req_header(conn, "host") do
      [host | _rest] when byte_size(host) <= 255 -> admitted_host(host, conn.host)
      _none -> conn.host
    end
  end

  defp admitted_host(host, fallback) do
    if Regex.match?(@host, host), do: host, else: fallback
  end
end
