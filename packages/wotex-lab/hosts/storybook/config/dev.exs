import Config

config :wotex_lab_storybook, WotexLabStorybookWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4003"))],
  secret_key_base: String.duplicate("wotex-lab-storybook-development-only-", 2),
  code_reloader: true,
  debug_errors: true,
  check_origin: false

config :phoenix, :plug_init_mode, :runtime
