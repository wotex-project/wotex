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

      configured =
        case System.get_env("WOTEX_LAB_GREPTIME_PROFILE") do
          nil ->
            WotexLabWorkbench.Observability.Durable.configure(url, bearer?)

          "local" ->
            WotexLabWorkbench.Observability.Durable.configure(url, bearer?)

          "hosted" ->
            WotexLabWorkbench.Observability.Durable.configure_hosted(
              url,
              System.get_env("WOTEX_LAB_GREPTIME_AUDIENCE"),
              bearer?,
              System.get_env("WOTEX_LAB_GREPTIME_CA_CERTFILE")
            )

          _other ->
            {:error, :invalid_profile}
        end

      configured =
        case {configured, System.get_env("WOTEX_LAB_GREPTIME_DATABASE")} do
          {{:ok, options}, nil} ->
            {:ok, options}

          {{:ok, options}, database} ->
            WotexLabWorkbench.Observability.Durable.put_database(options, database)

          {error, _} ->
            error
        end

      case configured do
        {:ok, options} -> options
        {:error, _error} -> raise "GreptimeDB exporter configuration is invalid"
      end
  end

config :wotex_lab_workbench, metrics_durable: metrics_durable

# Durable reads are separately selected. The local receiver URL is an exact
# loopback base; the hosted profile names an exact HTTPS origin and a query
# credential that is checked here and read again per request, never stored.
# The database is the one the exporter writes, never a request value.
if url = System.get_env("WOTEX_LAB_GREPTIME_QUERY_URL") do
  reader = WotexLabWorkbench.Observability.DurableReader
  database = System.get_env("WOTEX_LAB_GREPTIME_DATABASE")

  configured =
    case System.get_env("WOTEX_LAB_GREPTIME_QUERY_PROFILE") do
      profile when profile in [nil, "local"] ->
        reader.configure(url, database)

      "hosted" ->
        with {:ok, _} <- reader.lookup_credential() do
          reader.configure_hosted(
            url,
            database,
            System.get_env("WOTEX_LAB_GREPTIME_QUERY_CA_CERTFILE")
          )
        end

      _ ->
        :error
    end

  case configured do
    {:ok, options} ->
      config :wotex_lab_workbench, metrics_durable_query: options

    _ ->
      raise "durable reads require a loopback WOTEX_LAB_GREPTIME_QUERY_URL, or the hosted profile " <>
              "with an HTTPS origin and a distinct WOTEX_LAB_GREPTIME_QUERY_TOKEN"
  end
end

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

# Operator listeners bind loopback over plain HTTP unless the operator selects
# the mutual-TLS remote transport with its bind address, files and peer ranges.
metrics_transport =
  case System.get_env("WOTEX_LAB_METRICS_TRANSPORT") do
    nil ->
      :local

    "local" ->
      :local

    "remote" ->
      case WotexLabWorkbench.Observability.OperatorTransport.configure_remote(
             System.get_env("WOTEX_LAB_METRICS_BIND"),
             System.get_env("WOTEX_LAB_METRICS_TLS_CERTFILE"),
             System.get_env("WOTEX_LAB_METRICS_TLS_KEYFILE"),
             System.get_env("WOTEX_LAB_METRICS_TLS_CLIENT_CACERTFILE"),
             System.get_env("WOTEX_LAB_METRICS_ALLOW")
           ) do
        {:ok, transport} ->
          transport

        {:error, _} ->
          raise "remote metrics transport needs a bind address, TLS files and peer ranges"
      end

    _ ->
      raise "WOTEX_LAB_METRICS_TRANSPORT must be local or remote"
  end

with_transport = fn
  options, :local -> options
  options, transport -> Keyword.put(options, :transport, transport)
end

# No credential is read unless the listener is explicitly requested. Retain
# only its digest; never put the supplied Bearer token in application options.
if port = System.get_env("WOTEX_LAB_METRICS_PORT") do
  case WotexLabWorkbench.Observability.Scrape.configure(
         port,
         System.get_env("WOTEX_LAB_METRICS_TOKEN")
       ) do
    {:ok, options} ->
      config :wotex_lab_workbench, metrics_scrape: with_transport.(options, metrics_transport)

    {:error, _invalid} ->
      raise "metrics listener requires an admitted port and URL-safe token (43–128 characters)"
  end
end

# The operator query listener is also opt-in, uses the same transport and keeps only the
# digest of its own credential, which must differ from the scrape credential.
if port = System.get_env("WOTEX_LAB_METRICS_QUERY_PORT") do
  case WotexLabWorkbench.Observability.QueryListener.configure(
         port,
         System.get_env("WOTEX_LAB_METRICS_QUERY_TOKEN")
       ) do
    {:ok, options} ->
      config :wotex_lab_workbench, metrics_query: with_transport.(options, metrics_transport)

    {:error, _} ->
      raise "metric query listener requires an admitted port and URL-safe token (43–128 characters)"
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

# Lab spans and exception logs leave the host only when the operator names the
# OTLP receiver; the database selects a provisioned retention TTL. The hosted
# profile checks its credential here and reads it again per write, never
# storing it.
if url = System.get_env("WOTEX_LAB_OTLP_URL") do
  otlp = WotexLabWorkbench.Observability.Otlp
  database = System.get_env("WOTEX_LAB_OTLP_DATABASE")

  configured =
    case System.get_env("WOTEX_LAB_OTLP_PROFILE") do
      profile when profile in [nil, "local"] ->
        otlp.configure(url, database)

      "hosted" ->
        with {:ok, _} <- otlp.lookup_credential() do
          otlp.configure_hosted(
            url,
            System.get_env("WOTEX_LAB_OTLP_AUDIENCE"),
            database,
            System.get_env("WOTEX_LAB_OTLP_CA_CERTFILE")
          )
        end

      _ ->
        :error
    end

  case configured do
    {:ok, options} ->
      config :wotex_lab_workbench, metrics_otlp: options

    _ ->
      raise "OTLP export requires WOTEX_LAB_OTLP_URL=http://127.0.0.1:<port>/v1/otlp, or the " <>
              "hosted profile with an HTTPS URL, its exact audience and a WOTEX_LAB_OTLP_TOKEN"
  end
end

# HTTP control mutations stay refused unless the operator opts in. The limits
# below are the documented defaults; nothing else is read for this surface.
if System.get_env("WOTEX_LAB_CONTROL_MUTATIONS") == "1" do
  config :wotex_lab_workbench,
    control_mutations: [
      max_requests: 30,
      window_ms: 60_000,
      session_concurrency: 1,
      host_concurrency: 8,
      origins: []
    ]
end

if maude = System.get_env("WOTEX_LAB_MAUDE") do
  config :wotex_lab_workbench, formal_engine: maude
end

if ttl = System.get_env("WOTEX_LAB_WORKBENCH_SESSION_TTL_MS") do
  config :wotex_lab_workbench, session_ttl_ms: String.to_integer(ttl)
end
