import Config

if config_target() != :host do
  case Application.ensure_all_started(:nerves_bootstrap) do
    {:ok, _} ->
      :ok

    {:error, reason} ->
      raise "Firmware requires the nerves_bootstrap 1.15.0 archive: #{inspect(reason)}"
  end
end

config :wotex_lab_nerves,
  target: config_target()

config :shoehorn,
  init: [:nerves_runtime, :wotex_lab_nerves]
