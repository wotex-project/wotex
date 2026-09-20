import Config

if config_env() == :prod do
  secret_key_base =
    System.get_env("WOTEX_STORYBOOK_SECRET_KEY_BASE") ||
      raise "WOTEX_STORYBOOK_SECRET_KEY_BASE is required for the qualification host"

  port = String.to_integer(System.get_env("WOTEX_STORYBOOK_PORT", "4003"))

  config :wotex_lab_storybook, WotexLabStorybookWeb.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: port],
    secret_key_base: secret_key_base,
    server: true
end

if static = System.get_env("WOTEX_WORKBENCH_STATIC") do
  config :wotex_lab_storybook, workbench_static: Path.expand(static)
end
