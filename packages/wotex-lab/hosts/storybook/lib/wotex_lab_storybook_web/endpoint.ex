defmodule WotexLabStorybookWeb.Endpoint do
  @moduledoc "Loopback-only Phoenix endpoint for local integration qualification."

  use Phoenix.Endpoint, otp_app: :wotex_lab_storybook

  @session_options [
    store: :cookie,
    key: "_wotex_lab_storybook",
    signing_salt: "wotex-lab-storybook-session",
    same_site: "Strict",
    http_only: true,
    max_age: 8 * 60 * 60
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options], max_frame_size: 65_536],
    longpoll: false

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded],
    pass: ["application/x-www-form-urlencoded"],
    length: 65_536

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug WotexLabStorybookWeb.SecurityHeaders
  plug WotexLabStorybookWeb.Router
end
