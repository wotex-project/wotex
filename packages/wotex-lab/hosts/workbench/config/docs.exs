import Config

config :wotex_lab_workbench, WotexLabWorkbenchWeb.Endpoint,
  server: false,
  secret_key_base: String.duplicate("wotex-lab-workbench-docs-only-", 3),
  session_secure: false

config :logger, level: :warning
