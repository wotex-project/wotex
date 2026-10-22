import Config

e2e? = System.get_env("WOTEX_LAB_E2E") == "1"

config :wotex_lab_workbench, WotexLabWorkbenchWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: if(e2e?, do: 0, else: 4002)],
  server: e2e?,
  secret_key_base: String.duplicate("wotex-lab-workbench-test-only-", 3),
  session_secure: false

if e2e? do
  config :wotex_lab_workbench, WotexLabWorkbenchWeb.Endpoint,
    url: [host: "127.0.0.1"],
    check_origin: ["//127.0.0.1"]
end

config :wotex_lab_workbench,
  session_ttl_ms: 60 * 1_000,
  session_sweep_ms: 50,
  max_sessions: 16,
  metrics_capacity: 64,
  control_mutations: [
    max_requests: 12,
    window_ms: 60_000,
    session_concurrency: 1,
    host_concurrency: 4,
    origins: ["https://client.example"]
  ]

config :logger, level: :warning

config :phoenix_test,
  otp_app: :wotex_lab_workbench,
  endpoint: WotexLabWorkbenchWeb.Endpoint,
  playwright: [
    assets_dir: ".",
    timeout: 5_000,
    screenshot_dir: "_build/test/e2e",
    browser_context_opts: [viewport: %{width: 1280, height: 900}]
  ]
