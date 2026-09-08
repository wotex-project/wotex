import Config

config :wotex_lab_nerves,
  target: config_target()

config :shoehorn,
  init: [:nerves_runtime, :wotex_lab_nerves]
