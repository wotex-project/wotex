import Config

config :wotex_lab_storybook, WotexLabStorybookWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4004],
  server: false,
  secret_key_base: String.duplicate("wotex-lab-storybook-test-only-", 3)

config :phoenix_storybook, :compilation_mode, :eager
config :logger, level: :warning
