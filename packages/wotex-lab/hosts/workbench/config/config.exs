import Config

# Static, non-secret host configuration. Runtime values (port, secret key
# base, session lifetime, formal engine path) live in config/runtime.exs.
config :wotex_lab_workbench, WotexLabWorkbenchWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: WotexLabWorkbenchWeb.ErrorHTML], layout: false],
  pubsub_server: WotexLabWorkbench.PubSub,
  live_view: [signing_salt: "wotex-lab-workbench-live"]

config :wotex_lab_workbench,
  lab_max_children: 256,
  session_ttl_ms: 30 * 60 * 1_000,
  session_sweep_ms: 60 * 1_000,
  max_sessions: 64,
  metrics_capacity: 1_024,
  promex_enabled: false,
  metrics_history_enabled: false,
  metrics_history_options: [],
  metrics_scrape: false,
  formal_engine: nil

config :phoenix, :json_library, Jason

# One compile-time adapter choice for the explicit host; never changed by a
# Lab instance. No PromEx supervisor starts merely by configuring its adapter.
config :prom_ex, :storage_adapter, WotexLabWorkbench.Observability.Store

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"
