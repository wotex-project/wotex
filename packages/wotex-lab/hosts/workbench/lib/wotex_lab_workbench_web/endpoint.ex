defmodule WotexLabWorkbenchWeb.Endpoint do
  @moduledoc """
  The host endpoint: local static assets only, bounded request bodies and
  frames, a signed cookie session with strict same-site and secure flags in
  production, and the LiveView socket. No CDN, no long polling.
  """

  use Phoenix.Endpoint, otp_app: :wotex_lab_workbench

  @session_options [
    store: :cookie,
    key: "_wotex_lab_workbench",
    signing_salt: "wotex-lab-workbench-session",
    same_site: "Strict",
    http_only: true,
    max_age: 24 * 60 * 60
  ]

  @doc "Session options with the configured secure flag; shared by the socket."
  @spec session_options() :: keyword()
  def session_options, do: Keyword.put(@session_options, :secure, config(:session_secure, true))

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [
      connect_info: [session: {__MODULE__, :session_options, []}],
      max_frame_size: 65_536
    ],
    longpoll: false

  plug Plug.Static,
    at: "/",
    from: :wotex_lab_workbench,
    gzip: false,
    only: WotexLabWorkbenchWeb.static_paths()

  plug Plug.Static, at: "/js/phoenix", from: {:phoenix, "priv/static"}, only: ~w(phoenix.min.js)

  plug Plug.Static,
    at: "/js/live_view",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.min.js)

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    length: 65_536,
    json_decoder: Jason

  plug Plug.MethodOverride
  plug Plug.Head
  plug :session
  plug WotexLabWorkbenchWeb.Router

  defp session(conn, _opts), do: Plug.Session.call(conn, Plug.Session.init(session_options()))
end
