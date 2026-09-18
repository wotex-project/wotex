defmodule WotexLabWorkbench.Observability.Durable do
  @moduledoc """
  Closed configuration for the optional GreptimeDB remote-write exporter.

  The default endpoint is an exact IPv4-loopback HTTP path. The separately
  selected hosted profile requires HTTPS, an exact audience origin and Bearer
  authentication. Every hosted write is resolved and pinned by
  `Wotex.Lab.Metrics.ReqSink`; private, link-local, metadata, multicast and
  mixed public/private DNS answers are refused and TLS peer/hostname checks
  remain enabled.
  When bearer authentication is selected, only a fixed environment reference
  enters supervision; the token is resolved inside each disposable export
  worker and is never retained in application or bridge state.

  `put_database/2` optionally selects a provisioned database, such as one
  created by `WotexLabWorkbench.Observability.Provisioning` with a retention
  TTL. Each write then carries `x-greptime-db-name`; without it GreptimeDB
  writes to `public`, whose retention the Lab does not provision.
  """

  alias Wotex.Lab.{Error, Options}
  alias Wotex.Lab.Metrics.{ReqSink, Retention}
  alias WotexLabWorkbench.Observability.Capture

  @credential_env "WOTEX_LAB_GREPTIME_TOKEN"
  @token ~r/\A[A-Za-z0-9_-]{43,128}\z/
  @keys ~w(url profile audience tls_ca_certfile bearer interval_ms queue_limit deadline_ms database)a
  @defaults [
    profile: :local,
    audience: nil,
    tls_ca_certfile: nil,
    database: nil,
    interval_ms: 5_000,
    queue_limit: 16,
    deadline_ms: 5_000
  ]

  @doc "Admits an exact local write URL and whether just-in-time Bearer lookup is required."
  @spec configure(term(), term()) :: {:ok, keyword()} | {:error, Error.t()}
  def configure(url, bearer?) when is_binary(url) and is_boolean(bearer?) do
    options = [url: url, bearer: bearer?] ++ @defaults
    with :ok <- validate(options), do: {:ok, options}
  end

  def configure(_, _), do: invalid()

  @doc "Admits an authenticated HTTPS write endpoint with an exact audience and optional CA."
  @spec configure_hosted(term(), term(), term(), term()) ::
          {:ok, keyword()} | {:error, Error.t()}
  def configure_hosted(url, audience, bearer?, tls_ca_certfile \\ nil)

  def configure_hosted(url, audience, true, tls_ca_certfile)
      when is_binary(url) and is_binary(audience) and
             (is_nil(tls_ca_certfile) or is_binary(tls_ca_certfile)) do
    options =
      [
        url: url,
        profile: :hosted,
        audience: audience,
        tls_ca_certfile: tls_ca_certfile,
        bearer: true
      ] ++ Keyword.drop(@defaults, [:profile, :audience, :tls_ca_certfile])

    with :ok <- validate(options), do: {:ok, options}
  end

  def configure_hosted(_, _, _, _), do: invalid()

  @doc "Selects the provisioned GreptimeDB database for admitted exporter options."
  @spec put_database(keyword(), term()) :: {:ok, keyword()} | {:error, Error.t()}
  def put_database(opts, database) when is_list(opts) do
    with {:ok, database} <- Retention.database(database),
         options = Keyword.put(opts, :database, database),
         :ok <- validate(options) do
      {:ok, options}
    else
      _ -> invalid()
    end
  end

  def put_database(_, _), do: invalid()

  @doc "Validates the closed local exporter configuration without opening a connection."
  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(opts) when is_list(opts) do
    with :ok <- Options.validate(opts, @keys),
         true <- destination?(opts),
         true <- is_boolean(Keyword.get(opts, :bearer)),
         true <- database?(Keyword.get(opts, :database)),
         true <- integer?(opts, :interval_ms, 1_000, 60_000),
         true <- integer?(opts, :queue_limit, 1, 256),
         true <- integer?(opts, :deadline_ms, 100, 60_000) do
      :ok
    else
      _ -> invalid()
    end
  end

  def validate(_), do: invalid()

  @doc "Builds the base bridge child options, optionally writing the same captures to local history."
  @spec child_options(keyword(), GenServer.server() | nil) :: keyword()
  def child_options(opts, history) do
    sink_config = %{
      url: Keyword.fetch!(opts, :url),
      profile: Keyword.fetch!(opts, :profile),
      audience: Keyword.fetch!(opts, :audience),
      tls_ca_certfile: Keyword.fetch!(opts, :tls_ca_certfile),
      receive_timeout: Keyword.fetch!(opts, :deadline_ms),
      connect_timeout: Keyword.fetch!(opts, :deadline_ms),
      max_response_bytes: 4_096
    }

    [
      id: :workbench,
      name: __MODULE__.Bridge,
      scrape: &Capture.sample/0,
      sink: sink(sink_config, Keyword.get(opts, :database)),
      credential: credential(Keyword.fetch!(opts, :bearer)),
      history: history,
      interval_ms: Keyword.fetch!(opts, :interval_ms),
      queue_limit: Keyword.fetch!(opts, :queue_limit),
      deadline_ms: Keyword.fetch!(opts, :deadline_ms),
      labels: [{"instance", "workbench"}],
      profile: :greptime,
      restart: :permanent
    ]
  end

  @doc false
  @spec lookup_credential(atom()) :: {:ok, ReqSink.credential()} | :error
  def lookup_credential(:greptime_bearer) do
    case System.fetch_env(@credential_env) do
      {:ok, token} when is_binary(token) ->
        if Regex.match?(@token, token), do: {:ok, {:bearer, token}}, else: :error

      :error ->
        :error
    end
  end

  def lookup_credential(_), do: :error

  defp destination?(opts) do
    case Keyword.get(opts, :profile) do
      :local ->
        is_nil(Keyword.get(opts, :audience)) and
          is_nil(Keyword.get(opts, :tls_ca_certfile)) and
          local_write_url?(Keyword.get(opts, :url))

      :hosted ->
        Keyword.get(opts, :bearer) == true and
          valid_ca?(Keyword.get(opts, :tls_ca_certfile)) and
          hosted_write_url?(Keyword.get(opts, :url), Keyword.get(opts, :audience))

      _ ->
        false
    end
  end

  defp sink(config, nil),
    do: fn request, credential -> ReqSink.write(request, credential, config) end

  defp sink(config, database) do
    fn %{headers: headers} = request, credential ->
      ReqSink.write(
        %{request | headers: [{"x-greptime-db-name", database} | headers]},
        credential,
        config
      )
    end
  end

  defp database?(nil), do: true
  defp database?(database), do: match?({:ok, _}, Retention.database(database))

  defp credential(false), do: nil

  defp credential(true),
    do: %{reference: :greptime_bearer, lookup: &__MODULE__.lookup_credential/1}

  defp local_write_url?(url) when is_binary(url) and byte_size(url) in 1..2_048 do
    case URI.new(url) do
      {:ok,
       %URI{
         scheme: "http",
         host: "127.0.0.1",
         path: "/v1/prometheus/write",
         query: nil,
         fragment: nil,
         userinfo: nil,
         port: port
       }} ->
        is_integer(port) and port in 1..65_535

      _ ->
        false
    end
  end

  defp local_write_url?(_), do: false

  defp hosted_write_url?(url, audience)
       when is_binary(url) and byte_size(url) in 1..2_048 and is_binary(audience) and
              byte_size(audience) in 1..2_048 do
    with {:ok, uri} <- URI.new(url),
         {:ok, expected} <- URI.new(audience),
         true <- exact_hosted_write_uri?(uri),
         true <- origin_uri?(expected),
         true <- origin(uri) == origin(expected) do
      true
    else
      _ -> false
    end
  end

  defp hosted_write_url?(_, _), do: false

  defp exact_hosted_write_uri?(%URI{
         scheme: "https",
         host: host,
         path: "/v1/prometheus/write",
         query: nil,
         fragment: nil,
         userinfo: nil,
         port: port
       }),
       do: is_binary(host) and byte_size(host) > 0 and (is_nil(port) or port in 1..65_535)

  defp exact_hosted_write_uri?(_), do: false

  defp origin_uri?(%URI{
         scheme: "https",
         host: host,
         path: path,
         query: nil,
         fragment: nil,
         userinfo: nil
       }),
       do: is_binary(host) and byte_size(host) > 0 and path in [nil, "", "/"]

  defp origin_uri?(_), do: false

  defp origin(%URI{scheme: scheme, host: host, port: port}) do
    host = if String.contains?(host, ":"), do: "[#{host}]", else: host
    suffix = if is_nil(port) or port == 443, do: "", else: ":#{port}"
    "#{scheme}://#{host}#{suffix}"
  end

  defp valid_ca?(nil), do: true
  defp valid_ca?(path), do: is_binary(path) and byte_size(path) in 1..2_048

  defp integer?(opts, key, minimum, maximum) do
    value = Keyword.get(opts, key)
    is_integer(value) and value in minimum..maximum
  end

  defp invalid,
    do: {:error, Error.new(:invalid_durable_metrics, :construction, "durable exporter is invalid")}
end
