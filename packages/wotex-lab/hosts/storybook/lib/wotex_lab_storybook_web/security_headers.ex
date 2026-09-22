defmodule WotexLabStorybookWeb.SecurityHeaders do
  @moduledoc false

  import Plug.Conn

  @doc "Returns the validated plug options unchanged."
  @spec init(keyword()) :: keyword()
  def init(options), do: options

  @doc "Adds the Storybook host's restrictive browser security policy."
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _) do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

    policy =
      "default-src 'self'; " <>
        "base-uri 'self'; object-src 'none'; frame-ancestors 'none'; " <>
        "form-action 'self'; img-src 'self' data:; font-src 'self'; " <>
        "style-src 'self' 'unsafe-inline'; " <>
        "script-src 'self' 'nonce-#{nonce}'; connect-src 'self' ws: wss:"

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy)
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("permissions-policy", "camera=(), microphone=(), geolocation=()")
  end
end
