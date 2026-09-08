import Config

config :wotex_lab_workbench, promex_enabled: System.get_env("WOTEX_LAB_PROMEX") == "1"

config :wotex_lab_workbench,
  metrics_history_enabled: System.get_env("WOTEX_LAB_METRICS_HISTORY") == "1"

metrics_durable =
  case System.get_env("WOTEX_LAB_GREPTIME_URL") do
    nil ->
      false

    url ->
      bearer? = System.get_env("WOTEX_LAB_GREPTIME_TOKEN") != nil

      case WotexLabWorkbench.Observability.Durable.configure(url, bearer?) do
        {:ok, options} -> options
        {:error, _error} -> raise "GreptimeDB exporter configuration is invalid"
      end
  end

config :wotex_lab_workbench, metrics_durable: metrics_durable

# BeamLens remains completely dormant unless the trusted local operator opts
# in. Provider availability is checked only when an investigation is requested;
# boot never searches credentials, contacts Ollama or downloads a model.
beamlens_enabled = System.get_env("WOTEX_LAB_BEAMLENS") == "trusted-local"
config :wotex_lab_workbench, beamlens_enabled: beamlens_enabled

if beamlens_enabled do
  port = System.get_env("PORT") || "4000"

  provider =
    case System.get_env("WOTEX_LAB_BEAMLENS_PROVIDER") do
      "codex_then_ollama" ->
        :codex_then_ollama

      "ollama" ->
        :ollama

      _other ->
        raise "BeamLens requires WOTEX_LAB_BEAMLENS_PROVIDER=codex_then_ollama or ollama"
    end

  config :wotex_lab_workbench,
    beamlens_provider: provider,
    beamlens_bridge_url:
      System.get_env("WOTEX_LAB_BEAMLENS_BRIDGE_URL") ||
        "http://127.0.0.1:#{port}/api/internal/beamlens/v1"
end

# No credential is read unless the listener is explicitly requested. Retain
# only its digest; never put the supplied Bearer token in application options.
if port = System.get_env("WOTEX_LAB_METRICS_PORT") do
  case WotexLabWorkbench.Observability.Scrape.configure(
         port,
         System.get_env("WOTEX_LAB_METRICS_TOKEN")
       ) do
    {:ok, options} ->
      config :wotex_lab_workbench, metrics_scrape: options

    {:error, _invalid} ->
      raise "metrics listener requires an admitted port and URL-safe token (43–128 characters)"
  end
end

# Every operator-owned value is read here, once, at boot. Nothing below
# downloads, discovers or starts anything: the formal engine path only names
# a binary the operator provisioned and the host verifies before use.
if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE is required: mix phx.gen.secret generates one"

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :wotex_lab_workbench, WotexLabWorkbenchWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true
end

if maude = System.get_env("WOTEX_LAB_MAUDE") do
  config :wotex_lab_workbench, formal_engine: maude
end

if ttl = System.get_env("WOTEX_LAB_WORKBENCH_SESSION_TTL_MS") do
  config :wotex_lab_workbench, session_ttl_ms: String.to_integer(ttl)
end
