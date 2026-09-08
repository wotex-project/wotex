import Config

config :wotex_lab_workbench, WotexLabWorkbenchWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  debug_errors: true,
  secret_key_base: String.duplicate("wotex-lab-workbench-development-only-", 3),
  session_secure: false

config :logger, level: :debug
