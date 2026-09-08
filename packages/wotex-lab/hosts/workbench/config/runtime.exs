import Config

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
