[
  import_deps: [:phoenix, :phoenix_live_view],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "{mix,.formatter,.check,.credo}.exs",
    "{config,lib,test}/**/*.{ex,exs,heex}",
    "tools/**/*.exs",
    "priv/seeds.exs"
  ],
  line_length: 100
]
