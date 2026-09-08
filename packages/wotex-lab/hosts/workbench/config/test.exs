import Config

config :wotex_lab_workbench, WotexLabWorkbenchWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base: String.duplicate("wotex-lab-workbench-test-only-", 3),
  session_secure: false

config :wotex_lab_workbench,
  session_ttl_ms: 60 * 1_000,
  session_sweep_ms: 50,
  max_sessions: 16,
  metrics_capacity: 64

config :logger, level: :warning
