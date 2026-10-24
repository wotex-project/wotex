import Config

e2e? = System.get_env("WOTEX_LAB_E2E") == "1"

config :wotex_lab_storybook, WotexLabStorybookWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: if(e2e?, do: 0, else: 4004)],
  server: e2e?,
  secret_key_base: String.duplicate("wotex-lab-storybook-test-only-", 3)

config :phoenix_storybook, :compilation_mode, :eager
config :logger, level: :warning

if e2e? do
  config :wotex_lab_storybook, WotexLabStorybookWeb.Endpoint,
    url: [host: "127.0.0.1"],
    check_origin: ["//127.0.0.1"]
end

config :phoenix_test,
  otp_app: :wotex_lab_storybook,
  endpoint: WotexLabStorybookWeb.Endpoint,
  playwright: [
    assets_dir: Path.expand("../../workbench", __DIR__),
    timeout: 5_000,
    screenshot_dir: "_build/test/e2e",
    browser_context_opts: [viewport: %{width: 1280, height: 900}]
  ]
