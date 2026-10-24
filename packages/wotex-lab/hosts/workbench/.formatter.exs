[
  import_deps: [:phoenix, :phoenix_live_view, :phoenix_storybook],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "{mix,.formatter,.check,.credo}.exs",
    "{config,lib,storybook,test}/**/*.{ex,exs,heex}",
    "tools/**/*.exs",
    "priv/seeds.exs"
  ],
  line_length: 100
]
