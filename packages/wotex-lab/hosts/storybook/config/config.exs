import Config

config :wotex_lab_storybook, WotexLabStorybookWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: WotexLabStorybookWeb.ErrorHTML], layout: false],
  pubsub_server: WotexLabStorybook.PubSub,
  live_view: [signing_salt: "wotex-lab-storybook-live"]

config :wotex_lab_storybook,
  workbench_static: Path.expand("../../workbench/priv/static", __DIR__)

config :phoenix, :json_library, Jason

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"
