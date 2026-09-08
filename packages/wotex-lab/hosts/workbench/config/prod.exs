import Config

config :wotex_lab_workbench, WotexLabWorkbenchWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  session_secure: true

config :logger, level: :info
